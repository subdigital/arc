import Foundation
import Testing
@testable import ArcCore

@Suite struct OrderingTests {
    /// Creates tickets "1", "2", … in Todo, ordered ARC-1, ARC-2, … (creation puts new ones on top, so reverse).
    private func seededStore(count: Int) async throws -> (ArcStore, Project, [Ticket]) {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        var tickets: [Ticket] = []
        for index in 1...count { tickets.append(try await store.task("t\(index)", in: project)) }
        for ticket in tickets.reversed() { try await store.moveTicket(id: ticket.id, position: .top) }
        #expect(try await store.order(of: .todo) == Array(1...count))
        return (store, project, tickets)
    }

    @Test func moveBeforeFirst() async throws {
        let (store, _, t) = try await seededStore(count: 3)
        try await store.moveTicket(id: t[2].id, position: .before(t[0].id))
        #expect(try await store.order(of: .todo) == [3, 1, 2])
    }

    @Test func moveBetweenAndAfterAndBottom() async throws {
        let (store, _, t) = try await seededStore(count: 4)
        try await store.moveTicket(id: t[0].id, position: .after(t[1].id))
        #expect(try await store.order(of: .todo) == [2, 1, 3, 4])
        try await store.moveTicket(id: t[1].id, position: .bottom)
        #expect(try await store.order(of: .todo) == [1, 3, 4, 2])
        try await store.moveTicket(id: t[3].id, position: .after(t[3 - 1].id))
        #expect(try await store.order(of: .todo) == [1, 3, 4, 2])
    }

    @Test func moveToAnotherStatusAtPosition() async throws {
        let (store, project, t) = try await seededStore(count: 3)
        let a = try await store.task("a", in: project, status: .inProgress)
        let b = try await store.task("b", in: project, status: .inProgress)
        // In Progress order: b, a
        #expect(try await store.order(of: .inProgress) == [b.number, a.number])

        let moved = try await store.moveTicket(id: t[0].id, status: .inProgress, position: .after(b.id))
        #expect(moved.status == .inProgress)
        #expect(try await store.order(of: .inProgress) == [b.number, t[0].number, a.number])
        #expect(try await store.order(of: .todo) == [2, 3])

        let top = try await store.moveTicket(id: t[1].id, status: .inProgress, position: .top)
        #expect(top.status == .inProgress)
        #expect(try await store.order(of: .inProgress).first == t[1].number)
    }

    @Test func movingToClosedStatusSetsCompletion() async throws {
        let (store, _, t) = try await seededStore(count: 2)
        let done = try await store.moveTicket(id: t[0].id, status: .done, position: .top)
        #expect(done.completedAt != nil)
        let back = try await store.moveTicket(id: t[0].id, status: .todo, position: .top)
        #expect(back.completedAt == nil)
    }

    @Test func neighborInWrongStatusRejected() async throws {
        let (store, project, t) = try await seededStore(count: 2)
        let other = try await store.task("other", in: project, status: .done)
        await #expect(throws: ArcError.self) {
            try await store.moveTicket(id: t[0].id, position: .before(other.id))
        }
        await #expect(throws: ArcError.self) {
            try await store.moveTicket(id: t[0].id, position: .before(t[0].id))
        }
    }

    @Test func repeatedInsertsBetweenNeighborsNeverCollapseTheGap() async throws {
        let (store, _, t) = try await seededStore(count: 3)
        // Alternately wedge ARC-3 and ARC-2 right behind ARC-1; each wedge halves the gap to the
        // next ticket, so within ~25 rounds the gap would drop below 1e-6 without renormalization.
        for round in 0..<40 {
            let mover = round.isMultiple(of: 2) ? t[2] : t[1]
            try await store.moveTicket(id: mover.id, position: .after(t[0].id))
            let order = try await store.order(of: .todo)
            #expect(order.first == 1)
            #expect(order.last == (round.isMultiple(of: 2) ? 2 : 3))
            let keys = try await store.pool.read { try Double.fetchAll($0, sql: "SELECT sort_key FROM ticket ORDER BY sort_key") }
            for (low, high) in zip(keys, keys.dropFirst()) { #expect(high - low >= ArcStore.minimumSortGap / 2) }
        }
    }

    @Test func forcedRenormalizationKeepsOrderAndRestoresGaps() async throws {
        let (store, _, t) = try await seededStore(count: 3)
        // Force two keys almost together, then insert between them.
        try await store.pool.write { db in
            try db.execute(sql: "UPDATE ticket SET sort_key = 10 WHERE number = 1")
            try db.execute(sql: "UPDATE ticket SET sort_key = 10.0000001 WHERE number = 2")
            try db.execute(sql: "UPDATE ticket SET sort_key = 20 WHERE number = 3")
        }
        try await store.moveTicket(id: t[2].id, position: .after(t[0].id))
        #expect(try await store.order(of: .todo) == [1, 3, 2])
        let keys = try await store.pool.read { try Double.fetchAll($0, sql: "SELECT sort_key FROM ticket ORDER BY sort_key") }
        for (low, high) in zip(keys, keys.dropFirst()) { #expect(high - low >= 0.4) }
    }
}
