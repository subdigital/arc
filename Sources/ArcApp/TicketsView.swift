import ArcCore
import SwiftUI

/// Everything shown for one scope: filter bar, then the list or the board.
struct TicketsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: TicketListModel
    @State private var epicTitle: String?

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
        case .epic: epicTitle ?? "Epic"
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
                    app.creation = CreationRequest(projectID: defaultProjectID, epicID: epicID)
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .help("New task (C)")
            }
        }
        .task(id: reloadKey) {
            await model.reload()
            app.checkedTicketIDs.formIntersection(model.tickets.map(\.id))
            await loadEpicTitle()
        }
        .onChange(of: app.layoutToggleRequests) {
            model.settings.layout = model.settings.layout.toggled
        }
    }

    private var defaultProjectID: String? {
        switch model.scope {
        case .project(let id): id
        case .allTasks: model.settings.projectFilter.count == 1 ? model.settings.projectFilter.first : nil
        case .epic: model.tickets.first?.ticket.projectId
        }
    }

    private var epicID: String? {
        if case .epic(let id) = model.scope { id } else { nil }
    }

    private func loadEpicTitle() async {
        guard case .epic(let id) = model.scope else { return }
        if let epic = try? await app.store.ticket(id: id) { epicTitle = "\(epic.identifier) \(epic.title)" }
    }

    @ViewBuilder
    private var content: some View {
        if model.hasLoaded && model.tickets.isEmpty && !model.settings.hasActiveFilters {
            EmptyStateView(
                title: "No tickets here yet",
                message: "Create a task, or let an agent add one.",
                buttonTitle: "New Task"
            ) {
                app.creation = CreationRequest(projectID: defaultProjectID, epicID: epicID)
            }
        } else if model.hasLoaded && model.tickets.isEmpty {
            EmptyStateView(
                title: "No matching tickets",
                message: "Nothing matches the current filters.",
                buttonTitle: "Clear Filters"
            ) {
                model.settings.projectFilter = []
                model.settings.epicFilter = nil
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
            if case .epic = model.scope {} else {
                epicMenu
            }
            priorityMenu
            Toggle(isOn: $model.settings.showSubtasks) {
                Text("Show subtasks").font(Theme.metaFont)
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
                    model.settings.epicFilter = nil
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

    private var epicMenu: some View {
        Menu {
            Button("Any epic") { model.settings.epicFilter = nil }
            Divider()
            ForEach(model.availableEpics) { epic in
                Button {
                    model.settings.epicFilter = epic.id
                } label: {
                    Label("\(epic.identifier) \(epic.title)", systemImage: model.settings.epicFilter == epic.id ? "checkmark" : "")
                }
            }
        } label: {
            FlatChip(
                title: epicFilterTitle,
                systemImage: "square.stack.3d.up",
                isActive: model.settings.epicFilter != nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var epicFilterTitle: String {
        guard let id = model.settings.epicFilter else { return "Epic" }
        return model.availableEpics.first { $0.id == id }.map { "Epic · \($0.identifier)" } ?? "Epic"
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

    /// Epics can only be assigned when every selected ticket is a task in one project.
    private var epicChoices: [Ticket]? {
        let projects = Set(selected.map(\.ticket.projectId))
        guard projects.count == 1, selected.allSatisfy({ $0.ticket.kind == .task }), let project = projects.first else { return nil }
        return app.epicsByProject[project] ?? []
    }

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
            Menu("Epic") {
                Button("No epic") {
                    Task { await app.bulkUpdate(ids, TicketPatch(epicId: .set(nil)), done: "Updated") }
                }
                ForEach(epicChoices ?? []) { epic in
                    Button("\(epic.identifier) \(epic.title)") {
                        Task { await app.bulkUpdate(ids, TicketPatch(epicId: .set(epic.id)), done: "Updated") }
                    }
                }
            }
            .disabled(epicChoices == nil)
            .help(epicChoices == nil ? "Select tasks from a single project to assign an epic" : "Assign an epic")

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
