import Foundation
import Testing
@testable import ArcCore

@Suite struct QueryTests {
    struct Fixture {
        let store: ArcStore
        let website: Project
        let api: Project
        let epic: Ticket      // ARC-1 (website), parent of ARC-2
        let linked: Ticket    // ARC-2 website, child of ARC-1, in progress, high
        let plain: Ticket     // ARC-3 website, todo
        let done: Ticket      // ARC-4 website, done
        let sub: Ticket       // ARC-5 child of ARC-2
        let apiTask: Ticket   // ARC-6 api, todo, urgent
    }

    private func fixture() async throws -> Fixture {
        let store = try makeStore()
        let website = try await store.createProject(name: "Website")
        let api = try await store.createProject(name: "API")
        let epic = try await store.task("Launch", in: website)
        let linked = try await store.createTicket(NewTicket(
            title: "Build footer", description: "uses OAuth", projectId: website.id, parentId: epic.id,
            status: .inProgress, priority: .high))
        let plain = try await store.task("Write copy", in: website)
        let done = try await store.task("Old thing", in: website, status: .done)
        let sub = try await store.child("Footer links", of: linked)
        let apiTask = try await store.createTicket(NewTicket(title: "Add OAuth", projectId: api.id, priority: .urgent))
        return Fixture(store: store, website: website, api: api, epic: epic, linked: linked, plain: plain, done: done, sub: sub, apiTask: apiTask)
    }

    private func numbers(_ f: Fixture, _ query: TicketQuery) async throws -> [Int] {
        try await f.store.tickets(matching: query).map(\.ticket.number)
    }

    @Test func defaultExcludesClosedAndOrdersByStatusThenManualOrder() async throws {
        let f = try await fixture()
        // Workflow order: Todo (newest on top) 6, 5, 3, 1, then In Progress 2.
        #expect(try await numbers(f, TicketQuery()) == [6, 5, 3, 1, 2])
    }

    @Test func includeClosedAddsDoneAndCanceled() async throws {
        let f = try await fixture()
        #expect(try await numbers(f, TicketQuery(includeClosed: true)) == [6, 5, 3, 1, 2, 4])
    }

    @Test func filterByProjectAndStatuses() async throws {
        let f = try await fixture()
        let query = TicketQuery(projectIds: [f.website.id], statuses: [.todo, .inProgress])
        #expect(try await numbers(f, query) == [5, 3, 1, 2])
        // Explicit statuses win over includeClosed = false.
        #expect(try await numbers(f, TicketQuery(statuses: [.done])) == [4])
    }

    @Test func filterByPriorityAndParent() async throws {
        let f = try await fixture()
        #expect(try await numbers(f, TicketQuery(priorities: [.urgent, .high])) == [6, 2])
        // The parent filter returns direct children only.
        #expect(try await numbers(f, TicketQuery(parentId: f.epic.id)) == [2])
        #expect(try await numbers(f, TicketQuery(parentId: f.linked.id)) == [5])
        #expect(try await numbers(f, TicketQuery(topLevelOnly: true)) == [6, 3, 1])
    }

    @Test func textQueryMatchesTitleDescriptionAndIdentifier() async throws {
        let f = try await fixture()
        #expect(try await numbers(f, TicketQuery(text: "oauth")) == [6, 2])
        #expect(try await numbers(f, TicketQuery(text: "arc-3")) == [3])
        #expect(try await numbers(f, TicketQuery(text: "ARC-6")) == [6])
        #expect(try await numbers(f, TicketQuery(text: "50%")).isEmpty)
        #expect(try await numbers(f, TicketQuery(text: "  ")) == [6, 5, 3, 1, 2])
    }

    @Test func limit() async throws {
        let f = try await fixture()
        #expect(try await numbers(f, TicketQuery(limit: 2)) == [6, 5])
    }

    @Test func summaryCarriesJoinedData() async throws {
        let f = try await fixture()
        let rows = try await f.store.tickets(matching: TicketQuery(includeClosed: true))
        let linked = try #require(rows.first { $0.ticket.number == 2 })
        #expect(linked.projectName == "Website")
        #expect(linked.parent?.identifier == "ARC-1")
        #expect(linked.childCount == 1 && linked.childrenDone == 0)
        let sub = try #require(rows.first { $0.ticket.number == 5 })
        #expect(sub.parent?.identifier == "ARC-2")
    }

    @Test func childProgressCountsDone() async throws {
        let f = try await fixture()
        try await f.store.updateTicket(id: f.sub.id, TicketPatch(status: .done))
        let row = try await f.store.ticketSummary(id: f.linked.id)
        #expect(row.childCount == 1 && row.childrenDone == 1)
    }

    @Test func parentProgressExcludesCanceled() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let epic = try await store.task("Epic", in: project)
        try await store.task("d1", in: project, status: .done, parent: epic)
        try await store.task("d2", in: project, status: .done, parent: epic)
        try await store.task("t", in: project, status: .todo, parent: epic)
        try await store.task("c", in: project, status: .canceled, parent: epic)
        let progress = try await store.parentsWithProgress()
        #expect(progress.count == 1)
        #expect(progress[0].done == 2)
        #expect(progress[0].total == 3)
        #expect(progress[0].projectName == "A")
        let dto = ParentProgressDTO(progress[0])
        #expect(dto.done == 2 && dto.total == 3)
    }

    @Test func detailIncludesParentAndChildren() async throws {
        let f = try await fixture()
        let detail = try await f.store.ticketDetail(reference: "arc-2")
        #expect(detail.parent?.number == 1)
        #expect(detail.children.map(\.number) == [5])
        #expect(detail.project.name == "Website")
        let dto = TicketDTO(detail)
        #expect(dto.parent?.identifier == "ARC-1")
        #expect(dto.children?.map(\.identifier) == ["ARC-5"])
    }

    @Test func prioritySortRankOrder() {
        let sorted = [TicketPriority.low, .none, .urgent].sorted { $0.sortRank < $1.sortRank }
        #expect(sorted == [.urgent, .low, .none])
    }
}
