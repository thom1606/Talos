import AppKit
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
    private var extensions: [LoadedExtension] = []

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
        self.extensions = extensions
    }

    func shortcutTiles() -> [ShortcutTile] {
        let commands = extensions.reduce(into: [String: (LoadedExtension, ExtensionCommand)]()) {
            result, loaded in
            for command in loaded.manifest.commands {
                result["\(loaded.id).\(command.name)"] = (loaded, command)
            }
        }

        func options(for command: ExtensionCommand, in loaded: LoadedExtension) -> [(String, ExtensionCommand)] {
            (command.subcommands ?? []).compactMap { name in
                guard let child = loaded.manifest.commands.first(where: { $0.name == name }),
                      child.subcommands?.isEmpty != false else { return nil }
                return (name, child)
            }
        }

        func collect(_ items: [WheelItem], prefix: String = "") -> [ShortcutTile] {
            items.flatMap { item -> [ShortcutTile] in
                if let children = item.children {
                    let folder = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return collect(children, prefix: prefix + (folder.map { "\($0) / " } ?? ""))
                }
                guard let actionID = item.actionID,
                      let (loaded, command) = commands[actionID] else { return [] }
                let title = prefix + displayTitle(for: item, fallback: command.displayName)
                let subcommands = options(for: command, in: loaded)
                if !subcommands.isEmpty {
                    return subcommands.map { name, child in
                        ShortcutTile(id: "\(item.id.uuidString)/\(name)",
                                     title: "\(title) / \(child.displayName)",
                                     tile: Tile(id: item.id, extensionBundleID: loaded.id,
                                                action: name, config: item.config),
                                     command: child)
                    }
                }
                return [ShortcutTile(id: item.id.uuidString, title: title,
                                     tile: Tile(id: item.id, extensionBundleID: loaded.id,
                                                action: command.name, config: item.config),
                                     command: command)]
            }
        }

        func actionIDs(in items: [WheelItem]) -> [String] {
            items.flatMap { item in
                if let children = item.children { return actionIDs(in: children) }
                return item.actionID.map { [$0] } ?? []
            }
        }

        let configured = collect(WheelConfigurationStore.load().items)
        let configuredActions = Set(actionIDs(in: WheelConfigurationStore.load().items))
        let referencedSubcommands = Set(extensions.flatMap { loaded in
            loaded.manifest.commands.flatMap { $0.subcommands ?? [] }.map { "\(loaded.id).\($0)" }
        })
        let available = extensions.flatMap { loaded in
            loaded.manifest.commands.flatMap { command -> [ShortcutTile] in
                let actionID = "\(loaded.id).\(command.name)"
                guard !configuredActions.contains(actionID), !referencedSubcommands.contains(actionID) else {
                    return []
                }
                let subcommands = options(for: command, in: loaded)
                if !subcommands.isEmpty {
                    return subcommands.map { name, child in
                        ShortcutTile(id: "\(actionID)/\(name)",
                                     title: "\(command.displayName) / \(child.displayName)",
                                     tile: Tile(id: UUID(), extensionBundleID: loaded.id,
                                                action: name, config: [:]), command: child)
                    }
                }
                return [ShortcutTile(id: actionID, title: command.displayName,
                                     tile: Tile(id: UUID(), extensionBundleID: loaded.id,
                                                action: command.name, config: [:]), command: command)]
            }
        }
        return configured + available
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

    func actions(for files: [DraggedFile]) -> [WheelAction] {
        let commands = extensions.reduce(into: [String: (LoadedExtension, ExtensionCommand)]()) {
            result, loadedExtension in
            for command in loadedExtension.manifest.commands {
                result["\(loadedExtension.id).\(command.name)"] = (loadedExtension, command)
            }
        }

        return WheelConfigurationStore.load().items.compactMap { item in
            action(from: item, commands: commands, files: files)
        }
    }

    func perform(_ action: WheelAction, files: [DraggedFile]) {
        switch action.destination {
        case .settings:
            openSettings()
        case let .folder(children):
            guard !children.isEmpty else { return }
        case let .extensionAction(tile):
            Task {
                do {
                    let configuredTile = try configured(tile)
                    try await runtime.activate(tile: configuredTile, files: files.map { .init(path: $0.url.path, name: $0.url.lastPathComponent, contentType: $0.contentType.identifier, accessURL: $0.url) })
                } catch {
                    reportError(error.localizedDescription)
                }
            }
        }
    }

    func prepare(_ action: WheelAction) {
        guard case let .extensionAction(tile) = action.destination else { return }
        Task {
            // Activation reports any real startup failure if the user actually drops.
            try? await runtime.prepare(bundleID: tile.extensionBundleID)
        }
    }

    private func action(
        from item: WheelItem,
        commands: [String: (LoadedExtension, ExtensionCommand)],
        files: [DraggedFile]
    ) -> WheelAction? {
        if let children = item.children {
            let matchingChildren = children.compactMap {
                action(from: $0, commands: commands, files: files)
            }
            guard children.isEmpty || !matchingChildren.isEmpty else { return nil }
            return WheelAction(
                id: item.id,
                title: displayTitle(for: item, fallback: String(localized: "Folder")),
                symbolName: "folder",
                destination: .folder(matchingChildren)
            )
        }

        guard let actionID = item.actionID else { return nil }
        if actionID == "talos.system.settings" {
            return WheelAction(
                id: item.id,
                title: displayTitle(for: item, fallback: String(localized: "Settings")),
                symbolName: "gearshape",
                destination: .settings
            )
        }

        guard let (loadedExtension, command) = commands[actionID], command.supports(files) else {
            return nil
        }

        return extensionAction(command, in: loadedExtension, id: item.id,
                               title: displayTitle(for: item, fallback: command.displayName),
                               files: files, config: item.config)
    }

    private func extensionAction(_ command: ExtensionCommand, in loaded: LoadedExtension,
                                 id: UUID, title: String? = nil, files: [DraggedFile],
                                 config: [String: TileConfigValue] = [:]) -> WheelAction? {
        guard command.supports(files) else { return nil }
        if let names = command.subcommands {
            let children = names.compactMap { name -> WheelAction? in
                guard let child = loaded.manifest.commands.first(where: { $0.name == name }) else { return nil }
                return extensionAction(child, in: loaded, id: UUID(), files: files)
            }
            guard !children.isEmpty else { return nil }
            return WheelAction(id: id, title: title ?? command.displayName, symbolName: resolvedSymbolName(command.icon),
                               destination: .folder(children))
        }
        return WheelAction(id: id, title: title ?? command.displayName, symbolName: resolvedSymbolName(command.icon),
                           destination: .extensionAction(Tile(id: id, extensionBundleID: loaded.id,
                                                              action: command.name, config: config)))
    }

    private func configured(_ tile: Tile) throws -> Tile {
        guard let command = extensions.first(where: { $0.id == tile.extensionBundleID })?
            .manifest.commands.first(where: { $0.name == tile.action }) else { return tile }
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

    private func displayTitle(for item: WheelItem, fallback: String) -> String {
        let customTitle = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }

        return fallback
    }

    private func resolvedSymbolName(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "" }
        guard NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else {
            return "questionmark"
        }
        return name
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
        guard !files.isEmpty else { return false }
        if supportedFileTypes.contains("*") { return true }

        return files.allSatisfy { file in
            supportedFileTypes.contains { identifier in
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
