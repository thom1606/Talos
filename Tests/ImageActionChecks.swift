import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct ImageActionChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.jpg")
        let output = root.appendingPathComponent("clean.png")
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(original as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Private comment"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 52.0, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        let originalBytes = try Data(contentsOf: original)
        let request = NativeActionRequest(id: UUID().uuidString, kind: "image", input: original.path, output: output.path, stripMetadata: true)
        let requestURL = root.appendingPathComponent("request.json")
        try JSONEncoder().encode(request).write(to: requestURL)
        let session = try NativeActionSession(file: requestURL)
        session.processImage()
        let result = CGImageSourceCreateWithURL(output as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(result, 0, nil) as! [CFString: Any]
        precondition(properties[kCGImagePropertyExifDictionary] == nil)
        precondition(properties[kCGImagePropertyGPSDictionary] == nil)
        precondition(properties[kCGImagePropertyPixelWidth] as? Int == 40)
        let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: 20, height: 15))!
        let first = try session.saveCrop(cropped)
        let second = try session.saveCrop(cropped)
        precondition(first != second)
        let cropSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: first) as CFURL, nil)!
        let cropProperties = CGImageSourceCopyPropertiesAtIndex(cropSource, 0, nil) as! [CFString: Any]
        precondition(cropProperties[kCGImagePropertyPixelWidth] as? Int == 20)
        precondition(cropProperties[kCGImagePropertyPixelHeight] as? Int == 15)
        let originalAfter = try Data(contentsOf: original)
        precondition(originalAfter == originalBytes)
        print("Passed: real image metadata removal, crop dimensions, unique output names and original preservation")
    }
}
