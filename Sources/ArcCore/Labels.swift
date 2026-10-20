import Foundation
import GRDB

extension ArcStore {
    static let labelColors = ["#5E6AD2", "#4CB782", "#F2C94C", "#F2994A", "#EB5757", "#BB87FC", "#4EA7FC", "#26B5CE"]

    static func labelKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// A stable color for a label name, so the same label looks the same everywhere.
    static func defaultLabelColor(for name: String) -> String {
        var hash: UInt32 = 5381
        for byte in labelKey(name).utf8 { hash = hash &* 33 &+ UInt32(byte) }
        return labelColors[Int(hash % UInt32(labelColors.count))]
    }

    public func labels() async throws -> [Label] {
        try await read { db in try Label.fetchAll(db, sql: "SELECT * FROM label ORDER BY name_key") }
    }

    public func labels(ticketId: String) async throws -> [Label] {
        try await read { db in try Self.labels(db, ticketId: ticketId) }
    }

    static func labels(_ db: Database, ticketId: String) throws -> [Label] {
        try Label.fetchAll(db, sql: """
            SELECT label.* FROM label JOIN ticket_label ON ticket_label.label_id = label.id
            WHERE ticket_label.ticket_id = ? ORDER BY label.name_key
            """, arguments: [ticketId])
    }

    /// Finds a label by name (case-insensitive) or creates it. Labels exist on demand: there is no setup step.
    @discardableResult
    static func findOrCreateLabel(_ db: Database, name: String, color: String? = nil, at timestamp: Date) throws -> Label {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ArcError.invalidArgument("A label name is required.") }
        if let existing = try Label.fetchOne(db, sql: "SELECT * FROM label WHERE name_key = ?", arguments: [labelKey(trimmed)]) {
            return existing
        }
        let label = Label(
            id: UUID().uuidString, name: trimmed, nameKey: labelKey(trimmed),
            color: color ?? defaultLabelColor(for: trimmed), description: "", externalId: nil, createdAt: timestamp
        )
        try label.insert(db)
        return label
    }

    /// Replaces the ticket's labels with `names`, creating any that do not exist yet.
    @discardableResult
    public func setLabels(ticketId: String, names: [String]) async throws -> [Label] {
        let timestamp = now()
        return try await write { db in
            _ = try Self.requireTicket(db, id: ticketId)
            let wanted = try names.map { try Self.findOrCreateLabel(db, name: $0, at: timestamp) }
            try db.execute(sql: "DELETE FROM ticket_label WHERE ticket_id = ?", arguments: [ticketId])
            for label in Set(wanted.map(\.id)) {
                try db.execute(sql: "INSERT INTO ticket_label (ticket_id, label_id) VALUES (?, ?)", arguments: [ticketId, label])
            }
            try db.execute(sql: "UPDATE ticket SET updated_at = ? WHERE id = ?", arguments: [timestamp, ticketId])
            return try Self.labels(db, ticketId: ticketId)
        }
    }

    @discardableResult
    public func addLabel(ticketId: String, name: String) async throws -> [Label] {
        let timestamp = now()
        return try await write { db in
            _ = try Self.requireTicket(db, id: ticketId)
            let label = try Self.findOrCreateLabel(db, name: name, at: timestamp)
            try db.execute(sql: "INSERT OR IGNORE INTO ticket_label (ticket_id, label_id) VALUES (?, ?)", arguments: [ticketId, label.id])
            try db.execute(sql: "UPDATE ticket SET updated_at = ? WHERE id = ?", arguments: [timestamp, ticketId])
            return try Self.labels(db, ticketId: ticketId)
        }
    }

    @discardableResult
    public func removeLabel(ticketId: String, labelId: String) async throws -> [Label] {
        let timestamp = now()
        return try await write { db in
            _ = try Self.requireTicket(db, id: ticketId)
            try db.execute(sql: "DELETE FROM ticket_label WHERE ticket_id = ? AND label_id = ?", arguments: [ticketId, labelId])
            try db.execute(sql: "UPDATE ticket SET updated_at = ? WHERE id = ?", arguments: [timestamp, ticketId])
            return try Self.labels(db, ticketId: ticketId)
        }
    }

    @discardableResult
    public func updateLabel(id: String, name: String? = nil, color: String? = nil, description: String? = nil) async throws -> Label {
        try await write { db in
            guard var label = try Label.fetchOne(db, sql: "SELECT * FROM label WHERE id = ?", arguments: [id]) else {
                throw ArcError.notFound("Label not found.")
            }
            if let name {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw ArcError.invalidArgument("A label name is required.") }
                let clash = try String.fetchOne(db, sql: "SELECT id FROM label WHERE name_key = ? AND id <> ?", arguments: [Self.labelKey(trimmed), id])
                if clash != nil { throw ArcError.conflict("The label '\(trimmed)' already exists.") }
                label.name = trimmed
                label.nameKey = Self.labelKey(trimmed)
            }
            if let color { label.color = color }
            if let description { label.description = description }
            try label.update(db)
            return label
        }
    }

    public func deleteLabel(id: String) async throws {
        try await write { db in try db.execute(sql: "DELETE FROM label WHERE id = ?", arguments: [id]) }
    }
}
