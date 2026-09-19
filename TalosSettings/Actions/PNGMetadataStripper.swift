import Foundation

/// ImageIO adds an EXIF block even when source metadata is omitted. Keep only pixels,
/// transparency and colour-rendering chunks in the newly encoded PNG.
nonisolated enum PNGMetadataStripper {
    static func strip(_ file: URL) throws {
        let data = try Data(contentsOf: file)
        let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        guard data.starts(with: signature) else { throw CocoaError(.fileReadCorruptFile) }
        let retained: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND", "tRNS", "sRGB", "gAMA", "cHRM", "iCCP"]
        var output = signature
        var offset = signature.count
        while offset < data.count {
            guard data.count - offset >= 12 else { throw CocoaError(.fileReadCorruptFile) }
            let length = data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= data.count - offset - 12 else { throw CocoaError(.fileReadCorruptFile) }
            let end = offset + 12 + length
            let kind = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if retained.contains(kind) { output.append(data[offset..<end]) }
            offset = end
        }
        try output.write(to: file, options: .atomic)
    }
}
