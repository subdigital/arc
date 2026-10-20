import Foundation
import GRDB
import Testing
@testable import ArcCore

@Suite struct DatabaseTests {
    @Test func createsFileAtOverridePathInWALMode() async throws {
        let path = temporaryDatabasePath()
        let store = try ArcStore(path: path)
        #expect(FileManager.default.fileExists(atPath: path))
        let mode = try await store.pool.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") }
        #expect(mode == "wal")
        let foreignKeys = try await store.pool.read { try Int.fetchOne($0, sql: "PRAGMA foreign_keys") }
        #expect(foreignKeys == 1)
    }

    @Test func resolvesPathFromEnvironment() {
        #expect(ArcDatabase.resolvePath(environment: ["ARC_DB_PATH": "/tmp/x/arc.sqlite"]) == "/tmp/x/arc.sqlite")
        #expect(ArcDatabase.resolvePath(environment: [:]).hasSuffix("Library/Application Support/Arc/arc.sqlite"))
        #expect(ArcDatabase.resolvePath(environment: ["ARC_DB_PATH": ""]).hasSuffix("Arc/arc.sqlite"))
    }

    @Test func migrationV1CreatesSchemaOnEmptyDatabase() async throws {
        let store = try makeStore()
        try await store.pool.read { db in
            for table in ["meta", "project", "ticket", "comment"] {
                #expect(try db.tableExists(table), "missing table \(table)")
            }
            let next = try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'next_ticket_number'")
            #expect(next == "1")
            let indexes = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'"))
            #expect(indexes.isSuperset(of: ["ticket_project_status_sort", "ticket_parent"]))
            let applied = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
            #expect(applied == ["v1", "v2", "v3"])
        }
    }

    @Test func reopeningKeepsDataAndDoesNotRemigrate() async throws {
        let path = temporaryDatabasePath()
        let first = try ArcStore(path: path)
        _ = try await first.createProject(name: "Website")
        let second = try ArcStore(path: path)
        #expect(try await second.projects().map(\.name) == ["Website"])
    }

    @Test func refusesDatabaseFromNewerVersion() async throws {
        let path = temporaryDatabasePath()
        let store = try ArcStore(path: path)
        try await store.pool.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v999-from-the-future')")
        }
        do {
            _ = try ArcStore(path: path)
            Issue.record("expected schema_too_new")
        } catch let error as ArcError {
            #expect(error.code == .schemaTooNew)
            #expect(error.message.contains("newer version of Arc"))
        }
    }
}
