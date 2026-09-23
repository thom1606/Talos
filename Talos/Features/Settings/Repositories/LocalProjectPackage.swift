import Foundation
import UniformTypeIdentifiers

struct LocalProjectPackage: Decodable {
    let name: String
    let version: String
    let talos: TalosConfiguration
    let commands: [Command]

    struct TalosConfiguration: Decodable {
        let bundleID: String
        let entry: String
        let locales: [String: String]

        private enum CodingKeys: String, CodingKey {
            case bundleID = "bundleId"
            case entry
            case locales
        }
    }

    struct Command: Decodable {
        let name: String
        let displayName: String
        let icon: String?
        let supportedFileTypes: [String]
        let subcommands: [String]?
    }

    static func read(from projectURL: URL) throws -> Self {
        let packageURL = projectURL.appending(path: "package.json")

        do {
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf: packageURL))
        } catch {
            throw LocalProjectError.invalidPackage(
                "Could not read a Talos package.json in \(projectURL.lastPathComponent)"
            )
        }
    }

    func displayName(in projectURL: URL) -> String {
        guard
            let localePath = talos.locales["en"],
            let localeURL = safeURL(for: localePath, in: projectURL),
            let data = try? Data(contentsOf: localeURL),
            let locale = try? JSONDecoder().decode(Locale.self, from: data),
            let displayName = locale.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !displayName.isEmpty
        else {
            return name
        }

        return displayName
    }

    func wheelTiles(extensionName: String) -> [WheelTilePresentation] {
        let children = Set(commands.flatMap { $0.subcommands ?? [] })
        return commands.filter { !children.contains($0.name) }.map { command in
            WheelTilePresentation(
                id: "\(talos.bundleID).\(command.name)",
                extensionBundleID: talos.bundleID,
                action: command.name,
                title: command.displayName,
                extensionName: extensionName,
                symbolName: command.icon,
                supportedContexts: supportedContexts(for: command.supportedFileTypes)
            )
        }
    }

    func hasBuild(in projectURL: URL) -> Bool {
        let outputDirectory = projectURL.appending(path: "dist", directoryHint: .isDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return contents.contains { $0.pathExtension == "talos" }
    }

    private func supportedContexts(for identifiers: [String]) -> Set<WheelPreviewContext> {
        if identifiers.contains("*") {
            return Set(WheelPreviewContext.allCases)
        }

        return Set(WheelPreviewContext.allCases.filter { context in
            identifiers.contains { identifier in
                guard let supportedType = UTType(identifier) else { return false }
                return context.contentType.conforms(to: supportedType)
            }
        })
    }

    private func safeURL(for relativePath: String, in root: URL) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }

        let root = root.standardizedFileURL
        let candidate = root.appending(path: relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    private struct Locale: Decodable {
        let displayName: String?
    }
}

enum LocalProjectError: LocalizedError {
    case invalidPackage(String)
    case cannotCreateBookmark

    var errorDescription: String? {
        switch self {
        case let .invalidPackage(message):
            message
        case .cannotCreateBookmark:
            "Talos could not keep access to this project folder"
        }
    }
}

private extension WheelPreviewContext {
    var contentType: UTType {
        switch self {
        case .folder:
            .folder
        case .image:
            .image
        case .video:
            .movie
        case .audio:
            .audio
        case .pdf:
            .pdf
        }
    }
}
