import Foundation

/// Lenient parsing of the human-style references accepted by the CLI, MCP tools and app:
/// ticket identifiers, statuses, priorities and kinds.
public enum Reference {
    public static let identifierPrefix = "ARC"

    public static func identifier(for number: Int) -> String { "\(identifierPrefix)-\(number)" }

    /// `ARC-12`, `arc-12`, `12` (surrounding whitespace ignored) → 12.
    public static func ticketNumber(_ reference: String) throws -> Int {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        var digits = Substring(trimmed)
        if trimmed.range(of: "^arc-", options: [.regularExpression, .caseInsensitive]) != nil {
            digits = digits.dropFirst(4)
        }
        guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit), let number = Int(digits), number > 0 else {
            throw ArcError.invalidArgument("'\(reference)' is not a ticket reference. Use an identifier like ARC-12 or a bare number.")
        }
        return number
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

    public static func kind(_ reference: String) throws -> TicketKind {
        let key = normalize(reference)
        if let kind = TicketKind(rawValue: key) { return kind }
        throw ArcError.invalidArgument(
            "Unknown kind '\(reference)'. Valid kinds: \(TicketKind.allCases.map(\.rawValue).joined(separator: ", "))."
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
