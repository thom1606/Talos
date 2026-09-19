import Foundation
import UniformTypeIdentifiers

actor FileInspector {
    func inspect(_ urls: [URL]) -> [ModuleFile] {
        urls.map { url in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey])
            let directory = values?.isDirectory == true
            let fallback = Self.fallbackType(for: url.pathExtension, directory: directory)
            let type = values?.contentType.map { $0.isDynamic ? fallback : $0 } ?? fallback
            return ModuleFile(url: url, typeIdentifier: type.identifier, isDirectory: directory, isPackage: values?.isPackage == true)
        }
    }

    private static func fallbackType(for pathExtension: String, directory: Bool) -> UTType {
        guard !directory else { return .folder }
        switch pathExtension.lowercased() {
        case "txt", "text", "md", "markdown", "csv", "log", "swift", "m", "mm", "h", "c", "cpp", "json", "xml", "yaml", "yml", "html", "htm":
            return .plainText
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "gif": return .gif
        case "tif", "tiff": return .tiff
        case "heic": return .heic
        case "heif": return .heif
        case "mov": return .quickTimeMovie
        case "mp4": return .mpeg4Movie
        default: return UTType(filenameExtension: pathExtension) ?? .data
        }
    }
}
