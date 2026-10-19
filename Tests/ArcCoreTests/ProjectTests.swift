import Foundation
import Testing
@testable import ArcCore

@Suite struct ProjectTests {
    @Test func createAndList() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "  Website ", description: "Marketing site")
        #expect(project.name == "Website")
        #expect(!project.isArchived)
        #expect(try await store.projects().map(\.name) == ["Website"])
    }

    @Test func blankNameRejected() async throws {
        let store = try makeStore()
        await #expect(throws: ArcError.self) { try await store.createProject(name: "   ") }
    }

    @Test func duplicateNameIsConflictIgnoringCase() async throws {
        let store = try makeStore()
        _ = try await store.createProject(name: "Website")
        do {
            _ = try await store.createProject(name: "website")
            Issue.record("expected conflict")
        } catch let error as ArcError {
            #expect(error.code == .conflict)
            #expect(error.message.contains("already in use"))
        }
    }

    @Test func renameChecksUniqueness() async throws {
        let store = try makeStore()
        _ = try await store.createProject(name: "Website")
        let api = try await store.createProject(name: "API")
        await #expect(throws: ArcError.self) { try await store.updateProject(id: api.id, name: "WEBSITE") }
        let renamed = try await store.updateProject(id: api.id, name: "api")
        #expect(renamed.name == "api")
    }

    @Test func archiveHidesButKeepsTickets() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "Website")
        let ticket = try await store.task("Fix footer", in: project)
        let archived = try await store.setProjectArchived(id: project.id, archived: true)
        #expect(archived.isArchived)
        #expect(try await store.projects().isEmpty)
        #expect(try await store.projects(includeArchived: true).count == 1)
        #expect(try await store.resolveTicket("ARC-1").id == ticket.id)
        #expect(try await store.tickets(matching: TicketQuery()).isEmpty)
        #expect(try await store.tickets(matching: TicketQuery(projectIds: [project.id])).count == 1)

        _ = try await store.setProjectArchived(id: project.id, archived: false)
        #expect(try await store.projects().count == 1)
    }

    @Test func deleteCascadesToTicketsAndComments() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "Website")
        let epic = try await store.epic("Launch", in: project)
        let first = try await store.task("One", in: project, epic: epic)
        try await store.task("Two", in: project)
        try await store.task("Three", in: project)
        try await store.addComment(ticketId: first.id, body: "hi", author: .user)

        try await store.deleteProject(id: project.id)
        for reference in ["ARC-1", "ARC-2", "ARC-3", "ARC-4"] {
            do {
                _ = try await store.resolveTicket(reference)
                Issue.record("\(reference) should be gone")
            } catch let error as ArcError {
                #expect(error.code == .notFound)
            }
        }
        let comments = try await store.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM comment") }
        #expect(comments == 0)
    }

    @Test func resolveByNameListsExistingProjectsOnMiss() async throws {
        let store = try makeStore()
        _ = try await store.createProject(name: "Website")
        _ = try await store.createProject(name: "API")
        #expect(try await store.resolveProject("website").name == "Website")
        do {
            _ = try await store.resolveProject("Nope")
            Issue.record("expected not_found")
        } catch let error as ArcError {
            #expect(error.code == .notFound)
            #expect(error.message.contains("API"))
            #expect(error.message.contains("Website"))
        }
    }
}
