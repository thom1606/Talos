import Foundation
import UniformTypeIdentifiers

nonisolated public struct ModuleFile: Codable, Sendable, Equatable {
    public let url: URL
    public let typeIdentifier: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public init(url: URL, typeIdentifier: String, isDirectory: Bool = false, isPackage: Bool = false) {
        self.url = url; self.typeIdentifier = typeIdentifier; self.isDirectory = isDirectory; self.isPackage = isPackage
    }
}
