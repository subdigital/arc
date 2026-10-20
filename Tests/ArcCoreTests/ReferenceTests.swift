import Foundation
import Testing
@testable import ArcCore

@Suite struct ReferenceTests {
    @Test(arguments: [
        ("ARC-12", "ARC", 12), ("arc-12", "ARC", 12), ("Arc-7", "ARC", 7), ("12", "ARC", 12), (" 12 ", "ARC", 12),
        ("FIC-123", "FIC", 123), ("fic-123", "FIC", 123), ("Eng2-5", "ENG2", 5),
    ])
    func ticketKeys(input: String, prefix: String, number: Int) throws {
        #expect(try Reference.ticketKey(input) == TicketKey(prefix: prefix, number: number))
    }

    @Test(arguments: ["", "ARC-", "ARC-x", "abc", "0", "-3", "ARC-1.5", "ARC 12", "-5", "1A-2", "A_B-2", "FIC-0"])
    func badTicketReferences(input: String) {
        #expect(throws: ArcError.self) { try Reference.ticketKey(input) }
    }

    @Test(arguments: [
        ("In Progress", TicketStatus.inProgress), ("in-progress", .inProgress), ("in_progress", .inProgress),
        ("IN PROGRESS", .inProgress), ("In Review", .inReview), ("backlog", .backlog), ("Todo", .todo),
        ("done", .done), ("Canceled", .canceled), ("cancelled", .canceled), (" todo ", .todo),
    ])
    func statuses(input: String, expected: TicketStatus) throws {
        #expect(try Reference.status(input) == expected)
    }

    @Test func badStatusListsValidOnes() {
        do {
            _ = try Reference.status("finished")
            Issue.record("expected error")
        } catch let error as ArcError {
            #expect(error.code == .invalidArgument)
            #expect(error.message.contains("in_progress"))
        } catch {}
    }

    @Test(arguments: [("none", TicketPriority.none), ("Urgent", .urgent), ("HIGH", .high), ("medium", .medium), ("low", .low)])
    func priorities(input: String, expected: TicketPriority) throws {
        #expect(try Reference.priority(input) == expected)
    }

    @Test func badPriority() {
        #expect(throws: ArcError.self) { try Reference.priority("critical") }
    }

    @Test func storeResolvesLenientTicketReferences() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        for index in 1...12 { try await store.task("t\(index)", in: project) }
        for reference in ["ARC-12", "arc-12", "12"] {
            #expect(try await store.resolveTicket(reference).number == 12)
        }
        do {
            _ = try await store.resolveTicket("ARC-99999")
            Issue.record("expected not_found")
        } catch let error as ArcError {
            #expect(error.code == .notFound)
        }
    }
}
