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
            ["ID", "STATUS", "PRIORITY", "TITLE", "PROJECT", "PARENT", "LABELS"],
            tickets.map { ticket in
                var title = ticket.title
                if let progress = ticket.childProgress { title += " [\(progress.done)/\(progress.total)]" }
                if ticket.blocked == true { title += " (blocked)" }
                return [
                    ticket.identifier, ticket.status, ticket.priority, title,
                    ticket.project.name, ticket.parent?.identifier ?? "", ticket.labels.map(\.name).joined(separator: ", "),
                ]
            }
        )
    }

    public static func ticket(_ ticket: TicketDTO) -> String {
        var lines = ["\(ticket.identifier)  \(ticket.title)"]
        lines.append("Status: \(ticket.status)   Priority: \(ticket.priority)")
        lines.append("Project: \(ticket.project.name)")
        if let parent = ticket.parent { lines.append("Parent: \(parent.identifier) \(parent.title)") }
        if let milestone = ticket.milestone { lines.append("Milestone: \(milestone)") }
        if !ticket.labels.isEmpty { lines.append("Labels: \(ticket.labels.map(\.name).joined(separator: ", "))") }
        lines.append("Created: \(iso(ticket.createdAt))   Updated: \(iso(ticket.updatedAt))")
        if let started = ticket.startedAt { lines.append("Started: \(iso(started))") }
        if let completed = ticket.completedAt { lines.append("Completed: \(iso(completed))") }
        if let canceled = ticket.canceledAt { lines.append("Canceled: \(iso(canceled))") }
        if let archived = ticket.archivedAt { lines.append("Archived: \(iso(archived))") }
        if let relations = ticket.relations {
            func list(_ title: String, _ refs: [TicketRefDTO]) {
                guard !refs.isEmpty else { return }
                lines.append("\(title): " + refs.map { "\($0.identifier) [\($0.status)]" }.joined(separator: ", "))
            }
            list("Blocked by", relations.blockedBy)
            list("Blocks", relations.blocks)
            list("Related", relations.related)
            list("Duplicate of", relations.duplicateOf)
            list("Duplicated by", relations.duplicatedBy)
        }
        if let description = ticket.description, !description.isEmpty {
            lines.append("")
            lines.append(description)
        }
        if let children = ticket.children, !children.isEmpty {
            lines.append("")
            lines.append("Children:")
            lines += children.map { "  \($0.identifier)  [\($0.status)]  \($0.title)" }
        }
        if let attachments = ticket.attachments, !attachments.isEmpty {
            lines.append("")
            lines.append("Attachments:")
            lines += attachments.map { "  [\($0.kind)] \($0.title)  \($0.path ?? $0.url ?? "")" }
        }
        if let comments = ticket.comments, !comments.isEmpty {
            lines.append("")
            lines.append("Comments:")
            for comment in comments {
                let reply = comment.replyTo.map { _ in " (reply)" } ?? ""
                lines.append("  [\(comment.authorName ?? comment.author)\(reply)] \(iso(comment.createdAt))")
                lines += comment.body.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : "    \($0)" }
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func milestones(_ milestones: [MilestoneDTO]) -> String {
        guard !milestones.isEmpty else { return "No milestones." }
        return table(
            ["NAME", "TARGET", "DESCRIPTION"],
            milestones.map { [$0.name, $0.targetDate.map { $0.formatted(.iso8601.year().month().day()) } ?? "", firstLine($0.description)] }
        )
    }

    public static func labels(_ labels: [LabelDTO]) -> String {
        labels.isEmpty ? "No labels." : labels.map(\.name).joined(separator: "\n")
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
