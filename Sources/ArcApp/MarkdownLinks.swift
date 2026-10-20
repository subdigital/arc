import ArcMarkdown
import Foundation

/// Thin alias so views do not need to import the whole Markdown module just to decode `arc://` links.
enum MarkdownLinks {
    static func ticketIdentifier(from url: URL) -> String? { MarkdownLinker.ticketIdentifier(from: url) }
}
