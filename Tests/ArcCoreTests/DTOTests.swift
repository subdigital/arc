import Foundation
import Testing
@testable import ArcCore

@Suite struct DTOTests {
    @Test func errorDTOEncodesCodeAndMessage() throws {
        let json = try ArcJSON.string(ArcErrorDTO(.notFound("Ticket ARC-9 not found.")))
        #expect(json == #"{"error":{"code":"not_found","message":"Ticket ARC-9 not found."}}"#)
    }

    @Test func errorCodesAreStable() {
        #expect(Set(ArcError.Code.allCases.map(\.rawValue)) ==
            ["not_found", "invalid_argument", "conflict", "database_busy", "schema_too_new", "internal"])
    }

    @Test func ticketDetailSnapshot() async throws {
        let clock = TestClock()
        let store = try makeStore(now: clock.callback)
        let project = try await store.createProject(name: "Website", color: "#5E6AD2")
        let epic = try await store.epic("Launch", in: project)
        let task = try await store.createTicket(NewTicket(
            title: "Build footer", description: "Needs `links`", projectId: project.id, epicId: epic.id,
            status: .inProgress, priority: .high
        ))
        try await store.subtask("Add tests", of: task)
        clock.advance()
        try await store.addComment(ticketId: task.id, body: "Started", author: .agent)

        var detail = try await store.ticketDetail(id: task.id)
        detail.comments[0].id = "comment-id"
        detail.project.id = "project-id"
        let dto = TicketDTO(detail)
        let json = try ArcJSON.string(dto, pretty: true)

        #expect(json == """
        {
          "comments" : [
            {
              "author" : "agent",
              "body" : "Started",
              "createdAt" : "2027-01-15T08:01:00Z",
              "id" : "comment-id"
            }
          ],
          "completedAt" : null,
          "createdAt" : "2027-01-15T08:00:00Z",
          "description" : "Needs `links`",
          "epic" : {
            "identifier" : "ARC-1",
            "status" : "todo",
            "title" : "Launch"
          },
          "identifier" : "ARC-2",
          "kind" : "task",
          "parent" : null,
          "priority" : "high",
          "project" : {
            "id" : "project-id",
            "name" : "Website"
          },
          "status" : "in_progress",
          "subtasks" : [
            {
              "identifier" : "ARC-3",
              "status" : "todo",
              "title" : "Add tests"
            }
          ],
          "title" : "Build footer",
          "updatedAt" : "2027-01-15T08:00:00Z"
        }
        """)
    }
}
