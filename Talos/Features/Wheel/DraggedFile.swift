import Foundation
import UniformTypeIdentifiers

nonisolated struct DraggedFile: Sendable {
    let url: URL
    let contentType: UTType
}

actor DraggedFileInspector {
    func inspect(_ urls: [URL]) -> [DraggedFile] {
        urls.map { url in
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
            let isDirectory = values?.isDirectory == true
            let fallback = Self.fallbackType(for: url.pathExtension, isDirectory: isDirectory)
            let contentType = values?.contentType.flatMap { $0.isDynamic ? nil : $0 } ?? fallback
            return DraggedFile(url: url, contentType: contentType)
        }
    }

    private static func fallbackType(for pathExtension: String, isDirectory: Bool) -> UTType {
        guard !isDirectory else { return .folder }

        switch pathExtension.lowercased() {
        case "txt", "text", "md", "markdown", "csv", "log", "swift", "json", "xml", "yaml", "yml":
            return .plainText
        case "png":
            return .png
        case "jpg", "jpeg":
            return .jpeg
        case "gif":
            return .gif
        case "tif", "tiff":
            return .tiff
        case "heic":
            return .heic
        case "mov":
            return .quickTimeMovie
        case "mp4":
            return .mpeg4Movie
        case "pdf":
            return .pdf
        default:
            return UTType(filenameExtension: pathExtension) ?? .data
        }
    }
}
