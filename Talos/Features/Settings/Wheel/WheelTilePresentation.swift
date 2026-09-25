import AppKit
import Foundation

struct WheelTilePresentation: Identifiable, Equatable {
    let id: String
    let extensionBundleID: String
    let action: String
    let title: String
    let description: String?
    let extensionName: String
    let symbolName: String?
    let settings: [ExtensionSetting]

    var helpText: String {
        let details = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return details.isEmpty ? title : details
    }

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
        description: nil,
        extensionName: "Talos",
        symbolName: "gearshape",
        settings: []
    )
}
