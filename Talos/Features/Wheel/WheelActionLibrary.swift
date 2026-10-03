import Foundation
import UniformTypeIdentifiers

@MainActor
final class WheelActionLibrary {
    struct ShortcutTile {
        let id: String
        let title: String
        let tile: Tile
        let command: ExtensionCommand
    }

    private let runtime: SDKRuntime
    private let openSettings: () -> Void
    private let reportError: (String) -> Void
    private struct Catalog {
        let loaded: LoadedExtension
        let index: ExtensionCommandIndex
    }

    private var catalogs: [Catalog] = []
    private var commands: [String: (Catalog, ExtensionCommand)] = [:]

    init(
        runtime: SDKRuntime,
        openSettings: @escaping () -> Void,
        reportError: @escaping (String) -> Void
    ) {
        self.runtime = runtime
        self.openSettings = openSettings
        self.reportError = reportError
    }

    func update(extensions: [LoadedExtension]) {
        catalogs = extensions.map { Catalog(loaded: $0, index: ExtensionCommandIndex($0.manifest.commands)) }
        commands = catalogs.reduce(into: [:]) { result, catalog in
            for command in catalog.loaded.manifest.commands {
                result["\(catalog.loaded.id).\(command.name)"] = (catalog, command)
                _ = WheelActionPresentation.symbol(command.icon, missing: "")
            }
        }
    }

    func shortcutTiles() -> [ShortcutTile] {
        var configuredActions = Set<String>()
        func collect(_ items: [WheelItem], prefix: String = "") -> [ShortcutTile] {
            items.flatMap { item -> [ShortcutTile] in
                if let children = item.children {
                    let folder = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return collect(children, prefix: prefix + (folder.map { "\($0) / " } ?? ""))
                }
                guard let actionID = item.actionID else { return [] }
                configuredActions.insert(actionID)
                guard let (catalog, command) = commands[actionID] else { return [] }
                return shortcuts(for: command, in: catalog, item: item,
                                 title: prefix + WheelActionPresentation.title(for: item, fallback: command.displayName))
            }
        }

        let configured = collect(WheelConfigurationStore.load().allItems)
        let available = catalogs.flatMap { catalog in
            catalog.index.roots.flatMap { command -> [ShortcutTile] in
                guard !configuredActions.contains("\(catalog.loaded.id).\(command.name)") else { return [] }
                return shortcuts(for: command, in: catalog)
            }
        }
        return configured + available
    }

    private func shortcuts(for command: ExtensionCommand, in catalog: Catalog,
                           item: WheelItem? = nil, title: String? = nil) -> [ShortcutTile] {
        let options = catalog.index.children(of: command).filter { $0.subcommands?.isEmpty != false }
        let baseID = item?.id.uuidString ?? "\(catalog.loaded.id).\(command.name)"
        let title = title ?? command.displayName
        return (options.isEmpty ? [command] : options).map { child in
            let isChild = child.name != command.name
            return ShortcutTile(
                id: baseID + (isChild ? "/\(child.name)" : ""),
                title: title + (isChild ? " / \(child.displayName)" : ""),
                tile: Tile(id: item?.id ?? UUID(), extensionBundleID: catalog.loaded.id,
                           action: child.name, config: item?.config ?? [:]),
                command: child
            )
        }
    }

    func performShortcutTile(id: String, files: [DraggedFile]) async throws {
        guard let tile = shortcutTiles().first(where: { $0.id == id }) else {
            throw ShortcutTileError.unavailable
        }
        guard tile.command.supports(files) else {
            throw ShortcutTileError.unsupportedFiles(tile.title)
        }
        let configuredTile = try configured(tile.tile)
        try await runtime.activateAndWait(
            tile: configuredTile,
            files: files.map { .init(path: $0.url.path, name: $0.url.lastPathComponent,
                               contentType: $0.contentType.identifier, accessURL: $0.url) }
        )
    }

    func actions(for files: [DraggedFile]) -> [WheelKind: [WheelAction]] {
        let configuration = WheelConfigurationStore.load()
        return Dictionary(uniqueKeysWithValues: WheelKind.allCases.map { wheel in
            (wheel, configuration.items(for: wheel).compactMap { action(from: $0, files: files) })
        })
    }

    func perform(_ action: WheelAction, files: [DraggedFile]) {
        switch action.destination {
        case .settings:
            openSettings()
        case let .folder(children):
            guard !children.isEmpty else { return }
        case let .extensionAction(tile):
            guard action.isEnabled else { return }
            Task {
                do {
                    let configuredTile = try configured(tile)
                    let selected = files.filter { action.fileURLs.contains($0.url) }
                    guard !selected.isEmpty else { return }
                    try await runtime.activate(tile: configuredTile, files: selected.map { .init(path: $0.url.path, name: $0.url.lastPathComponent, contentType: $0.contentType.identifier, accessURL: $0.url) })
                } catch {
                    reportError(error.localizedDescription)
                }
            }
        }
    }

    func prepare(_ action: WheelAction) {
        guard case let .extensionAction(tile) = action.destination else { return }
        let bundleID = tile.extensionBundleID
        Task { @concurrent [runtime] in
            // Activation reports any real startup failure if the user actually drops.
            try? await runtime.prepare(bundleID: bundleID)
        }
    }

    private func action(
        from item: WheelItem,
        files: [DraggedFile]
    ) -> WheelAction? {
        if let children = item.children {
            let matchingChildren = children.compactMap {
                action(from: $0, files: files)
            }
            return WheelAction(
                id: item.id,
                title: WheelActionPresentation.title(for: item, fallback: String(localized: "Folder")),
                symbolName: "folder",
                destination: .folder(matchingChildren),
                isEnabled: matchingChildren.contains(where: \.isEnabled)
            )
        }

        guard let actionID = item.actionID else { return nil }
        if actionID == "talos.system.settings" {
            return WheelAction(
                id: item.id,
                title: WheelActionPresentation.title(for: item, fallback: String(localized: "Settings")),
                symbolName: "gearshape",
                destination: .settings
            )
        }

        guard let (catalog, command) = commands[actionID] else {
            return nil
        }

        return extensionAction(command, in: catalog, id: item.id,
                               title: WheelActionPresentation.title(for: item, fallback: command.displayName),
                               files: files, config: item.config)
    }

    private func extensionAction(_ command: ExtensionCommand, in catalog: Catalog,
                                 id: UUID, title: String? = nil, files: [DraggedFile],
                                 config: [String: TileConfigValue] = [:]) -> WheelAction? {
        let matchingFiles = command.matchingFiles(in: files)
        if command.subcommands != nil {
            let subcommands = catalog.index.children(of: command)
            let groups = Dictionary(grouping: matchingFiles, by: { $0.category })
            if groups.count > 1 {
                let children = DraggedFile.Category.allCases.compactMap { category -> WheelAction? in
                    guard let groupFiles = groups[category], !groupFiles.isEmpty else { return nil }
                    let options = subcommands.compactMap { child -> WheelAction? in
                        guard !child.matchingFiles(in: groupFiles).isEmpty else { return nil }
                        return extensionAction(child, in: catalog, id: UUID(), files: groupFiles)
                    }
                    return WheelAction(id: UUID(), title: "\(category.title) (\(groupFiles.count))",
                                       symbolName: category.symbolName, destination: .folder(options),
                                       isEnabled: options.contains(where: \.isEnabled))
                }
                return WheelAction(id: id, title: title ?? command.displayName,
                                   symbolName: WheelActionPresentation.symbol(command.icon, missing: ""), destination: .folder(children),
                                   isEnabled: children.contains(where: \.isEnabled))
            }
            let children = subcommands.compactMap { child -> WheelAction? in
                guard !child.matchingFiles(in: matchingFiles).isEmpty else { return nil }
                return extensionAction(child, in: catalog, id: UUID(), files: matchingFiles)
            }
            return WheelAction(id: id, title: title ?? command.displayName, symbolName: WheelActionPresentation.symbol(command.icon, missing: ""),
                               destination: .folder(children),
                               isEnabled: children.contains(where: \.isEnabled))
        }
        return WheelAction(id: id, title: title ?? command.displayName, symbolName: WheelActionPresentation.symbol(command.icon, missing: ""),
                           destination: .extensionAction(Tile(id: id, extensionBundleID: catalog.loaded.id,
                                                              action: command.name, config: config)),
                           fileURLs: matchingFiles.map(\.url),
                           isEnabled: !matchingFiles.isEmpty)
    }

    private func configured(_ tile: Tile) throws -> Tile {
        guard let (_, command) = commands["\(tile.extensionBundleID).\(tile.action)"] else { return tile }
        var configuredTile = tile
        let settings = command.settings ?? []
        let passwords = settings.contains(where: { $0.type == .password })
            ? try ActionSettingSecretStore().passwords(for: tile.id) : [:]
        for setting in settings {
            if setting.type == .password {
                if let password = passwords[setting.name] {
                    configuredTile.config[setting.name] = .string(password)
                }
            } else if configuredTile.config[setting.name] == nil {
                configuredTile.config[setting.name] = setting.defaultValue
            }
        }
        for setting in settings {
            if setting.required == true {
                guard let value = configuredTile.config[setting.name] else {
                    throw WheelActionConfigurationError.missing(setting.displayName)
                }
                if case let .string(text) = value, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw WheelActionConfigurationError.missing(setting.displayName)
                }
            }
        }
        return configuredTile
    }

}

private enum ShortcutTileError: LocalizedError {
    case unavailable
    case unsupportedFiles(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "This tile is no longer available in Talos."
        case let .unsupportedFiles(title): "The selected files are not supported by \(title)."
        }
    }
}

private extension ExtensionCommand {
    func supports(_ files: [DraggedFile]) -> Bool {
        !files.isEmpty && matchingFiles(in: files).count == files.count
    }

    func matchingFiles(in files: [DraggedFile]) -> [DraggedFile] {
        files.filter { file in
            supportedFileTypes.contains { identifier in
                if identifier == "*" { return true }
                if identifier.hasPrefix(".") {
                    return !file.contentType.conforms(to: .folder) &&
                        file.url.lastPathComponent.lowercased().hasSuffix(identifier.lowercased())
                }
                guard let supportedType = UTType(identifier) else { return false }
                return file.contentType.conforms(to: supportedType)
            }
        }
    }
}

private enum WheelActionConfigurationError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case let .missing(name): "Set \(name) in this action's settings first."
        }
    }
}
