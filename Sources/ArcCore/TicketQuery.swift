import Foundation
import GRDB

public struct TicketQuery: Sendable, Equatable {
    public var projectIds: Set<String>
    public var statuses: Set<TicketStatus>
    public var priorities: Set<TicketPriority>
    /// Only direct children of this ticket.
    public var parentId: String?
    /// Only tickets without a parent.
    public var topLevelOnly: Bool
    /// Tickets with any of these labels.
    public var labelIds: Set<String>
    public var milestoneId: String?
    public var text: String?
    /// Without explicit `statuses`, closed tickets (Done, Canceled) are left out unless this is true.
    public var includeClosed: Bool
    /// Archived projects' tickets are only listed when asked for, or when `projectIds` names them.
    public var includeArchivedProjects: Bool
    public var limit: Int?

    public init(
        projectIds: Set<String> = [],
        statuses: Set<TicketStatus> = [],
        priorities: Set<TicketPriority> = [],
        parentId: String? = nil,
        topLevelOnly: Bool = false,
        labelIds: Set<String> = [],
        milestoneId: String? = nil,
        text: String? = nil,
        includeClosed: Bool = false,
        includeArchivedProjects: Bool = false,
        limit: Int? = nil
    ) {
        self.projectIds = projectIds
        self.statuses = statuses
        self.priorities = priorities
        self.parentId = parentId
        self.topLevelOnly = topLevelOnly
        self.labelIds = labelIds
        self.milestoneId = milestoneId
        self.text = text
        self.includeClosed = includeClosed
        self.includeArchivedProjects = includeArchivedProjects
        self.limit = limit
    }
}

public struct TicketRef: Sendable, Hashable {
    public var id: String
    public var prefix: String
    public var number: Int
    public var title: String
    public var status: TicketStatus

    public var identifier: String { "\(prefix)-\(number)" }
}

/// A ticket plus the joined data list rows and cards need.
public struct TicketSummary: Sendable, Hashable, Identifiable, FetchableRecord {
    public var ticket: Ticket
    public var projectName: String
    public var parent: TicketRef?
    public var childCount: Int
    public var childrenDone: Int
    public var milestoneName: String?
    /// True while at least one ticket that blocks this one is still open.
    public var isBlocked: Bool
    public var labels: [TicketLabel] = []

    public var id: String { ticket.id }

    public init(row: Row) throws {
        ticket = try Ticket(row: row)
        projectName = row["project_name"]
        childCount = row["child_count"]
        childrenDone = row["child_done_count"]
        milestoneName = row["milestone_name"]
        isBlocked = (row["blocked_count"] as Int? ?? 0) > 0
        parent = Self.ref(row, prefix: "parent_ref")
    }

    private static func ref(_ row: Row, prefix: String) -> TicketRef? {
        guard let id: String = row["\(prefix)_id"],
              let keyPrefix: String = row["\(prefix)_prefix"],
              let number: Int = row["\(prefix)_number"],
              let title: String = row["\(prefix)_title"],
              let status: TicketStatus = row["\(prefix)_status"]
        else { return nil }
        return TicketRef(id: id, prefix: keyPrefix, number: number, title: title, status: status)
    }
}

public struct ParentProgress: Sendable, Hashable, Identifiable, FetchableRecord {
    public var ticket: Ticket
    public var projectName: String
    /// Children, not counting Canceled ones.
    public var total: Int
    public var done: Int

    public var id: String { ticket.id }

    public init(row: Row) throws {
        ticket = try Ticket(row: row)
        projectName = row["project_name"]
        total = row["total"]
        done = row["done"]
    }
}

public struct TicketDetail: Sendable, Hashable {
    public var ticket: Ticket
    public var project: Project
    public var parent: Ticket?
    public var children: [Ticket]
    public var comments: [Comment]
    public var labels: [TicketLabel]
    public var relations: TicketRelations
    public var attachments: [Attachment]
    public var milestone: Milestone?
}

extension ArcStore {
    static let statusOrderSQL = """
        CASE ticket.status WHEN 'backlog' THEN 0 WHEN 'todo' THEN 1 WHEN 'in_progress' THEN 2 \
        WHEN 'in_review' THEN 3 WHEN 'done' THEN 4 ELSE 5 END
        """

    static let summarySQL = """
        SELECT ticket.*, project.name AS project_name,
               par.id AS parent_ref_id, par.prefix AS parent_ref_prefix, par.number AS parent_ref_number,
               par.title AS parent_ref_title, par.status AS parent_ref_status,
               (SELECT COUNT(*) FROM ticket c WHERE c.parent_id = ticket.id) AS child_count,
               (SELECT COUNT(*) FROM ticket c WHERE c.parent_id = ticket.id AND c.status = 'done') AS child_done_count,
               milestone.name AS milestone_name,
               (SELECT COUNT(*) FROM relation r JOIN ticket b ON b.id = r.from_id
                WHERE r.to_id = ticket.id AND r.type = 'blocks' AND b.status NOT IN ('done', 'canceled')) AS blocked_count
        FROM ticket
        JOIN project ON project.id = ticket.project_id
        LEFT JOIN ticket par ON par.id = ticket.parent_id
        LEFT JOIN milestone ON milestone.id = ticket.milestone_id
        """

    /// Tickets ordered by status (workflow order), then manual order.
    public func tickets(matching query: TicketQuery) async throws -> [TicketSummary] {
        try await read { db in try Self.tickets(db, matching: query) }
    }

    static func tickets(_ db: Database, matching query: TicketQuery) throws -> [TicketSummary] {
        var clauses: [String] = []
        var arguments = StatementArguments()

        func addIn<V: DatabaseValueConvertible>(_ column: String, _ values: [V]) {
            guard !values.isEmpty else { return }
            clauses.append("\(column) IN (\(databaseQuestionMarks(count: values.count)))")
            arguments += StatementArguments(values)
        }

        addIn("ticket.project_id", query.projectIds.sorted())
        if query.projectIds.isEmpty && !query.includeArchivedProjects {
            clauses.append("project.archived_at IS NULL")
        }
        if query.statuses.isEmpty {
            if !query.includeClosed { clauses.append("ticket.status NOT IN ('done', 'canceled')") }
        } else {
            addIn("ticket.status", query.statuses.map(\.rawValue).sorted())
        }
        addIn("ticket.priority", query.priorities.map(\.rawValue).sorted())
        if let parentId = query.parentId {
            clauses.append("ticket.parent_id = ?")
            arguments += [parentId]
        }
        if query.topLevelOnly { clauses.append("ticket.parent_id IS NULL") }
        if !query.labelIds.isEmpty {
            let ids = query.labelIds.sorted()
            clauses.append("EXISTS (SELECT 1 FROM ticket_label tl WHERE tl.ticket_id = ticket.id AND tl.label_id IN (\(databaseQuestionMarks(count: ids.count))))")
            arguments += StatementArguments(ids)
        }
        if let milestoneId = query.milestoneId {
            clauses.append("ticket.milestone_id = ?")
            arguments += [milestoneId]
        }
        if let text = query.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let pattern = "%\(escaped)%"
            clauses.append("""
                (ticket.title LIKE ? ESCAPE '\\' OR ticket.description LIKE ? ESCAPE '\\' \
                OR (ticket.prefix || '-' || ticket.number) LIKE ? ESCAPE '\\')
                """)
            arguments += [pattern, pattern, pattern]
        }

        var sql = summarySQL
        if !clauses.isEmpty { sql += "\nWHERE " + clauses.joined(separator: " AND ") }
        sql += "\nORDER BY \(statusOrderSQL), ticket.sort_key, ticket.number"
        if let limit = query.limit {
            sql += "\nLIMIT ?"
            arguments += [max(limit, 0)]
        }
        return try attachLabels(db, to: try TicketSummary.fetchAll(db, sql: sql, arguments: arguments))
    }

    /// Fills in each summary's labels with one extra query.
    static func attachLabels(_ db: Database, to summaries: [TicketSummary]) throws -> [TicketSummary] {
        guard !summaries.isEmpty else { return summaries }
        var byTicket: [String: [TicketLabel]] = [:]
        let rows = try Row.fetchAll(db, sql: """
            SELECT ticket_label.ticket_id AS ticket_id, label.* FROM ticket_label
            JOIN label ON label.id = ticket_label.label_id ORDER BY label.name_key
            """)
        for row in rows {
            byTicket[row["ticket_id"], default: []].append(try TicketLabel(row: row))
        }
        guard !byTicket.isEmpty else { return summaries }
        return summaries.map { summary in
            var copy = summary
            copy.labels = byTicket[summary.ticket.id] ?? []
            return copy
        }
    }

    /// Every existing identifier, e.g. `ARC-12` (used to decide which references in text are real).
    public func ticketIdentifiers() async throws -> Set<String> {
        try await read { db in Set(try String.fetchAll(db, sql: "SELECT prefix || '-' || number FROM ticket")) }
    }

    public func ticketSummary(id: String) async throws -> TicketSummary {
        try await read { db in
            guard let summary = try TicketSummary.fetchOne(db, sql: Self.summarySQL + "\nWHERE ticket.id = ?", arguments: [id]) else {
                throw ArcError.notFound("Ticket not found.")
            }
            return try Self.attachLabels(db, to: [summary])[0]
        }
    }

    public func ticketDetail(id: String) async throws -> TicketDetail {
        try await read { db in try Self.detail(db, ticket: Self.requireTicket(db, id: id)) }
    }

    /// Looks up a ticket by `ARC-12`, `arc-12`, `FIC-7` or `12` and loads everything the detail page needs.
    public func ticketDetail(reference: String) async throws -> TicketDetail {
        let key = try Reference.ticketKey(reference)
        return try await read { db in try Self.detail(db, ticket: Self.requireTicket(db, key: key)) }
    }

    static func detail(_ db: Database, ticket: Ticket) throws -> TicketDetail {
        let project = try requireProject(db, id: ticket.projectId)
        let parent = try ticket.parentId.flatMap {
            try Ticket.fetchOne(db, sql: "SELECT * FROM ticket WHERE id = ?", arguments: [$0])
        }
        let children = try Ticket.fetchAll(
            db,
            sql: "SELECT * FROM ticket WHERE parent_id = ? ORDER BY sort_key, number",
            arguments: [ticket.id]
        )
        let comments = try Comment.fetchAll(
            db,
            sql: "SELECT * FROM comment WHERE ticket_id = ? ORDER BY created_at, rowid",
            arguments: [ticket.id]
        )
        let milestone = try ticket.milestoneId.flatMap {
            try Milestone.fetchOne(db, sql: "SELECT * FROM milestone WHERE id = ?", arguments: [$0])
        }
        return TicketDetail(
            ticket: ticket, project: project, parent: parent, children: children, comments: comments,
            labels: try labels(db, ticketId: ticket.id), relations: try relations(db, ticketId: ticket.id),
            attachments: try Attachment.fetchAll(db, sql: "SELECT * FROM attachment WHERE ticket_id = ? ORDER BY created_at, rowid", arguments: [ticket.id]),
            milestone: milestone
        )
    }

    /// Tickets that have children, with their progress (Canceled children excluded), ordered by project name then workflow order.
    public func parentsWithProgress(includeArchivedProjects: Bool = false) async throws -> [ParentProgress] {
        try await read { db in
            var sql = """
                SELECT ticket.*, project.name AS project_name,
                       (SELECT COUNT(*) FROM ticket t WHERE t.parent_id = ticket.id AND t.status <> 'canceled') AS total,
                       (SELECT COUNT(*) FROM ticket t WHERE t.parent_id = ticket.id AND t.status = 'done') AS done
                FROM ticket JOIN project ON project.id = ticket.project_id
                WHERE EXISTS (SELECT 1 FROM ticket c WHERE c.parent_id = ticket.id)
                """
            if !includeArchivedProjects { sql += " AND project.archived_at IS NULL" }
            sql += "\nORDER BY project.name_key, \(Self.statusOrderSQL), ticket.sort_key, ticket.number"
            return try ParentProgress.fetchAll(db, sql: sql)
        }
    }
}
