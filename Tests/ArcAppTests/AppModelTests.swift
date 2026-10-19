import ArcCore
import Foundation
import Testing
@testable import ArcApp

@MainActor
@Suite struct AppModelTests {
    private func model() throws -> AppModel {
        AppModel(store: try ArcStore(path: temporaryDatabasePath()),
                 settingsStore: ViewSettingsStore(defaults: UserDefaults(suiteName: "arc-\(UUID().uuidString)")!))
    }

    // MARK: History

    @Test func backAndForwardWalkSelectionAndPages() throws {
        let app = try model()
        #expect(!app.canGoBack && !app.canGoForward)

        app.selection = .epics
        app.open(ticket: "t1")
        app.open(ticket: "t2")
        #expect(app.canGoBack)

        app.navigateBack()
        #expect(app.path == [.ticket("t1")] && app.selection == .epics)
        app.navigateBack()
        #expect(app.path.isEmpty && app.selection == .epics)
        app.navigateBack()
        #expect(app.selection == .allTasks)
        #expect(!app.canGoBack && app.canGoForward)

        app.navigateForward()
        #expect(app.selection == .epics && app.path.isEmpty)
        app.navigateForward()
        app.navigateForward()
        #expect(app.path == [.ticket("t1"), .ticket("t2")])
        #expect(!app.canGoForward)
    }

    @Test func navigatingAfterGoingBackDropsTheForwardHistory() throws {
        let app = try model()
        app.open(ticket: "a")
        app.open(ticket: "b")
        app.navigateBack()
        app.open(ticket: "c")
        #expect(!app.canGoForward)
        #expect(app.path == [.ticket("a"), .ticket("c")])
    }

    @Test func restoringDoesNotAddHistoryEntries() throws {
        let app = try model()
        app.open(ticket: "a")
        app.navigateBack()
        app.navigateForward()
        app.navigateBack()
        app.navigateBack()
        #expect(app.selection == .allTasks && app.path.isEmpty)
        #expect(!app.canGoBack)
    }

    // MARK: Multi-select

    @Test func toggleAndRangeSelection() throws {
        let app = try model()
        let order = ["a", "b", "c", "d", "e"]
        app.toggleChecked("b")
        app.checkRange(to: "d", order: order)
        #expect(app.checkedTicketIDs == ["b", "c", "d"])
        app.toggleChecked("c")
        #expect(app.checkedTicketIDs == ["b", "d"])
    }

    @Test func actionTargetsPreferTickedRowsOverTheCursor() throws {
        let app = try model()
        app.selectedTicketID = "cursor"
        #expect(app.actionTargets == ["cursor"])
        app.toggleChecked("x")
        app.toggleChecked("y")
        #expect(Set(app.actionTargets) == ["x", "y"])
    }

    @Test func changingSidebarSelectionClearsTicks() throws {
        let app = try model()
        app.toggleChecked("x")
        app.selection = .epics
        #expect(app.checkedTicketIDs.isEmpty)
    }

    // MARK: Bulk operations

    @Test func bulkStatusAndPriorityApplyToEveryTicket() async throws {
        let app = try model()
        let project = try await app.store.createProject(name: "A")
        let one = try await app.store.createTicket(NewTicket(title: "1", projectId: project.id))
        let two = try await app.store.createTicket(NewTicket(title: "2", projectId: project.id))

        await app.bulkUpdate([one.id, two.id], TicketPatch(status: .inProgress, priority: .high), done: "Updated")
        for id in [one.id, two.id] {
            let ticket = try await app.store.ticket(id: id)
            #expect(ticket.status == .inProgress && ticket.priority == .high)
        }
        #expect(app.toast?.message == "Updated 2 tickets")
        #expect(app.error == nil)
    }

    @Test func bulkMoveReportsSubtasksThatCannotMove() async throws {
        let app = try model()
        let a = try await app.store.createProject(name: "A")
        let b = try await app.store.createProject(name: "B")
        let task = try await app.store.createTicket(NewTicket(title: "task", projectId: a.id))
        let sub = try await app.store.createTicket(NewTicket(title: "sub", kind: .subtask, parentId: task.id))

        await app.bulkUpdate([sub.id, task.id], TicketPatch(projectId: b.id), done: "Moved")
        #expect(try await app.store.ticket(id: task.id).projectId == b.id)
        #expect(app.toast?.message == "Moved 1 ticket")
        #expect(app.error != nil, "the subtask failure must be surfaced")
    }

    @Test func bulkDeleteRemovesTicketsAndClearsTicks() async throws {
        let app = try model()
        let project = try await app.store.createProject(name: "A")
        let one = try await app.store.createTicket(NewTicket(title: "1", projectId: project.id))
        let two = try await app.store.createTicket(NewTicket(title: "2", projectId: project.id))
        app.toggleChecked(one.id)
        app.toggleChecked(two.id)

        await app.bulkDelete([one.id, two.id])
        #expect(app.checkedTicketIDs.isEmpty)
        #expect(try await app.store.ticketNumbers().isEmpty)
        #expect(app.toast?.message == "Deleted 2 tickets")
    }

    @Test func pickerAppliesToAllTargets() async throws {
        let app = try model()
        let project = try await app.store.createProject(name: "A")
        let one = try await app.store.createTicket(NewTicket(title: "1", projectId: project.id))
        let two = try await app.store.createTicket(NewTicket(title: "2", projectId: project.id))
        let done = TicketStatus.allCases.firstIndex(of: .done)!
        await app.applyPick(done, for: PickerRequest(ticketIDs: [one.id, two.id], kind: .status))
        #expect(try await app.store.ticket(id: two.id).status == .done)
        let urgent = TicketPriority.menuOrder.firstIndex(of: .urgent)!
        await app.applyPick(urgent, for: PickerRequest(ticketIDs: [one.id], kind: .priority))
        #expect(try await app.store.ticket(id: one.id).priority == .urgent)
    }
}
