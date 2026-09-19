import Foundation

/// A placement has its own identity, so actions may appear more than once.
nonisolated struct WheelEntry: Codable, Identifiable, Sendable, Equatable {
    var id = UUID().uuidString
    var actionID: String?
    var title: String = "Folder"
    var children: [WheelEntry]?
    var customTitle: String?
    var settings: [String: String]?

    static func action(_ id: String) -> Self { Self(actionID: id) }
    static func folder(_ title: String) -> Self { Self(title: title, children: []) }

    static func entries(in entries: [Self], path: [String]) -> [Self] {
        guard let first = path.first else { return entries }
        guard let folder = entries.first(where: { $0.id == first }), let children = folder.children else { return [] }
        return Self.entries(in: children, path: Array(path.dropFirst()))
    }

    static func replace(in entries: inout [Self], path: [String], with replacement: [Self]) {
        guard let first = path.first else { entries = replacement; return }
        guard let index = entries.firstIndex(where: { $0.id == first }), var children = entries[index].children else { return }
        replace(in: &children, path: Array(path.dropFirst()), with: replacement)
        entries[index].children = children
    }
}
