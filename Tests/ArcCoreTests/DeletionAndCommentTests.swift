import Foundation
import Testing
@testable import ArcCore

@Suite struct DeletionAndCommentTests {
    @Test func deletingTicketDeletesItsCommentsAndKeepsChildren() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let parent = try await store.task("Parent", in: project)
        let child = try await store.child("Child", of: parent)
        let grandchild = try await store.child("Grandchild", of: child)
        try await store.addComment(ticketId: child.id, body: "note", author: .user)
        try await store.deleteTicket(id: child.id)
        await #expect(throws: ArcError.self) { try await store.ticket(id: child.id) }
        #expect(try await store.ticket(id: grandchild.id).parentId == nil)
        #expect(try await store.ticket(id: parent.id).parentId == nil)
        #expect(try await store.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM comment") } == 0)
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
