import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}

guard CommandLine.arguments.count == 8,
      let x = Int(CommandLine.arguments[3]),
      let y = Int(CommandLine.arguments[4]),
      let width = Int(CommandLine.arguments[5]),
      let height = Int(CommandLine.arguments[6]),
      x >= 0, y >= 0, width > 0, height > 0 else {
    fail("Invalid crop request")
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let format = CommandLine.arguments[7]
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
guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
      x <= image.width, y <= image.height,
      width <= image.width - x, height <= image.height - y,
      let cropped = image.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else {
    fail("Crop extends outside the image")
}

var result = cropped
if format == "jpg" {
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fail("Cannot create JPEG image")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let flattened = context.makeImage() else { fail("Cannot create JPEG image") }
    result = flattened
}

guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
    fail("Cannot create output image")
}
let destinationOptions: [CFString: Any] = format == "jpg" ? [kCGImageDestinationLossyCompressionQuality: 0.95] : [:]
CGImageDestinationAddImage(destination, result, destinationOptions as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fail("Cannot write output image") }
