import CryptoKit
import Foundation

// Validate the real release archive with the public key shipped in Talos.
// This also prevents publishing a feed with a missing signature or wrong URL.
let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fatalError("Usage: verify-appcast.swift appcast.xml Talos.zip Info.plist downloadURL")
}
let feed = try XMLDocument(contentsOf: URL(fileURLWithPath: arguments[1]))
let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[2]), options: .mappedIfSafe)
let plistData = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
let info = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
let namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
guard let item = try feed.nodes(forXPath: "/rss/channel/item").first as? XMLElement,
      let enclosure = item.elements(forName: "enclosure").first,
      enclosure.attribute(forName: "url")?.stringValue == arguments[4],
      enclosure.attribute(forName: "length")?.stringValue == String(archive.count),
      let encodedSignature = enclosure.attribute(forLocalName: "edSignature", uri: namespace)?.stringValue,
      let signature = Data(base64Encoded: encodedSignature),
      let encodedKey = info["SUPublicEDKey"] as? String,
      let keyData = Data(base64Encoded: encodedKey),
      item.elements(forLocalName: "version", uri: namespace).first?.stringValue == info["CFBundleVersion"] as? String,
      item.elements(forLocalName: "shortVersionString", uri: namespace).first?.stringValue == info["CFBundleShortVersionString"] as? String,
      item.elements(forLocalName: "minimumSystemVersion", uri: namespace).first?.stringValue == info["LSMinimumSystemVersion"] as? String else {
    fatalError("Appcast signature, URL, size, version, or minimum macOS version is missing or incorrect")
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
guard key.isValidSignature(signature, for: archive) else {
    fatalError("The update signature does not match the public key shipped in Talos")
}
print("Verified Sparkle update signature, download URL, size, and app version metadata")
