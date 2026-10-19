import Foundation
import Testing
@testable import ArcMarkdown

func plain(_ text: AttributedString) -> String { String(text.characters) }

func intents(_ text: AttributedString) -> [(String, InlinePresentationIntent)] {
    text.runs.map { (String(text[$0.range].characters), $0.inlinePresentationIntent ?? []) }
}

@Suite struct MarkdownParserTests {
    @Test func headingsAndParagraphs() {
        let blocks = MarkdownParser.parse("# One\n\n###### Six\n\nHello world")
        #expect(blocks.count == 3)
        guard case .heading(1, let one) = blocks[0], case .heading(6, let six) = blocks[1], case .paragraph(let body) = blocks[2] else {
            Issue.record("unexpected blocks: \(blocks)")
            return
        }
        #expect(plain(one) == "One")
        #expect(plain(six) == "Six")
        #expect(plain(body) == "Hello world")
    }

    @Test func inlineFormatting() {
        let blocks = MarkdownParser.parse("a **bold** *it* ~~gone~~ `code` [link](https://example.com) ***both***")
        guard case .paragraph(let text) = blocks[0] else { Issue.record("not a paragraph"); return }
        #expect(plain(text) == "a bold it gone code link both")
        let runs = intents(text)
        #expect(runs.contains { $0.0 == "bold" && $0.1 == .stronglyEmphasized })
        #expect(runs.contains { $0.0 == "it" && $0.1 == .emphasized })
        #expect(runs.contains { $0.0 == "gone" && $0.1 == .strikethrough })
        #expect(runs.contains { $0.0 == "code" && $0.1 == .code })
        #expect(runs.contains { $0.0 == "both" && $0.1 == [.emphasized, .stronglyEmphasized] })
        let link = text.runs.first { $0.link != nil }
        #expect(link?.link == URL(string: "https://example.com"))
        #expect(link.map { String(text[$0.range].characters) } == "link")
    }

    @Test func softBreaksKeepTheNewline() {
        guard case .paragraph(let text) = MarkdownParser.parse("line one\nline two")[0] else { return }
        #expect(plain(text) == "line one\nline two")
    }

    @Test func straightQuotesAndDashesAreNotMadeSmart() {
        guard case .paragraph(let text) = MarkdownParser.parse(#"He said "hi" -- really..."#)[0] else { return }
        #expect(plain(text) == #"He said "hi" -- really..."#)
    }

    @Test func nestedBulletedAndNumberedLists() {
        let source = """
        - one
          - nested a
          - nested b
            1. deep
        - two

        3. three
        4. four
        """
        let blocks = MarkdownParser.parse(source)
        guard case .list(let outer) = blocks[0] else { Issue.record("no list"); return }
        #expect(!outer.isOrdered)
        #expect(outer.items.count == 2)
        guard case .list(let inner) = outer.items[0].blocks[1] else { Issue.record("no nested list"); return }
        #expect(inner.items.count == 2)
        guard case .list(let deep) = inner.items[1].blocks[1] else { Issue.record("no third level"); return }
        #expect(deep.isOrdered)
        guard case .list(let numbered) = blocks[1] else { Issue.record("no numbered list"); return }
        #expect(numbered.isOrdered && numbered.start == 3 && numbered.items.count == 2)
    }

    @Test func taskItemsCarryStateAndSourceRange() {
        let source = "- [ ] Write tests\n- [x] Ship it\n  - [ ] nested\n1. [X] numbered"
        let blocks = MarkdownParser.parse(source)
        guard case .list(let list) = blocks[0] else { Issue.record("no list"); return }
        let first = list.items[0].task
        #expect(first?.isChecked == false)
        #expect(first?.range == 2..<5)
        let second = list.items[1].task
        #expect(second?.isChecked == true)
        let bytes = Array(source.utf8)
        for task in [first, second].compactMap({ $0 }) {
            let range = task.range!
            #expect(String(decoding: bytes[range], as: UTF8.self).hasPrefix("["))
        }
        guard case .list(let nested) = list.items[1].blocks[1] else { Issue.record("no nested"); return }
        #expect(nested.items[0].task?.isChecked == false)
        #expect(String(decoding: bytes[nested.items[0].task!.range!], as: UTF8.self) == "[ ]")
        guard case .list(let numbered) = blocks[1] else { Issue.record("no numbered"); return }
        #expect(numbered.items[0].task?.isChecked == true)
        #expect(String(decoding: bytes[numbered.items[0].task!.range!], as: UTF8.self) == "[X]")
    }

    @Test func taskRangesUseUTF8OffsetsAfterMultibyteText() {
        let source = "é ünïcode ✓\n\n- [ ] after multibyte"
        guard case .list(let list) = MarkdownParser.parse(source)[1] else { Issue.record("no list"); return }
        let range = list.items[0].task!.range!
        #expect(String(decoding: Array(source.utf8)[range], as: UTF8.self) == "[ ]")
    }

    @Test func checkboxesInsideBlockquotesRenderAsPlainText() {
        // cmark-gfm's tasklist extension does not apply inside blockquotes; the text must survive.
        guard case .quote(let inner) = MarkdownParser.parse("> - [ ] quoted task")[0], case .list(let list) = inner[0],
              case .paragraph(let text) = list.items[0].blocks[0]
        else { Issue.record("unexpected structure"); return }
        #expect(list.items[0].task == nil)
        #expect(plain(text) == "[ ] quoted task")
    }

    @Test func codeBlocksKeepLanguageAndText() {
        let source = "```swift\nlet x = 1\nprint(x)\n```\n\n    indented\n\n```\nplain\n```"
        let blocks = MarkdownParser.parse(source)
        #expect(blocks[0] == .code(language: "swift", code: "let x = 1\nprint(x)"))
        #expect(blocks[1] == .code(language: nil, code: "indented"))
        #expect(blocks[2] == .code(language: nil, code: "plain"))
    }

    @Test func tablesKeepAlignmentAndCells() {
        let source = """
        | Name | Count | Note |
        | :--- | ----: | :--: |
        | a    | 1     | x    |
        | **b** | 22   | y    |
        """
        guard case .table(let table) = MarkdownParser.parse(source)[0] else { Issue.record("no table"); return }
        #expect(table.alignments == [.leading, .trailing, .center])
        #expect(table.header.map(plain) == ["Name", "Count", "Note"])
        #expect(table.rows.count == 2)
        #expect(table.rows[1].map(plain) == ["b", "22", "y"])
        #expect(intents(table.rows[1][0]).first?.1 == .stronglyEmphasized)
    }

    @Test func blockquotesRulesAndNestedContent() {
        let blocks = MarkdownParser.parse("> quoted **text**\n> > deeper\n\n---\n\nafter")
        guard case .quote(let inner) = blocks[0] else { Issue.record("no quote"); return }
        #expect(inner.count == 2)
        guard case .quote = inner[1] else { Issue.record("no nested quote"); return }
        #expect(blocks[1] == .rule)
        guard case .paragraph = blocks[2] else { Issue.record("no paragraph"); return }
    }

    @Test func imagesBecomeBlocksAndSplitParagraphs() {
        let blocks = MarkdownParser.parse("![diagram](https://example.com/d.png)\n\nbefore ![alt text](/tmp/x.png) after")
        #expect(blocks[0] == .image(source: "https://example.com/d.png", alt: "diagram"))
        guard blocks.count == 4, case .paragraph(let before) = blocks[1], case .paragraph(let after) = blocks[3] else {
            Issue.record("unexpected blocks: \(blocks)")
            return
        }
        #expect(plain(before) == "before ")
        #expect(blocks[2] == .image(source: "/tmp/x.png", alt: "alt text"))
        #expect(plain(after) == " after")
    }

    @Test func rawHTMLStaysLiteralText() {
        let blocks = MarkdownParser.parse("<div class=\"x\">hi</div>\n\nText with <b>inline</b> html")
        #expect(blocks[0] == .html("<div class=\"x\">hi</div>"))
        guard case .paragraph(let text) = blocks[1] else { Issue.record("no paragraph"); return }
        #expect(plain(text) == "Text with <b>inline</b> html")
    }

    @Test func emptyAndWhitespaceInput() {
        #expect(MarkdownParser.parse("").isEmpty)
        #expect(MarkdownParser.parse("  \n\n ").isEmpty)
    }

    @Test func kitchenSinkParsesEveryBlockKind() {
        let blocks = MarkdownParser.parse(MarkdownFixtures.kitchenSink)
        func has(_ test: (MarkdownBlock) -> Bool) -> Bool { blocks.contains(where: test) }
        #expect(has { if case .heading = $0 { true } else { false } })
        #expect(has { if case .list = $0 { true } else { false } })
        #expect(has { if case .code = $0 { true } else { false } })
        #expect(has { if case .table = $0 { true } else { false } })
        #expect(has { if case .quote = $0 { true } else { false } })
        #expect(has { if case .rule = $0 { true } else { false } })
        #expect(has { if case .image = $0 { true } else { false } })
        #expect(has { if case .html = $0 { true } else { false } })
    }
}

enum MarkdownFixtures {
    static let kitchenSink = """
    # Heading 1
    ## Heading 2
    ###### Heading 6

    Paragraph with **bold**, *italic*, ~~strike~~, `code`, a [link](https://example.com) and https://bare.example.com/path.
    See ARC-12 and `ARC-12`.

    - bullet
      - nested
    1. numbered
    2. second

    - [ ] todo item
    - [x] done item

    > quote
    > continues

    ---

    ```swift
    // comment
    let greeting = "hello"
    func add(_ a: Int, _ b: Int) -> Int { a + b }
    ```

    | Left | Right |
    | :--- | ----: |
    | a | 1 |

    ![diagram](https://example.com/d.png)

    <div>raw html</div>
    """
}
