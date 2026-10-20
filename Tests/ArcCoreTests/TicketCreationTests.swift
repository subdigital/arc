import Foundation
import Testing
@testable import ArcCore

@Suite struct TicketCreationTests {
    private func failure(_ body: () async throws -> Void) async -> ArcError? {
        do { try await body(); return nil } catch { return error as? ArcError }
    }

    @Test func defaultsAndSequentialNumbersAcrossProjects() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let first = try await store.task("First", in: a)
        let second = try await store.task("Second", in: b)
        #expect(first.number == 1 && second.number == 2)
        #expect(first.identifier == "ARC-1")
        #expect(first.status == .todo)
        #expect(first.priority == .none)
        #expect(first.completedAt == nil)
    }

    @Test func blankTitleRejected() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let error = await failure { _ = try await store.createTicket(NewTicket(title: " \n ", projectId: project.id)) }
        #expect(error?.code == .invalidArgument)
        #expect(error?.message.contains("title is required") == true)
    }

    @Test func missingProjectRejected() async throws {
        let store = try makeStore()
        let missing = await failure { _ = try await store.createTicket(NewTicket(title: "X")) }
        #expect(missing?.message.contains("project is required") == true)
        let unknown = await failure { _ = try await store.createTicket(NewTicket(title: "X", projectId: "nope")) }
        #expect(unknown?.code == .notFound)
    }

    @Test func closedStatusAtCreationSetsCompletion() async throws {
        let clock = TestClock()
        let store = try makeStore(now: clock.callback)
        let project = try await store.createProject(name: "A")
        let done = try await store.task("Done already", in: project, status: .done)
        #expect(done.completedAt == clock.now)
    }

    @Test func newTicketsLandAtTopOfTheirStatus() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        for title in ["one", "two", "three"] { try await store.task(title, in: project) }
        #expect(try await store.order(of: .todo) == [3, 2, 1])
    }
}
