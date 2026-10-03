import Foundation

/// Shared command metadata; each caller keeps its own loading and execution policy.
nonisolated struct ExtensionCommandIndex {
    let roots: [ExtensionCommand]
    private let commands: [String: ExtensionCommand]

    init(_ commands: [ExtensionCommand]) {
        self.commands = Dictionary(commands.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let children = Set(commands.flatMap { $0.subcommands ?? [] })
        roots = commands.filter { !children.contains($0.name) }
    }

    func children(of command: ExtensionCommand) -> [ExtensionCommand] {
        (command.subcommands ?? []).compactMap { commands[$0] }
    }
}
