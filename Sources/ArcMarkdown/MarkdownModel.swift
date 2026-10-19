import Foundation

/// A task-list checkbox. `range` is the `[ ]`/`[x]` text as UTF-8 offsets into the source the
/// blocks were parsed from; it is nil when the checkbox could not be located (not clickable).
public struct MarkdownTask: Sendable, Hashable {
    public var isChecked: Bool
    public var range: Range<Int>?

    public init(isChecked: Bool, range: Range<Int>?) {
        self.isChecked = isChecked
        self.range = range
    }
}

public enum MarkdownAlignment: Sendable, Hashable {
    case leading, center, trailing
}

public struct MarkdownListItem: Sendable, Hashable {
    public var blocks: [MarkdownBlock]
    public var task: MarkdownTask?

    public init(blocks: [MarkdownBlock], task: MarkdownTask? = nil) {
        self.blocks = blocks
        self.task = task
    }
}

public struct MarkdownList: Sendable, Hashable {
    public var isOrdered: Bool
    public var start: Int
    public var items: [MarkdownListItem]

    public init(isOrdered: Bool, start: Int = 1, items: [MarkdownListItem]) {
        self.isOrdered = isOrdered
        self.start = start
        self.items = items
    }
}

public struct MarkdownTable: Sendable, Hashable {
    public var alignments: [MarkdownAlignment]
    public var header: [AttributedString]
    public var rows: [[AttributedString]]

    public init(alignments: [MarkdownAlignment], header: [AttributedString], rows: [[AttributedString]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }
}

/// The renderer's input: a small, pure, `Sendable` tree produced by `MarkdownParser`.
public indirect enum MarkdownBlock: Sendable, Hashable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case list(MarkdownList)
    case code(language: String?, code: String)
    case table(MarkdownTable)
    case quote([MarkdownBlock])
    case rule
    case image(source: String, alt: String)
    /// Raw HTML, kept as literal text.
    case html(String)
}
