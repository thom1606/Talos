import AppIntents
import Foundation
import UniformTypeIdentifiers

struct TalosTileEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Talos Tile")
    static let defaultQuery = TalosTileQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct TalosTileQuery: EntityQuery {
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    func entities(for identifiers: [TalosTileEntity.ID]) async throws -> [TalosTileEntity] {
        let ids = Set(identifiers)
        return await suggestedEntities().filter { ids.contains($0.id) }
    }

    func suggestedEntities() async -> [TalosTileEntity] {
        guard let app = await AppDelegate.current else { return [] }
        return await app.shortcutTiles().map { TalosTileEntity(id: $0.id, name: $0.title) }
    }
}

struct RunTalosTileIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Talos Tile"
    static let description = IntentDescription("Run a tile from your Talos wheel with files from Shortcuts.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Tile") var tile: TalosTileEntity
    @Parameter(title: "Files", supportedContentTypes: [.item]) var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$tile) with \(\.$files)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !files.isEmpty else { throw TalosShortcutError.noFiles }
        guard let app = await AppDelegate.current else { throw TalosShortcutError.appUnavailable }

        let urls = files.compactMap(\.fileURL)
        guard urls.count == files.count else { throw TalosShortcutError.unreadableFiles }
        let scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

        let inspected = await DraggedFileInspector().inspect(urls)
        guard inspected.count == urls.count else { throw TalosShortcutError.unreadableFiles }
        try await app.runShortcutTile(id: tile.id, files: inspected)
        return .result(dialog: "Ran \(tile.name) in Talos.")
    }
}

private enum TalosShortcutError: LocalizedError {
    case noFiles
    case unreadableFiles
    case appUnavailable

    var errorDescription: String? {
        switch self {
        case .noFiles: "Choose at least one file to run this tile."
        case .unreadableFiles: "Talos could not read all of the selected files."
        case .appUnavailable: "Talos is not ready yet. Open Talos and try again."
        }
    }
}
