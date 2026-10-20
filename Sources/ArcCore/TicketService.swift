import Foundation
import GRDB

public struct NewTicket: Sendable {
    public var title: String
    public var description: String
    public var projectId: String?
    public var parentId: String?
    public var status: TicketStatus
    public var priority: TicketPriority

    public init(
        title: String,
        description: String = "",
        projectId: String? = nil,
        parentId: String? = nil,
        status: TicketStatus = .todo,
        priority: TicketPriority = .none
    ) {
        self.title = title
        self.description = description
        self.projectId = projectId
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
    public var status: TicketStatus?
    public var priority: TicketPriority?
    public var projectId: String?
    public var parentId: Change<String?>
    public var milestoneId: Change<String?>

    public init(
        title: String? = nil,
        description: String? = nil,
        status: TicketStatus? = nil,
        priority: TicketPriority? = nil,
        projectId: String? = nil,
        parentId: Change<String?> = .keep,
        milestoneId: Change<String?> = .keep
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.projectId = projectId
        self.parentId = parentId
        self.milestoneId = milestoneId
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

    /// Resolves `ARC-12`, `arc-12`, `FIC-7` or `12` (meaning `ARC-12`).
    public func resolveTicket(_ reference: String) async throws -> Ticket {
        let key = try Reference.ticketKey(reference)
        return try await read { db in try Self.requireTicket(db, key: key) }
    }

    static func requireTicket(_ db: Database, id: String) throws -> Ticket {
        guard let ticket = try Ticket.fetchOne(db, sql: "SELECT * FROM ticket WHERE id = ?", arguments: [id]) else {
            throw ArcError.notFound("Ticket not found.")
        }
        return ticket
    }

    static func requireTicket(_ db: Database, key: TicketKey) throws -> Ticket {
        guard let ticket = try Ticket.fetchOne(
            db, sql: "SELECT * FROM ticket WHERE prefix = ? AND number = ?", arguments: [key.prefix, key.number]
        ) else {
            throw ArcError.notFound("Ticket \(key.identifier) not found.")
        }
        return ticket
    }

    // MARK: - Create

    @discardableResult
    public func createTicket(_ new: NewTicket) async throws -> Ticket {
        let timestamp = now()
        return try await write { db in
            let title = new.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw ArcError.invalidArgument("A title is required.") }

            // A child defaults to its parent's project.
            var projectId = new.projectId
            if projectId == nil, let parentId = new.parentId {
                projectId = try Self.requireTicket(db, id: parentId).projectId
            }
            guard let projectId else { throw ArcError.invalidArgument("A project is required (or a parent ticket to take it from).") }
            _ = try Self.requireProject(db, id: projectId)

            let number = try Self.allocateNumber(db)
            var ticket = Ticket(
                id: UUID().uuidString,
                prefix: Reference.identifierPrefix,
                number: number,
                projectId: projectId,
                parentId: new.parentId,
                title: title,
                description: new.description,
                status: new.status,
                priority: new.priority,
                sortKey: try Self.topSortKey(db, status: new.status, excluding: nil),
                createdAt: timestamp,
                updatedAt: timestamp,
                startedAt: nil,
                completedAt: nil,
                canceledAt: nil,
                archivedAt: nil,
                milestoneId: nil,
                externalId: nil
            )
            Self.apply(status: new.status, to: &ticket, at: timestamp)
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
            var ticket = try Self.requireTicket(db, id: id)

            if let title = patch.title {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw ArcError.invalidArgument("A title is required.") }
                ticket.title = trimmed
            }
            if let description = patch.description { ticket.description = description }
            if let priority = patch.priority { ticket.priority = priority }
            if case .set(let parentId) = patch.parentId { ticket.parentId = parentId }
            if let projectId = patch.projectId, projectId != ticket.projectId {
                _ = try Self.requireProject(db, id: projectId)
                ticket.projectId = projectId
                ticket.milestoneId = nil // milestones belong to a project
            }
            if case .set(let milestoneId) = patch.milestoneId { ticket.milestoneId = milestoneId }
            try Self.validateMilestone(db, ticket)

            try Self.validateHierarchy(db, ticket)

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

    /// Sets the status and the timestamps that go with it, the way Linear does: the first move into a started
    /// status sets `startedAt` (reopening keeps it), Done sets `completedAt`, Canceled sets `canceledAt`, and
    /// moving back to an open status clears both closing dates.
    static func apply(status: TicketStatus, to ticket: inout Ticket, at timestamp: Date) {
        ticket.status = status
        switch status {
        case .backlog, .todo:
            ticket.completedAt = nil
            ticket.canceledAt = nil
        case .inProgress, .inReview:
            ticket.completedAt = nil
            ticket.canceledAt = nil
            if ticket.startedAt == nil { ticket.startedAt = timestamp }
        case .done:
            ticket.completedAt = timestamp
            ticket.canceledAt = nil
        case .canceled:
            ticket.canceledAt = timestamp
            ticket.completedAt = nil
        }
    }

    // MARK: - Delete

    /// Deletes a ticket and its comments. Its children are kept and become top-level tickets.
    public func deleteTicket(id: String) async throws {
        try await write { db in
            _ = try Self.requireTicket(db, id: id)
            try db.execute(sql: "DELETE FROM ticket WHERE id = ?", arguments: [id])
        }
        removeAttachmentFiles(ticketId: id)
    }

    // MARK: - Hierarchy rules

    /// A parent must exist, may live in any project, and must not be the ticket itself or one of its descendants.
    static func validateHierarchy(_ db: Database, _ ticket: Ticket) throws {
        guard let parentId = ticket.parentId else { return }
        let parent = try requireTicket(db, id: parentId)
        guard parent.id != ticket.id else {
            throw ArcError.invalidArgument("A ticket cannot be its own parent.")
        }
        let cycle = try Bool.fetchOne(db, sql: """
            WITH RECURSIVE ancestors(id, parent_id) AS (
                SELECT id, parent_id FROM ticket WHERE id = ?
                UNION ALL
                SELECT t.id, t.parent_id FROM ticket t JOIN ancestors a ON t.id = a.parent_id
            )
            SELECT EXISTS (SELECT 1 FROM ancestors WHERE id = ?)
            """, arguments: [parent.id, ticket.id]) ?? false
        if cycle {
            throw ArcError.invalidArgument("\(parent.identifier) is a descendant of \(ticket.identifier); a ticket cannot be moved under its own descendant.")
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
    public func addComment(
        ticketId: String, body: String, author: CommentAuthor, parentId: String? = nil, authorName: String? = nil
    ) async throws -> Comment {
        let timestamp = now()
        return try await write { db in
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ArcError.invalidArgument("A comment body is required.")
            }
            _ = try Self.requireTicket(db, id: ticketId)
            if let parentId {
                guard let parent = try Comment.fetchOne(db, sql: "SELECT * FROM comment WHERE id = ?", arguments: [parentId]),
                      parent.ticketId == ticketId
                else { throw ArcError.invalidArgument("A reply must answer a comment on the same ticket.") }
            }
            let comment = Comment(
                id: UUID().uuidString, ticketId: ticketId, body: body, author: author, createdAt: timestamp,
                parentId: parentId, authorName: authorName, updatedAt: nil, externalId: nil
            )
            try comment.insert(db)
            return comment
        }
    }

    @discardableResult
    public func updateComment(id: String, body: String) async throws -> Comment {
        let timestamp = now()
        return try await write { db in
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ArcError.invalidArgument("A comment body is required.")
            }
            guard var comment = try Comment.fetchOne(db, sql: "SELECT * FROM comment WHERE id = ?", arguments: [id]) else {
                throw ArcError.notFound("Comment not found.")
            }
            comment.body = body
            comment.updatedAt = timestamp
            try comment.update(db)
            return comment
        }
    }
}

extension ArcStore {
    /// A milestone must belong to the ticket's own project.
    static func validateMilestone(_ db: Database, _ ticket: Ticket) throws {
        guard let milestoneId = ticket.milestoneId else { return }
        guard let milestone = try Milestone.fetchOne(db, sql: "SELECT * FROM milestone WHERE id = ?", arguments: [milestoneId]) else {
            throw ArcError.notFound("Milestone not found.")
        }
        guard milestone.projectId == ticket.projectId else {
            throw ArcError.invalidArgument("Milestone '\(milestone.name)' belongs to a different project.")
        }
    }
}
