import Foundation
import UniformTypeIdentifiers

nonisolated public struct ModuleRelease: Codable, Sendable, Equatable {
    public let tag: String
    public let asset: String
    public let sha256: String
}
