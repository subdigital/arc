import Foundation
import GRDB

public struct TicketQuery: Sendable, Equatable {
    public var projectIds: Set<String>
    public var kinds: Set<TicketKind>
    public var statuses: Set<TicketStatus>
    public var priorities: Set<TicketPriority>
    public var epicId: String?
    public var parentId: String?
    public var text: String?
    /// Without explicit `statuses`, closed tickets (Done, Canceled) are left out unless this is true.
    public var includeClosed: Bool
    /// Archived projects' tickets are only listed when asked for, or when `projectIds` names them.
    public var includeArchivedProjects: Bool
    public var limit: Int?

    public init(
        projectIds: Set<String> = [],
        kinds: Set<TicketKind> = [],
        statuses: Set<TicketStatus> = [],
        priorities: Set<TicketPriority> = [],
        epicId: String? = nil,
        parentId: String? = nil,
        text: String? = nil,
        includeClosed: Bool = false,
        includeArchivedProjects: Bool = false,
        limit: Int? = nil
    ) {
        self.projectIds = projectIds
        self.kinds = kinds
        self.statuses = statuses
        self.priorities = priorities
        self.epicId = epicId
        self.parentId = parentId
        self.text = text
        self.includeClosed = includeClosed
        self.includeArchivedProjects = includeArchivedProjects
        self.limit = limit
    }
}

public struct TicketRef: Sendable, Hashable {
    public var id: String
    public var number: Int
    public var title: String
    public var status: TicketStatus

    public var identifier: String { Reference.identifier(for: number) }
}

/// A ticket plus the joined data list rows and cards need.
public struct TicketSummary: Sendable, Hashable, Identifiable, FetchableRecord {
    public var ticket: Ticket
    public var projectName: String
    /// The ticket's epic; for a subtask, its parent's epic.
    public var epic: TicketRef?
    public var parent: TicketRef?
    public var subtaskCount: Int
    public var subtasksDone: Int

    public var id: String { ticket.id }

    public init(row: Row) throws {
        ticket = try Ticket(row: row)
        projectName = row["project_name"]
        subtaskCount = row["subtask_count"]
        subtasksDone = row["subtask_done_count"]
        epic = Self.ref(row, prefix: "epic_ref")
        parent = Self.ref(row, prefix: "parent_ref")
    }

    private static func ref(_ row: Row, prefix: String) -> TicketRef? {
        guard let id: String = row["\(prefix)_id"],
              let number: Int = row["\(prefix)_number"],
              let title: String = row["\(prefix)_title"],
              let status: TicketStatus = row["\(prefix)_status"]
        else { return nil }
        return TicketRef(id: id, number: number, title: title, status: status)
    }
}

public struct EpicProgress: Sendable, Hashable, Identifiable, FetchableRecord {
    public var ticket: Ticket
    public var projectName: String
    /// Tasks in the epic, not counting Canceled ones.
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
    /// The ticket's epic; for a subtask, its parent's epic.
    public var epic: Ticket?
    public var parent: Ticket?
    public var subtasks: [Ticket]
    public var comments: [Comment]
}

extension ArcStore {
    static let statusOrderSQL = """
        CASE ticket.status WHEN 'backlog' THEN 0 WHEN 'todo' THEN 1 WHEN 'in_progress' THEN 2 \
        WHEN 'in_review' THEN 3 WHEN 'done' THEN 4 ELSE 5 END
        """

    static let summarySQL = """
        SELECT ticket.*, project.name AS project_name,
               epic.id AS epic_ref_id, epic.number AS epic_ref_number, epic.title AS epic_ref_title, epic.status AS epic_ref_status,
               par.id AS parent_ref_id, par.number AS parent_ref_number, par.title AS parent_ref_title, par.status AS parent_ref_status,
               (SELECT COUNT(*) FROM ticket s WHERE s.parent_id = ticket.id) AS subtask_count,
               (SELECT COUNT(*) FROM ticket s WHERE s.parent_id = ticket.id AND s.status = 'done') AS subtask_done_count
        FROM ticket
        JOIN project ON project.id = ticket.project_id
        LEFT JOIN ticket par ON par.id = ticket.parent_id
        LEFT JOIN ticket epic ON epic.id = COALESCE(ticket.epic_id, par.epic_id)
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
        addIn("ticket.kind", query.kinds.map(\.rawValue).sorted())
        if query.statuses.isEmpty {
            if !query.includeClosed { clauses.append("ticket.status NOT IN ('done', 'canceled')") }
        } else {
            addIn("ticket.status", query.statuses.map(\.rawValue).sorted())
        }
        addIn("ticket.priority", query.priorities.map(\.rawValue).sorted())
        if let epicId = query.epicId {
            clauses.append("COALESCE(ticket.epic_id, par.epic_id) = ?")
            arguments += [epicId]
        }
        if let parentId = query.parentId {
            clauses.append("ticket.parent_id = ?")
            arguments += [parentId]
        }
        if let text = query.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let pattern = "%\(escaped)%"
            clauses.append("""
                (ticket.title LIKE ? ESCAPE '\\' OR ticket.description LIKE ? ESCAPE '\\' \
                OR ('ARC-' || ticket.number) LIKE ? ESCAPE '\\')
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

    /// Every existing ticket number (used to decide which `ARC-n` references are real).
    public func ticketNumbers() async throws -> Set<Int> {
        try await read { db in Set(try Int.fetchAll(db, sql: "SELECT number FROM ticket")) }
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

    /// Looks up a ticket by `ARC-12`, `arc-12` or `12` and loads everything the detail page needs.
    public func ticketDetail(reference: String) async throws -> TicketDetail {
        let number = try Reference.ticketNumber(reference)
        return try await read { db in try Self.detail(db, ticket: Self.requireTicket(db, number: number)) }
    }

    static func detail(_ db: Database, ticket: Ticket) throws -> TicketDetail {
        let project = try requireProject(db, id: ticket.projectId)
        let parent = try ticket.parentId.flatMap {
            try Ticket.fetchOne(db, sql: "SELECT * FROM ticket WHERE id = ?", arguments: [$0])
        }
        let epicId = ticket.epicId ?? parent?.epicId
        let epic = try epicId.flatMap {
            try Ticket.fetchOne(db, sql: "SELECT * FROM ticket WHERE id = ?", arguments: [$0])
        }
        let subtasks = try Ticket.fetchAll(
            db,
            sql: "SELECT * FROM ticket WHERE parent_id = ? ORDER BY sort_key, number",
            arguments: [ticket.id]
        )
        let comments = try Comment.fetchAll(
            db,
            sql: "SELECT * FROM comment WHERE ticket_id = ? ORDER BY created_at, rowid",
            arguments: [ticket.id]
        )
        return TicketDetail(ticket: ticket, project: project, epic: epic, parent: parent, subtasks: subtasks, comments: comments)
    }

    /// Epics with their task progress (Canceled tasks excluded), ordered by project name then workflow order.
    public func epicsWithProgress(includeArchivedProjects: Bool = false) async throws -> [EpicProgress] {
        try await read { db in
            var sql = """
                SELECT ticket.*, project.name AS project_name,
                       (SELECT COUNT(*) FROM ticket t WHERE t.epic_id = ticket.id AND t.status <> 'canceled') AS total,
                       (SELECT COUNT(*) FROM ticket t WHERE t.epic_id = ticket.id AND t.status = 'done') AS done
                FROM ticket JOIN project ON project.id = ticket.project_id
                WHERE ticket.kind = 'epic'
                """
            if !includeArchivedProjects { sql += " AND project.archived_at IS NULL" }
            sql += "\nORDER BY project.name_key, \(Self.statusOrderSQL), ticket.sort_key, ticket.number"
            return try EpicProgress.fetchAll(db, sql: sql)
        }
    }
}
