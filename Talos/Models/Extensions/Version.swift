import Foundation
import UniformTypeIdentifiers

nonisolated public struct Version: Comparable, Sendable {
    public let components: [Int]
    public init?(_ raw: String) {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }
        components = values + Array(repeating: 0, count: 3 - values.count)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}
