import Foundation
import GRDB

/// A ticket's relations as seen from that ticket, with the inverse of each stored row already applied.
public struct TicketRelations: Sendable, Hashable {
    public var blocks: [TicketRef] = []
    public var blockedBy: [TicketRef] = []
    public var related: [TicketRef] = []
    /// Tickets this one is a duplicate of.
    public var duplicateOf: [TicketRef] = []
    /// Tickets that are duplicates of this one.
    public var duplicatedBy: [TicketRef] = []

    public var isEmpty: Bool {
        blocks.isEmpty && blockedBy.isEmpty && related.isEmpty && duplicateOf.isEmpty && duplicatedBy.isEmpty
    }

    /// Blockers that are not finished yet.
    public var openBlockers: [TicketRef] { blockedBy.filter { $0.status.isOpen } }
}

extension ArcStore {
    public func relations(ticketId: String) async throws -> TicketRelations {
        try await read { db in try Self.relations(db, ticketId: ticketId) }
    }

    static func relations(_ db: Database, ticketId: String) throws -> TicketRelations {
        var result = TicketRelations()
        let rows = try Row.fetchAll(db, sql: """
            SELECT relation.type AS type, relation.from_id AS from_id, relation.to_id AS to_id,
                   other.id AS id, other.prefix AS prefix, other.number AS number, other.title AS title, other.status AS status
            FROM relation JOIN ticket other ON other.id = CASE WHEN relation.from_id = ?1 THEN relation.to_id ELSE relation.from_id END
            WHERE relation.from_id = ?1 OR relation.to_id = ?1
            ORDER BY other.prefix, other.number
            """, arguments: [ticketId])
        for row in rows {
            let ref = TicketRef(id: row["id"], prefix: row["prefix"], number: row["number"], title: row["title"], status: row["status"])
            let outgoing = (row["from_id"] as String) == ticketId
            switch (row["type"] as RelationType) {
            case .blocks: if outgoing { result.blocks.append(ref) } else { result.blockedBy.append(ref) }
            case .duplicate: if outgoing { result.duplicateOf.append(ref) } else { result.duplicatedBy.append(ref) }
            case .related: result.related.append(ref)
            }
        }
        return result
    }

    /// Relates two tickets. `blocks`/`duplicate` read "from → to"; `related` is symmetric. Adding an existing
    /// relation is a no-op, so imports and retries are safe.
    @discardableResult
    public func addRelation(from: String, to: String, type: RelationType) async throws -> TicketRelation {
        let timestamp = now()
        return try await write { db in
            let source = try Self.requireTicket(db, id: from)
            let target = try Self.requireTicket(db, id: to)
            guard source.id != target.id else { throw ArcError.invalidArgument("A ticket cannot be related to itself.") }
            var (fromId, toId) = (source.id, target.id)
            if type == .related, fromId > toId { swap(&fromId, &toId) }
            if let existing = try TicketRelation.fetchOne(
                db, sql: "SELECT * FROM relation WHERE from_id = ? AND to_id = ? AND type = ?", arguments: [fromId, toId, type]
            ) { return existing }
            if type == .blocks {
                // `to` must not already block `from`, directly or through a chain.
                let cycle = try Bool.fetchOne(db, sql: """
                    WITH RECURSIVE downstream(id) AS (
                        SELECT ?1
                        UNION
                        SELECT r.to_id FROM relation r JOIN downstream d ON r.from_id = d.id WHERE r.type = 'blocks'
                    )
                    SELECT EXISTS (SELECT 1 FROM downstream WHERE id = ?2)
                    """, arguments: [target.id, source.id]) ?? false
                if cycle {
                    throw ArcError.invalidArgument("\(target.identifier) already blocks \(source.identifier) (directly or indirectly); that would be a cycle.")
                }
            }
            let relation = TicketRelation(id: UUID().uuidString, fromId: fromId, toId: toId, type: type, createdAt: timestamp)
            try relation.insert(db)
            return relation
        }
    }

    public func removeRelation(from: String, to: String, type: RelationType) async throws {
        try await write { db in
            var (fromId, toId) = (from, to)
            if type == .related, fromId > toId { swap(&fromId, &toId) }
            try db.execute(sql: "DELETE FROM relation WHERE from_id = ? AND to_id = ? AND type = ?", arguments: [fromId, toId, type])
        }
    }
}
