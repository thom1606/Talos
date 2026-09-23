import Foundation

extension WheelItem {
    func title(using tiles: [WheelTilePresentation]) -> String {
        if isFolder {
            let title = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? String(localized: "Folder") : title
        }

        return customTitle
            ?? tiles.first(where: { $0.id == actionID })?.title
            ?? String(localized: "Unavailable action")
    }

    func symbolName(using tiles: [WheelTilePresentation]) -> String {
        if isFolder {
            return "folder"
        }

        return tiles.first(where: { $0.id == actionID })?.resolvedSymbolName
            ?? "questionmark"
    }

    func supports(
        _ context: WheelPreviewContext,
        using tiles: [WheelTilePresentation]
    ) -> Bool {
        if let children {
            return children.isEmpty || children.contains { child in
                child.supports(context, using: tiles)
            }
        }

        return tiles.first(where: { $0.id == actionID })?
            .supportedContexts.contains(context) == true
    }
}
