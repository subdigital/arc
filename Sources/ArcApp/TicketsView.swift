import ArcCore
import SwiftUI

/// Everything shown for one scope: filter bar, then the list or the board.
struct TicketsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: TicketListModel
    @State private var parentTitle: String?

    init(scope: Scope, app: AppModel) {
        _model = State(initialValue: TicketListModel(scope: scope, store: app.store, settingsStore: app.settingsStore))
    }

    private struct ReloadKey: Equatable {
        var generation: Int
        var query: TicketQuery
    }

    private var reloadKey: ReloadKey {
        ReloadKey(generation: app.feed.generation, query: TicketListModel.query(for: model.scope, settings: model.settings))
    }

    private var title: String {
        switch model.scope {
        case .allTasks: "All Tasks"
        case .project(let id): app.project(id: id)?.name ?? "Project"
        case .children: parentTitle ?? "Sub-tickets"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(model: model)
            Rectangle().fill(Theme.border).frame(height: 1)
            content
        }
        .background(Theme.bgContent)
        .overlay(alignment: .bottom) {
            if !app.checkedTicketIDs.isEmpty {
                BulkActionBar(model: model)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: app.checkedTicketIDs.isEmpty)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Layout", selection: $model.settings.layout) {
                    Image(systemName: "list.bullet").tag(TicketLayout.list).help("List")
                    Image(systemName: "rectangle.split.3x1").tag(TicketLayout.board).help("Board")
                }
                .pickerStyle(.segmented)
                .help("Switch layout (⌘B)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.creation = CreationRequest(projectID: defaultProjectID, parentID: parentID)
                } label: {
                    Label("New Ticket", systemImage: "plus")
                }
                .help("New ticket (C)")
            }
        }
        .task(id: reloadKey) {
            await model.reload()
            app.checkedTicketIDs.formIntersection(model.tickets.map(\.id))
            await loadParentTitle()
        }
        .onChange(of: app.layoutToggleRequests) {
            model.settings.layout = model.settings.layout.toggled
        }
    }

    private var defaultProjectID: String? {
        switch model.scope {
        case .project(let id): id
        case .allTasks: model.settings.projectFilter.count == 1 ? model.settings.projectFilter.first : nil
        case .children: nil
        }
    }

    private var parentID: String? {
        if case .children(let id) = model.scope { id } else { nil }
    }

    private func loadParentTitle() async {
        guard case .children(let id) = model.scope else { return }
        if let parent = try? await app.store.ticket(id: id) { parentTitle = "\(parent.identifier) \(parent.title)" }
    }

    @ViewBuilder
    private var content: some View {
        if model.hasLoaded && model.tickets.isEmpty && !model.settings.hasActiveFilters {
            EmptyStateView(
                title: "No tickets here yet",
                message: "Create a ticket, or let an agent add one.",
                buttonTitle: "New Ticket"
            ) {
                app.creation = CreationRequest(projectID: defaultProjectID, parentID: parentID)
            }
        } else if model.hasLoaded && model.tickets.isEmpty {
            EmptyStateView(
                title: "No matching tickets",
                message: "Nothing matches the current filters.",
                buttonTitle: "Clear Filters"
            ) {
                model.settings.projectFilter = []
                model.settings.parentFilter = nil
                model.settings.labelFilter = []
                model.settings.milestoneFilter = nil
                model.settings.priorityFilter = []
                model.settings.showSubtasks = true
            }
        } else {
            switch model.settings.layout {
            case .list: TicketListView(model: model)
            case .board: BoardView(model: model)
            }
        }
    }
}

// MARK: - Filter bar

struct FilterBar: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: TicketListModel

    var body: some View {
        HStack(spacing: 8) {
            if case .allTasks = model.scope {
                projectMenu
            }
            if case .children = model.scope {} else {
                parentMenu
            }
            if !model.availableLabels.isEmpty { labelMenu }
            if !model.availableMilestones.isEmpty { milestoneMenu }
            priorityMenu
            Toggle(isOn: $model.settings.showSubtasks) {
                Text("Show sub-tickets").font(Theme.metaFont)
            }
            .toggleStyle(.checkbox)
            .foregroundStyle(Theme.textSecondary)
            if model.settings.layout == .board {
                Toggle(isOn: $model.settings.showCanceled) {
                    Text("Show canceled").font(Theme.metaFont)
                }
                .toggleStyle(.checkbox)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if model.settings.hasActiveFilters {
                Button("Clear filters") {
                    model.settings.projectFilter = []
                    model.settings.parentFilter = nil
                    model.settings.labelFilter = []
                    model.settings.milestoneFilter = nil
                    model.settings.priorityFilter = []
                    model.settings.showSubtasks = true
                }
                .buttonStyle(.plain)
                .font(Theme.metaFont)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Theme.bgContent)
    }

    private var projectMenu: some View {
        Menu {
            ForEach(app.projects) { project in
                Toggle(project.name, isOn: Binding(
                    get: { model.settings.projectFilter.contains(project.id) },
                    set: { isOn in
                        if isOn { model.settings.projectFilter.insert(project.id) } else { model.settings.projectFilter.remove(project.id) }
                    }
                ))
            }
        } label: {
            FlatChip(
                title: model.settings.projectFilter.isEmpty ? "Project" : "Project · \(model.settings.projectFilter.count)",
                systemImage: "folder",
                isActive: !model.settings.projectFilter.isEmpty
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var parentMenu: some View {
        Menu {
            Button("Any parent") { model.settings.parentFilter = nil }
            Divider()
            ForEach(model.availableParents) { parent in
                Button {
                    model.settings.parentFilter = parent.id
                } label: {
                    Label("\(parent.identifier) \(parent.title)", systemImage: model.settings.parentFilter == parent.id ? "checkmark" : "")
                }
            }
        } label: {
            FlatChip(
                title: parentFilterTitle,
                systemImage: "square.stack.3d.up",
                isActive: model.settings.parentFilter != nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var parentFilterTitle: String {
        guard let id = model.settings.parentFilter else { return "Parent" }
        return model.availableParents.first { $0.id == id }.map { "Parent · \($0.identifier)" } ?? "Parent"
    }

    private var labelMenu: some View {
        Menu {
            ForEach(model.availableLabels) { label in
                Toggle(label.name, isOn: Binding(
                    get: { model.settings.labelFilter.contains(label.id) },
                    set: { isOn in
                        if isOn { model.settings.labelFilter.insert(label.id) } else { model.settings.labelFilter.remove(label.id) }
                    }
                ))
            }
        } label: {
            FlatChip(
                title: model.settings.labelFilter.isEmpty ? "Label" : "Label · \(model.settings.labelFilter.count)",
                systemImage: "tag",
                isActive: !model.settings.labelFilter.isEmpty
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var milestoneMenu: some View {
        Menu {
            Button("Any milestone") { model.settings.milestoneFilter = nil }
            Divider()
            ForEach(model.availableMilestones) { milestone in
                Button {
                    model.settings.milestoneFilter = milestone.id
                } label: {
                    Label(milestone.name, systemImage: model.settings.milestoneFilter == milestone.id ? "checkmark" : "")
                }
            }
        } label: {
            FlatChip(
                title: model.availableMilestones.first { $0.id == model.settings.milestoneFilter }.map { "Milestone · \($0.name)" } ?? "Milestone",
                systemImage: "flag",
                isActive: model.settings.milestoneFilter != nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(TicketPriority.menuOrder, id: \.self) { priority in
                Toggle(priority.displayName, isOn: Binding(
                    get: { model.settings.priorityFilter.contains(priority.rawValue) },
                    set: { isOn in
                        if isOn { model.settings.priorityFilter.insert(priority.rawValue) } else { model.settings.priorityFilter.remove(priority.rawValue) }
                    }
                ))
            }
        } label: {
            FlatChip(
                title: model.settings.priorityFilter.isEmpty ? "Priority" : "Priority · \(model.settings.priorityFilter.count)",
                systemImage: "chart.bar",
                isActive: !model.settings.priorityFilter.isEmpty
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Bulk actions

/// Floating bar shown while rows are ticked.
struct BulkActionBar: View {
    @Environment(AppModel.self) private var app
    let model: TicketListModel

    private var ids: [String] { Array(app.checkedTicketIDs) }
    private var selected: [TicketSummary] { model.tickets.filter { app.checkedTicketIDs.contains($0.id) } }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(ids.count) selected").font(Theme.rowFont).foregroundStyle(Theme.textPrimary)
            Rectangle().fill(Theme.border).frame(width: 1, height: 18)

            Menu("Status") {
                StatusMenuItems(current: nil) { status in
                    Task { await app.bulkUpdate(ids, TicketPatch(status: status), done: "Updated") }
                }
            }
            Menu("Priority") {
                PriorityMenuItems(current: nil) { priority in
                    Task { await app.bulkUpdate(ids, TicketPatch(priority: priority), done: "Updated") }
                }
            }
            Menu("Project") {
                ForEach(app.projects) { project in
                    Button(project.name) {
                        Task { await app.bulkUpdate(ids, TicketPatch(projectId: project.id), done: "Moved") }
                    }
                }
            }
            Button("Parent") { app.parentPicking = ids }
                .help("Set or clear the parent of the selected tickets")

            Button("Delete", role: .destructive) { app.pendingDeletionIDs = ids }
            Rectangle().fill(Theme.border).frame(width: 1, height: 18)
            Button {
                app.checkedTicketIDs = []
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
            }
            .help("Clear selection (Esc)")
            .accessibilityLabel("Clear selection")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .font(Theme.rowFont)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Theme.bgElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
    }
}
