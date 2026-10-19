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
        #expect(done.completedAt == clock.now)

        clock.advance()
        let reopened = try await store.updateTicket(id: ticket.id, TicketPatch(status: .todo))
        #expect(reopened.completedAt == nil)

        clock.advance()
        let canceled = try await store.updateTicket(id: ticket.id, TicketPatch(status: .canceled))
        #expect(canceled.completedAt == clock.now)
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

    @Test func movingTaskMovesSubtasksAndClearsForeignEpic() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let epic = try await store.epic("Epic", in: a)           // ARC-1
        let task = try await store.task("Task", in: a, epic: epic) // ARC-2
        let s1 = try await store.subtask("s1", of: task)
        let s2 = try await store.subtask("s2", of: task)

        let moved = try await store.updateTicket(id: task.id, TicketPatch(projectId: b.id))
        #expect(moved.projectId == b.id)
        #expect(moved.epicId == nil)
        #expect(moved.number == task.number)
        for sub in [s1, s2] {
            #expect(try await store.ticket(id: sub.id).projectId == b.id)
        }
        #expect(try await store.ticket(id: epic.id).projectId == a.id)
    }

    @Test func movingTaskKeepsEpicWhenGivenOneInTheTargetProject() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let epicA = try await store.epic("Epic A", in: a)
        let epicB = try await store.epic("Epic B", in: b)
        let task = try await store.task("Task", in: a, epic: epicA)
        let moved = try await store.updateTicket(id: task.id, TicketPatch(projectId: b.id, epicId: .set(epicB.id)))
        #expect(moved.epicId == epicB.id)
    }

    @Test func movingEpicMovesTasksAndTheirSubtasks() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let epic = try await store.epic("Epic", in: a)
        let t1 = try await store.task("t1", in: a, epic: epic)
        let t2 = try await store.task("t2", in: a, epic: epic)
        let sub = try await store.subtask("sub", of: t1)
        let other = try await store.task("other", in: a)

        try await store.updateTicket(id: epic.id, TicketPatch(projectId: b.id))
        for moved in [epic, t1, t2, sub] {
            #expect(try await store.ticket(id: moved.id).projectId == b.id)
        }
        #expect(try await store.ticket(id: t1.id).epicId == epic.id)
        #expect(try await store.ticket(id: t2.id).epicId == epic.id)
        #expect(try await store.ticket(id: other.id).projectId == a.id)
    }

    @Test func subtaskCannotMoveOnItsOwn() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let task = try await store.task("Task", in: a)
        let sub = try await store.subtask("sub", of: task)
        await #expect(throws: ArcError.self) { try await store.updateTicket(id: sub.id, TicketPatch(projectId: b.id)) }
    }

    @Test func reparentingSubtaskFollowsNewParentsProject() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let t1 = try await store.task("t1", in: a)
        let t2 = try await store.task("t2", in: b)
        let sub = try await store.subtask("sub", of: t1)
        let moved = try await store.updateTicket(id: sub.id, TicketPatch(parentId: .set(t2.id)))
        #expect(moved.parentId == t2.id)
        #expect(moved.projectId == b.id)
    }

    @Test func epicAssignmentRules() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let epicA = try await store.epic("Epic A", in: a)
        let epicB = try await store.epic("Epic B", in: b)
        let task = try await store.task("Task", in: a)

        let assigned = try await store.updateTicket(id: task.id, TicketPatch(epicId: .set(epicA.id)))
        #expect(assigned.epicId == epicA.id)
        await #expect(throws: ArcError.self) { try await store.updateTicket(id: task.id, TicketPatch(epicId: .set(epicB.id))) }
        let cleared = try await store.updateTicket(id: task.id, TicketPatch(epicId: .set(nil)))
        #expect(cleared.epicId == nil)
    }

    @Test func kindChangesRespectChildren() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let task = try await store.task("Task", in: a)
        _ = try await store.subtask("sub", of: task)
        await #expect(throws: ArcError.self) { try await store.updateTicket(id: task.id, TicketPatch(kind: .epic)) }

        let lone = try await store.task("Lone", in: a)
        let asEpic = try await store.updateTicket(id: lone.id, TicketPatch(kind: .epic))
        #expect(asEpic.kind == .epic)
        let backToTask = try await store.updateTicket(id: lone.id, TicketPatch(kind: .task))
        #expect(backToTask.kind == .task)

        let epic = try await store.epic("Epic", in: a)
        _ = try await store.task("In epic", in: a, epic: epic)
        await #expect(throws: ArcError.self) { try await store.updateTicket(id: epic.id, TicketPatch(kind: .task)) }
    }

    @Test func taskBecomesSubtaskWhenGivenAParent() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let parent = try await store.task("Parent", in: a)
        let task = try await store.task("Task", in: a)
        let sub = try await store.updateTicket(id: task.id, TicketPatch(kind: .subtask, parentId: .set(parent.id)))
        #expect(sub.kind == .subtask)
        #expect(sub.parentId == parent.id)
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
