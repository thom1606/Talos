import SwiftUI

/// Foundation parses Markdown; these views supply native layout for its block intents.
struct WindowMarkdownView: View {
    private let blocks: [WindowMarkdownBlock]

    init(content: String) {
        blocks = WindowMarkdownBlock.parse(content)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    WindowMarkdownBlockView(block: block)
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

    var body: some View {
        switch block.kind {
        case .header(let level):
            Text(block.text)
                .font(headingFont(level))
                .accessibilityAddTraits(.isHeader)
        case .orderedList, .unorderedList:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(block.children) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker(for: item)).monospacedDigit()
                            .frame(minWidth: 18, alignment: .trailing)
                        WindowMarkdownBlockView(block: item)
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
                                Text(cell.text)
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
            Text(block.text).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var childBlocks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(block.children) { WindowMarkdownBlockView(block: $0) }
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
