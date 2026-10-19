import ArcCore
import SwiftUI

struct CreateTicketSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: CreationRequest

    @State private var title = ""
    @State private var details = ""
    @State private var kind: TicketKind
    @State private var projectID: String?
    @State private var epicID: String?
    @State private var parentID: String?
    @State private var status: TicketStatus = .todo
    @State private var priority: TicketPriority = .none
    @State private var tasksInProject: [Ticket] = []
    @FocusState private var titleFocused: Bool

    init(request: CreationRequest) {
        self.request = request
        _kind = State(initialValue: request.parentID == nil ? request.kind : .subtask)
        _projectID = State(initialValue: request.projectID)
        _epicID = State(initialValue: request.epicID)
        _parentID = State(initialValue: request.parentID)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (kind == .subtask ? parentID != nil : projectID != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New \(kind.displayName)").font(.system(size: 15, weight: .semibold))

            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .focused($titleFocused)
            TextEditor(text: $details)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90, maxHeight: 160)
                .padding(6)
                .background(Theme.bgContent, in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("Add a description… (Markdown)")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.leading, 11)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Kind").foregroundStyle(Theme.textSecondary)
                    Picker("Kind", selection: $kind) {
                        ForEach(TicketKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if kind != .subtask {
                    GridRow {
                        Text("Project").foregroundStyle(Theme.textSecondary)
                        Picker("Project", selection: $projectID) {
                            Text("Choose…").tag(String?.none)
                            ForEach(app.projects) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if kind == .task {
                    GridRow {
                        Text("Epic").foregroundStyle(Theme.textSecondary)
                        Picker("Epic", selection: $epicID) {
                            Text("None").tag(String?.none)
                            ForEach(app.epicsByProject[projectID ?? ""] ?? []) {
                                Text("\($0.identifier) \($0.title)").tag(Optional($0.id))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if kind == .subtask {
                    GridRow {
                        Text("Parent").foregroundStyle(Theme.textSecondary)
                        Picker("Parent", selection: $parentID) {
                            Text("Choose…").tag(String?.none)
                            ForEach(tasksInProject) { Text("\($0.identifier) \($0.title)").tag(Optional($0.id)) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                GridRow {
                    Text("Status").foregroundStyle(Theme.textSecondary)
                    Picker("Status", selection: $status) {
                        ForEach(TicketStatus.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text("Priority").foregroundStyle(Theme.textSecondary)
                    Picker("Priority", selection: $priority) {
                        ForEach(TicketPriority.menuOrder, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .font(Theme.rowFont)

            HStack {
                Text("⌘↩ to create").font(Theme.metaFont).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SubtleButtonStyle())
                Button("Create \(kind.displayName)") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Theme.bgElevated)
        .onAppear {
            titleFocused = true
            if projectID == nil { projectID = app.projects.first?.id }
        }
        .task(id: projectID) { await loadTasks() }
        .onChange(of: projectID) {
            if let epicID, !(app.epicsByProject[projectID ?? ""] ?? []).contains(where: { $0.id == epicID }) {
                self.epicID = nil
            }
        }
        .onChange(of: kind) {
            if kind != .task { epicID = nil }
        }
    }

    private func loadTasks() async {
        var query = TicketQuery(kinds: [.task], includeClosed: true, includeArchivedProjects: true)
        if let projectID { query.projectIds = [projectID] }
        let found = (try? await app.store.tickets(matching: query).map(\.ticket)) ?? []
        tasksInProject = found
        if let parentID, request.parentID != nil, projectID == request.projectID || projectID == nil,
           let parent = try? await app.store.ticket(id: parentID) {
            if projectID == nil { projectID = parent.projectId }
        }
        if let parentID, !found.contains(where: { $0.id == parentID }) { self.parentID = nil }
    }

    private func save() {
        guard canSave else { return }
        let new = NewTicket(
            title: title,
            description: details,
            kind: kind,
            projectId: kind == .subtask ? nil : projectID,
            epicId: kind == .task ? epicID : nil,
            parentId: kind == .subtask ? parentID : nil,
            status: status,
            priority: priority
        )
        Task {
            if let ticket = await app.perform({ try await app.store.createTicket(new) }) {
                app.selectedTicketID = ticket.id
                dismiss()
            }
        }
    }
}
