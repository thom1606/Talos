import AppKit
import QuickLookUI

/// Finder's standard spacebar preview, including navigation through a mixed selection.
@MainActor
final class QuickLookPreviewController: NSObject, @MainActor QLPreviewPanelDataSource, @MainActor QLPreviewPanelDelegate {
    private var prepared: QuickLookFiles?
    private var items: [QuickLookItem] = []
    private var onClose: (() -> Void)?
    private var visibilityObservation: NSKeyValueObservation?
    private var generation = UUID()
    var hasItems: Bool { !items.isEmpty }

    func show(_ files: [URL], renderMarkdown: Bool = true, onClose: @escaping () -> Void) async throws {
        let token = UUID()
        generation = token
        let result = try await Task.detached {
            try QuickLookFiles.prepare(files, renderMarkdown: renderMarkdown)
        }.value
        guard token == generation else {
            result.cleanUp()
            onClose()
            return
        }
        releaseFiles()
        prepared = result
        items = zip(result.previews, files).map { QuickLookItem(url: $0.0, title: $0.1.lastPathComponent) }
        self.onClose = onClose
        guard let panel = QLPreviewPanel.shared() else {
            releaseFiles()
            throw CocoaError(.featureUnsupported)
        }
        visibilityObservation = panel.observe(\.isVisible, options: [.new]) { [weak self] panel, change in
            guard change.newValue == false else { return }
            Task { @MainActor [weak self] in
                if !panel.isVisible { self?.releaseFiles() }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
    }

    func beginControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func endControl(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        items.indices.contains(index) ? items[index] : nil
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, event.keyCode == 49 || event.keyCode == 53 else { return false }
        panel.performClose(nil)
        return true
    }

    func windowWillClose(_ notification: Notification) { releaseFiles() }

    func close() {
        generation = UUID()
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared()?.close() }
        releaseFiles()
    }

    private func releaseFiles() {
        visibilityObservation = nil
        items = []
        prepared?.cleanUp()
        prepared = nil
        onClose?()
        onClose = nil
    }
}

@MainActor
private final class QuickLookItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
    }
}

/// Keep drop permissions and rendered documents alive until Quick Look closes.
nonisolated struct QuickLookFiles: Sendable {
    let previews: [URL]
    private let scopedFiles: [URL]
    private let directory: URL

    static func prepare(_ files: [URL], renderMarkdown: Bool = true) throws -> Self {
        guard !files.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Talos-QuickLook-\(UUID())")
        var scopedFiles: [URL] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let previews = try files.enumerated().map { index, file in
                try Task.checkCancellation()
                if file.startAccessingSecurityScopedResource() { scopedFiles.append(file) }
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                guard values.isRegularFile == true || values.isDirectory == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                let isMarkdown = ["md", "markdown"].contains(file.pathExtension.lowercased())
                    || file.lastPathComponent.lowercased() == "readme"
                guard renderMarkdown, values.isRegularFile == true, isMarkdown else { return file }
                let folder = directory.appendingPathComponent(String(index))
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let content = try String(contentsOf: file, encoding: .utf8)
                let html = MarkdownPreviewHTML.render(content, sourceFile: file, directory: folder)
                let preview = folder.appendingPathComponent(file.lastPathComponent + ".html")
                try html.write(to: preview, atomically: true, encoding: .utf8)
                return preview
            }
            return Self(previews: previews, scopedFiles: scopedFiles, directory: directory)
        } catch {
            scopedFiles.forEach { $0.stopAccessingSecurityScopedResource() }
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func cleanUp() {
        scopedFiles.forEach { $0.stopAccessingSecurityScopedResource() }
        try? FileManager.default.removeItem(at: directory)
    }
}
