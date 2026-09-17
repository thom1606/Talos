import AppKit
import SwiftUI

/// Adopt this protocol on your @main type. TalosSDK owns process/window lifecycle.
public protocol ModuleApplication {
    @MainActor static func run(session: ModuleSession) async throws
}

extension ModuleApplication {
    @MainActor public static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = ModuleApplicationDelegate { session in try await Self.run(session: session) }
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class ModuleApplicationDelegate: NSObject, NSApplicationDelegate {
    let action: @MainActor (ModuleSession) async throws -> Void
    private var task: Task<Void, Never>?
    init(action: @escaping @MainActor (ModuleSession) async throws -> Void) { self.action = action }

    func applicationDidFinishLaunching(_ notification: Notification) {
        task = Task {
            do {
                let session = try ModuleSession.fromLaunchArguments()
                do {
                    try await action(session)
                    // A handler may provide its own completion with output files.
                    // ModuleSession ignores a second terminal event.
                    try await session.complete(message: "Done")
                } catch is CancellationError {
                    try? await session.fail("Cancelled")
                } catch {
                    try? await session.fail(error.localizedDescription)
                }
            } catch {
                // Double-clicking a module is not an invocation; don't leave a process running.
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            }
            NSApp.terminate(nil)
        }
    }
}

/// Native window presentation without repeating NSWindow setup in every module.
@MainActor public enum ModuleUI {
    /// Returns true for the primary button, false for Cancel or closing the window.
    /// Padding and content layout belong to your view.
    public static func showWindow<Content: View>(
        _ title: String, width: CGFloat = 480, height: CGFloat = 360,
        primary: String = "Done", secondary: String? = "Cancel",
        @ViewBuilder content: () -> Content
    ) async -> Bool {
        let presenter = ModuleWindowPresenter()
        return await withCheckedContinuation { continuation in
            presenter.present(title: title, width: width, height: height,
                              primary: primary, secondary: secondary, content: content(), continuation: continuation)
        }
    }
}

@MainActor private final class ModuleWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<Bool, Never>?
    // NSWindow.delegate is weak. Keep this presenter alive until the window closes.
    private var lifetime: ModuleWindowPresenter?

    func present<Content: View>(title: String, width: CGFloat, height: CGFloat,
                               primary: String, secondary: String?, content: Content,
                               continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
        lifetime = self
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false; window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.title = title; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.delegate = self
        window.contentView = NSHostingView(rootView: ModuleWindow(title, close: { [weak self] in self?.finish(false) },
            primaryAction: ModuleWindowAction(primary) { [weak self] in self?.finish(true) },
            secondaryAction: secondary.map { title in ModuleWindowAction(title) { [weak self] in self?.finish(false) } }
        ) { content })
        self.window = window
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) { finish(false) }
    private func finish(_ accepted: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        window?.close(); window = nil
        continuation.resume(returning: accepted)
        lifetime = nil
    }
}
