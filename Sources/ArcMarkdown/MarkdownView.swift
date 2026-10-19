import AppKit
import SwiftUI

extension HighlightSwiftHighlighter {
    public static let shared = HighlightSwiftHighlighter()
}

extension ImageLoader {
    public static let shared = ImageLoader()
}

/// Renders GitHub Flavored Markdown with the dark Arc look.
///
/// Links are ordinary `Text` links, so the host decides what they do through the `openURL`
/// environment (the app routes `arc://ticket/<n>` to the ticket and everything else to the browser).
public struct MarkdownView: View {
    private let source: String
    private let knownTickets: Set<Int>
    private let style: MarkdownStyle
    private let highlighter: any CodeHighlighter
    private let imageLoader: ImageLoader
    private let onSourceChange: ((String) -> Void)?

    /// - Parameters:
    ///   - knownTickets: Numbers of existing tickets; only `ARC-n` references to these become links.
    ///   - onSourceChange: Called with the updated source when a task-list checkbox is clicked.
    ///     When nil, checkboxes are read-only.
    public init(
        _ source: String,
        knownTickets: Set<Int> = [],
        style: MarkdownStyle = MarkdownStyle(),
        highlighter: any CodeHighlighter = HighlightSwiftHighlighter.shared,
        imageLoader: ImageLoader = .shared,
        onSourceChange: ((String) -> Void)? = nil
    ) {
        self.source = source
        self.knownTickets = knownTickets
        self.style = style
        self.highlighter = highlighter
        self.imageLoader = imageLoader
        self.onSourceChange = onSourceChange
    }

    public var body: some View {
        let blocks = MarkdownLinker.link(MarkdownParser.parse(source), knownTickets: knownTickets)
        let context = RenderContext(
            style: style,
            highlighter: highlighter,
            imageLoader: imageLoader,
            toggle: onSourceChange.map { change in
                { task in
                    if let updated = MarkdownSource.toggleTask(task, in: source) { change(updated) }
                }
            }
        )
        BlocksView(blocks: blocks, context: context)
            .tint(style.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RenderContext {
    var style: MarkdownStyle
    let highlighter: any CodeHighlighter
    let imageLoader: ImageLoader
    let toggle: ((MarkdownTask) -> Void)?

    /// Applies link and inline-code styling that `Text` does not do on its own.
    func styled(_ text: AttributedString) -> AttributedString {
        var result = text
        for run in text.runs {
            if run.link != nil {
                result[run.range].foregroundColor = style.accent
            }
            if (run.inlinePresentationIntent ?? []).contains(.code) {
                result[run.range].font = .system(size: style.codeSize, design: .monospaced)
                result[run.range].backgroundColor = style.inlineCodeBackground
            }
        }
        return result
    }
}

private struct BlocksView: View {
    let blocks: [MarkdownBlock]
    let context: RenderContext
    var spacing: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: spacing ?? context.style.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block, context: context)
            }
        }
    }
}

private struct BlockView: View {
    let block: MarkdownBlock
    let context: RenderContext

    /// Quoted content is drawn in the secondary text color.
    private var quoted: RenderContext {
        var quoted = context
        quoted.style.text = context.style.secondaryText
        return quoted
    }

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(context.styled(text))
                .font(.system(size: context.style.headingSize(level), weight: .semibold))
                .foregroundStyle(context.style.text)
                .padding(.top, level <= 2 ? 4 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text):
            Text(context.styled(text))
                .font(.system(size: context.style.bodySize))
                .foregroundStyle(context.style.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .list(let list):
            ListView(list: list, context: context)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code, context: context)
        case .table(let table):
            TableView(table: table, context: context)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(context.style.border.opacity(2)).frame(width: 3)
                BlocksView(blocks: inner, context: quoted)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Rectangle().fill(context.style.border).frame(height: 1).padding(.vertical, 4)
        case .image(let source, let alt):
            MarkdownImageView(source: source, alt: alt, context: context)
        case .html(let raw):
            Text(raw)
                .font(.system(size: context.style.codeSize, design: .monospaced))
                .foregroundStyle(context.style.secondaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ListView: View {
    let list: MarkdownList
    let context: RenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(for: item, index: index)
                    BlocksView(blocks: item.blocks, context: context, spacing: 4)
                }
            }
        }
        .padding(.leading, 2)
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, index: Int) -> some View {
        if let task = item.task {
            Button {
                context.toggle?(task)
            } label: {
                Image(systemName: task.isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: context.style.bodySize))
                    .foregroundStyle(task.isChecked ? context.style.accent : context.style.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(context.toggle == nil || task.range == nil)
            .accessibilityLabel(task.isChecked ? "Checked" : "Unchecked")
        } else if list.isOrdered {
            Text("\(list.start + index).")
                .font(.system(size: context.style.bodySize).monospacedDigit())
                .foregroundStyle(context.style.secondaryText)
                .frame(minWidth: 18, alignment: .trailing)
        } else {
            Text("•")
                .font(.system(size: context.style.bodySize))
                .foregroundStyle(context.style.secondaryText)
                .frame(width: 12)
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String
    let context: RenderContext

    @State private var highlighted: AttributedString?
    @State private var hovering = false
    @State private var copied = false

    private var font: Font { .system(size: context.style.codeSize, design: .monospaced) }

    var body: some View {
        ScrollView(.horizontal) {
            Group {
                if let highlighted {
                    Text(highlighted)
                } else {
                    Text(code).foregroundStyle(context.style.text)
                }
            }
            .font(font)
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: true)
            .padding(12)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(context.style.codeBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(context.style.border, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                if let language, hovering {
                    Text(language).font(.system(size: 11)).foregroundStyle(context.style.secondaryText)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(context.style.secondaryText)
                        .padding(5)
                        .background(context.style.border, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Copy code")
                .accessibilityLabel("Copy code")
                .opacity(hovering || copied ? 1 : 0)
            }
            .padding(6)
        }
        .onHover { hovering = $0 }
        .task(id: "\(language ?? ""):\(code)") {
            highlighted = await context.highlighter.highlight(code, language: language)
        }
    }
}

private struct TableView: View {
    let table: MarkdownTable
    let context: RenderContext

    var body: some View {
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        TableCell(text: cell, alignment: alignment(column), isHeader: true, context: context)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            TableCell(text: cell, alignment: alignment(column), isHeader: false, context: context)
                        }
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(context.style.border, lineWidth: 1))
        }
        .scrollIndicators(.automatic)
    }

    private func alignment(_ column: Int) -> MarkdownAlignment {
        column < table.alignments.count ? table.alignments[column] : .leading
    }
}

private struct TableCell: View {
    let text: AttributedString
    let alignment: MarkdownAlignment
    let isHeader: Bool
    let context: RenderContext

    var body: some View {
        Text(context.styled(text))
            .font(.system(size: context.style.bodySize - 0.5, weight: isHeader ? .semibold : .regular))
            .foregroundStyle(context.style.text)
            .multilineTextAlignment(textAlignment)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHeader ? context.style.tableHeaderBackground : .clear)
            .border(context.style.border, width: 0.5)
            .gridColumnAlignment(horizontalAlignment)
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

private struct MarkdownImageView: View {
    let source: String
    let alt: String
    let context: RenderContext

    private enum Phase {
        case loading
        case loaded(NSImage)
        case failed
    }

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loaded(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel(alt)
            case .loading, .failed:
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                    Text(alt.isEmpty ? "image" : alt)
                }
                .font(.system(size: context.style.bodySize - 1))
                .foregroundStyle(context.style.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(context.style.codeBackground, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(alt.isEmpty ? "Image" : alt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: source) {
            switch await context.imageLoader.load(source) {
            case .loaded(let data):
                phase = NSImage(data: data).map(Phase.loaded) ?? .failed
            case .failed:
                phase = .failed
            }
        }
    }
}
