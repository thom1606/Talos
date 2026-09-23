import AppKit
import Foundation

enum WheelPreviewContext: String, CaseIterable, Identifiable {
    case folder
    case image
    case video
    case audio
    case pdf

    var id: Self { self }

    var title: String {
        switch self {
        case .folder:
            String(localized: "Folder")
        case .image:
            String(localized: "Image")
        case .video:
            String(localized: "Video")
        case .audio:
            String(localized: "Audio")
        case .pdf:
            "PDF"
        }
    }

    var symbolName: String {
        switch self {
        case .folder:
            "folder"
        case .image:
            "photo"
        case .video:
            "film"
        case .audio:
            "waveform"
        case .pdf:
            "doc.richtext"
        }
    }
}

struct WheelTilePresentation: Identifiable, Equatable {
    let id: String
    let extensionBundleID: String
    let action: String
    let title: String
    let extensionName: String
    let symbolName: String?
    let supportedContexts: Set<WheelPreviewContext>

    var resolvedSymbolName: String {
        guard let symbolName else { return "questionmark" }

        let trimmedName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedName.isEmpty,
            NSImage(
                systemSymbolName: trimmedName,
                accessibilityDescription: nil
            ) != nil
        else {
            return "questionmark"
        }

        return trimmedName
    }
}

extension WheelTilePresentation {
    /// Built-in actions live outside extension repositories and therefore
    /// remain available even when no extensions are linked or installed.
    static let systemSettings = WheelTilePresentation(
        id: "talos.system.settings",
        extensionBundleID: "talos.system",
        action: "open-settings",
        title: String(localized: "Settings"),
        extensionName: "Talos",
        symbolName: "gearshape",
        supportedContexts: Set(WheelPreviewContext.allCases)
    )
}
