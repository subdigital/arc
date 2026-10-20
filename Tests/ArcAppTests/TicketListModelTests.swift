import ArcCore
import Foundation
import Testing
@testable import ArcApp

@MainActor
@Suite struct TicketListModelTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "arc-tests-\(UUID().uuidString)")!
    }

    // MARK: Query construction

    @Test func allTasksListsEveryTicketAcrossActiveProjects() {
        let query = TicketListModel.query(for: .allTasks, settings: ViewSettings())
        #expect(query.projectIds.isEmpty)
        #expect(query.includeClosed)
        #expect(!query.includeArchivedProjects)
        #expect(query.parentId == nil && !query.topLevelOnly)
        #expect(query.priorities.isEmpty)
    }

    @Test func projectFilterAppliesInAllTasksOnly() {
        var settings = ViewSettings()
        settings.projectFilter = ["a", "b"]
        #expect(TicketListModel.query(for: .allTasks, settings: settings).projectIds == ["a", "b"])
        #expect(TicketListModel.query(for: .project("p"), settings: settings).projectIds == ["p"])
    }

    @Test func hidingSubTicketsKeepsTopLevelOnly() {
        var settings = ViewSettings()
        settings.showSubtasks = false
        #expect(TicketListModel.query(for: .allTasks, settings: settings).topLevelOnly)
        #expect(TicketListModel.query(for: .project("p"), settings: settings).topLevelOnly)
        #expect(!TicketListModel.query(for: .children("t"), settings: settings).topLevelOnly)
    }

    @Test func parentAndPriorityFilters() {
        var settings = ViewSettings()
        settings.parentFilter = "parent-1"
        settings.priorityFilter = [TicketPriority.high.rawValue, TicketPriority.urgent.rawValue]
        let query = TicketListModel.query(for: .project("p"), settings: settings)
        #expect(query.parentId == "parent-1")
        #expect(query.priorities == [.high, .urgent])
    }

    @Test func childrenScopeUsesTheParentAndIgnoresTheParentFilter() {
        var settings = ViewSettings()
        settings.parentFilter = "other"
        let query = TicketListModel.query(for: .children("e"), settings: settings)
        #expect(query.parentId == "e")
        #expect(query.projectIds.isEmpty)
    }

    // MARK: Persistence

    @Test func settingsRoundTripPerScope() {
        let store = ViewSettingsStore(defaults: defaults())
        #expect(store.settings(for: .allTasks) == ViewSettings())

        var website = ViewSettings()
        website.layout = .board
        website.priorityFilter = [TicketPriority.high.rawValue]
        website.showSubtasks = false
        website.showCanceled = true
        website.collapsedStatuses = [.backlog]
        website.parentFilter = "e1"
        store.save(website, for: .project("website"))

        var all = ViewSettings()
        all.projectFilter = ["a", "b"]
        store.save(all, for: .allTasks)

        #expect(store.settings(for: .project("website")) == website)
        #expect(store.settings(for: .allTasks) == all)
        #expect(store.settings(for: .project("api")) == ViewSettings(), "other entries are unaffected")
    }

    @Test func filtersRememberedPerProjectAcrossModels() async throws {
        let store = try ArcStore(path: temporaryDatabasePath())
        let settingsStore = ViewSettingsStore(defaults: defaults())

        let website = TicketListModel(scope: .project("website"), store: store, settingsStore: settingsStore)
        website.settings.priorityFilter = [TicketPriority.high.rawValue]
        let api = TicketListModel(scope: .project("api"), store: store, settingsStore: settingsStore)
        #expect(api.settings.priorityFilter.isEmpty)

        let again = TicketListModel(scope: .project("website"), store: store, settingsStore: settingsStore)
        #expect(again.settings.priorityFilter == [TicketPriority.high.rawValue])
    }

    @Test func defaultCollapsedGroupsAreDoneAndCanceled() {
        #expect(ViewSettings().collapsedStatuses == [.done, .canceled])
    }

    @Test func undecodableStoredDataFallsBackToDefaults() {
        let suite = defaults()
        suite.set(Data("not json".utf8), forKey: "arc.viewSettings.v1")
        #expect(ViewSettingsStore(defaults: suite).settings(for: .allTasks) == ViewSettings())
    }

    // MARK: Arrangement against a real store

    private func seeded() async throws -> (TicketListModel, ArcStore, Project) {
        let store = try ArcStore(path: temporaryDatabasePath())
        let project = try await store.createProject(name: "Website")
        let model = TicketListModel(scope: .project(project.id), store: store, settingsStore: ViewSettingsStore(defaults: defaults()))
        return (model, store, project)
    }

    @Test func groupsFollowTheListOrderAndHideEmptyOnes() async throws {
        let (model, store, project) = try await seeded()
        try await store.createTicket(NewTicket(title: "todo 1", projectId: project.id))
        try await store.createTicket(NewTicket(title: "todo 2", projectId: project.id))
        try await store.createTicket(NewTicket(title: "doing", projectId: project.id, status: .inProgress))
        await model.reload()

        let groups = model.listGroups
        #expect(groups.map(\.status) == [.inProgress, .todo])
        #expect(groups.map(\.count) == [1, 2])
    }

    @Test func childrenNestUnderTheirParentOnlyInTheSameGroup() async throws {
        let (model, store, project) = try await seeded()
        let parent = try await store.createTicket(NewTicket(title: "parent", projectId: project.id))
        let sameGroup = try await store.createTicket(NewTicket(title: "child todo", parentId: parent.id))
        let otherGroup = try await store.createTicket(NewTicket(title: "child done", parentId: parent.id, status: .done))
        await model.reload()

        let todo = try #require(model.listGroups.first { $0.status == .todo })
        #expect(todo.rows.map(\.id) == [parent.id, sameGroup.id])
        #expect(todo.rows.map(\.isNested) == [false, true])
        let done = try #require(model.listGroups.first { $0.status == .done })
        #expect(done.rows.map(\.id) == [otherGroup.id])
        #expect(done.rows[0].isNested == false)
    }

    @Test func nestingFollowsGrandchildren() async throws {
        let (model, store, project) = try await seeded()
        let parent = try await store.createTicket(NewTicket(title: "parent", projectId: project.id))
        let child = try await store.createTicket(NewTicket(title: "child", parentId: parent.id))
        let grandchild = try await store.createTicket(NewTicket(title: "grandchild", parentId: child.id))
        await model.reload()
        let todo = try #require(model.listGroups.first { $0.status == .todo })
        #expect(todo.rows.map(\.id) == [parent.id, child.id, grandchild.id])
        #expect(todo.rows.map(\.depth) == [0, 1, 2])
    }

    @Test func boardHasWorkflowColumnsAndHidesCanceledByDefault() async throws {
        let (model, store, project) = try await seeded()
        try await store.createTicket(NewTicket(title: "x", projectId: project.id, status: .canceled))
        await model.reload()
        #expect(model.boardColumns.map(\.status) == [.backlog, .todo, .inProgress, .inReview, .done])
        model.settings.showCanceled = true
        #expect(model.boardColumns.map(\.status).last == .canceled)
        #expect(model.boardColumns.last?.cards.count == 1)
    }

    @Test func hidingSubTicketsKeepsParentProgressCounts() async throws {
        let (model, store, project) = try await seeded()
        let parent = try await store.createTicket(NewTicket(title: "parent", projectId: project.id))
        try await store.createTicket(NewTicket(title: "child", parentId: parent.id, status: .done))
        model.settings.showSubtasks = false
        await model.reload()

        #expect(model.tickets.count == 1)
        #expect(model.tickets[0].childCount == 1)
        #expect(model.tickets[0].childrenDone == 1)
    }

    @Test func collapsingAGroupHidesItsRowsFromKeyboardNavigation() async throws {
        let (model, store, project) = try await seeded()
        let a = try await store.createTicket(NewTicket(title: "a", projectId: project.id))
        let done = try await store.createTicket(NewTicket(title: "b", projectId: project.id, status: .done))
        await model.reload()

        #expect(model.navigationOrder == [a.id], "Done starts collapsed")
        model.toggleCollapsed(.done)
        #expect(model.navigationOrder == [a.id, done.id])
    }

    @Test func neighborWalksTheVisibleOrderAndClamps() async throws {
        let (model, store, project) = try await seeded()
        let first = try await store.createTicket(NewTicket(title: "1", projectId: project.id))
        let second = try await store.createTicket(NewTicket(title: "2", projectId: project.id))
        await model.reload()
        // newest first within a group
        #expect(model.navigationOrder == [second.id, first.id])
        #expect(model.neighbor(of: nil, offset: 1) == second.id)
        #expect(model.neighbor(of: second.id, offset: 1) == first.id)
        #expect(model.neighbor(of: first.id, offset: 1) == first.id)
        #expect(model.neighbor(of: second.id, offset: -1) == second.id)
    }

    @Test func boardNeighborJumpsColumns() async throws {
        let (model, store, project) = try await seeded()
        let todo = try await store.createTicket(NewTicket(title: "todo", projectId: project.id))
        let doing = try await store.createTicket(NewTicket(title: "doing", projectId: project.id, status: .inProgress))
        model.settings.layout = .board
        await model.reload()
        #expect(model.boardNeighbor(of: todo.id, columnOffset: 1) == doing.id)
        #expect(model.boardNeighbor(of: doing.id, columnOffset: -1) == todo.id)
        #expect(model.boardNeighbor(of: doing.id, columnOffset: 1) == doing.id, "nothing to the right: stay put")
    }

    @Test func drillDownListsTheTicketsChildren() async throws {
        let (_, store, project) = try await seeded()
        let epic = try await store.createTicket(NewTicket(title: "Epic", projectId: project.id))
        try await store.createTicket(NewTicket(title: "in epic", projectId: project.id, parentId: epic.id))
        try await store.createTicket(NewTicket(title: "outside", projectId: project.id))
        let model = TicketListModel(scope: .children(epic.id), store: store, settingsStore: ViewSettingsStore(defaults: defaults()))
        await model.reload()
        #expect(model.tickets.map(\.ticket.title) == ["in epic"])
    }

    @Test func parentWithTwoDoneOneTodoOneCanceledShowsTwoOfThree() async throws {
        let (_, store, project) = try await seeded()
        let epic = try await store.createTicket(NewTicket(title: "Epic", projectId: project.id))
        for status in [TicketStatus.done, .done, .todo, .canceled] {
            try await store.createTicket(NewTicket(title: "t", projectId: project.id, parentId: epic.id, status: status))
        }
        let progress = try await store.parentsWithProgress()
        #expect(progress.first.map { "\($0.done)/\($0.total)" } == "2/3")
    }
}
