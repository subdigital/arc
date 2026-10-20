import Foundation
import Testing
@testable import ArcCore

@Suite struct TicketUpdateTests {
    @Test func updatesTimestampAndFields() async throws {
        let clock = TestClock()
        let store = try makeStore(now: clock.callback)
        let project = try await store.createProject(name: "A")
        let ticket = try await store.task("Old", in: project)
        clock.advance()
        let updated = try await store.updateTicket(id: ticket.id, TicketPatch(title: " New ", description: "d", priority: .urgent))
        #expect(updated.title == "New")
        #expect(updated.description == "d")
        #expect(updated.priority == .urgent)
        #expect(updated.updatedAt == clock.now)
        #expect(updated.createdAt == ticket.createdAt)
        #expect(updated.number == ticket.number)
    }

    @Test func blankTitleRejected() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let ticket = try await store.task("Old", in: project)
        await #expect(throws: ArcError.self) { try await store.updateTicket(id: ticket.id, TicketPatch(title: "  ")) }
    }

    @Test func anyStatusTransitionAllowedAndCompletionTracked() async throws {
        let clock = TestClock()
        let store = try makeStore(now: clock.callback)
        let project = try await store.createProject(name: "A")
        let ticket = try await store.task("T", in: project, status: .backlog)

        clock.advance()
        let done = try await store.updateTicket(id: ticket.id, TicketPatch(status: .done))
        #expect(done.status == .done)
        #expect(done.completedAt == clock.now && done.canceledAt == nil)

        clock.advance()
        let reopened = try await store.updateTicket(id: ticket.id, TicketPatch(status: .todo))
        #expect(reopened.completedAt == nil && reopened.canceledAt == nil)

        clock.advance()
        let canceled = try await store.updateTicket(id: ticket.id, TicketPatch(status: .canceled))
        #expect(canceled.canceledAt == clock.now && canceled.completedAt == nil)

        // The first move into a started status sets startedAt; reopening later keeps it.
        clock.advance()
        let started = try await store.updateTicket(id: ticket.id, TicketPatch(status: .inProgress))
        #expect(started.startedAt == clock.now && started.canceledAt == nil)
        clock.advance()
        let backToTodo = try await store.updateTicket(id: ticket.id, TicketPatch(status: .todo))
        let restarted = try await store.updateTicket(id: backToTodo.id, TicketPatch(status: .inReview))
        #expect(restarted.startedAt == started.startedAt)
    }

    @Test func statusChangeWithoutPositionPutsTicketOnTop() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let a = try await store.task("a", in: project, status: .inProgress)
        let b = try await store.task("b", in: project)
        #expect(try await store.order(of: .inProgress) == [a.number])
        try await store.updateTicket(id: b.id, TicketPatch(status: .inProgress))
        #expect(try await store.order(of: .inProgress) == [b.number, a.number])
    }

    @Test func unknownTicketIsNotFound() async throws {
        let store = try makeStore()
        do {
            try await store.updateTicket(id: "nope", TicketPatch(title: "x"))
            Issue.record("expected not_found")
        } catch let error as ArcError {
            #expect(error.code == .notFound)
        }
    }
}
