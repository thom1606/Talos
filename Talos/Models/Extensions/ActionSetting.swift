import Foundation

/// JavaScript SDK functions emit these descriptors at build time. Talos owns all form rendering.
nonisolated public struct ActionSetting: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case text, password, number, toggle, select }
    public let id: String
    public let type: Kind
    public let label: String
    public let translations: [String: String]?
    public let defaultValue: String?
    public let required: Bool?
    public let choices: [String]?
    public let minimum: Double?
    public let maximum: Double?

    public var localizedLabel: String {
        translations?[Locale.current.language.languageCode?.identifier ?? "en"] ?? label
    }
}
