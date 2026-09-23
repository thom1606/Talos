import AppKit
import UniformTypeIdentifiers
import WebKit

/// Generic file access for activation inputs and output beside the selected input.
@MainActor
final class ExtensionWindowBridge: NSObject, WKScriptMessageHandlerWithReply {
    private weak var window: NSWindow?
    private let pageURL: URL
    private let files: WindowFileStore
    private var closed = false
    private let extensionID: String
    private var saveInputIndex = 0
    private let runtime: SDKRuntime
    private let request: TalosWindowRequest

    init(window: NSWindow, pageURL: URL, inputFiles: [URL], extensionID: String, runtime: SDKRuntime, request: TalosWindowRequest) {
        self.runtime = runtime
        self.request = request
        self.window = window
        self.pageURL = pageURL
        files = WindowFileStore(inputs: inputFiles)
        self.extensionID = extensionID
    }

    func bootstrap(dataJSON: String?, contextJSON: String?) throws -> WKUserScript {
        let data = try JSONSerialization.jsonObject(with: Data((dataJSON ?? "null").utf8), options: .fragmentsAllowed)
        let context = try JSONSerialization.jsonObject(with: Data((contextJSON ?? "null").utf8), options: .fragmentsAllowed)
        let styles: [(String, NSFont.TextStyle)] = [
            ("largeTitle", .largeTitle), ("title", .title1), ("title2", .title2), ("title3", .title3),
            ("headline", .headline), ("body", .body), ("callout", .callout), ("subheadline", .subheadline),
            ("footnote", .footnote), ("caption", .caption1), ("caption2", .caption2)
        ]
        var typography: [String: String] = [:]
        for (name, style) in styles {
            let font = NSFont.preferredFont(forTextStyle: style, options: [:])
            typography["--talos-font-\(name)-size"] = "\(font.pointSize)px"
            typography["--talos-font-\(name)-line-height"] = "\(ceil(font.ascender - font.descender + font.leading))px"
            typography["--talos-font-\(name)-weight"] = font.fontDescriptor.symbolicTraits.contains(.bold) ? "700" : "400"
        }
        let payload: [String: Any] = ["data": data, "context": context,
                                     "preferredLanguages": Locale.preferredLanguages, "typography": typography, "colors": colors()]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys), as: UTF8.self)
        return WKUserScript(source: """
        (() => {
            const payload = \(json);
            const request = message => window.webkit.messageHandlers.talosWindow.postMessage(message);
            Object.defineProperty(window, '__talosWindow', { value: Object.freeze({ ...payload, request }) });
            const applyTypography = () => {
                if (!document.documentElement) return false;
                for (const [name, value] of Object.entries({ ...payload.typography, ...payload.colors })) document.documentElement.style.setProperty(name, value);
                return true;
            };
            if (!applyTypography()) {
                const observer = new MutationObserver(() => { if (applyTypography()) observer.disconnect(); });
                observer.observe(document, { childList: true, subtree: true });
            }
            const refreshColors = () => request({ method: 'colors' }).then(colors => {
                for (const [name, value] of Object.entries(colors)) document.documentElement.style.setProperty(name, value);
            }).catch(() => {});
            window.addEventListener('focus', refreshColors);
            document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshColors(); });
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', refreshColors);
            for (const level of ['log', 'info', 'debug', 'warn', 'error']) {
                const original = console[level].bind(console);
                console[level] = (...args) => {
                    original(...args);
                    const message = args.map(value => {
                        try { return typeof value === 'string' ? value : JSON.stringify(value); }
                        catch { return String(value); }
                    }).join(' ').slice(0, 16384);
                    request({ method: 'console', level, message }).catch(() => {});
                };
            }
            window.addEventListener('error', event => console.error(event.message));
            window.addEventListener('unhandledrejection', event => console.error(String(event.reason)));
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url == pageURL,
              let body = message.body as? [String: Any], let method = body["method"] as? String else {
            replyHandler(nil, "Invalid window request")
            return
        }
        Task { @MainActor in
            do { replyHandler(try await handle(method, body: body), nil) }
            catch { replyHandler(nil, error.localizedDescription) }
        }
    }

    private func handle(_ method: String, body: [String: Any]) async throws -> Any {
        guard !closed, let window, window.isVisible else { throw WindowFileError.invalid("Window is closed") }
        switch method {
        case "invoke":
            guard let method = body["name"] as? String, let payload = body["payloadJSON"] as? String else {
                throw WindowFileError.invalid("Invalid extension request")
            }
            let json = try await runtime.invokeWindow(request, method: method, payloadJSON: payload)
            guard !closed else { throw WindowFileError.invalid("Window closed") }
            return try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
        case "colors":
            return colors()
        case "console":
            let level = (body["level"] as? String).flatMap(ExtensionLogMessage.Level.init(rawValue:)) ?? .log
            ExtensionLogMessage(extensionID: extensionID, level: level,
                message: "[window] " + String((body["message"] as? String ?? "").prefix(16_384))).writeToLog()
            return NSNull()
        case "close":
            window.performClose(nil)
            return NSNull()
        case "fileInfo":
            guard let index = body["index"] as? Int else { throw WindowFileError.invalid("Missing input file") }
            let info = try await files.info(index: index)
            return ["name": info.name, "type": info.type, "size": info.size]
        case "readFile":
            guard let index = body["index"] as? Int, let offset = body["offset"] as? Int,
                  let length = body["length"] as? Int, let size = body["size"] as? Int else {
                throw WindowFileError.invalid("Invalid file range")
            }
            return try await files.read(index: index, offset: offset, length: length, size: size)
        case "beginSave":
            guard let size = body["size"] as? Int, size >= 0,
                  let name = body["suggestedName"] as? String, !name.isEmpty else {
                throw WindowFileError.invalid("Missing output filename or size")
            }
            return try await files.beginSave(inputIndex: saveInputIndex, suggestedName: name, size: size)
        case "setSaveInput":
            guard let index = body["index"] as? Int else { throw WindowFileError.invalid("Missing input file") }
            _ = try await files.info(index: index)
            saveInputIndex = index
            return NSNull()
        case "writeFile":
            guard let id = body["id"] as? String, let offset = body["offset"] as? Int,
                  let bytes = body["bytes"] as? String else { throw WindowFileError.invalid("Invalid save chunk") }
            try await files.write(id: id, offset: offset, base64: bytes)
            return NSNull()
        case "finishSave":
            guard let id = body["id"] as? String else { throw WindowFileError.invalid("Missing save identifier") }
            return try await files.finish(id: id)
        case "cancelSave":
            guard let id = body["id"] as? String else { throw WindowFileError.invalid("Missing save identifier") }
            await files.cancel(id: id)
            return NSNull()
        default:
            throw WindowFileError.invalid("Unsupported window operation")
        }
    }

    /// Resolve the system accent in both appearances; CSS selects the matching variant.
    private func colors() -> [String: String] {
        func accent(_ name: NSAppearance.Name) -> String {
            var value = "AccentColor"
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                if let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
                    value = "rgb(\(Int((color.redComponent * 255).rounded())) \(Int((color.greenComponent * 255).rounded())) \(Int((color.blueComponent * 255).rounded())))"
                }
            }
            return value
        }
        return ["--talosColor": "#EC3013", "--accentColor": "light-dark(\(accent(.aqua)), \(accent(.darkAqua)))"]
    }

    func close() {
        closed = true
        Task { await runtime.closeWindow(request); await files.cancel() }
    }
}
