import Foundation

nonisolated struct InstalledModule: Codable, Identifiable, Sendable {
    let id: UUID
    var sourceID: UUID?
    let manifest: ModuleManifest
    var directory: URL
    var enabled: Bool
    var isBundled: Bool?
}
