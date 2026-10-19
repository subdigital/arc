import ArcCore
import Foundation

/// Compact plain-text rendering used when `--json` is not given.
public enum HumanFormat {
    public static func table(_ headers: [String], _ rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        var widths = headers.map(\.count)
        for row in rows {
            for (index, cell) in row.enumerated() { widths[index] = max(widths[index], cell.count) }
        }
        func line(_ cells: [String]) -> String {
            // The last column is left unpadded so lines carry no trailing whitespace.
            cells.enumerated().map { index, cell in
                index == cells.count - 1 ? cell : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }
        return ([line(headers)] + rows.map(line))
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
    }

    public static func projects(_ projects: [ProjectDTO]) -> String {
        guard !projects.isEmpty else { return "No projects." }
        return table(
            ["NAME", "ARCHIVED", "DESCRIPTION"],
            projects.map { [$0.name, $0.archived ? "yes" : "", firstLine($0.description)] }
        )
    }

    public static func project(_ project: ProjectDTO) -> String {
        "\(project.name)\(project.archived ? " (archived)" : "")"
    }

    public static func tickets(_ tickets: [TicketDTO]) -> String {
        guard !tickets.isEmpty else { return "No tickets." }
        return table(
            ["ID", "STATUS", "PRIORITY", "KIND", "TITLE", "PROJECT", "EPIC"],
            tickets.map { ticket in
                var title = ticket.title
                if let progress = ticket.subtaskProgress { title += " [\(progress.done)/\(progress.total)]" }
                return [
                    ticket.identifier, ticket.status, ticket.priority, ticket.kind, title,
                    ticket.project.name, ticket.epic?.identifier ?? "",
                ]
            }
        )
    }

    public static func ticket(_ ticket: TicketDTO) -> String {
        var lines = ["\(ticket.identifier)  \(ticket.title)"]
        lines.append("Kind: \(ticket.kind)   Status: \(ticket.status)   Priority: \(ticket.priority)")
        lines.append("Project: \(ticket.project.name)")
        if let epic = ticket.epic { lines.append("Epic: \(epic.identifier) \(epic.title)") }
        if let parent = ticket.parent { lines.append("Parent: \(parent.identifier) \(parent.title)") }
        lines.append("Created: \(iso(ticket.createdAt))   Updated: \(iso(ticket.updatedAt))")
        if let completed = ticket.completedAt { lines.append("Completed: \(iso(completed))") }
        if let description = ticket.description, !description.isEmpty {
            lines.append("")
            lines.append(description)
        }
        if let subtasks = ticket.subtasks, !subtasks.isEmpty {
            lines.append("")
            lines.append("Subtasks:")
            lines += subtasks.map { "  \($0.identifier)  [\($0.status)]  \($0.title)" }
        }
        if let comments = ticket.comments, !comments.isEmpty {
            lines.append("")
            lines.append("Comments:")
            for comment in comments {
                lines.append("  [\(comment.author)] \(iso(comment.createdAt))")
                lines += comment.body.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : "    \($0)" }
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func comment(_ result: CommentResultDTO) -> String {
        "Added comment to \(result.ticket)."
    }

    public static func deleted(_ result: DeletedDTO) -> String {
        "Deleted \(result.identifier)."
    }

    private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
