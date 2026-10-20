import Foundation
import GRDB
import Testing
@testable import ArcCore

@Suite struct HierarchyTests {
    private func failure(_ body: () async throws -> Void) async -> ArcError? {
        do { try await body(); return nil } catch { return error as? ArcError }
    }

    @Test func childDefaultsToParentsProject() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let parent = try await store.task("Parent", in: project)
        let child = try await store.child("Child", of: parent)
        #expect(child.projectId == project.id)
        #expect(child.parentId == parent.id)
        #expect(try await store.ticketDetail(id: parent.id).children.map(\.number) == [child.number])
    }

    @Test func parentMayBeInAnotherProject() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let parent = try await store.task("Parent", in: a)
        let child = try await store.createTicket(NewTicket(title: "Child", projectId: b.id, parentId: parent.id))
        #expect(child.projectId == b.id)
        #expect(child.parentId == parent.id)
    }

    @Test func nestingHasNoDepthLimit() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        var current = try await store.task("Root", in: project)
        for level in 1...6 { current = try await store.child("Level \(level)", of: current) }
        #expect(current.number == 7)
        let roots = try await store.tickets(matching: TicketQuery(topLevelOnly: true))
        #expect(roots.map(\.ticket.number) == [1])
    }

    @Test func missingProjectAndParentIsRejected() async throws {
        let store = try makeStore()
        let error = await failure { _ = try await store.createTicket(NewTicket(title: "X")) }
        #expect(error?.message.contains("project is required") == true)
        let unknown = await failure { _ = try await store.createTicket(NewTicket(title: "X", parentId: "nope")) }
        #expect(unknown?.code == .notFound)
    }

    @Test func aTicketCannotBeItsOwnAncestor() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let a = try await store.task("a", in: project)
        let b = try await store.child("b", of: a)
        let c = try await store.child("c", of: b)

        let itself = await failure { _ = try await store.updateTicket(id: a.id, TicketPatch(parentId: .set(a.id))) }
        #expect(itself?.code == .invalidArgument)
        let cycle = await failure { _ = try await store.updateTicket(id: a.id, TicketPatch(parentId: .set(c.id))) }
        #expect(cycle?.code == .invalidArgument)
        #expect(cycle?.message.contains("descendant") == true)
        #expect(try await store.ticket(id: a.id).parentId == nil)
    }

    @Test func reparentAndClear() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let p1 = try await store.task("p1", in: project)
        let p2 = try await store.task("p2", in: project)
        let child = try await store.child("child", of: p1)
        let moved = try await store.updateTicket(id: child.id, TicketPatch(parentId: .set(p2.id)))
        #expect(moved.parentId == p2.id)
        let cleared = try await store.updateTicket(id: child.id, TicketPatch(parentId: .set(nil)))
        #expect(cleared.parentId == nil)
    }

    @Test func movingATicketLeavesItsChildrenWhereTheyAre() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let parent = try await store.task("Parent", in: a)
        let child = try await store.child("Child", of: parent)
        let moved = try await store.updateTicket(id: parent.id, TicketPatch(projectId: b.id))
        #expect(moved.projectId == b.id)
        #expect(try await store.ticket(id: child.id).projectId == a.id)
        #expect(try await store.ticket(id: child.id).parentId == parent.id)
    }

    // MARK: Identifiers

    @Test func importedPrefixesResolveAndNewTicketsStayArc() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let now = Date().timeIntervalSince1970
        try await store.pool.write { db in
            try db.execute(sql: """
                INSERT INTO ticket (id, prefix, number, project_id, title, status, priority, sort_key, created_at, updated_at)
                VALUES ('imported', 'FIC', 123, ?, 'Imported', 'todo', 0, 0, ?, ?)
                """, arguments: [project.id, now, now])
        }
        let fic = try await store.resolveTicket("fic-123")
        #expect(fic.identifier == "FIC-123")
        // A bare number means ARC; the imported ticket does not take ARC-123.
        await #expect(throws: ArcError.self) { try await store.resolveTicket("123") }

        let created = try await store.task("New", in: project)
        #expect(created.identifier == "ARC-1")
        #expect(try await store.ticketIdentifiers() == ["FIC-123", "ARC-1"])
        #expect(try await store.tickets(matching: TicketQuery(text: "FIC-12")).map(\.ticket.identifier) == ["FIC-123"])
        let detail = try await store.ticketDetail(reference: "FIC-123")
        #expect(TicketDTO(detail).identifier == "FIC-123")
    }

    @Test func prefixAndNumberAreUniqueTogether() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let now = Date().timeIntervalSince1970
        func insert(_ id: String, _ prefix: String, _ number: Int) async throws {
            try await store.pool.write { db in
                try db.execute(sql: """
                    INSERT INTO ticket (id, prefix, number, project_id, title, status, priority, sort_key, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 't', 'todo', 0, 0, ?, ?)
                    """, arguments: [id, prefix, number, project.id, now, now])
            }
        }
        try await insert("1", "FIC", 1)
        try await insert("2", "ENG", 1)
        await #expect(throws: (any Error).self) { try await insert("3", "FIC", 1) }
    }

    // MARK: Migration

    @Test func migrationTurnsEpicsIntoParentsAndKeepsData() async throws {
        let path = temporaryDatabasePath()
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)

        // Build a database as the previous release left it: migrator stopped after v1.
        var v1 = DatabaseMigrator()
        let full = ArcDatabase.makeMigrator()
        let queue = try DatabaseQueue(path: path, configuration: ArcDatabase.configuration())
        _ = full
        v1 = ArcDatabase.makeMigrator()
        try v1.migrate(queue, upTo: "v1")
        let t = 1_800_000_000.0
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO project (id, name, name_key, color, created_at, updated_at) VALUES ('p', 'P', 'p', '#fff', ?, ?)", arguments: [t, t])
            func ticket(_ id: String, _ number: Int, _ kind: String, epic: String? = nil, parent: String? = nil, status: String = "todo") throws {
                try db.execute(sql: """
                    INSERT INTO ticket (id, number, kind, project_id, epic_id, parent_id, title, status, priority, sort_key, created_at, updated_at, completed_at)
                    VALUES (?, ?, ?, 'p', ?, ?, ?, ?, 2, ?, ?, ?, ?)
                    """, arguments: [id, number, kind, epic, parent, "T\(number)", status, Double(number), t, t, status == "done" ? t : nil])
            }
            try ticket("epic", 1, "epic")
            try ticket("task", 2, "task", epic: "epic", status: "done")
            try ticket("sub", 3, "subtask", parent: "task")
            try ticket("loose", 4, "task")
            try db.execute(sql: "INSERT INTO comment (id, ticket_id, body, author, created_at) VALUES ('c', 'sub', 'hi', 'agent', ?)", arguments: [t])
            try db.execute(sql: "UPDATE meta SET value = '5' WHERE key = 'next_ticket_number'")
        }
        try queue.close()

        let store = try ArcStore(path: path)
        let all = try await store.tickets(matching: TicketQuery(includeClosed: true))
        #expect(all.count == 4)
        let byNumber = Dictionary(uniqueKeysWithValues: all.map { ($0.ticket.number, $0.ticket) })
        #expect(byNumber[1]?.parentId == nil)
        #expect(byNumber[2]?.parentId == "epic")
        #expect(byNumber[3]?.parentId == "task")
        #expect(byNumber[4]?.parentId == nil)
        #expect(all.allSatisfy { $0.ticket.prefix == "ARC" })
        #expect(byNumber[2]?.status == .done && byNumber[2]?.priority == .high && byNumber[2]?.completedAt != nil)
        #expect(try await store.comments(ticketId: "sub").map(\.body) == ["hi"])

        // The counter continues, and the new schema's rules apply.
        let project = try await store.resolveProject("P")
        let next = try await store.task("Next", in: project)
        #expect(next.identifier == "ARC-5")
        try await store.deleteTicket(id: "epic")
        #expect(try await store.ticket(id: "task").parentId == nil)
    }
}
