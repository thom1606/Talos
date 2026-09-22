import AppKit
import SwiftUI

/// Exposes the settings window created and owned by SwiftUI's `Window` scene.
///
/// Talos only needs the reference to coordinate its Dock presence and the
/// custom quit behavior. Window creation, layout, title bars, and toolbars stay
/// entirely under SwiftUI and AppKit control.
struct SettingsWindowReader: NSViewRepresentable {
    let onWindowChange: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.onWindowChange = onWindowChange
        nsView.reportWindow()
    }
}

final class WindowReaderView: NSView {
    var onWindowChange: (@MainActor (NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindow()
    }

    func reportWindow() {
        guard let window else { return }
        onWindowChange?(window)
    }
}
