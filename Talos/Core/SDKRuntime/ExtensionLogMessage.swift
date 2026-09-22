import OSLog

nonisolated struct ExtensionLogMessage: Sendable, Equatable {
    let extensionID: String
    let level: Level
    let message: String

    enum Level: String, Sendable {
        case log, info, debug, warn, error

        var osLogType: OSLogType {
            switch self {
            case .log, .warn: .default
            case .info: .info
            case .debug: .debug
            case .error: .error
            }
        }
    }

    private static let logger = Logger(subsystem: "com.thom1606.Talos", category: "Extensions")

    func writeToLog() {
        // Extension-authored console output must remain readable in Console.app.
        Self.logger.log(
            level: level.osLogType,
            "[\(extensionID, privacy: .public)] [\(level.rawValue, privacy: .public)] \(message, privacy: .public)"
        )
    }
}
