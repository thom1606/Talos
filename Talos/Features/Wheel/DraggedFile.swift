import Foundation
import UniformTypeIdentifiers

nonisolated struct DraggedFile: Sendable {
    let url: URL
    let contentType: UTType

    enum Category: CaseIterable {
        case image, pdf, video, audio, other

        var title: String {
            switch self {
            case .image: String(localized: "Images")
            case .pdf: String(localized: "PDFs")
            case .video: String(localized: "Videos")
            case .audio: String(localized: "Audio")
            case .other: String(localized: "Files")
            }
        }

        var symbolName: String {
            switch self {
            case .image: "photo"
            case .pdf: "doc.richtext"
            case .video: "film"
            case .audio: "waveform"
            case .other: "doc"
            }
        }
    }

    var category: Category {
        if contentType.conforms(to: .folder) { return .other }
        if contentType.conforms(to: .pdf) { return .pdf }
        if contentType.conforms(to: .image) { return .image }
        if contentType.conforms(to: .movie) { return .video }
        if contentType.conforms(to: .audio) { return .audio }
        return .other
    }
}

actor DraggedFileInspector {
    func inspect(_ urls: [URL]) -> [DraggedFile] {
        var files: [DraggedFile] = []
        files.reserveCapacity(urls.count)
        for url in urls {
            // A newer drag should not wait for an obsolete scan of a large selection.
            if Task.isCancelled { break }
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
            files.append(DraggedFile(url: url, contentType: contentType))
        }
        return files
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
