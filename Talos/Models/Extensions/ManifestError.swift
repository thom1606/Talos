import Foundation
import UniformTypeIdentifiers

nonisolated public enum ManifestError: LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}
