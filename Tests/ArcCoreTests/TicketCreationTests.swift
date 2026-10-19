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
        let second = try await store.epic("Second", in: b)
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

    @Test func subtaskTakesParentProject() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let parent = try await store.task("Parent", in: project)
        let child = try await store.subtask("Child", of: parent)
        #expect(child.projectId == project.id)
        #expect(child.parentId == parent.id)
        #expect(try await store.ticketDetail(id: parent.id).subtasks.map(\.number) == [child.number])
    }

    @Test func subtaskParentMustBeATask() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let epic = try await store.epic("Epic", in: project)
        let task = try await store.task("Task", in: project)
        let child = try await store.subtask("Child", of: task)

        for parent in [epic, child] {
            let error = await failure { _ = try await store.subtask("Nested", of: parent) }
            #expect(error?.code == .invalidArgument)
            #expect(error?.message.contains("Subtasks can only belong to tasks") == true)
        }
        let orphan = await failure { _ = try await store.createTicket(NewTicket(title: "Orphan", kind: .subtask, projectId: project.id)) }
        #expect(orphan?.code == .invalidArgument)
    }

    @Test func taskWithParentRejected() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let task = try await store.task("Task", in: project)
        let error = await failure {
            _ = try await store.createTicket(NewTicket(title: "X", kind: .task, projectId: project.id, parentId: task.id))
        }
        #expect(error?.code == .invalidArgument)
    }

    @Test func epicMustBeAnEpicInTheSameProject() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let epicA = try await store.epic("Epic A", in: a)
        let taskA = try await store.task("Task A", in: a)

        let linked = try await store.task("Linked", in: a, epic: epicA)
        #expect(linked.epicId == epicA.id)

        let crossProject = await failure { _ = try await store.task("Cross", in: b, epic: epicA) }
        #expect(crossProject?.code == .invalidArgument)
        let notAnEpic = await failure { _ = try await store.task("Bad", in: a, epic: taskA) }
        #expect(notAnEpic?.code == .invalidArgument)
        let epicWithEpic = await failure {
            _ = try await store.createTicket(NewTicket(title: "E", kind: .epic, projectId: a.id, epicId: epicA.id))
        }
        #expect(epicWithEpic?.code == .invalidArgument)
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
