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

        // Tickets get a key prefix (imported tickets keep their source's key, new ones are ARC-n) and the
        // hierarchy becomes a single `parent_id` of any depth: epics turn into plain parent tickets.
        migrator.registerMigration("v2") { db in
            try db.execute(sql: """
                CREATE TABLE ticket_new (
                    id TEXT NOT NULL PRIMARY KEY,
                    prefix TEXT NOT NULL,
                    number INTEGER NOT NULL,
                    project_id TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
                    parent_id TEXT REFERENCES ticket(id) ON DELETE SET NULL,
                    title TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL,
                    priority INTEGER NOT NULL,
                    sort_key DOUBLE NOT NULL,
                    created_at DOUBLE NOT NULL,
                    updated_at DOUBLE NOT NULL,
                    completed_at DOUBLE,
                    UNIQUE (prefix, number)
                )
                """)
            try db.execute(sql: """
                INSERT INTO ticket_new
                    (id, prefix, number, project_id, parent_id, title, description, status, priority,
                     sort_key, created_at, updated_at, completed_at)
                SELECT id, 'ARC', number, project_id, COALESCE(parent_id, epic_id), title, description, status, priority,
                       sort_key, created_at, updated_at, completed_at
                FROM ticket
                """)
            try db.execute(sql: "DROP TABLE ticket")
            try db.execute(sql: "ALTER TABLE ticket_new RENAME TO ticket")
            try db.create(index: "ticket_project_status_sort", on: "ticket", columns: ["project_id", "status", "sort_key"])
            try db.create(index: "ticket_parent", on: "ticket", columns: ["parent_id"])
        }

        // Timestamps like Linear's, labels, relations, milestones, attachments, comment threads, project icons,
        // and external ids so an import can be re-run without duplicating anything.
        migrator.registerMigration("v3") { db in
            try db.execute(sql: """
                ALTER TABLE ticket ADD COLUMN started_at DOUBLE;
                ALTER TABLE ticket ADD COLUMN canceled_at DOUBLE;
                ALTER TABLE ticket ADD COLUMN archived_at DOUBLE;
                ALTER TABLE ticket ADD COLUMN milestone_id TEXT REFERENCES milestone(id) ON DELETE SET NULL;
                ALTER TABLE ticket ADD COLUMN external_id TEXT;
                ALTER TABLE project ADD COLUMN icon TEXT;
                ALTER TABLE project ADD COLUMN external_id TEXT;
                ALTER TABLE comment ADD COLUMN parent_id TEXT REFERENCES comment(id) ON DELETE CASCADE;
                ALTER TABLE comment ADD COLUMN author_name TEXT;
                ALTER TABLE comment ADD COLUMN updated_at DOUBLE;
                ALTER TABLE comment ADD COLUMN external_id TEXT;
                """)
            // Linear cancels carry their own date; older rows used completed_at for both closed states.
            try db.execute(sql: """
                UPDATE ticket SET canceled_at = completed_at, completed_at = NULL WHERE status = 'canceled'
                """)

            try db.create(table: "milestone") { t in
                t.primaryKey("id", .text)
                t.column("project_id", .text).notNull().references("project", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("target_date", .double)
                t.column("sort_order", .double).notNull().defaults(to: 0)
                t.column("external_id", .text)
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
            }
            try db.create(index: "milestone_project", on: "milestone", columns: ["project_id", "sort_order"])

            try db.create(table: "label") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("name_key", .text).notNull().unique()
                t.column("color", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("external_id", .text)
                t.column("created_at", .double).notNull()
            }
            try db.create(table: "ticket_label") { t in
                t.column("ticket_id", .text).notNull().references("ticket", onDelete: .cascade)
                t.column("label_id", .text).notNull().references("label", onDelete: .cascade)
                t.primaryKey(["ticket_id", "label_id"])
            }
            try db.create(index: "ticket_label_label", on: "ticket_label", columns: ["label_id"])

            // `blocks` and `duplicate` are directed (from → to); `related` is stored once, smaller id first.
            try db.create(table: "relation") { t in
                t.primaryKey("id", .text)
                t.column("from_id", .text).notNull().references("ticket", onDelete: .cascade)
                t.column("to_id", .text).notNull().references("ticket", onDelete: .cascade)
                t.column("type", .text).notNull().check(sql: "type IN ('blocks','related','duplicate')")
                t.column("created_at", .double).notNull()
                t.uniqueKey(["from_id", "to_id", "type"])
                t.check(sql: "from_id <> to_id")
            }
            try db.create(index: "relation_to", on: "relation", columns: ["to_id"])

            try db.create(table: "attachment") { t in
                t.primaryKey("id", .text)
                t.column("ticket_id", .text).notNull().references("ticket", onDelete: .cascade)
                t.column("kind", .text).notNull().check(sql: "kind IN ('link','file')")
                t.column("title", .text).notNull()
                t.column("url", .text)
                t.column("path", .text)
                t.column("mime_type", .text)
                t.column("size", .integer)
                t.column("external_id", .text)
                t.column("created_at", .double).notNull()
            }
            try db.create(index: "attachment_ticket", on: "attachment", columns: ["ticket_id", "created_at"])

            // What an import created or last wrote, so a re-run can tell new / unchanged / edited-since.
            try db.create(table: "import_record") { t in
                t.column("external_id", .text).notNull().primaryKey()
                t.column("kind", .text).notNull()
                t.column("local_id", .text).notNull()
                t.column("source_hash", .text).notNull()
                t.column("imported_at", .double).notNull()
            }
            try db.create(index: "import_record_local", on: "import_record", columns: ["kind", "local_id"])

            try db.execute(sql: "CREATE UNIQUE INDEX ticket_external ON ticket(external_id) WHERE external_id IS NOT NULL")
            try db.execute(sql: "CREATE UNIQUE INDEX project_external ON project(external_id) WHERE external_id IS NOT NULL")
            try db.execute(sql: "CREATE UNIQUE INDEX comment_external ON comment(external_id) WHERE external_id IS NOT NULL")
            try db.execute(sql: "CREATE UNIQUE INDEX milestone_external ON milestone(external_id) WHERE external_id IS NOT NULL")
            try db.execute(sql: "CREATE UNIQUE INDEX label_external ON label(external_id) WHERE external_id IS NOT NULL")
            try db.execute(sql: "CREATE UNIQUE INDEX attachment_external ON attachment(external_id) WHERE external_id IS NOT NULL")
            try db.create(index: "ticket_milestone", on: "ticket", columns: ["milestone_id"])
        }

        return migrator
    }
}
