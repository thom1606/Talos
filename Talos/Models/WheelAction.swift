import SwiftUI

/// Modules supply a tree of actions. IDs should be namespaced and stable.
struct TalosAction: Identifiable {
    let id: String
    let title: String
    var symbol: String? = nil
    let destination: Destination

    enum Destination {
        case submenu([TalosAction])
        case window
        case handler(@MainActor ([URL]) -> Void)
    }
}
