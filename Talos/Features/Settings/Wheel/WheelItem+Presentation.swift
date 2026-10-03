import Foundation

extension WheelItem {
    func title(using tiles: [WheelTilePresentation]) -> String {
        if isFolder {
            return WheelActionPresentation.title(for: self, fallback: String(localized: "Folder"))
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

    func isAvailable(using tiles: [WheelTilePresentation]) -> Bool {
        isFolder || tiles.contains(where: { $0.id == actionID })
    }
}
