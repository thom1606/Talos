import Foundation
import UniformTypeIdentifiers

nonisolated public struct ModuleAction: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let symbol: String?
    public let acceptedTypes: [String]
    public let minimumFiles: Int
    public let maximumFiles: Int?
    public let children: [ModuleAction]?
    public var settings: [ActionSetting]? = nil
    public var translations: [String: String]? = nil

    public var localizedTitle: String {
        translations?[Locale.current.language.languageCode?.identifier ?? "en"] ?? title
    }

    public func matches(_ files: [ModuleFile]) -> Bool {
        guard files.count >= minimumFiles, maximumFiles.map({ files.count <= $0 }) ?? true else { return false }
        return files.allSatisfy { file in
            acceptedTypes.contains { accepted in
                if accepted == "public.folder" { return file.isDirectory && !file.isPackage }
                guard !file.isDirectory,
                      let type = UTType(file.typeIdentifier), let expected = UTType(accepted) else { return false }
                return type.conforms(to: expected) || Self.knownConformance[file.typeIdentifier]?.contains(accepted) == true
            }
        }
    }

    public func filtered(for files: [ModuleFile]) -> ModuleAction? {
        guard matches(files) else { return nil }
        guard let children else { return self }
        let matching = children.compactMap { $0.filtered(for: files) }
        guard !matching.isEmpty else { return nil }
        return ModuleAction(id: id, title: title, symbol: symbol, acceptedTypes: acceptedTypes,
                            minimumFiles: minimumFiles, maximumFiles: maximumFiles, children: matching, settings: settings, translations: translations)
    }

    // SwiftPM's command-line test host does not always have LaunchServices' UTI
    // hierarchy available. Keep the common leaf-to-category relationships
    // deterministic there as well as when a module is tested outside Finder.
    private static let knownConformance: [String: Set<String>] = [
        "public.png": ["public.image", "public.data", "public.item"],
        "public.jpeg": ["public.image", "public.data", "public.item"],
        "public.gif": ["public.image", "public.data", "public.item"],
        "public.tiff": ["public.image", "public.data", "public.item"],
        "public.heic": ["public.image", "public.data", "public.item"],
        "public.heif": ["public.image", "public.data", "public.item"],
        "public.mpeg-4": ["public.movie", "public.data", "public.item"],
        "com.apple.quicktime-movie": ["public.movie", "public.data", "public.item"],
        "public.plain-text": ["public.text", "public.data", "public.item"],
        "public.utf8-plain-text": ["public.plain-text", "public.text", "public.data", "public.item"],
        "public.rtf": ["public.text", "public.data", "public.item"]
    ]
}
