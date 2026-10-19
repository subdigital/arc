import Foundation
import Markdown

/// Parses GitHub Flavored Markdown (tables, strikethrough, task lists) into `[MarkdownBlock]`.
public enum MarkdownParser {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        // Smart punctuation is off so quotes and dashes in tickets stay exactly as typed.
        let document = Document(parsing: source, options: [.disableSmartOpts])
        let converter = Converter(source: source)
        return converter.blocks(of: document)
    }

    private struct Converter {
        let source: String
        let lineStarts: [Int]
        let bytes: [UInt8]

        init(source: String) {
            self.source = source
            self.bytes = Array(source.utf8)
            var starts = [0]
            for (index, byte) in bytes.enumerated() where byte == 0x0A { starts.append(index + 1) }
            self.lineStarts = starts
        }

        func blocks(of parent: Markup) -> [MarkdownBlock] {
            var result: [MarkdownBlock] = []
            for child in parent.children { result += block(child) }
            return result
        }

        func block(_ markup: Markup) -> [MarkdownBlock] {
            switch markup {
            case let heading as Heading:
                return [.heading(level: heading.level, text: inline(heading.children))]
            case let paragraph as Paragraph:
                return paragraphBlocks(paragraph)
            case let list as UnorderedList:
                return [.list(MarkdownList(isOrdered: false, items: listItems(list)))]
            case let list as OrderedList:
                return [.list(MarkdownList(isOrdered: true, start: Int(list.startIndex), items: listItems(list)))]
            case let code as CodeBlock:
                let language = code.language?.split(separator: " ").first.map(String.init)
                var text = code.code
                if text.hasSuffix("\n") { text.removeLast() }
                return [.code(language: language?.isEmpty == false ? language : nil, code: text)]
            case let table as Table:
                return [.table(convert(table))]
            case let quote as BlockQuote:
                return [.quote(blocks(of: quote))]
            case is ThematicBreak:
                return [.rule]
            case let html as HTMLBlock:
                return [.html(html.rawHTML.trimmingCharacters(in: .newlines))]
            default:
                // Anything unexpected still shows its text rather than vanishing.
                let text = markup.format().trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? [] : [.paragraph(AttributedString(text))]
            }
        }

        // MARK: Lists

        func listItems(_ list: some Markup) -> [MarkdownListItem] {
            list.children.compactMap { $0 as? ListItem }.map { item in
                var task: MarkdownTask?
                if let checkbox = item.checkbox {
                    task = MarkdownTask(isChecked: checkbox == .checked, range: checkboxRange(of: item))
                }
                return MarkdownListItem(blocks: blocks(of: item), task: task)
            }
        }

        /// Finds `[ ]`/`[x]` after the item's list marker, as UTF-8 offsets.
        func checkboxRange(of item: ListItem) -> Range<Int>? {
            guard let start = item.range?.lowerBound,
                  start.line >= 1, start.line <= lineStarts.count
            else { return nil }
            var index = lineStarts[start.line - 1] + start.column - 1
            guard index >= 0, index < bytes.count else { return nil }
            // Skip the marker ("-", "*", "+", "12." or "12)"), then the spaces after it.
            while index < bytes.count, bytes[index] != 0x20, bytes[index] != 0x09, bytes[index] != 0x0A { index += 1 }
            while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
            guard index + 3 <= bytes.count,
                  bytes[index] == UInt8(ascii: "["),
                  [UInt8(ascii: " "), UInt8(ascii: "x"), UInt8(ascii: "X")].contains(bytes[index + 1]),
                  bytes[index + 2] == UInt8(ascii: "]")
            else { return nil }
            return index..<(index + 3)
        }

        // MARK: Tables

        func convert(_ table: Table) -> MarkdownTable {
            let alignments = table.columnAlignments.map { alignment -> MarkdownAlignment in
                switch alignment {
                case .center: .center
                case .right: .trailing
                default: .leading
                }
            }
            let header = Array(table.head.cells.map { inline($0.children) })
            let rows = Array(table.body.rows.map { row in Array(row.cells.map { inline($0.children) }) })
            return MarkdownTable(alignments: alignments, header: header, rows: rows)
        }

        // MARK: Paragraphs and images

        /// Standalone images become blocks of their own; the text around them stays paragraphs.
        func paragraphBlocks(_ paragraph: Paragraph) -> [MarkdownBlock] {
            var result: [MarkdownBlock] = []
            var pending: [Markup] = []

            func flush() {
                guard !pending.isEmpty else { return }
                var text = inline(pending)
                pending = []
                trim(&text)
                if !text.characters.isEmpty { result.append(.paragraph(text)) }
            }

            for child in paragraph.children {
                if let image = child as? Image {
                    flush()
                    result.append(.image(source: image.source ?? "", alt: image.plainText))
                } else {
                    pending.append(child)
                }
            }
            flush()
            return result
        }

        /// Removes leading/trailing newlines left by breaks next to an image.
        func trim(_ text: inout AttributedString) {
            while let first = text.characters.first, first == "\n" {
                text.removeSubrange(text.startIndex..<text.index(afterCharacter: text.startIndex))
            }
            while let last = text.characters.last, last == "\n" {
                text.removeSubrange(text.index(beforeCharacter: text.endIndex)..<text.endIndex)
            }
        }

        // MARK: Inline content

        func inline(_ children: some Sequence<Markup>) -> AttributedString {
            var result = AttributedString()
            for child in children { append(child, intent: [], link: nil, to: &result) }
            return result
        }

        func append(_ markup: Markup, intent: InlinePresentationIntent, link: URL?, to output: inout AttributedString) {
            func run(_ text: String, intent: InlinePresentationIntent) {
                var piece = AttributedString(text)
                if !intent.isEmpty { piece.inlinePresentationIntent = intent }
                if let link { piece.link = link }
                output.append(piece)
            }

            switch markup {
            case let text as Text:
                run(text.string, intent: intent)
            case is SoftBreak, is LineBreak:
                // GitHub comments keep single newlines as line breaks.
                run("\n", intent: intent)
            case let code as InlineCode:
                run(code.code, intent: intent.union(.code))
            case let html as InlineHTML:
                run(html.rawHTML, intent: intent)
            case let image as Image:
                run(image.plainText, intent: intent)
            case let emphasis as Emphasis:
                for child in emphasis.children { append(child, intent: intent.union(.emphasized), link: link, to: &output) }
            case let strong as Strong:
                for child in strong.children { append(child, intent: intent.union(.stronglyEmphasized), link: link, to: &output) }
            case let strike as Strikethrough:
                for child in strike.children { append(child, intent: intent.union(.strikethrough), link: link, to: &output) }
            case let anchor as Link:
                let destination = anchor.destination.flatMap { URL(string: $0) } ?? link
                for child in anchor.children { append(child, intent: intent, link: destination, to: &output) }
            default:
                for child in markup.children { append(child, intent: intent, link: link, to: &output) }
            }
        }
    }
}
