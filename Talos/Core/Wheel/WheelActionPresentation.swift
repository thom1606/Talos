import AppKit

@MainActor
enum WheelActionPresentation {
    // System symbol validity is stable for the lifetime of the running app.
    private static var symbols: [String: String] = [:]

    static func title(for item: WheelItem, fallback: String) -> String {
        let title = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? fallback : title
    }

    static func symbol(_ name: String?, missing: String = "questionmark") -> String {
        guard let name, !name.isEmpty else { return missing }
        if let cached = symbols[name] { return cached }
        let resolved = NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? "questionmark" : name
        symbols[name] = resolved
        return resolved
    }
}
