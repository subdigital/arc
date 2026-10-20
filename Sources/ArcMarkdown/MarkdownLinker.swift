import Foundation

/// Turns `ARC-12` ticket references and bare URLs into links, skipping code and existing links.
public enum MarkdownLinker {
    public static let ticketScheme = "arc"
    public static let ticketHost = "ticket"

    /// `identifier` is a ticket key such as `ARC-12` or `FIC-7`.
    public static func ticketURL(identifier: String) -> URL {
        URL(string: "\(ticketScheme)://\(ticketHost)/\(identifier.uppercased())")!
    }

    /// The identifier in an `arc://ticket/<identifier>` URL (a bare number from older links means `ARC-n`).
    public static func ticketIdentifier(from url: URL) -> String? {
        guard url.scheme == ticketScheme, url.host == ticketHost else { return nil }
        let last = url.lastPathComponent.uppercased()
        if Int(last) != nil { return "ARC-\(last)" }
        return last.contains("-") ? last : nil
    }

    private static let ticketPattern = try! NSRegularExpression(pattern: #"\b([A-Za-z][A-Za-z0-9]{1,9})-(\d+)\b"#)
    private static let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s<>]+"#, options: [.caseInsensitive])

    /// Links identifiers such as `ARC-n` that are in `knownTickets` (uppercased; others stay plain) and, when `detectURLs`, bare http(s) URLs.
    public static func link(_ blocks: [MarkdownBlock], knownTickets: Set<String>, detectURLs: Bool = true) -> [MarkdownBlock] {
        blocks.map { link($0, knownTickets, detectURLs) }
    }

    public static func link(_ text: AttributedString, knownTickets: Set<String>, detectURLs: Bool = true) -> AttributedString {
        var result = text
        // Runs are collected first because mutating while iterating would invalidate them.
        for run in Array(text.runs) {
            guard run.link == nil, !(run.inlinePresentationIntent ?? []).contains(.code) else { continue }
            let plain = String(text[run.range].characters)
            var matches: [(range: NSRange, url: URL)] = []

            if detectURLs {
                for match in urlPattern.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                    let trimmed = trimmedURLRange(match.range, in: plain)
                    if let url = URL(string: (plain as NSString).substring(with: trimmed)) { matches.append((trimmed, url)) }
                }
            }
            for match in ticketPattern.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                let identifier = (plain as NSString).substring(with: match.range).uppercased()
                guard knownTickets.contains(identifier),
                      !matches.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 })
                else { continue }
                matches.append((match.range, ticketURL(identifier: identifier)))
            }

            for (nsRange, url) in matches {
                guard let range = Range(nsRange, in: plain) else { continue }
                let lower = result.index(run.range.lowerBound, offsetByCharacters: plain.distance(from: plain.startIndex, to: range.lowerBound))
                let upper = result.index(lower, offsetByCharacters: plain.distance(from: range.lowerBound, to: range.upperBound))
                result[lower..<upper].link = url
            }
        }
        return result
    }

    /// Drops trailing punctuation (and an unmatched `)`) that belongs to the sentence, not the URL.
    private static func trimmedURLRange(_ range: NSRange, in text: String) -> NSRange {
        let string = text as NSString
        var length = range.length
        while length > 0 {
            let last = string.character(at: range.location + length - 1)
            guard let scalar = Unicode.Scalar(last) else { break }
            let character = Character(scalar)
            if ".,;:!?'\"".contains(character) {
                length -= 1
            } else if character == ")" {
                let candidate = string.substring(with: NSRange(location: range.location, length: length))
                if candidate.filter({ $0 == "(" }).count < candidate.filter({ $0 == ")" }).count { length -= 1 } else { break }
            } else {
                break
            }
        }
        return NSRange(location: range.location, length: length)
    }

    private static func link(_ block: MarkdownBlock, _ known: Set<String>, _ detectURLs: Bool) -> MarkdownBlock {
        switch block {
        case .heading(let level, let text):
            return .heading(level: level, text: link(text, knownTickets: known, detectURLs: detectURLs))
        case .paragraph(let text):
            return .paragraph(link(text, knownTickets: known, detectURLs: detectURLs))
        case .list(var list):
            list.items = list.items.map { item in
                var item = item
                item.blocks = link(item.blocks, knownTickets: known, detectURLs: detectURLs)
                return item
            }
            return .list(list)
        case .table(var table):
            table.header = table.header.map { link($0, knownTickets: known, detectURLs: detectURLs) }
            table.rows = table.rows.map { $0.map { link($0, knownTickets: known, detectURLs: detectURLs) } }
            return .table(table)
        case .quote(let blocks):
            return .quote(link(blocks, knownTickets: known, detectURLs: detectURLs))
        case .code, .rule, .image, .html:
            return block
        }
    }
}
