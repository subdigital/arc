import ArcMarkdown
import Foundation

/// Thin alias so views do not need to import the whole Markdown module just to decode `arc://` links.
enum MarkdownLinks {
    static func ticketNumber(from url: URL) -> Int? { MarkdownLinker.ticketNumber(from: url) }
}
