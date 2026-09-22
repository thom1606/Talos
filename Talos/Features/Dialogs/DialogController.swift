import AppKit

@MainActor
final class DialogController {
    func present(_ request: TalosDialogRequest) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = request.message

        switch request.kind {
        case .alert:
            alert.addButton(withTitle: "OK")
        case .confirmation:
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
        }

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
