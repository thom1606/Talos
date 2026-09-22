import Foundation

struct WheelAction: Identifiable, Equatable {
    let id: UUID
    let title: String
    let symbolName: String
    let destination: Destination

    indirect enum Destination: Equatable {
        case folder([WheelAction])
        case extensionAction(Tile)
        case settings
    }

    var isFolder: Bool {
        if case .folder = destination { return true }
        return false
    }
}
