import AppKit
import Foundation
import Testing
@testable import ArcMarkdown

@Suite struct HighlighterTests {
    private func colors(_ text: AttributedString) -> Set<NSColor> {
        Set(text.runs.compactMap { $0.appKit.foregroundColor })
    }

    @Test func swiftProducesSeveralColoredRuns() async throws {
        let highlighter = HighlightSwiftHighlighter()
        let code = """
        // greeting
        let message = "hello"
        func add(_ a: Int, _ b: Int) -> Int { return a + b }
        """
        let result = try #require(await highlighter.highlight(code, language: "swift"))
        #expect(String(result.characters).trimmingCharacters(in: .whitespacesAndNewlines) == code)
        #expect(result.runs.count > 5)
        #expect(colors(result).count >= 3, "keywords, strings and comments should differ")
    }

    @Test func worksOffTheMainThread() async throws {
        let highlighter = HighlightSwiftHighlighter()
        let result = await Task.detached {
            await highlighter.highlight("let x = 1", language: "swift")
        }.value
        #expect(result != nil)
    }

    @Test func unknownOrMissingLanguageIsPlain() async {
        let highlighter = HighlightSwiftHighlighter()
        #expect(await highlighter.highlight("some text", language: "nosuchlang") == nil)
        #expect(await highlighter.highlight("some text", language: nil) == nil)
        #expect(await highlighter.highlight("some text", language: "") == nil)
        #expect(await highlighter.highlight("", language: "swift") == nil)
    }

    @Test func languageAliasesAndCaseWork() async {
        let highlighter = HighlightSwiftHighlighter()
        for language in ["Swift", "js", "python", "json", "bash", "sh"] {
            #expect(await highlighter.highlight("x = 1", language: language) != nil, "\(language)")
        }
    }

    @Test func repeatedRequestsAreCached() async throws {
        let highlighter = HighlightSwiftHighlighter()
        let first = try #require(await highlighter.highlight("let a = 1", language: "swift"))
        let second = try #require(await highlighter.highlight("let a = 1", language: "swift"))
        #expect(first == second)
    }
}
