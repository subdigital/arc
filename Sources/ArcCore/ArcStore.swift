import Foundation
import GRDB

/// Entry point to Arc's data. All domain rules live here so the app, the CLI and the MCP server
/// behave identically. Safe to use from several processes against the same file.
public final class ArcStore: Sendable {
    public let path: String
    public let pool: DatabasePool
    let now: @Sendable () -> Date

    public static let projectColors = [
        "#5E6AD2", "#4CB782", "#F2C94C", "#F2994A", "#EB5757", "#BB87FC", "#4EA7FC", "#26B5CE",
    ]

    /// The colors offered in the project editor: the automatic ones first, then a few more.
    public static let colorChoices = projectColors + [
        "#E5548C", "#8FD14F", "#A0714F", "#95A2B3",
    ]

    /// Opens the store at `path`, or at `ARC_DB_PATH` / the default location when `path` is nil.
    public init(path: String? = nil, now: @escaping @Sendable () -> Date = { Date() }) throws {
        let resolved = path ?? ArcDatabase.resolvePath()
        self.path = resolved
        self.pool = try ArcDatabase.open(path: resolved)
        self.now = now
    }

    func read<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        do { return try await pool.read(body) } catch { throw ArcError.wrapping(error) }
    }

    func write<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        do { return try await pool.write(body) } catch { throw ArcError.wrapping(error) }
    }

    // MARK: - Projects

    public func projects(includeArchived: Bool = false) async throws -> [Project] {
        try await read { db in
            let filter = includeArchived ? "" : "WHERE archived_at IS NULL"
            return try Project.fetchAll(db, sql: "SELECT * FROM project \(filter) ORDER BY name_key")
        }
    }

    public func project(id: String) async throws -> Project {
        try await read { db in try Self.requireProject(db, id: id) }
    }

    /// Resolves a project by id or (case-insensitive) name. Includes archived projects.
    public func resolveProject(_ reference: String) async throws -> Project {
        try await read { db in try Self.resolveProject(db, reference) }
    }

    public func createProject(name: String, description: String = "", color: String? = nil, icon: String? = nil) async throws -> Project {
        let timestamp = now()
        return try await write { db in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ArcError.invalidArgument("A project name is required.") }
            let key = Reference.projectKey(trimmed)
            try Self.requireNameAvailable(db, key: key, name: trimmed, excluding: nil)
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM project") ?? 0
            let project = Project(
                id: UUID().uuidString,
                name: trimmed,
                nameKey: key,
                description: description,
                color: color ?? Self.projectColors[count % Self.projectColors.count],
                icon: icon.map(ProjectIcons.normalized),
                externalId: nil,
                archivedAt: nil,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try project.insert(db)
            return project
        }
    }

        /// `icon` is an emoji or SF Symbol name; an empty string clears it.
    public func updateProject(id: String, name: String? = nil, description: String? = nil, color: String? = nil, icon: String? = nil) async throws -> Project {
        let timestamp = now()
        return try await write { db in
            var project = try Self.requireProject(db, id: id)
            if let name {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw ArcError.invalidArgument("A project name is required.") }
                let key = Reference.projectKey(trimmed)
                try Self.requireNameAvailable(db, key: key, name: trimmed, excluding: id)
                project.name = trimmed
                project.nameKey = key
            }
            if let description { project.description = description }
            if let color { project.color = color }
            if let icon { project.icon = icon.isEmpty ? nil : ProjectIcons.normalized(icon) }
            project.updatedAt = timestamp
            try project.update(db)
            return project
        }
    }

    public func setProjectArchived(id: String, archived: Bool) async throws -> Project {
        let timestamp = now()
        return try await write { db in
            var project = try Self.requireProject(db, id: id)
            project.archivedAt = archived ? timestamp : nil
            project.updatedAt = timestamp
            try project.update(db)
            return project
        }
    }

    /// Deletes the project, its tickets and their comments.
    public func deleteProject(id: String) async throws {
        try await write { db in
            _ = try Self.requireProject(db, id: id)
            try db.execute(sql: "DELETE FROM project WHERE id = ?", arguments: [id])
        }
    }

    static func requireProject(_ db: Database, id: String) throws -> Project {
        guard let project = try Project.fetchOne(db, sql: "SELECT * FROM project WHERE id = ?", arguments: [id]) else {
            throw ArcError.notFound("Project not found.")
        }
        return project
    }

    static func resolveProject(_ db: Database, _ reference: String) throws -> Project {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let project = try Project.fetchOne(
            db,
            sql: "SELECT * FROM project WHERE name_key = ? OR id = ?",
            arguments: [Reference.projectKey(trimmed), trimmed]
        ) {
            return project
        }
        let names = try String.fetchAll(db, sql: "SELECT name FROM project ORDER BY name_key")
        let listing = names.isEmpty ? "There are no projects yet." : "Existing projects: \(names.joined(separator: ", "))."
        throw ArcError.notFound("Project '\(reference)' not found. \(listing)")
    }

    private static func requireNameAvailable(_ db: Database, key: String, name: String, excluding id: String?) throws {
        let clash = try String.fetchOne(
            db,
            sql: "SELECT id FROM project WHERE name_key = ? AND id <> ?",
            arguments: [key, id ?? ""]
        )
        if clash != nil {
            throw ArcError.conflict("The project name '\(name)' is already in use.")
        }
    }
}
