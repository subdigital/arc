import Foundation
import Testing
@testable import ArcCore

@Suite struct DeletionAndCommentTests {
    @Test func deletingTaskDeletesSubtasks() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let task = try await store.task("Task", in: project)
        let s1 = try await store.subtask("s1", of: task)
        let s2 = try await store.subtask("s2", of: task)
        try await store.addComment(ticketId: s1.id, body: "note", author: .user)
        try await store.deleteTicket(id: task.id)
        for id in [task.id, s1.id, s2.id] {
            await #expect(throws: ArcError.self) { try await store.ticket(id: id) }
        }
        #expect(try await store.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM comment") } == 0)
    }

    @Test func deletingEpicKeepsTasks() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let epic = try await store.epic("Epic", in: project)
        let task = try await store.task("Task", in: project, epic: epic)
        try await store.deleteTicket(id: epic.id)
        let kept = try await store.ticket(id: task.id)
        #expect(kept.epicId == nil)
    }

    @Test func numbersAreNeverReused() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        for index in 1...9 { try await store.task("t\(index)", in: project) }
        let nine = try await store.resolveTicket("ARC-9")
        try await store.deleteTicket(id: nine.id)
        let next = try await store.task("next", in: project)
        #expect(next.identifier == "ARC-10")
    }

    @Test func deletingUnknownTicketIsNotFound() async throws {
        let store = try makeStore()
        await #expect(throws: ArcError.self) { try await store.deleteTicket(id: "nope") }
    }

    @Test func commentsAreAttributedAndListedOldestFirst() async throws {
        let clock = TestClock()
        let store = try makeStore(now: clock.callback)
        let project = try await store.createProject(name: "A")
        let ticket = try await store.task("T", in: project)
        try await store.addComment(ticketId: ticket.id, body: "first", author: .user)
        clock.advance()
        try await store.addComment(ticketId: ticket.id, body: "Implemented the parser", author: .agent)
        let comments = try await store.comments(ticketId: ticket.id)
        #expect(comments.map(\.body) == ["first", "Implemented the parser"])
        #expect(comments.map(\.author) == [.user, .agent])
        #expect(try await store.ticketDetail(id: ticket.id).comments.count == 2)
    }

    @Test func commentsWithSameTimestampKeepInsertionOrder() async throws {
        let store = try makeStore(now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let project = try await store.createProject(name: "A")
        let ticket = try await store.task("T", in: project)
        for body in ["a", "b", "c"] { try await store.addComment(ticketId: ticket.id, body: body, author: .user) }
        #expect(try await store.comments(ticketId: ticket.id).map(\.body) == ["a", "b", "c"])
    }

    @Test func blankCommentRejected() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let ticket = try await store.task("T", in: project)
        await #expect(throws: ArcError.self) { try await store.addComment(ticketId: ticket.id, body: " \n", author: .agent) }
        await #expect(throws: ArcError.self) { try await store.addComment(ticketId: "nope", body: "x", author: .agent) }
    }

    @Test func updateCommentRewritesBodyAndRejectsBlank() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let ticket = try await store.task("T", in: project)
        let comment = try await store.addComment(ticketId: ticket.id, body: "- [ ] one", author: .agent)
        let updated = try await store.updateComment(id: comment.id, body: "- [x] one")
        #expect(updated.body == "- [x] one")
        #expect(updated.author == .agent)
        #expect(try await store.comments(ticketId: ticket.id).first?.body == "- [x] one")
        await #expect(throws: ArcError.self) { try await store.updateComment(id: comment.id, body: "  ") }
        await #expect(throws: ArcError.self) { try await store.updateComment(id: "nope", body: "x") }
    }
}
