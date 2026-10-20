import ArcCore
import SwiftUI

struct CreateTicketSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: CreationRequest

    @State private var title = ""
    @State private var details = ""
    @State private var projectID: String?
    @State private var parentID: String?
    @State private var status: TicketStatus
    @State private var priority: TicketPriority
    @State private var createMore: Bool
    @State private var parent: Ticket?
    @State private var showingParentPicker = false
    @FocusState private var titleFocused: Bool

    init(request: CreationRequest) {
        self.request = request
        _projectID = State(initialValue: request.projectID)
        _parentID = State(initialValue: request.parentID)
        _status = State(initialValue: request.status)
        _priority = State(initialValue: request.priority)
        _createMore = State(initialValue: request.createMore)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && projectID != nil
    }

    private var projectName: String {
        app.projects.first { $0.id == projectID }?.name ?? "Project"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TextField("Ticket title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .focused($titleFocused)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // A vertical TextField draws its own placeholder, so caret and placeholder always line up.
            TextField("Add description… (Markdown)", text: $details, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(5...12)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)

            pills
                .padding(.horizontal, 16)
                .padding(.top, 6)

            Rectangle().fill(Theme.border).frame(height: 1).padding(.top, 14)
            HStack(spacing: 10) {
                Text("⌘↩ to create").font(Theme.metaFont).foregroundStyle(Theme.textTertiary)
                Spacer()
                Toggle("Create more", isOn: $createMore)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(Theme.metaFont)
                    .foregroundStyle(Theme.textSecondary)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SubtleButtonStyle())
                Button("Create Ticket") { save() }
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
        .task(id: parentID) {
            guard let parentID else { parent = nil; return }
            parent = try? await app.store.ticket(id: parentID)
            // A child defaults to its parent's project until another one is chosen.
            if request.projectID == nil, let parent { projectID = parent.projectId }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
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
            Text("New Ticket").font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
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

            Button {
                showingParentPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 11))
                    Text(parent.map { "\($0.identifier) \($0.title)" } ?? "Parent").lineLimit(1)
                }
                .modifier(Pill(isSet: parentID != nil))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingParentPicker, arrowEdge: .bottom) {
                TicketSearchList { picked in
                    parentID = picked
                    showingParentPicker = false
                }
                .environment(app)
            }
            Spacer(minLength: 0)
        }
    }

    private func save() {
        guard canSave else { return }
        let new = NewTicket(
            title: title,
            description: details,
            projectId: projectID,
            parentId: parentID,
            status: status,
            priority: priority
        )
        Task {
            guard let ticket = await app.perform({ try await app.store.createTicket(new) }) else { return }
            app.selectedTicketID = ticket.id
            app.showToast("Created \(ticket.identifier)")
            dismiss()
            guard createMore else { return }
            // Present the form again, carrying the properties over, so it is clear something happened.
            let next = CreationRequest(
                projectID: ticket.projectId,
                parentID: parentID,
                status: status,
                priority: priority,
                createMore: true
            )
            try? await Task.sleep(for: .milliseconds(350))
            app.creation = next
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
