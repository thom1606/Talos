import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers
import OSLog

/// Native preview chrome shared by Markdown and React windows.
@MainActor
final class ExtensionWindowController: NSObject, NSWindowDelegate {
    private struct Entry {
        let window: NSWindow
        let webPage: WebPage?
        let scripts: WKUserContentController?
        let bridge: ExtensionWindowBridge?
        let loadTask: Task<Void, Never>?
    }
    private var windows: [ObjectIdentifier: Entry] = [:]
    private var preparedPage: PreparedWindowPage?
    private var isClosingAll = false
    private let logger = Logger(subsystem: "com.thom1606.Talos", category: "ExtensionWindows")

    /// Start WebKit with an empty, isolated document before the first user action.
    /// No extension JavaScript or dropped files are loaded during preparation.
    func prepare() {
        guard preparedPage == nil else { return }
        let prepared = PreparedWindowPage()
        _ = prepared.page.load(simulatedRequest: URLRequest(url: PreparedWindowPage.documentURL),
                               responseHTML: "<html><head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'\"></head><body></body></html>")
        preparedPage = prepared
    }

    func show(_ request: TalosWindowRequest, resources: TalosWindowResources) throws {
        let startedAt = ContinuousClock.now
        let width = min(1_200, max(320, request.width ?? 480))
        let height = min(900, max(180, request.height ?? 320))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = request.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: min(height, 440))
        window.delegate = self
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }

        let webPage: WebPage?
        var scripts: WKUserContentController?
        var windowBridge: ExtensionWindowBridge?
        var loadTask: Task<Void, Never>?
        if let pageURL = resources.pageURL {
            let prepared = preparedPage ?? PreparedWindowPage()
            let wasPrepared = preparedPage != nil
            preparedPage = nil
            let documentURL = PreparedWindowPage.documentURL
            let bridge = ExtensionWindowBridge(window: window, pageURL: documentURL,
                                               inputFiles: resources.inputFiles, extensionID: request.extensionID)
            windowBridge = bridge
            let bootstrap = try bridge.bootstrap(dataJSON: request.dataJSON, contextJSON: request.contextJSON)
            prepared.assets.directory = pageURL.deletingLastPathComponent()
            prepared.scripts.addScriptMessageHandler(bridge, contentWorld: .page, name: "talosWindow")
            prepared.scripts.addUserScript(bootstrap)
            scripts = prepared.scripts
            let browser = prepared.page
            let navigation = browser.load(documentURL)
            loadTask = Task { [logger] in
                do {
                    for try await event in navigation where event == .finished {
                        let elapsed = startedAt.duration(to: .now)
                        logger.info("Window document loaded in \(String(describing: elapsed), privacy: .public); prepared=\(wasPrepared); extension=\(request.extensionID, privacy: .public)")
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    logger.error("Window navigation failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            webPage = browser
        } else {
            webPage = nil
        }

        window.contentView = NSHostingView(rootView: ExtensionWindowChrome(
            title: request.title, text: request.content, webPage: webPage,
            close: { [weak window] in window?.performClose(nil) }
        ))
        windows[ObjectIdentifier(window)] = Entry(window: window, webPage: webPage, scripts: scripts, bridge: windowBridge, loadTask: loadTask)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func closeAll() {
        isClosingAll = true
        defer { isClosingAll = false }
        for entry in Array(windows.values) { entry.window.close() }
        preparedPage?.page.stopLoading()
        preparedPage = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let entry = windows.removeValue(forKey: ObjectIdentifier(window)) else { return }
        entry.bridge?.close()
        entry.loadTask?.cancel()
        entry.webPage?.stopLoading()
        entry.scripts?.removeScriptMessageHandler(forName: "talosWindow", contentWorld: .page)
        // Refill with a fresh data store, never a page that ran another extension.
        if !isClosingAll, windows.isEmpty, entry.webPage != nil { prepare() }
    }
}

@MainActor
private final class PreparedWindowPage {
    static let documentURL = URL(string: "talos-window://bundle/index.html")!
    let assets = ExtensionWindowAssets()
    let scripts: WKUserContentController
    let page: WebPage

    init() {
        var configuration = WebPage.Configuration()
        configuration.deviceSensorAuthorization = .init(decision: .deny)
        configuration.urlSchemeHandlers[URLScheme("talos-window")!] = assets
        configuration.websiteDataStore = .nonPersistent()
        scripts = configuration.userContentController
        page = WebPage(configuration: configuration,
                       navigationDecider: ExtensionWindowNavigation(documentURL: Self.documentURL))
        #if DEBUG
        page.isInspectable = true
        #endif
    }
}

private struct ExtensionWindowChrome: View {
    let title: String
    let text: String
    let webPage: WebPage?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).padding(.horizontal, 48)
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(.primary.opacity(0.06), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
                    .help("Close")
                    Spacer()
                }.padding(.horizontal, 12)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            Divider()
            if let webPage {
                WebView(webPage)
                    .webViewContentBackground(.hidden)
                    .webViewMagnificationGestures(.disabled)
                    .webViewLinkPreviews(.disabled)
            } else {
                WindowMarkdownView(content: text)
            }
        }
        .background(.regularMaterial)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct ExtensionWindowNavigation: WebPage.NavigationDeciding {
    let documentURL: URL
    func decidePolicy(for action: WebPage.NavigationAction,
                      preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        action.target?.isMainFrame == true && action.request.url == documentURL ? .allow : .cancel
    }
}

/// Serve only the assets in this window's bundle, without granting WebKit filesystem access.
@MainActor
private final class ExtensionWindowAssets: URLSchemeHandler {
    var directory: URL?
    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, Error> {
        AsyncThrowingStream { continuation in
            do {
                guard let directory, let url = request.url, url.host == "bundle" else { throw URLError(.badURL) }
                let root = directory.resolvingSymlinksInPath()
                let file = root.appendingPathComponent(url.path).resolvingSymlinksInPath()
                guard file.path.hasPrefix(root.path + "/") else { throw URLError(.noPermissionsToReadFile) }
                let data = try Data(contentsOf: file)
                let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                continuation.yield(.response(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8")))
                continuation.yield(.data(data))
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
}
