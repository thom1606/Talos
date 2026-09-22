import SwiftUI

struct RepositoryPresentation: Identifiable {
    let id: String
    let name: String
    let source: String
    let kind: SourceKind
    var installedVersion: String?
    var availableVersion: String?
    var status: Status

    enum SourceKind: Hashable {
        case package
        case localProject
        case github

        var symbolName: String {
            switch self {
            case .package:
                "doc"
            case .localProject:
                "folder"
            case .github:
                "shippingbox"
            }
        }
    }

    enum Status: Equatable {
        case running
        case updateAvailable
        case fetching
        case installing
        case buildRequired
        case permissionDenied

        var title: String {
            switch self {
            case .running:
                "Running"
            case .updateAvailable:
                "Update available"
            case .fetching:
                "Fetching latest version"
            case .installing:
                "Installing extension"
            case .buildRequired:
                "Build required"
            case .permissionDenied:
                "No repository permission"
            }
        }

        func symbolName(for sourceKind: SourceKind) -> String {
            switch self {
            case .running:
                sourceKind.symbolName
            case .updateAvailable:
                "arrow.down.circle.fill"
            case .buildRequired, .permissionDenied:
                "exclamationmark.triangle.fill"
            case .fetching, .installing:
                ""
            }
        }

        var tint: Color {
            switch self {
            case .running:
                .secondary
            case .updateAvailable:
                .blue
            case .fetching, .installing:
                .secondary
            case .buildRequired, .permissionDenied:
                .red
            }
        }

        var subtitleTint: Color {
            switch self {
            case .updateAvailable:
                .blue
            case .buildRequired, .permissionDenied:
                .red
            case .running, .fetching, .installing:
                .secondary
            }
        }

        var isProgressing: Bool {
            switch self {
            case .fetching, .installing:
                true
            default:
                false
            }
        }

        func instruction(for repository: RepositoryPresentation) -> String {
            switch self {
            case .running:
                if let installedVersion = repository.installedVersion {
                    installedVersion
                } else {
                    "Running"
                }
            case .updateAvailable:
                repository.availableVersion.map { "Update available: \($0)" } ?? "New update available"
            case .fetching:
                "Fetching latest version…"
            case .installing:
                "Installing the extension…"
            case .buildRequired:
                "Build project to proceed"
            case .permissionDenied:
                "No permission to repository"
            }
        }
    }
}
