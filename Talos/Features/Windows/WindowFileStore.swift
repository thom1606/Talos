import Foundation
import UniformTypeIdentifiers

nonisolated enum WindowFileError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { message } else { nil } }
}

/// Type-agnostic I/O, scoped to this window's inputs and a user-approved save destination.
actor WindowFileStore {
    static let chunkSize = 1_024 * 1_024
    struct Info: Sendable {
        let name: String
        let type: String
        let size: Int
    }
    private struct Save {
        let id: String
        let destination: URL
        let directory: URL
        let temporaryFile: URL
        let handle: FileHandle
        let scoped: Bool
        let size: Int
        var written = 0
    }
    private let inputs: [URL]
    private var save: Save?

    init(inputs: [URL]) { self.inputs = inputs }

    func info(index: Int) throws -> Info {
        let url = try input(index)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize else {
            throw WindowFileError.invalid("Select a regular file to read")
        }
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        return Info(name: url.lastPathComponent,
                    type: contentType?.preferredMIMEType ?? "application/octet-stream", size: size)
    }

    func read(index: Int, offset: Int, length: Int, size: Int) throws -> String {
        guard offset >= 0, length > 0, length <= Self.chunkSize, offset <= size, length <= size - offset else {
            throw WindowFileError.invalid("Invalid file range")
        }
        let url = try input(index)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.seekToEnd() == UInt64(size) else { throw WindowFileError.invalid("The input file changed while reading") }
        try handle.seek(toOffset: UInt64(offset))
        let bytes = try handle.read(upToCount: length) ?? Data()
        guard bytes.count == length else { throw WindowFileError.invalid("The input file changed while reading") }
        return bytes.base64EncodedString()
    }

    func beginSave(to destination: URL, size: Int) throws -> String {
        guard save == nil, size >= 0 else { throw WindowFileError.invalid("A save is already in progress or has an invalid size") }
        let scoped = destination.startAccessingSecurityScopedResource()
        var directory: URL?
        do {
            let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                      appropriateFor: destination, create: true)
            directory = folder
            let temporaryFile = folder.appendingPathComponent("output")
            guard FileManager.default.createFile(atPath: temporaryFile.path, contents: nil) else {
                throw WindowFileError.invalid("Cannot create output file")
            }
            let handle = try FileHandle(forWritingTo: temporaryFile)
            let id = UUID().uuidString
            save = Save(id: id, destination: destination, directory: folder, temporaryFile: temporaryFile,
                        handle: handle, scoped: scoped, size: size)
            return id
        } catch {
            if let directory { try? FileManager.default.removeItem(at: directory) }
            if scoped { destination.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    func write(id: String, offset: Int, base64: String) throws {
        guard var current = save, current.id == id,
              offset == current.written, base64.utf8.count <= (Self.chunkSize + 2) / 3 * 4,
              let bytes = Data(base64Encoded: base64), !bytes.isEmpty, bytes.count <= Self.chunkSize,
              bytes.count <= current.size - current.written else {
            throw WindowFileError.invalid("Invalid save chunk")
        }
        try current.handle.write(contentsOf: bytes)
        current.written += bytes.count
        save = current
    }

    func finish(id: String) throws -> String {
        guard let current = save, current.id == id, current.written == current.size else {
            throw WindowFileError.invalid("The output file is incomplete")
        }
        defer { cancel(id: id) }
        try current.handle.synchronize()
        try current.handle.close()
        if FileManager.default.fileExists(atPath: current.destination.path) {
            _ = try FileManager.default.replaceItemAt(current.destination, withItemAt: current.temporaryFile)
        } else {
            try FileManager.default.moveItem(at: current.temporaryFile, to: current.destination)
        }
        return current.destination.lastPathComponent
    }

    func cancel(id: String? = nil) {
        guard let current = save, id == nil || id == current.id else { return }
        save = nil
        try? current.handle.close()
        try? FileManager.default.removeItem(at: current.directory)
        if current.scoped { current.destination.stopAccessingSecurityScopedResource() }
    }

    private func input(_ index: Int) throws -> URL {
        guard inputs.indices.contains(index) else { throw WindowFileError.invalid("Unknown input file") }
        return inputs[index]
    }
}
