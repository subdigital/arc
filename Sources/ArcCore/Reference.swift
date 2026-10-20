import Foundation

/// Lenient parsing of the human-style references accepted by the CLI, MCP tools and app:
/// ticket identifiers, statuses, priorities and kinds.
/// A ticket's key: the prefix and number that make up an identifier such as `ARC-12`.
public struct TicketKey: Hashable, Sendable {
    public var prefix: String
    public var number: Int

    public var identifier: String { "\(prefix)-\(number)" }
}

public enum Reference {
    public static let identifierPrefix = "ARC"

    public static func identifier(for number: Int) -> String { "\(identifierPrefix)-\(number)" }

    /// `ARC-12`, `fic-7`, `12` (a bare number means `ARC-12`); surrounding whitespace is ignored.
    public static func ticketKey(_ reference: String) throws -> TicketKey {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let prefix: String
        let digits: Substring
        if parts.count == 2 {
            prefix = parts[0].uppercased()
            digits = parts[1]
            guard let first = prefix.first, first.isLetter, prefix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                throw invalidReference(reference)
            }
        } else {
            prefix = identifierPrefix
            digits = Substring(trimmed)
        }
        guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit), let number = Int(digits), number > 0 else {
            throw invalidReference(reference)
        }
        return TicketKey(prefix: prefix, number: number)
    }

    private static func invalidReference(_ reference: String) -> ArcError {
        ArcError.invalidArgument("'\(reference)' is not a ticket reference. Use an identifier like ARC-12 (or FIC-7 for imported tickets), or a bare number for ARC tickets.")
    }

    /// `In Progress`, `in-progress`, `in_progress` → `.inProgress`.
    public static func status(_ reference: String) throws -> TicketStatus {
        let key = normalize(reference)
        if let status = TicketStatus(rawValue: key) { return status }
        if key == "cancelled" { return .canceled }
        throw ArcError.invalidArgument(
            "Unknown status '\(reference)'. Valid statuses: \(TicketStatus.allCases.map(\.rawValue).joined(separator: ", "))."
        )
    }

    public static func priority(_ reference: String) throws -> TicketPriority {
        let key = normalize(reference)
        if let match = TicketPriority.allCases.first(where: { $0.name == key }) { return match }
        throw ArcError.invalidArgument(
            "Unknown priority '\(reference)'. Valid priorities: \(TicketPriority.allCases.map(\.name).joined(separator: ", "))."
        )
    }

    /// Lowercases, trims, and turns runs of spaces/hyphens into underscores.
    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[\\s-]+", with: "_", options: .regularExpression)
    }

    static func projectKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
