import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}

struct Redaction: Decodable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

let arguments = CommandLine.arguments
let redacting = arguments.count == 6 && arguments[3] == "redact"
let normalizing = arguments.count == 4 && arguments[3] == "normalize"
guard normalizing || redacting || arguments.count == 8 else { fail("Invalid image request") }
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let format = normalizing ? "png" : arguments[redacting ? 5 : 7]
guard let type = format == "png" ? UTType.png : format == "jpg" ? UTType.jpeg : nil else {
    fail("Unsupported output format")
}
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
      let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
    fail("Cannot open image")
}

// ImageIO applies EXIF orientation before crop coordinates from the displayed preview.
let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight)
]
guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
    fail("Cannot decode image")
}

var result: CGImage
let width: Int
let height: Int
if normalizing {
    width = image.width
    height = image.height
    // WebP assumes sRGB unless it carries an ICC profile. Bake orientation and convert
    // wide-gamut/CMYK inputs to sRGB before the extension's WebP encoder sees the pixels.
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("Cannot normalize image")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let normalized = context.makeImage() else { fail("Cannot normalize image") }
    result = normalized
} else if redacting {
    guard let rectangles = try? JSONDecoder().decode([Redaction].self, from: Data(arguments[4].utf8)),
          !rectangles.isEmpty,
          rectangles.allSatisfy({ $0.x >= 0 && $0.y >= 0 && $0.width > 0 && $0.height > 0 &&
              $0.x <= image.width && $0.y <= image.height &&
              $0.width <= image.width - $0.x && $0.height <= image.height - $0.y }) else {
        fail("Redaction extends outside the image")
    }
    width = image.width
    height = image.height
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("Cannot create redacted image")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    context.setShouldAntialias(false)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    for rect in rectangles {
        // Preview coordinates start at the top; CoreGraphics starts at the bottom.
        context.fill(CGRect(x: rect.x, y: height - rect.y - rect.height, width: rect.width, height: rect.height))
    }
    guard let redacted = context.makeImage() else { fail("Cannot create redacted image") }
    result = redacted
} else {
    guard let x = Int(arguments[3]), let y = Int(arguments[4]),
          let cropWidth = Int(arguments[5]), let cropHeight = Int(arguments[6]),
          x >= 0, y >= 0, cropWidth > 0, cropHeight > 0,
          x <= image.width, y <= image.height,
          cropWidth <= image.width - x, cropHeight <= image.height - y,
          let cropped = image.cropping(to: CGRect(x: x, y: y, width: cropWidth, height: cropHeight)) else {
        fail("Crop extends outside the image")
    }
    result = cropped
    width = cropWidth
    height = cropHeight
}

if format == "jpg" {
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fail("Cannot create JPEG image")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(result, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let flattened = context.makeImage() else { fail("Cannot create JPEG image") }
    result = flattened
}

guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
    fail("Cannot create output image")
}
let destinationOptions: [CFString: Any] = format == "jpg" ? [kCGImageDestinationLossyCompressionQuality: 0.95] : [:]
CGImageDestinationAddImage(destination, result, destinationOptions as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fail("Cannot write output image") }
