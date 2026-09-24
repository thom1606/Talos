import AppKit
import Foundation
import PDFKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3,
      let document = PDFDocument(url: URL(fileURLWithPath: arguments[2])),
      document.pageCount > 0 else {
    fail("Cannot open PDF or the PDF has no pages")
}
guard !document.isLocked else { fail("Password-protected PDFs must be unlocked before conversion") }

switch arguments[1] {
case "render":
    guard arguments.count == 5, ["png", "jpg"].contains(arguments[4]) else {
        fail("Usage: pdf-tool render input.pdf output-directory png|jpg")
    }
    let directory = URL(fileURLWithPath: arguments[3], isDirectory: true)
    let fileType: NSBitmapImageRep.FileType = arguments[4] == "jpg" ? .jpeg : .png
    for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { fail("Cannot read PDF page \(index + 1)") }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
            fail("Invalid size on PDF page \(index + 1)")
        }
        let scale = min(2.0, 8192.0 / max(bounds.width, bounds.height))
        let width = max(1, Int(ceil(bounds.width * scale)))
        let height = max(1, Int(ceil(bounds.height * scale)))
        let thumbnail = page.thumbnail(of: NSSize(width: width, height: height), for: .cropBox)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fail("Cannot render PDF page \(index + 1)")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        thumbnail.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                       from: .zero, operation: .sourceOver, fraction: 1)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let properties: [NSBitmapImageRep.PropertyKey: Any] = fileType == .jpeg
            ? [.compressionFactor: 0.9] : [:]
        guard let data = bitmap.representation(using: fileType, properties: properties) else {
            fail("Cannot encode PDF page \(index + 1)")
        }
        let destination = directory.appendingPathComponent("page-\(index + 1).\(arguments[4])")
        do { try data.write(to: destination, options: .atomic) }
        catch { fail("Cannot save PDF page \(index + 1): \(error.localizedDescription)") }
    }
    print(document.pageCount)
case "text":
    let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
    guard let data = try? JSONSerialization.data(withJSONObject: pages),
          let json = String(data: data, encoding: .utf8) else {
        fail("Cannot extract PDF text")
    }
    print(json)
default:
    fail("Unknown PDF operation")
}
