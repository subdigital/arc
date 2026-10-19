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

    private var projectName: String {
        app.projects.first { $0.id == projectID }?.name ?? "Project"
    }

    private var epics: [Ticket] { app.epicsByProject[projectID ?? ""] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TextField("\(kind.displayName) title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .focused($titleFocused)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            TextEditor(text: $details)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110, maxHeight: 220)
                .padding(.horizontal, 15)
                .padding(.top, 8)
                .overlay(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("Add description… (Markdown)")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.leading, 20)
                            .padding(.top, 16)
                            .allowsHitTesting(false)
                    }
                }

            pills
                .padding(.horizontal, 16)
                .padding(.top, 6)

            Rectangle().fill(Theme.border).frame(height: 1).padding(.top, 14)
            HStack(spacing: 10) {
                Text("⌘↩ to create").font(Theme.metaFont).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SubtleButtonStyle())
                Button("Create \(kind.displayName)") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 640)
        .background(Theme.bgElevated)
        .onAppear {
            titleFocused = true
            if projectID == nil { projectID = app.projects.first?.id }
        }
        .task(id: projectID) { await loadTasks() }
        .onChange(of: projectID) {
            if let epicID, !epics.contains(where: { $0.id == epicID }) { self.epicID = nil }
        }
        .onChange(of: kind) {
            if kind != .task { epicID = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if kind != .subtask {
                Menu {
                    ForEach(app.projects) { project in
                        Button(project.name) { projectID = project.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hexString: app.projects.first { $0.id == projectID }?.color ?? "#5E6AD2")).frame(width: 8, height: 8)
                        Text(projectName)
                    }
                    .modifier(Pill(isSet: true))
                }
                .pillMenu()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
            Text("New \(kind.displayName)").font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var pills: some View {
        HStack(spacing: 8) {
            Menu {
                StatusMenuItems(current: status) { status = $0 }
            } label: {
                HStack(spacing: 6) { StatusGlyph(status: status, size: 13); Text(status.displayName) }
                    .modifier(Pill(isSet: true))
            }
            .pillMenu()

            Menu {
                PriorityMenuItems(current: priority) { priority = $0 }
            } label: {
                HStack(spacing: 6) {
                    PriorityGlyph(priority: priority, size: 13)
                    Text(priority == .none ? "Priority" : priority.displayName)
                }
                .modifier(Pill(isSet: priority != .none))
            }
            .pillMenu()

            Menu {
                ForEach(TicketKind.allCases, id: \.self) { option in
                    Button { kind = option } label: {
                        Label(option.displayName, systemImage: kind == option ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 6) { Image(systemName: "square.stack.3d.up").font(.system(size: 11)); Text(kind.displayName) }
                    .modifier(Pill(isSet: true))
            }
            .pillMenu()

            if kind == .task {
                Menu {
                    Button("No epic") { epicID = nil }
                    ForEach(epics) { epic in
                        Button("\(epic.identifier) \(epic.title)") { epicID = epic.id }
                    }
                } label: {
                    Text(epics.first { $0.id == epicID }?.title ?? "Epic")
                        .lineLimit(1)
                        .modifier(Pill(isSet: epicID != nil))
                }
                .pillMenu()
            }
            if kind == .subtask {
                Menu {
                    ForEach(tasksInProject) { task in
                        Button("\(task.identifier) \(task.title)") { parentID = task.id }
                    }
                } label: {
                    Text(tasksInProject.first { $0.id == parentID }.map { "\($0.identifier) \($0.title)" } ?? "Parent task")
                        .lineLimit(1)
                        .modifier(Pill(isSet: parentID != nil))
                }
                .pillMenu()
            }
            Spacer(minLength: 0)
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

/// Capsule used for the property chips in the creation sheet.
struct Pill: ViewModifier {
    var isSet: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13))
            .foregroundStyle(isSet ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Theme.bgSelected.opacity(0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Capsule())
    }
}

extension View {
    func pillMenu() -> some View {
        menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}
