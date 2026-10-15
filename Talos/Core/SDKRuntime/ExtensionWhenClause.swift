import Foundation

/// A command's `when` clause, as in VS Code: setting names and comparisons (`format == png`,
/// `quality != 85`, `label == 'two words'`) combined with `!`, `&&`, `||` and parentheses.
/// A bare name is true when the tile's value for it is true, non-empty text or non-zero.
nonisolated struct ExtensionWhenClause: Sendable {
    struct Comparison: Sendable, Equatable {
        let setting: String
        let value: String
    }

    private indirect enum Node: Sendable {
        case setting(String)
        case equals(Comparison)
        case not(Node)
        case and(Node, Node)
        case either(Node, Node)
    }

    private enum Token: Equatable {
        case name(String), quoted(String), not, and, either, equal, notEqual, open, close
    }

    private let root: Node

    init(_ source: String) throws {
        var tokens = try Self.tokens(in: source)[...]
        root = try Self.or(&tokens)
        guard tokens.isEmpty else { throw Self.invalid(source) }
    }

    /// Every setting the clause reads, so a manifest can check them against its settings.
    var settings: Set<String> { Self.settings(in: root) }

    /// Every `==` and `!=` comparison, so a manifest can check select values against its options.
    var comparisons: [Comparison] { Self.comparisons(in: root) }

    func evaluate(_ config: [String: TileConfigValue]) -> Bool {
        Self.evaluate(root, config)
    }

    private static func evaluate(_ node: Node, _ config: [String: TileConfigValue]) -> Bool {
        switch node {
        case let .setting(name):
            switch config[name] {
            case let .boolean(value): value
            case let .string(value): !value.isEmpty
            case let .number(value): value != 0
            case nil: false
            }
        case let .equals(comparison): matches(comparison, config)
        case let .not(node): !evaluate(node, config)
        case let .and(lhs, rhs): evaluate(lhs, config) && evaluate(rhs, config)
        case let .either(lhs, rhs): evaluate(lhs, config) || evaluate(rhs, config)
        }
    }

    private static func matches(_ comparison: Comparison, _ config: [String: TileConfigValue]) -> Bool {
        switch config[comparison.setting] {
        case let .boolean(value): String(value) == comparison.value
        case let .string(value): value == comparison.value
        case let .number(value): Double(comparison.value) == value
        case nil: false
        }
    }

    private static func settings(in node: Node) -> Set<String> {
        switch node {
        case let .setting(name): [name]
        case let .equals(comparison): [comparison.setting]
        case let .not(node): settings(in: node)
        case let .and(lhs, rhs), let .either(lhs, rhs): settings(in: lhs).union(settings(in: rhs))
        }
    }

    private static func comparisons(in node: Node) -> [Comparison] {
        switch node {
        case .setting: []
        case let .equals(comparison): [comparison]
        case let .not(node): comparisons(in: node)
        case let .and(lhs, rhs), let .either(lhs, rhs): comparisons(in: lhs) + comparisons(in: rhs)
        }
    }

    private static func or(_ tokens: inout ArraySlice<Token>) throws -> Node {
        var node = try and(&tokens)
        while tokens.first == .either {
            tokens.removeFirst()
            node = .either(node, try and(&tokens))
        }
        return node
    }

    private static func and(_ tokens: inout ArraySlice<Token>) throws -> Node {
        var node = try unary(&tokens)
        while tokens.first == .and {
            tokens.removeFirst()
            node = .and(node, try unary(&tokens))
        }
        return node
    }

    private static func unary(_ tokens: inout ArraySlice<Token>) throws -> Node {
        switch tokens.popFirst() {
        case let .name(name):
            guard let comparison = tokens.first, comparison == .equal || comparison == .notEqual else {
                return .setting(name)
            }
            tokens.removeFirst()
            let value: String
            switch tokens.popFirst() {
            case let .name(text), let .quoted(text): value = text
            default: throw invalid("expected a value after \(name)")
            }
            let node = Node.equals(.init(setting: name, value: value))
            return comparison == .equal ? node : .not(node)
        case .not:
            return .not(try unary(&tokens))
        case .open:
            let node = try or(&tokens)
            guard tokens.popFirst() == .close else { throw invalid("missing )") }
            return node
        default:
            throw invalid("expected a setting name")
        }
    }

    private static func tokens(in source: String) throws -> [Token] {
        let symbols: [(String, Token)] = [("&&", .and), ("||", .either), ("==", .equal), ("!=", .notEqual),
                                          ("!", .not), ("(", .open), (")", .close)]
        var tokens: [Token] = []
        var characters = source[...]
        while let character = characters.first {
            if character.isWhitespace {
                characters.removeFirst()
            } else if let (symbol, token) = symbols.first(where: { characters.hasPrefix($0.0) }) {
                tokens.append(token)
                characters.removeFirst(symbol.count)
            } else if character == "'" || character == "\"" {
                let text = characters.dropFirst().prefix { $0 != character }
                guard characters.dropFirst(text.count + 1).first == character else { throw invalid("unclosed quote") }
                tokens.append(.quoted(String(text)))
                characters.removeFirst(text.count + 2)
            } else if isNameCharacter(character) {
                let name = characters.prefix(while: isNameCharacter)
                tokens.append(.name(String(name)))
                characters.removeFirst(name.count)
            } else {
                throw invalid(source)
            }
        }
        return tokens
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || "-_.".contains(character))
    }

    private static func invalid(_ detail: String) -> Error {
        SDKRuntimeError.invalidManifest("Invalid when clause: \(detail)")
    }
}

nonisolated extension ExtensionCommand {
    /// Whether this subcommand's `when` clause allows it for a tile of its parent command.
    func isVisible(parentSettings: [ExtensionSetting], config: [String: TileConfigValue]) -> Bool {
        guard let when else { return true }
        var values = config
        for setting in parentSettings where values[setting.name] == nil {
            values[setting.name] = setting.defaultValue
        }
        return (try? ExtensionWhenClause(when))?.evaluate(values) ?? false
    }
}
