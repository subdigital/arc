import Foundation
import GRDB

public enum ArcDatabase {
    public static let pathEnvironmentKey = "ARC_DB_PATH"

    /// `ARC_DB_PATH` if set (and non-empty), otherwise `~/Library/Application Support/Arc/arc.sqlite`.
    public static func resolvePath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = environment[pathEnvironmentKey], !override.isEmpty {
            return (override as NSString).expandingTildeInPath
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Arc/arc.sqlite").path
    }

    static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(5)
        return configuration
    }

    /// Opens (creating if needed) the database at `path`, then migrates it forward.
    /// Refuses databases that contain migrations this build does not know about.
    static func open(path: String) throws -> DatabasePool {
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        let pool: DatabasePool
        do {
            pool = try DatabasePool(path: path, configuration: configuration())
            let migrator = makeMigrator()
            if try pool.read({ try migrator.hasBeenSuperseded($0) }) {
                throw ArcError.schemaTooNew()
            }
            try migrator.migrate(pool)
        } catch {
            throw ArcError.wrapping(error)
        }
        return pool
    }

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            try db.execute(sql: "INSERT INTO meta (key, value) VALUES ('next_ticket_number', '1')")

            try db.create(table: "project") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("name_key", .text).notNull().unique()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("color", .text).notNull()
                t.column("archived_at", .double)
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
            }

            try db.create(table: "ticket") { t in
                t.primaryKey("id", .text)
                t.column("number", .integer).notNull().unique()
                t.column("kind", .text).notNull().check(sql: "kind IN ('epic','task','subtask')")
                t.column("project_id", .text).notNull().references("project", onDelete: .cascade)
                t.column("epic_id", .text).references("ticket", onDelete: .setNull)
                t.column("parent_id", .text).references("ticket", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull()
                t.column("priority", .integer).notNull()
                t.column("sort_key", .double).notNull()
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
                t.column("completed_at", .double)
            }
            try db.create(index: "ticket_project_status_sort", on: "ticket", columns: ["project_id", "status", "sort_key"])
            try db.create(index: "ticket_epic", on: "ticket", columns: ["epic_id"])
            try db.create(index: "ticket_parent", on: "ticket", columns: ["parent_id"])

            try db.create(table: "comment") { t in
                t.primaryKey("id", .text)
                t.column("ticket_id", .text).notNull().references("ticket", onDelete: .cascade)
                t.column("body", .text).notNull()
                t.column("author", .text).notNull().check(sql: "author IN ('user','agent')")
                t.column("created_at", .double).notNull()
            }
            try db.create(index: "comment_ticket", on: "comment", columns: ["ticket_id", "created_at"])
        }

        return migrator
    }
}
