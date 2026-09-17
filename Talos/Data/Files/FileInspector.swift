import Foundation
import UniformTypeIdentifiers
import TalosSDK

actor FileInspector {
    func inspect(_ urls: [URL]) -> [ModuleFile] {
        urls.map { url in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey])
            let directory = values?.isDirectory == true
            let type = values?.contentType ?? (directory ? .folder : UTType(filenameExtension: url.pathExtension) ?? .data)
            return ModuleFile(url: url, typeIdentifier: type.identifier, isDirectory: directory, isPackage: values?.isPackage == true)
        }
    }
}
