import Foundation
import GRDB

extension ArcStore {
    public func milestones(projectId: String) async throws -> [Milestone] {
        try await read { db in
            try Milestone.fetchAll(db, sql: "SELECT * FROM milestone WHERE project_id = ? ORDER BY sort_order, created_at", arguments: [projectId])
        }
    }

    public func milestone(id: String) async throws -> Milestone {
        try await read { db in
            guard let milestone = try Milestone.fetchOne(db, sql: "SELECT * FROM milestone WHERE id = ?", arguments: [id]) else {
                throw ArcError.notFound("Milestone not found.")
            }
            return milestone
        }
    }

    /// Resolves a milestone of `projectId` by name (case-insensitive) or id.
    public func resolveMilestone(_ reference: String, projectId: String) async throws -> Milestone {
        try await read { db in
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            if let found = try Milestone.fetchOne(
                db,
                sql: "SELECT * FROM milestone WHERE project_id = ? AND (lower(name) = lower(?) OR id = ?)",
                arguments: [projectId, trimmed, trimmed]
            ) { return found }
            let names = try String.fetchAll(db, sql: "SELECT name FROM milestone WHERE project_id = ? ORDER BY sort_order", arguments: [projectId])
            let listing = names.isEmpty ? "This project has no milestones." : "Milestones: \(names.joined(separator: ", "))."
            throw ArcError.notFound("Milestone '\(reference)' not found. \(listing)")
        }
    }

    @discardableResult
    public func createMilestone(
        projectId: String, name: String, description: String = "", targetDate: Date? = nil, sortOrder: Double? = nil
    ) async throws -> Milestone {
        let timestamp = now()
        return try await write { db in
            _ = try Self.requireProject(db, id: projectId)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ArcError.invalidArgument("A milestone name is required.") }
            let last = try Double.fetchOne(db, sql: "SELECT MAX(sort_order) FROM milestone WHERE project_id = ?", arguments: [projectId])
            let milestone = Milestone(
                id: UUID().uuidString, projectId: projectId, name: trimmed, description: description,
                targetDate: targetDate, sortOrder: sortOrder ?? ((last ?? 0) + 1), externalId: nil,
                createdAt: timestamp, updatedAt: timestamp
            )
            try milestone.insert(db)
            return milestone
        }
    }

    @discardableResult
    public func updateMilestone(
        id: String, name: String? = nil, description: String? = nil, targetDate: Change<Date?> = .keep
    ) async throws -> Milestone {
        let timestamp = now()
        return try await write { db in
            guard var milestone = try Milestone.fetchOne(db, sql: "SELECT * FROM milestone WHERE id = ?", arguments: [id]) else {
                throw ArcError.notFound("Milestone not found.")
            }
            if let name {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw ArcError.invalidArgument("A milestone name is required.") }
                milestone.name = trimmed
            }
            if let description { milestone.description = description }
            if case .set(let date) = targetDate { milestone.targetDate = date }
            milestone.updatedAt = timestamp
            try milestone.update(db)
            return milestone
        }
    }

    /// Deleting a milestone leaves its tickets in the project without one.
    public func deleteMilestone(id: String) async throws {
        try await write { db in
            guard try Milestone.fetchOne(db, sql: "SELECT * FROM milestone WHERE id = ?", arguments: [id]) != nil else {
                throw ArcError.notFound("Milestone not found.")
            }
            try db.execute(sql: "DELETE FROM milestone WHERE id = ?", arguments: [id])
        }
    }
}
