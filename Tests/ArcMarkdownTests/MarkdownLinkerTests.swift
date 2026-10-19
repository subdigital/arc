import Foundation
import Testing
@testable import ArcMarkdown

@Suite struct MarkdownLinkerTests {
    private func links(_ blocks: [MarkdownBlock]) -> [(String, URL)] {
        var found: [(String, URL)] = []
        func visit(_ blocks: [MarkdownBlock]) {
            for block in blocks {
                switch block {
                case .paragraph(let text), .heading(_, let text): found += linkRuns(text)
                case .list(let list): list.items.forEach { visit($0.blocks) }
                case .quote(let inner): visit(inner)
                case .table(let table): (table.header + table.rows.flatMap { $0 }).forEach { found += linkRuns($0) }
                default: break
                }
            }
        }
        visit(blocks)
        return found
    }

    private func linkRuns(_ text: AttributedString) -> [(String, URL)] {
        text.runs.compactMap { run in run.link.map { (String(text[run.range].characters), $0) } }
    }

    private func linked(_ source: String, known: Set<Int>, urls: Bool = true) -> [(String, URL)] {
        links(MarkdownLinker.link(MarkdownParser.parse(source), knownTickets: known, detectURLs: urls))
    }

    @Test func knownTicketIsLinked() {
        let result = linked("Blocked by ARC-12 until Friday", known: [12])
        #expect(result.count == 1)
        #expect(result[0].0 == "ARC-12")
        #expect(result[0].1 == URL(string: "arc://ticket/12"))
        #expect(MarkdownLinker.ticketNumber(from: result[0].1) == 12)
    }

    @Test func caseInsensitiveAndMultiple() {
        let result = linked("arc-3, Arc-4 and ARC-5.", known: [3, 4, 5])
        #expect(result.map(\.0) == ["arc-3", "Arc-4", "ARC-5"])
    }

    @Test func unknownTicketStaysPlain() {
        #expect(linked("See ARC-99", known: [12]).isEmpty)
    }

    @Test func notLinkedInsideCode() {
        #expect(linked("Use `ARC-12` here", known: [12]).isEmpty)
        #expect(linked("```\nARC-12\n```", known: [12]).isEmpty)
        #expect(linked("    ARC-12 indented code", known: [12]).isEmpty)
    }

    @Test func partialMatchesAreIgnored() {
        #expect(linked("XARC-12 and ARC-12x and ARC-", known: [12]).isEmpty)
    }

    @Test func linkedInListsQuotesTablesAndHeadings() {
        let source = "# About ARC-1\n\n- item ARC-1\n\n> quote ARC-1\n\n| h |\n| - |\n| ARC-1 |"
        #expect(linked(source, known: [1]).count == 4)
    }

    @Test func existingLinksAreLeftAlone() {
        let result = linked("[see ARC-12](https://example.com/x) and ARC-12", known: [12])
        #expect(result.count == 2)
        #expect(result[0].1 == URL(string: "https://example.com/x"))
        #expect(result[1].1 == URL(string: "arc://ticket/12"))
    }

    @Test func bareURLsBecomeLinksWithoutTrailingPunctuation() {
        let result = linked("Visit https://example.com/path?q=1. Also (https://example.com/a_(b)) and http://x.org, ok", known: [])
        #expect(result.map(\.0) == ["https://example.com/path?q=1", "https://example.com/a_(b)", "http://x.org"])
        #expect(linked("see https://example.com", known: [], urls: false).isEmpty)
    }

    @Test func urlContainingTicketIdIsOneLink() {
        let result = linked("https://example.com/ARC-12", known: [12])
        #expect(result.count == 1)
        #expect(result[0].1 == URL(string: "https://example.com/ARC-12"))
    }
}
