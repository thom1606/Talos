import AppKit
import SwiftUI

/// Foundation parses Markdown; these views supply native layout for its block intents.
struct WindowMarkdownView: View {
    private let blocks: [WindowMarkdownBlock]
    private let sourceFile: URL?

    init(content: String, sourceFile: URL? = nil) {
        blocks = WindowMarkdownBlock.parse(content)
        self.sourceFile = sourceFile
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    WindowMarkdownBlockView(block: block, sourceFile: sourceFile)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
                ? .systemAction : .discarded
        })
    }
}

struct WindowMarkdownBlock: Identifiable {
    let id: Int
    let kind: PresentationIntent.Kind
    var text = AttributedString()
    var children: [WindowMarkdownBlock] = []

    static func parse(_ source: String) -> [Self] {
        guard let parsed = try? AttributedString(markdown: source) else {
            return [.init(id: 0, kind: .paragraph, text: AttributedString(source))]
        }
        var blocks: [Self] = []
        for (intent, range) in parsed.runs[\.presentationIntent] {
            var text = AttributedString(parsed[range])
            text.presentationIntent = nil
            guard let intent else {
                blocks.append(.init(id: -blocks.count - 1, kind: .paragraph, text: text))
                continue
            }
            append(text, path: Array(intent.components.reversed())[...], to: &blocks)
        }
        return blocks
    }

    private static func append(_ text: AttributedString,
                               path: ArraySlice<PresentationIntent.IntentType>, to blocks: inout [Self]) {
        guard let intent = path.first else { return }
        if blocks.last?.id != intent.identity {
            blocks.append(.init(id: intent.identity, kind: intent.kind))
        }
        let index = blocks.count - 1
        if path.count == 1 {
            blocks[index].text.append(text)
        } else {
            append(text, path: path.dropFirst(), to: &blocks[index].children)
        }
    }
}

private struct WindowMarkdownBlockView: View {
    let block: WindowMarkdownBlock
    let sourceFile: URL?

    var body: some View {
        switch block.kind {
        case .header(let level):
            WindowMarkdownInlineView(text: block.text, sourceFile: sourceFile)
                .font(headingFont(level))
                .accessibilityAddTraits(.isHeader)
        case .orderedList, .unorderedList:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(block.children) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker(for: item)).monospacedDigit()
                            .frame(minWidth: 18, alignment: .trailing)
                        WindowMarkdownBlockView(block: item, sourceFile: sourceFile)
                    }
                }
            }
        case .blockQuote:
            childBlocks
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.quaternary).frame(width: 3)
                }
        case .codeBlock:
            ScrollView(.horizontal) {
                Text(block.text).font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false).padding(12)
            }
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        case .thematicBreak:
            Divider()
        case .table(let columns):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    ForEach(block.children) { row in
                        GridRow {
                            ForEach(row.children) { cell in
                                WindowMarkdownInlineView(text: cell.text, sourceFile: sourceFile)
                                    .fontWeight(row.kind == .tableHeaderRow ? .semibold : .regular)
                                    .gridColumnAlignment(columnAlignment(cell, columns: columns))
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        case .listItem, .tableRow, .tableHeaderRow:
            childBlocks
        default:
            WindowMarkdownInlineView(text: block.text, sourceFile: sourceFile)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var childBlocks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(block.children) { WindowMarkdownBlockView(block: $0, sourceFile: sourceFile) }
        }
    }

    private func marker(for item: WindowMarkdownBlock) -> String {
        if block.kind == .orderedList, case .listItem(let ordinal) = item.kind { return "\(ordinal)." }
        return "•"
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .largeTitle.bold()
        case 2: .title.bold()
        case 3: .title2.bold()
        default: .headline
        }
    }

    private func columnAlignment(_ cell: WindowMarkdownBlock, columns: [PresentationIntent.TableColumn]) -> HorizontalAlignment {
        guard case .tableCell(let index) = cell.kind, columns.indices.contains(index) else { return .leading }
        return switch columns[index].alignment {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }
}

private struct WindowMarkdownInlineView: View {
    let text: AttributedString
    let sourceFile: URL?
    private let segments: [Segment]

    init(text: AttributedString, sourceFile: URL?) {
        self.text = text
        self.sourceFile = sourceFile
        segments = text.runs[\.imageURL].map { url, range in
            Segment(imageURL: url, text: AttributedString(text[range]))
        }
    }

    var body: some View {
        if !segments.contains(where: { $0.imageURL != nil }) {
            Text(text)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(segments) { segment in
                    if let url = segment.imageURL {
                        WindowMarkdownImage(source: url, alt: String(segment.text.characters), sourceFile: sourceFile)
                    } else {
                        Text(segment.text)
                    }
                }
            }
        }
    }

    private struct Segment: Identifiable {
        let id = UUID()
        let imageURL: URL?
        let text: AttributedString
    }
}

private struct WindowMarkdownImage: View {
    let source: URL
    let alt: String
    let sourceFile: URL?

    private var resolvedURL: URL? {
        if ["https", "http"].contains(source.scheme?.lowercased() ?? "") { return source }
        guard source.scheme == nil, !source.path.hasPrefix("/"), let sourceFile else { return nil }
        let directory = sourceFile.deletingLastPathComponent().resolvingSymlinksInPath()
        let image = directory.appending(path: source.path).resolvingSymlinksInPath()
        guard image.path.hasPrefix(directory.path + "/") else { return nil }
        return image
    }

    var body: some View {
        if let url = resolvedURL, url.isFileURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: image.size.width)
                .accessibilityLabel(alt)
        } else if let url = resolvedURL, !url.isFileURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case let .success(image):
                    image.resizable().scaledToFit().accessibilityLabel(alt)
                case .failure:
                    Text(alt).foregroundStyle(.secondary)
                @unknown default:
                    Text(alt).foregroundStyle(.secondary)
                }
            }
        } else {
            Text(alt).foregroundStyle(.secondary)
        }
    }
}
