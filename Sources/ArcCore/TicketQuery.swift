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

    public var id: String { ticket.id }

    public init(row: Row) throws {
        ticket = try Ticket(row: row)
        projectName = row["project_name"]
        childCount = row["child_count"]
        childrenDone = row["child_done_count"]
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
               (SELECT COUNT(*) FROM ticket c WHERE c.parent_id = ticket.id AND c.status = 'done') AS child_done_count
        FROM ticket
        JOIN project ON project.id = ticket.project_id
        LEFT JOIN ticket par ON par.id = ticket.parent_id
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
        return try TicketSummary.fetchAll(db, sql: sql, arguments: arguments)
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
            return summary
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
        return TicketDetail(ticket: ticket, project: project, parent: parent, children: children, comments: comments)
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
