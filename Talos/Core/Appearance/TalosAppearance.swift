import SwiftUI

enum TalosAppearance {
    /// The red shown by the selected wheel tile over clear Liquid Glass.
    static let accentHex = "#CA491C"
    static let accent = Color(
        red: 0xCA / 255,
        green: 0x49 / 255,
        blue: 0x1C / 255
    )

    /// Multiplying this over the glass produces the same visible accent red.
    static let glassHoverTint = Color(
        red: 0xEC / 255,
        green: 0x30 / 255,
        blue: 0x13 / 255
    )
}
