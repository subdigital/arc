import Foundation
import GRDB

public struct NewTicket: Sendable {
    public var title: String
    public var description: String
    public var kind: TicketKind
    public var projectId: String?
    public var epicId: String?
    public var parentId: String?
    public var status: TicketStatus
    public var priority: TicketPriority

    public init(
        title: String,
        description: String = "",
        kind: TicketKind = .task,
        projectId: String? = nil,
        epicId: String? = nil,
        parentId: String? = nil,
        status: TicketStatus = .todo,
        priority: TicketPriority = .none
    ) {
        self.title = title
        self.description = description
        self.kind = kind
        self.projectId = projectId
        self.epicId = epicId
        self.parentId = parentId
        self.status = status
        self.priority = priority
    }
}

/// A field change that distinguishes "leave alone" from "set (possibly to nil)".
public enum Change<Value: Sendable>: Sendable {
    case keep
    case set(Value)
}

public struct TicketPatch: Sendable {
    public var title: String?
    public var description: String?
    public var kind: TicketKind?
    public var status: TicketStatus?
    public var priority: TicketPriority?
    public var projectId: String?
    public var epicId: Change<String?>
    public var parentId: Change<String?>

    public init(
        title: String? = nil,
        description: String? = nil,
        kind: TicketKind? = nil,
        status: TicketStatus? = nil,
        priority: TicketPriority? = nil,
        projectId: String? = nil,
        epicId: Change<String?> = .keep,
        parentId: Change<String?> = .keep
    ) {
        self.title = title
        self.description = description
        self.kind = kind
        self.status = status
        self.priority = priority
        self.projectId = projectId
        self.epicId = epicId
        self.parentId = parentId
    }
}

/// Where to put a ticket within its status bucket. Ids are ticket ids (not numbers).
public enum TicketPosition: Sendable, Equatable {
    case top
    case bottom
    case before(String)
    case after(String)
}

extension ArcStore {
    static let minimumSortGap = 1e-6

    // MARK: - Lookup

    public func ticket(id: String) async throws -> Ticket {
        try await read { db in try Self.requireTicket(db, id: id) }
    }

    /// Resolves `ARC-12`, `arc-12` or `12`.
    public func resolveTicket(_ reference: String) async throws -> Ticket {
        let number = try Reference.ticketNumber(reference)
        return try await read { db in try Self.requireTicket(db, number: number) }
    }

    static func requireTicket(_ db: Database, id: String) throws -> Ticket {
        guard let ticket = try Ticket.fetchOne(db, sql: "SELECT * FROM ticket WHERE id = ?", arguments: [id]) else {
            throw ArcError.notFound("Ticket not found.")
        }
        return ticket
    }

    static func requireTicket(_ db: Database, number: Int) throws -> Ticket {
        guard let ticket = try Ticket.fetchOne(db, sql: "SELECT * FROM ticket WHERE number = ?", arguments: [number]) else {
            throw ArcError.notFound("Ticket \(Reference.identifier(for: number)) not found.")
        }
        return ticket
    }

    // MARK: - Create

    public func createTicket(_ new: NewTicket) async throws -> Ticket {
        let timestamp = now()
        return try await write { db in
            let title = new.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw ArcError.invalidArgument("A title is required.") }

            var projectId = new.projectId
            if new.kind == .subtask {
                guard let parentId = new.parentId else {
                    throw ArcError.invalidArgument("A subtask requires a parent task.")
                }
                let parent = try Self.requireTicket(db, id: parentId)
                guard parent.kind == .task else {
                    throw ArcError.invalidArgument("Subtasks can only belong to tasks (\(parent.identifier) is \(Self.article(parent.kind))).")
                }
                if let projectId, projectId != parent.projectId {
                    throw ArcError.invalidArgument("A subtask always belongs to its parent's project. Move the parent task instead.")
                }
                projectId = parent.projectId
            }
            guard let projectId else { throw ArcError.invalidArgument("A project is required.") }
            _ = try Self.requireProject(db, id: projectId)

            let number = try Self.allocateNumber(db)
            var ticket = Ticket(
                id: UUID().uuidString,
                number: number,
                kind: new.kind,
                projectId: projectId,
                epicId: new.epicId,
                parentId: new.parentId,
                title: title,
                description: new.description,
                status: new.status,
                priority: new.priority,
                sortKey: try Self.topSortKey(db, status: new.status, excluding: nil),
                createdAt: timestamp,
                updatedAt: timestamp,
                completedAt: new.status.isClosed ? timestamp : nil
            )
            try Self.validateHierarchy(db, ticket)
            try ticket.insert(db)
            ticket = try Self.requireTicket(db, id: ticket.id)
            return ticket
        }
    }

    private static func allocateNumber(_ db: Database) throws -> Int {
        let current = try Int.fetchOne(db, sql: "SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'next_ticket_number'") ?? 1
        try db.execute(
            sql: "UPDATE meta SET value = ? WHERE key = 'next_ticket_number'",
            arguments: [String(current + 1)]
        )
        return current
    }

    // MARK: - Update

    @discardableResult
    public func updateTicket(id: String, _ patch: TicketPatch) async throws -> Ticket {
        let timestamp = now()
        return try await write { db in
            let original = try Self.requireTicket(db, id: id)
            var ticket = original

            if let title = patch.title {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw ArcError.invalidArgument("A title is required.") }
                ticket.title = trimmed
            }
            if let description = patch.description { ticket.description = description }
            if let priority = patch.priority { ticket.priority = priority }

            if let kind = patch.kind, kind != ticket.kind {
                ticket.kind = kind
                // Fields that cannot apply to the new kind are cleared unless the patch sets them.
                if kind != .subtask, case .keep = patch.parentId { ticket.parentId = nil }
                if kind != .task, case .keep = patch.epicId { ticket.epicId = nil }
            }
            if case .set(let parentId) = patch.parentId { ticket.parentId = parentId }
            if case .set(let epicId) = patch.epicId { ticket.epicId = epicId }

            if ticket.kind == .subtask, let parentId = ticket.parentId, parentId != original.parentId {
                // A subtask follows its parent's project.
                ticket.projectId = try Self.requireTicket(db, id: parentId).projectId
            }
            if let projectId = patch.projectId, projectId != ticket.projectId {
                guard ticket.kind != .subtask else {
                    throw ArcError.invalidArgument("A subtask always belongs to its parent's project. Move the parent task instead.")
                }
                _ = try Self.requireProject(db, id: projectId)
                ticket.projectId = projectId
                if let epicId = ticket.epicId, case .keep = patch.epicId {
                    let epic = try Self.requireTicket(db, id: epicId)
                    if epic.projectId != projectId { ticket.epicId = nil }
                }
            }

            try Self.validateHierarchy(db, ticket)
            try Self.validateKindChange(db, from: original, to: ticket)

            if ticket.projectId != original.projectId {
                try Self.cascadeProjectMove(db, ticket: ticket, timestamp: timestamp)
            }

            if let status = patch.status, status != ticket.status {
                Self.apply(status: status, to: &ticket, at: timestamp)
                ticket.sortKey = try Self.topSortKey(db, status: status, excluding: ticket.id)
            }

            ticket.updatedAt = timestamp
            try ticket.update(db)
            return ticket
        }
    }

    /// Moves a ticket within a status bucket, optionally changing its status.
    @discardableResult
    public func moveTicket(id: String, status: TicketStatus? = nil, position: TicketPosition) async throws -> Ticket {
        let timestamp = now()
        return try await write { db in
            var ticket = try Self.requireTicket(db, id: id)
            let target = status ?? ticket.status
            ticket.sortKey = try Self.sortKey(db, for: ticket.id, in: target, at: position)
            if target != ticket.status { Self.apply(status: target, to: &ticket, at: timestamp) }
            ticket.updatedAt = timestamp
            try ticket.update(db)
            return ticket
        }
    }

    private static func apply(status: TicketStatus, to ticket: inout Ticket, at timestamp: Date) {
        ticket.status = status
        ticket.completedAt = status.isClosed ? timestamp : nil
    }

    // MARK: - Delete

    /// Deletes a ticket and its comments. Subtasks go with their task; an epic's tasks are kept.
    public func deleteTicket(id: String) async throws {
        try await write { db in
            _ = try Self.requireTicket(db, id: id)
            try db.execute(sql: "DELETE FROM ticket WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Hierarchy rules

    private static func article(_ kind: TicketKind) -> String {
        kind == .epic ? "an epic" : "a \(kind.rawValue)"
    }

    /// Rules that depend on rows other than the one being written.
    static func validateHierarchy(_ db: Database, _ ticket: Ticket) throws {
        switch ticket.kind {
        case .subtask:
            guard let parentId = ticket.parentId else {
                throw ArcError.invalidArgument("A subtask requires a parent task.")
            }
            let parent = try requireTicket(db, id: parentId)
            guard parent.kind == .task else {
                throw ArcError.invalidArgument("Subtasks can only belong to tasks (\(parent.identifier) is \(article(parent.kind))).")
            }
            guard parent.id != ticket.id, parent.projectId == ticket.projectId else {
                throw ArcError.invalidArgument("A subtask always belongs to its parent's project.")
            }
            guard ticket.epicId == nil else {
                throw ArcError.invalidArgument("A subtask takes its epic from its parent task.")
            }
        case .task, .epic:
            guard ticket.parentId == nil else {
                throw ArcError.invalidArgument("Only subtasks can have a parent.")
            }
        }

        if let epicId = ticket.epicId {
            guard ticket.kind == .task else {
                throw ArcError.invalidArgument("Only tasks can belong to an epic.")
            }
            let epic = try requireTicket(db, id: epicId)
            guard epic.kind == .epic else {
                throw ArcError.invalidArgument("\(epic.identifier) is not an epic.")
            }
            guard epic.projectId == ticket.projectId else {
                throw ArcError.invalidArgument("A task's epic must be in the same project as the task.")
            }
        }
    }

    /// Changing kind must not strand existing children.
    private static func validateKindChange(_ db: Database, from old: Ticket, to new: Ticket) throws {
        guard old.kind != new.kind else { return }
        if old.kind == .task, new.kind != .task {
            let subtasks = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ticket WHERE parent_id = ?", arguments: [old.id]) ?? 0
            if subtasks > 0 {
                throw ArcError.invalidArgument("\(old.identifier) has subtasks; remove or move them before changing its kind.")
            }
        }
        if old.kind == .epic {
            let tasks = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ticket WHERE epic_id = ?", arguments: [old.id]) ?? 0
            if tasks > 0 {
                throw ArcError.invalidArgument("\(old.identifier) has tasks; remove them from the epic before changing its kind.")
            }
        }
    }

    /// Moving a task moves its subtasks; moving an epic moves its tasks and their subtasks.
    private static func cascadeProjectMove(_ db: Database, ticket: Ticket, timestamp: Date) throws {
        switch ticket.kind {
        case .task:
            try db.execute(
                sql: "UPDATE ticket SET project_id = ?, updated_at = ? WHERE parent_id = ?",
                arguments: [ticket.projectId, timestamp.timeIntervalSince1970, ticket.id]
            )
        case .epic:
            try db.execute(
                sql: """
                    UPDATE ticket SET project_id = ?, updated_at = ?
                    WHERE epic_id = ? OR parent_id IN (SELECT id FROM ticket WHERE epic_id = ?)
                    """,
                arguments: [ticket.projectId, timestamp.timeIntervalSince1970, ticket.id, ticket.id]
            )
        case .subtask:
            break
        }
    }

    // MARK: - Ordering

    private static func topSortKey(_ db: Database, status: TicketStatus, excluding id: String?) throws -> Double {
        let minimum = try Double.fetchOne(
            db,
            sql: "SELECT MIN(sort_key) FROM ticket WHERE status = ? AND id <> ?",
            arguments: [status, id ?? ""]
        )
        return minimum.map { $0 - 1 } ?? 0
    }

    private static func bottomSortKey(_ db: Database, status: TicketStatus, excluding id: String) throws -> Double {
        let maximum = try Double.fetchOne(
            db,
            sql: "SELECT MAX(sort_key) FROM ticket WHERE status = ? AND id <> ?",
            arguments: [status, id]
        )
        return maximum.map { $0 + 1 } ?? 0
    }

    private static func sortKey(_ db: Database, for id: String, in status: TicketStatus, at position: TicketPosition) throws -> Double {
        switch position {
        case .top:
            return try topSortKey(db, status: status, excluding: id)
        case .bottom:
            return try bottomSortKey(db, status: status, excluding: id)
        case .before(let neighborId), .after(let neighborId):
            guard neighborId != id else {
                throw ArcError.invalidArgument("A ticket cannot be positioned relative to itself.")
            }
            let isBefore: Bool = if case .before = position { true } else { false }
            // At most one renormalization is ever needed: afterwards every gap is 1.
            for attempt in 0..<2 {
                let neighbor = try requireTicket(db, id: neighborId)
                guard neighbor.status == status else {
                    throw ArcError.invalidArgument("\(neighbor.identifier) is not in \(status.displayName).")
                }
                let adjacent = try Double.fetchOne(
                    db,
                    sql: isBefore
                        ? "SELECT MAX(sort_key) FROM ticket WHERE status = ? AND id <> ? AND sort_key < ?"
                        : "SELECT MIN(sort_key) FROM ticket WHERE status = ? AND id <> ? AND sort_key > ?",
                    arguments: [status, id, neighbor.sortKey]
                )
                guard let adjacent else {
                    return isBefore ? neighbor.sortKey - 1 : neighbor.sortKey + 1
                }
                if abs(neighbor.sortKey - adjacent) >= minimumSortGap || attempt == 1 {
                    return (neighbor.sortKey + adjacent) / 2
                }
                try renormalize(db, status: status)
            }
            fatalError("unreachable")
        }
    }

    /// Renumbers a status bucket to 1, 2, 3, … keeping its current order.
    static func renormalize(_ db: Database, status: TicketStatus) throws {
        let ids = try String.fetchAll(
            db,
            sql: "SELECT id FROM ticket WHERE status = ? ORDER BY sort_key, number",
            arguments: [status]
        )
        for (index, id) in ids.enumerated() {
            try db.execute(sql: "UPDATE ticket SET sort_key = ? WHERE id = ?", arguments: [Double(index + 1), id])
        }
    }

    // MARK: - Comments

    public func comments(ticketId: String) async throws -> [Comment] {
        try await read { db in
            try Comment.fetchAll(
                db,
                sql: "SELECT * FROM comment WHERE ticket_id = ? ORDER BY created_at, rowid",
                arguments: [ticketId]
            )
        }
    }

    @discardableResult
    public func addComment(ticketId: String, body: String, author: CommentAuthor) async throws -> Comment {
        let timestamp = now()
        return try await write { db in
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ArcError.invalidArgument("A comment body is required.")
            }
            _ = try Self.requireTicket(db, id: ticketId)
            let comment = Comment(id: UUID().uuidString, ticketId: ticketId, body: body, author: author, createdAt: timestamp)
            try comment.insert(db)
            return comment
        }
    }

    @discardableResult
    public func updateComment(id: String, body: String) async throws -> Comment {
        try await write { db in
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ArcError.invalidArgument("A comment body is required.")
            }
            guard var comment = try Comment.fetchOne(db, sql: "SELECT * FROM comment WHERE id = ?", arguments: [id]) else {
                throw ArcError.notFound("Comment not found.")
            }
            comment.body = body
            try comment.update(db)
            return comment
        }
    }
}
