import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class ModuleLibraryModel {
    static let talosActionsURL = "https://github.com/thom1606/Talos-Actions"
    static let settingsActionID = "builtin.settings"
    private(set) var snapshot = LibrarySnapshot()
    private(set) var isBusy = false
    var error: String?
    @ObservationIgnored lazy var tasks = TasksModel()
    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let credentials = RepositoryCredentials()
    @ObservationIgnored private let github = GitHubRepositoryService()
    @ObservationIgnored private let local = LocalRepositoryService()
    @ObservationIgnored private let installer: ModuleInstaller
    @ObservationIgnored private var folderSave: Task<Void, Never>?
    @ObservationIgnored private var folderRevision = 0
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var loading: Task<LibrarySnapshot, Error>?
    @ObservationIgnored private var openSettings: @MainActor () -> Void = {}

    init(store: LibraryStore = LibraryStore(), installer: ModuleInstaller = ModuleInstaller()) {
        self.store = store; self.installer = installer
    }

    func configureOpenSettings(_ action: @escaping @MainActor () -> Void) {
        openSettings = action
    }

    func configureHostNotifications() {
        tasks.resumeNotification = { [weak self] installation, invocation, action in
            Task {
                guard let self else { return }
                await self.reload()
                guard let module = self.snapshot.installed.first(where: { $0.id == installation && $0.enabled }) else { return }
                await self.tasks.run(module: module, action: invocation.actionID, files: invocation.files, notificationAction: action)
            }
        }
    }
    func reload() async {
        let revision = folderRevision
        do {
            let latest = try await store.load()
            guard !isBusy, folderSave == nil, folderRevision == revision else { return }
            snapshot = latest; loaded = true
        }
        catch { self.error = error.localizedDescription }
    }
    func load() async {
        guard !loaded else { return }
        let pending = loading ?? Task { try await store.load() }
        loading = pending
        do {
            snapshot = try await pending.value; loaded = true
            #if TALOS_SETTINGS
            for index in snapshot.installed.indices where snapshot.installed[index].sourceID == nil && snapshot.installed[index].isBundled != true {
                let module = snapshot.installed[index]
                var source = RepositorySource(directory: module.directory, name: module.manifest.name)
                source.modules = [module.manifest]
                snapshot.repositories.append(source)
                snapshot.installed[index].sourceID = source.id
            }
            try await save()
            #endif
        }
        catch { self.error = error.localizedDescription }
        loading = nil
    }
    func addRepository(url: String, token: String) async {
        await perform {
            var source = try RepositorySource(url: url)
            guard !self.snapshot.repositories.contains(where: { $0.slug.lowercased() == source.slug.lowercased() }) else {
                throw ManifestError.invalid("This repository is already added")
            }
            source = try await self.github.refresh(source, token: token.isEmpty ? nil : token)
            if !token.isEmpty { try await self.credentials.set(token, for: source.id) }
            self.snapshot.repositories.append(source)
            try await self.synchronize(source)
        }
    }
    /// Shipped actions install offline from the signed host bundle before the wheel starts.
    func installDefaultActionsIfNeeded() async {
        guard !isBusy else { return }
        await perform {
            guard let config = Bundle.main.url(forResource: "built-in-actions", withExtension: "json"),
                  let archive = Bundle.main.url(forResource: "built-in-actions", withExtension: "talos") else {
                throw ManifestError.invalid("Bundled actions are missing. Reinstall Talos.")
            }
            let manifest = try JSONDecoder().decode(ModuleManifest.self, from: Data(contentsOf: config))
            let existing = self.snapshot.installed.first { $0.isBundled == true && $0.manifest.id == manifest.id }
            if let existing, existing.manifest.version == manifest.version { return }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
            try FileManager.default.copyItem(at: archive, to: temporary)
            var installed = try await self.installer.install(archive: temporary, manifest: manifest,
                sourceID: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!)
            installed.isBundled = true
            installed.enabled = existing?.enabled ?? true
            self.snapshot.installed.removeAll { $0.id == existing?.id }
            self.snapshot.installed.insert(installed, at: 0)
            try await self.save()
            if let existing { try? await self.installer.remove(existing) }
        }
    }
    func setToken(_ token: String, source: RepositorySource) async {
        await perform { try await self.credentials.set(token, for: source.id) }
    }
    func refresh() async {
        await perform {
            for index in self.snapshot.repositories.indices {
                let source = self.snapshot.repositories[index]
                do {
                    if source.isLocal { self.snapshot.repositories[index] = try await self.local.refresh(source) }
                    else {
                        let token = try await self.credentials.token(for: source.id)
                        self.snapshot.repositories[index] = try await self.github.refresh(source, token: token)
                    }
                } catch {
                    self.snapshot.repositories[index].error = error.localizedDescription
                }
            }
            try await self.save()
        }
    }
    func removeRepository(_ source: RepositorySource) async {
        await perform {
            let modules = self.snapshot.installed.filter { $0.sourceID == source.id }
            guard !modules.contains(where: ModuleLease.isInUse) else { throw ManifestError.invalid("Finish this repository's running tasks before removing it") }
            if !source.isLocal { try await self.credentials.set("", for: source.id) }
            self.snapshot.repositories.removeAll { $0.id == source.id }
            self.snapshot.installed.removeAll { $0.sourceID == source.id }
            try await self.save()
            for module in modules { try? await self.installer.remove(module) }
        }
    }
    func importPackage(_ archive: URL) async {
        await load()
        guard loaded else { return }
        await perform {
            var module = try await self.installer.importPackage(archive)
            do {
                var source = RepositorySource(directory: module.directory, name: module.manifest.name)
                source.modules = [module.manifest]
                module.sourceID = source.id
                self.snapshot.repositories.append(source)
                self.snapshot.installed.append(module)
                try await self.save()
            } catch {
                try? await self.installer.remove(module)
                throw error
            }
        }
    }

    func importLocal(_ directory: URL) async {
        await perform {
            guard !self.snapshot.repositories.contains(where: { $0.localDirectory?.standardizedFileURL == directory.standardizedFileURL }) else {
                throw ManifestError.invalid("This local repository is already linked")
            }
            let source = try await self.local.refresh(RepositorySource(directory: directory))
            self.snapshot.repositories.append(source)
            try await self.synchronize(source)
        }
    }
    func hasUpdate(_ source: RepositorySource) -> Bool {
        if snapshot.installed.contains(where: { $0.sourceID == source.id && !source.modules.map(\.id).contains($0.manifest.id) }) { return true }
        return source.modules.contains { manifest in
            guard let current = installed(manifest, source: source) else { return true }
            guard let available = Version(manifest.version), let version = Version(current.manifest.version) else { return false }
            return available > version
        }
    }
    func update(_ source: RepositorySource) async { await perform { try await self.synchronize(source) } }
    private func synchronize(_ source: RepositorySource) async throws {
        var created: [InstalledModule] = []
        var replaced: [InstalledModule] = []
        do {
            let removed = snapshot.installed.filter { $0.sourceID == source.id && !source.modules.map(\.id).contains($0.manifest.id) }
            guard !removed.contains(where: ModuleLease.isInUse) else { throw ManifestError.invalid("Finish the repository's running tasks before updating") }
            replaced.append(contentsOf: removed)
            snapshot.installed.removeAll { item in removed.contains { $0.id == item.id } }
            for manifest in source.modules {
                let old = installed(manifest, source: source)
                if let old, let current = Version(old.manifest.version), let available = Version(manifest.version), available <= current { continue }
                if let old, ModuleLease.isInUse(old) { throw ManifestError.invalid("Finish the module's running tasks before updating") }
                var module: InstalledModule
                if source.isLocal {
                    let directory = try await local.directory(for: manifest, source: source)
                    module = try await installer.importDirectory(directory, sourceID: source.id)
                } else {
                    let token = try await credentials.token(for: source.id)
                    let archive = try await github.download(manifest, from: source, token: token)
                    module = try await installer.install(archive: archive, manifest: manifest, sourceID: source.id)
                }
                created.append(module)
                if let old { module.enabled = old.enabled; replaced.append(old) }
                if let index = snapshot.installed.firstIndex(where: { $0.id == old?.id }) { snapshot.installed[index] = module }
                else { snapshot.installed.append(module) }
            }
            try await save()
        } catch {
            for module in created { try? await installer.remove(module) }
            throw error
        }
        for module in replaced { try? await installer.remove(module) }
    }
    struct ActionItem: Identifiable {
        let module: InstalledModule
        let action: ModuleAction
        var id: String { "\(module.sourceID?.uuidString ?? "local")/\(module.manifest.id)/\(action.id)" }
    }
    struct PaletteAction: Identifiable {
        let id: String
        let title: String
        let symbol: String?
    }
    var actionItems: [ActionItem] {
        let items = snapshot.installed.flatMap { module in module.manifest.actions.map { ActionItem(module: module, action: $0) } }
        let positions = Dictionary(snapshot.actionOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated().sorted {
            (positions[$0.element.id] ?? (snapshot.actionOrder.count + $0.offset)) < (positions[$1.element.id] ?? (snapshot.actionOrder.count + $1.offset))
        }.map(\.element)
    }
    var paletteActions: [PaletteAction] {
        actionItems.map { PaletteAction(id: $0.id, title: $0.action.localizedTitle, symbol: $0.action.symbol) }
            + [PaletteAction(id: Self.settingsActionID, title: String(localized: "Settings"), symbol: "gearshape")]
    }
    func actionEnabled(_ item: ActionItem) -> Bool { item.module.enabled && !snapshot.disabledActions.contains(item.id) }
    func setActionEnabled(_ enabled: Bool, item: ActionItem) async {
        await perform {
            if enabled {
                self.snapshot.disabledActions.remove(item.id)
                if let i = self.snapshot.installed.firstIndex(where: { $0.id == item.module.id }) { self.snapshot.installed[i].enabled = true }
            } else { self.snapshot.disabledActions.insert(item.id) }
            try await self.save()
        }
    }
    func moveActions(from indices: IndexSet, to destination: Int) async {
        await perform {
            var ids = self.actionItems.map(\.id)
            ids.move(fromOffsets: indices, toOffset: destination)
            self.snapshot.actionOrder = ids
            try await self.save()
        }
    }
    /// A wheel drop enables the action and places it among the visible actions atomically.
    func placeAction(_ id: String, at index: Int) async {
        guard let item = actionItems.first(where: { $0.id == id }) else { return }
        await perform {
            var ids = self.actionItems.filter(self.actionEnabled).map(\.id)
            ids.removeAll { $0 == id }
            ids.insert(id, at: min(max(0, index), ids.count))
            self.snapshot.disabledActions.remove(id)
            if let moduleIndex = self.snapshot.installed.firstIndex(where: { $0.id == item.module.id }) {
                self.snapshot.installed[moduleIndex].enabled = true
            }
            self.snapshot.actionOrder = ids + self.actionItems.map(\.id).filter { !ids.contains($0) }
            try await self.save()
        }
    }
    func setEnabled(_ enabled: Bool, module: InstalledModule) async {
        await perform {
            guard let i = self.snapshot.installed.firstIndex(where: { $0.id == module.id }) else { return }
            self.snapshot.installed[i].enabled = enabled
            try await self.save()
        }
    }
    func remove(_ module: InstalledModule) async {
        await perform {
            guard !ModuleLease.isInUse(module) else { throw ManifestError.invalid("Finish or cancel this module's tasks before removing it") }
            self.snapshot.installed.removeAll { $0.id == module.id }
            try await self.save()
            try? await self.installer.remove(module)
        }
    }
    func installed(_ manifest: ModuleManifest, source: RepositorySource) -> InstalledModule? {
        snapshot.installed.first { $0.sourceID == source.id && $0.manifest.id == manifest.id }
    }
    var wheelEntries: [WheelEntry] {
        snapshot.wheel ?? actionItems.filter(actionEnabled).map {
            // Stable identities until the legacy arrangement is first edited.
            WheelEntry(id: "legacy/" + $0.id, actionID: $0.id)
        } + [WheelEntry(id: "builtin.settings.default", actionID: Self.settingsActionID)]
    }

    func setWheelEntries(_ entries: [WheelEntry], at path: [String]) async {
        await perform {
            var tree = self.wheelEntries
            WheelEntry.replace(in: &tree, path: path, with: entries)
            self.snapshot.wheel = tree
            try await self.save()
        }
    }

    /// Publish every keystroke immediately without disabling the editor or losing focus.
    func renameFolder(_ id: String, title: String) {
        guard !isBusy else { return }
        func rename(_ entries: inout [WheelEntry]) {
            for index in entries.indices {
                if entries[index].id == id && entries[index].children != nil { entries[index].title = title }
                if var children = entries[index].children {
                    rename(&children)
                    entries[index].children = children
                }
            }
        }
        var tree = wheelEntries
        rename(&tree)
        guard tree != wheelEntries else { return }
        snapshot.wheel = tree
        folderRevision += 1
        let revision = folderRevision
        folderSave?.cancel()
        folderSave = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                try await self.save()
                if self.folderRevision == revision { self.folderSave = nil }
            } catch {
                // Keep the local edit if saving failed; a reload must not silently discard it.
                if self.folderRevision == revision { self.error = error.localizedDescription }
            }
        }
    }

    func settingsFields(for entry: WheelEntry) -> [ActionSetting] {
        actionItems.first(where: { $0.id == entry.actionID })?.action.settings ?? []
    }

    func updateTile(_ entry: WheelEntry) async {
        await perform {
            func replace(_ items: inout [WheelEntry]) {
                for index in items.indices {
                    if items[index].id == entry.id { items[index] = entry; return }
                    if var children = items[index].children {
                        replace(&children)
                        items[index].children = children
                    }
                }
            }
            var tree = self.wheelEntries
            replace(&tree)
            self.snapshot.wheel = tree
            try await self.save()
        }
    }

    /// The configured wheel can lay out its labels and glass before there is a drag selection.
    func previewActions() -> [TalosAction] {
        func preview(_ entries: [WheelEntry]) -> [TalosAction] {
            paginate(entries.compactMap { entry in
                if let children = entry.children {
                    return TalosAction(id: entry.id, title: entry.title, symbol: "folder", destination: .submenu(preview(children)))
                }
                if entry.actionID == Self.settingsActionID {
                    return TalosAction(id: entry.id, title: entry.customTitle ?? String(localized: "Settings"), symbol: "gearshape", destination: .window)
                }
                guard let item = actionItems.first(where: { $0.id == entry.actionID }), item.module.enabled else { return nil }
                return TalosAction(id: "\(entry.id)/\(item.action.id)", title: entry.customTitle ?? item.action.localizedTitle,
                    symbol: item.action.symbol, destination: .window)
            })
        }
        return preview(wheelEntries)
    }

    func actions(for files: [ModuleFile]) -> [TalosAction] {
        resolve(wheelEntries, files: files)
    }

    private func resolve(_ entries: [WheelEntry], files: [ModuleFile]) -> [TalosAction] {
        paginate(entries.compactMap { entry in
            if let children = entry.children {
                let actions = resolve(children, files: files)
                guard !actions.isEmpty else { return nil }
                let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "FOLDER" : entry.title
                return TalosAction(id: entry.id, title: title, symbol: "folder", destination: .submenu(actions))
            }
            if entry.actionID == Self.settingsActionID {
                return TalosAction(id: entry.id, title: entry.customTitle ?? String(localized: "Settings"), symbol: "gearshape", destination: .handler { [weak self] _ in
                    self?.openSettings()
                })
            }
            guard let item = actionItems.first(where: { $0.id == entry.actionID }), item.module.enabled,
                  let action = item.action.filtered(for: files) else { return nil }
            var mapped = map(action, module: item.module, placementID: entry.id, settings: entry.settings ?? [:])
            if let title = entry.customTitle, !title.isEmpty {
                mapped = TalosAction(id: mapped.id, title: title, symbol: mapped.symbol, destination: mapped.destination)
            }
            return mapped
        })
    }

    private func map(_ action: ModuleAction, module: InstalledModule, placementID: String, settings: [String: String]) -> TalosAction {
        let destination: TalosAction.Destination
        if let children = action.children {
            destination = .submenu(paginate(children.map { map($0, module: module, placementID: placementID, settings: settings) }))
        } else {
            destination = .handler { [weak self] urls in
                Task {
                    guard let self, self.snapshot.installed.contains(where: { $0.id == module.id && $0.enabled }) else { return }
                    let files = await FileInspector().inspect(urls)
                    guard action.matches(files) else { self.error = "These files no longer match this action"; return }
                    do {
                        let secrets = (action.settings ?? []).contains(where: { $0.type == .password })
                            ? try await TileCredentials().load(placementID) : [:]
                        let defaults = Dictionary(uniqueKeysWithValues: (action.settings ?? []).compactMap { field in
                            field.defaultValue.map { (field.id, $0) }
                        })
                        let values = defaults.merging(settings) { _, new in new }.merging(secrets) { _, new in new }
                        await self.tasks.run(module: module, action: action.id, files: files, settings: values)
                    } catch { self.error = error.localizedDescription }
                }
            }
        }
        return TalosAction(id: "\(placementID)/\(action.id)", title: action.localizedTitle, symbol: action.symbol, destination: destination)
    }
    private func paginate(_ items: [TalosAction]) -> [TalosAction] {
        guard items.count > 8 else { return items }
        return Array(items.prefix(7)) + [TalosAction(id: "more.\(items.count)", title: String(localized: "More"), symbol: "ellipsis", destination: .submenu(paginate(Array(items.dropFirst(7)))))]
    }
    private func save() async throws { try await store.save(snapshot) }
    private func perform(_ action: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        let previous = snapshot
        defer { isBusy = false }
        do { try await action() }
        catch { snapshot = previous; self.error = error.localizedDescription }
    }

}
