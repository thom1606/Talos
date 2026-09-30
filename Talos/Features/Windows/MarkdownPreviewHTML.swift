import Foundation

/// Quick Look renders HTML documents; reuse the native Markdown parser for its formatted input.
nonisolated enum MarkdownPreviewHTML {
    static func render(_ content: String, sourceFile: URL, directory: URL) -> String {
        let body = WindowMarkdownBlock.parse(content).map {
            block($0, sourceFile: sourceFile, directory: directory)
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file: https: http: data:; style-src 'unsafe-inline'">
        <title>\(escape(sourceFile.lastPathComponent))</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: 15px/1.6 -apple-system, sans-serif; padding: 24px; margin: 0 auto; max-width: 900px; overflow-wrap: break-word; }
        h1,h2,h3,h4,h5,h6 { line-height: 1.25; } h1,h2 { border-bottom: 1px solid #8884; padding-bottom: .3em; }
        img { max-width: 100%; height: auto; } a { color: #3584e4; }
        pre,code { font-family: ui-monospace, monospace; background: #8881; border-radius: 6px; }
        pre { padding: 12px; overflow: auto; } pre code { background: none; } code { padding: .15em .3em; }
        blockquote { margin-left: 0; padding-left: 16px; border-left: 3px solid #8886; }
        table { border-collapse: collapse; display: block; overflow: auto; } td { padding: 6px 12px; border: 1px solid #8884; }
        tr:first-child { font-weight: 600; } hr { border: 0; border-top: 1px solid #8884; }
        </style></head><body>\(body)</body></html>
        """
    }

    private static func block(_ value: WindowMarkdownBlock, sourceFile: URL, directory: URL) -> String {
        let children = value.children.map { block($0, sourceFile: sourceFile, directory: directory) }.joined()
        let text = inline(value.text, sourceFile: sourceFile, directory: directory)
        switch value.kind {
        case .header(let level): return "<h\(level)>\(text)</h\(level)>"
        case .paragraph: return "<p>\(text)</p>"
        case .orderedList: return "<ol>\(children)</ol>"
        case .unorderedList: return "<ul>\(children)</ul>"
        case .listItem(let ordinal): return "<li value=\"\(ordinal)\">\(children)</li>"
        case .blockQuote: return "<blockquote>\(children)</blockquote>"
        case .codeBlock: return "<pre><code>\(escape(String(value.text.characters)))</code></pre>"
        case .thematicBreak: return "<hr>"
        default: return tableBlock(value, text: text, children: children)
        }
    }

    private static func tableBlock(_ value: WindowMarkdownBlock, text: String, children: String) -> String {
        switch value.kind {
        case .table: return "<table>\(children)</table>"
        case .tableHeaderRow, .tableRow: return "<tr>\(children)</tr>"
        case .tableCell: return "<td>\(text)</td>"
        default: return text + children
        }
    }

    private static func inline(_ text: AttributedString, sourceFile: URL, directory: URL) -> String {
        text.runs.map { run in
            let plain = String(text[run.range].characters)
            var html = escape(plain)
            if let image = run.imageURL {
                guard let url = imageURL(image, sourceFile: sourceFile, directory: directory) else { return html }
                html = "<img src=\"\(escape(url))\" alt=\"\(html)\">"
            } else if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { html = "<code>\(html)</code>" }
                if intent.contains(.stronglyEmphasized) { html = "<strong>\(html)</strong>" }
                if intent.contains(.emphasized) { html = "<em>\(html)</em>" }
                if intent.contains(.strikethrough) { html = "<del>\(html)</del>" }
                if intent.contains(.lineBreak) { html += "<br>" }
            }
            if let link = run.link, ["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                html = "<a href=\"\(escape(link.absoluteString))\">\(html)</a>"
            }
            return html
        }.joined()
    }

    private static func imageURL(_ url: URL, sourceFile: URL, directory: URL) -> String? {
        if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { return url.absoluteString }
        guard url.scheme == nil, !url.path.hasPrefix("/") else { return nil }
        let root = sourceFile.deletingLastPathComponent().resolvingSymlinksInPath()
        let image = root.appendingPathComponent(url.path).resolvingSymlinksInPath()
        guard image.path.hasPrefix(root.path + "/") else { return nil }
        let name = UUID().uuidString + "." + image.pathExtension
        do {
            try FileManager.default.copyItem(at: image, to: directory.appendingPathComponent(name))
            return name
        } catch { return nil }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
