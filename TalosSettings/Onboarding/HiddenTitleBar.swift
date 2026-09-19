import AppKit
import SwiftUI

/// Removes title-bar chrome only while the first-run journey is visible.
struct HiddenTitleBar: NSViewRepresentable {
    var centred = false

    @MainActor private static let alreadyCentred = NSHashTable<NSWindow>.weakObjects()

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            strip(window)
            if centred, !Self.alreadyCentred.contains(window) {
                Self.alreadyCentred.add(window)
                window.center()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            strip(window)
        }
    }

    private func strip(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }
}
