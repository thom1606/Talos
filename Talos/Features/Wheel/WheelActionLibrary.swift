import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class WheelActionLibrary {
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
                    try await runtime.activate(tile: tile, files: files.map { .init(path: $0.url.path, name: $0.url.lastPathComponent, contentType: $0.contentType.identifier, accessURL: $0.url) })
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
                               title: displayTitle(for: item, fallback: command.displayName), files: files)
    }

    private func extensionAction(_ command: ExtensionCommand, in loaded: LoadedExtension,
                                 id: UUID, title: String? = nil, files: [DraggedFile]) -> WheelAction? {
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
                           destination: .extensionAction(Tile(extensionBundleID: loaded.id, action: command.name)))
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

private extension ExtensionCommand {
    func supports(_ files: [DraggedFile]) -> Bool {
        guard !files.isEmpty else { return false }
        if supportedFileTypes.contains("*") { return true }

        return files.allSatisfy { file in
            supportedFileTypes.contains { identifier in
                guard let supportedType = UTType(identifier) else { return false }
                return file.contentType.conforms(to: supportedType)
            }
        }
    }
}
