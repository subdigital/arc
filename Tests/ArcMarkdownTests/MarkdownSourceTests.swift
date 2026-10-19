import Foundation
import Testing
@testable import ArcMarkdown

@Suite struct MarkdownSourceTests {
    private func tasks(_ source: String) -> [MarkdownTask] {
        func collect(_ blocks: [MarkdownBlock]) -> [MarkdownTask] {
            blocks.flatMap { block -> [MarkdownTask] in
                switch block {
                case .list(let list): list.items.flatMap { ($0.task.map { [$0] } ?? []) + collect($0.blocks) }
                case .quote(let inner): collect(inner)
                default: []
                }
            }
        }
        return collect(MarkdownParser.parse(source))
    }

    @Test func togglesOnlyTheCheckboxCharacters() throws {
        let source = "# Plan\n\n- [ ] Write tests\n- [x] Ship it\n\nTrailing   text  \n"
        let all = tasks(source)
        #expect(all.count == 2)

        let ticked = try #require(MarkdownSource.toggleTask(all[0], in: source))
        #expect(ticked == "# Plan\n\n- [x] Write tests\n- [x] Ship it\n\nTrailing   text  \n")

        let unticked = try #require(MarkdownSource.toggleTask(all[1], in: source))
        #expect(unticked == "# Plan\n\n- [ ] Write tests\n- [ ] Ship it\n\nTrailing   text  \n")
    }

    @Test func restOfSourceIsByteIdentical() throws {
        let source = "é intro ✓\n\n   - [ ] nested ünï\n\n1. [X] numbered\n\t- [ ] tabbed\r\n"
        for task in tasks(source) {
            let toggled = try #require(MarkdownSource.toggleTask(task, in: source))
            let before = Array(source.utf8), after = Array(toggled.utf8)
            #expect(before.count == after.count)
            let range = try #require(task.range)
            var changed: [Int] = []
            for index in before.indices where before[index] != after[index] { changed.append(index) }
            #expect(changed == [range.lowerBound + 1])
        }
    }

    @Test func nestedAndNumberedItems() throws {
        let source = "- parent\n  - [ ] child\n1. [ ] first\n2. [x] second"
        let all = tasks(source)
        #expect(all.map(\.isChecked) == [false, false, true])
        let toggled = try #require(MarkdownSource.toggleTask(all[0], in: source))
        #expect(toggled == "- parent\n  - [x] child\n1. [ ] first\n2. [x] second")
        let second = try #require(MarkdownSource.toggleTask(all[2], in: source))
        #expect(second == "- parent\n  - [ ] child\n1. [ ] first\n2. [ ] second")
    }

    @Test func staleRangeIsRejected() throws {
        let source = "- [ ] one\n- [ ] two"
        let all = tasks(source)
        // Someone ticked it elsewhere since rendering.
        #expect(MarkdownSource.toggleTask(all[0], in: "- [x] one\n- [ ] two") == nil)
        // The text moved.
        #expect(MarkdownSource.toggleTask(all[1], in: "intro\n- [ ] one\n- [ ] two") == nil)
        // The source got shorter.
        #expect(MarkdownSource.toggleTask(all[1], in: "- [ ]") == nil)
        // No range to work with.
        #expect(MarkdownSource.toggleTask(MarkdownTask(isChecked: false, range: nil), in: source) == nil)
    }

    @Test func togglingTwiceRestoresTheOriginal() throws {
        let source = "- [ ] a\n- [x] b"
        let first = try #require(MarkdownSource.toggleTask(tasks(source)[0], in: source))
        let again = try #require(MarkdownSource.toggleTask(tasks(first)[0], in: first))
        #expect(again == source)
    }
}
