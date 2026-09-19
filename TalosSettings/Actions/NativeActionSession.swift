import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor final class NativeActionSession {
    static let current: NativeActionSession? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--action-request"), args.indices.contains(index + 1) else { return nil }
        return try? NativeActionSession(file: URL(fileURLWithPath: args[index + 1]))
    }()
    let request: NativeActionRequest
    private let response: URL
    private var finished = false
    init(file: URL) throws {
        request = try JSONDecoder().decode(NativeActionRequest.self, from: Data(contentsOf: file))
        guard UUID(uuidString: request.id) != nil else { throw CocoaError(.fileReadCorruptFile) }
        response = file.deletingLastPathComponent().appendingPathComponent(request.id + ".response.json")
    }
    func image() throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: request.input) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { throw CocoaError(.fileReadCorruptFile) }
        let size = max(properties[kCGImagePropertyPixelWidth] as? Int ?? 1, properties[kCGImagePropertyPixelHeight] as? Int ?? 1)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }
    func save(_ image: CGImage, to output: URL) throws {
        // Exclusive creation prevents an existing file from being overwritten.
        let descriptor = open(output.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteFileExists) }
        close(descriptor)
        do {
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(destination, image, [:] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            try PNGMetadataStripper.strip(output)
        } catch { try? FileManager.default.removeItem(at: output); throw error }
    }
    func processImage() {
        do {
            guard let output = request.output else { throw CocoaError(.fileWriteInvalidFileName) }
            try save(image(), to: URL(fileURLWithPath: output))
            finish(output: output)
        } catch { finish(error: error.localizedDescription) }
    }
    func saveCrop(_ image: CGImage) throws -> String {
        let input = URL(fileURLWithPath: request.input)
        for number in 1...9999 {
            let name = input.deletingPathExtension().lastPathComponent + "-cropped" + (number == 1 ? "" : " \(number)") + ".png"
            let output = input.deletingLastPathComponent().appendingPathComponent(name)
            do { try save(image, to: output); return output.path }
            catch let error as CocoaError where error.code == .fileWriteFileExists { continue }
        }
        throw CocoaError(.fileWriteFileExists)
    }
    func finish(output: String? = nil, error: String? = nil) {
        guard !finished else { return }
        var result: [String: String] = [:]
        if let output { result["output"] = output }
        if let error { result["error"] = error }
        do {
            try JSONEncoder().encode(result).write(to: response, options: .atomic)
            finished = true
        } catch { NSLog("Cannot deliver action result: %@", error.localizedDescription) }
    }
}
