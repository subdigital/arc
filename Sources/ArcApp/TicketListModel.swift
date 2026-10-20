import ArcCore
import Foundation
import Observation

struct TicketRowItem: Identifiable, Equatable {
    var summary: TicketSummary
    /// How many ancestors are shown above this row (0 = top level).
    var depth: Int

    var isNested: Bool { depth > 0 }

    var id: String { summary.id }
}

struct StatusGroup: Identifiable, Equatable {
    var status: TicketStatus
    var rows: [TicketRowItem]

    var id: TicketStatus { status }
    var count: Int { rows.count }
}

struct BoardColumn: Identifiable, Equatable {
    var status: TicketStatus
    var cards: [TicketSummary]

    var id: TicketStatus { status }
}

/// Fetches and arranges the tickets for one scope (All Tasks, a project, or the children of a ticket).
@MainActor
@Observable
final class TicketListModel {
    let scope: Scope
    private let store: ArcStore
    private let settingsStore: ViewSettingsStore

    var settings: ViewSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.save(settings, for: scope)
        }
    }

    private(set) var tickets: [TicketSummary] = []
    /// Tickets with children that a user can filter by within this scope.
    private(set) var availableParents: [Ticket] = []
    private(set) var availableLabels: [TicketLabel] = []
    /// Milestones of the project being viewed (project scope only).
    private(set) var availableMilestones: [Milestone] = []
    private(set) var hasLoaded = false

    init(scope: Scope, store: ArcStore, settingsStore: ViewSettingsStore) {
        self.scope = scope
        self.store = store
        self.settingsStore = settingsStore
        self.settings = settingsStore.settings(for: scope)
    }

    // MARK: Query

    /// The store query for a scope plus its filters. Pure, so it can be tested directly.
    nonisolated static func query(for scope: Scope, settings: ViewSettings) -> TicketQuery {
        var query = TicketQuery(includeClosed: true)
        switch scope {
        case .allTasks:
            query.projectIds = settings.projectFilter
        case .project(let id):
            query.projectIds = [id]
        case .children(let id):
            query.parentId = id
        }
        if !settings.showSubtasks {
            if case .children = scope {} else { query.topLevelOnly = true }
        }
        if case .children = scope {} else {
            query.parentId = settings.parentFilter
        }
        query.priorities = Set(settings.priorityFilter.compactMap(TicketPriority.init(rawValue:)))
        query.labelIds = settings.labelFilter
        if case .project = scope { query.milestoneId = settings.milestoneFilter }
        return query
    }

    func reload() async {
        do {
            let query = Self.query(for: scope, settings: settings)
            tickets = try await store.tickets(matching: query)

            var parentQuery = TicketQuery(includeClosed: true)
            switch scope {
            case .allTasks: parentQuery.projectIds = settings.projectFilter
            case .project(let id): parentQuery.projectIds = [id]
            case .children: break
            }
            availableParents = try await store.tickets(matching: parentQuery).filter { $0.childCount > 0 }.map(\.ticket)
            availableLabels = try await store.labels()
            if case .project(let id) = scope { availableMilestones = try await store.milestones(projectId: id) }
            hasLoaded = true
        } catch {
            // Keep showing the last good data; the next change tick retries.
        }
    }

    // MARK: Arrangement

    /// Status groups for the list view: workflow-active first, empty groups hidden.
    var listGroups: [StatusGroup] {
        let byStatus = Dictionary(grouping: tickets, by: { $0.ticket.status })
        return TicketStatus.listOrder.compactMap { status in
            guard let members = byStatus[status], !members.isEmpty else { return nil }
            return StatusGroup(status: status, rows: Self.nest(members))
        }
    }

    /// Children directly follow their parent when the parent is in the same group, at any depth.
    nonisolated static func nest(_ members: [TicketSummary]) -> [TicketRowItem] {
        let ids = Set(members.map(\.ticket.id))
        var childrenByParent: [String: [TicketSummary]] = [:]
        for member in members {
            if let parent = member.ticket.parentId, ids.contains(parent) {
                childrenByParent[parent, default: []].append(member)
            }
        }
        var rows: [TicketRowItem] = []
        func append(_ member: TicketSummary, depth: Int) {
            rows.append(TicketRowItem(summary: member, depth: depth))
            for child in childrenByParent[member.ticket.id] ?? [] { append(child, depth: depth + 1) }
        }
        for member in members {
            if let parent = member.ticket.parentId, ids.contains(parent) { continue }
            append(member, depth: 0)
        }
        return rows
    }

    var boardColumns: [BoardColumn] {
        let byStatus = Dictionary(grouping: tickets, by: { $0.ticket.status })
        return TicketStatus.boardOrder
            .filter { $0 != .canceled || settings.showCanceled }
            .map { BoardColumn(status: $0, cards: byStatus[$0] ?? []) }
    }

    func isCollapsed(_ status: TicketStatus) -> Bool { settings.collapsedStatuses.contains(status) }

    func toggleCollapsed(_ status: TicketStatus) {
        if settings.collapsedStatuses.contains(status) {
            settings.collapsedStatuses.remove(status)
        } else {
            settings.collapsedStatuses.insert(status)
        }
    }

    // MARK: Keyboard navigation

    /// Ticket ids in the order arrow keys / J / K walk them.
    var navigationOrder: [String] {
        switch settings.layout {
        case .list:
            listGroups.filter { !isCollapsed($0.status) }.flatMap { $0.rows.map(\.id) }
        case .board:
            boardColumns.flatMap { $0.cards.map(\.id) }
        }
    }

    func neighbor(of id: String?, offset: Int) -> String? {
        let order = navigationOrder
        guard !order.isEmpty else { return nil }
        guard let id, let index = order.firstIndex(of: id) else { return offset >= 0 ? order.first : order.last }
        return order[min(max(index + offset, 0), order.count - 1)]
    }

    /// Board: the card in the adjacent column at the same height (clamped).
    func boardNeighbor(of id: String?, columnOffset: Int) -> String? {
        let columns = boardColumns
        guard let id,
              let columnIndex = columns.firstIndex(where: { $0.cards.contains { $0.id == id } }),
              let row = columns[columnIndex].cards.firstIndex(where: { $0.id == id })
        else { return neighbor(of: id, offset: 1) }
        var target = columnIndex + columnOffset
        while columns.indices.contains(target) {
            let cards = columns[target].cards
            if !cards.isEmpty { return cards[min(row, cards.count - 1)].id }
            target += columnOffset
        }
        return id
    }

    func summary(id: String) -> TicketSummary? { tickets.first { $0.id == id } }
}
