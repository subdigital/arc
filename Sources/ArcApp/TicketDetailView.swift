import ArcCore
import ArcMarkdown
import SwiftUI

struct TicketDetailView: View {
    @Environment(AppModel.self) private var app
    let ticketID: String

    @State private var detail: TicketDetail?
    @State private var titleDraft = ""
    @State private var descriptionDraft = ""
    @State private var isEditingDescription = false
    @State private var descriptionSaveTask: Task<Void, Never>?
    @State private var newSubtask = ""
    @State private var commentDraft = ""
    @FocusState private var titleFocused: Bool
    @FocusState private var descriptionFocused: Bool
    @FocusState private var commentFocused: Bool

    var body: some View {
        Group {
            if let detail {
                HStack(spacing: 0) {
                    main(detail)
                    Rectangle().fill(Theme.border).frame(width: 1)
                    PropertiesPanel(detail: detail)
                        .frame(width: 260)
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bgContent)
        .navigationTitle(detail.map { "\($0.ticket.identifier) \($0.ticket.title)" } ?? "Ticket")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.pendingDeletion = ticketID
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete ticket (⌘⌫)")
            }
        }
        .task(id: app.feed.generation) { await load() }
        .onKeyPress(phases: .down) { press in
            if press.key == .escape {
                if isEditingDescription { finishEditingDescription() } else { app.goBack() }
                return .handled
            }
            if press.key == .delete, press.modifiers.contains(.command) {
                app.pendingDeletion = ticketID
                return .handled
            }
            return .ignored
        }
    }

    // MARK: Loading

    private func load() async {
        do {
            let loaded = try await app.store.ticketDetail(id: ticketID)
            detail = loaded
            if !titleFocused { titleDraft = loaded.ticket.title }
            if !isEditingDescription { descriptionDraft = loaded.ticket.description }
        } catch let error as ArcError where error.code == .notFound {
            app.goBack() // deleted elsewhere
        } catch {
            app.present(error)
        }
    }

    // MARK: Main column

    private func main(_ detail: TicketDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(detail)
                titleField(detail)
                descriptionSection(detail)
                childrenSection(detail)
                commentsSection(detail)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func header(_ detail: TicketDetail) -> some View {
        HStack(spacing: 10) {
            if let parent = detail.parent {
                Button {
                    app.open(ticket: parent.id)
                } label: {
                    HStack(spacing: 5) {
                        StatusGlyph(status: parent.status, size: 12)
                        Text("\(parent.identifier) \(parent.title)").lineLimit(1)
                    }
                    .font(Theme.metaFont)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help("Open parent task")
            }
            Spacer()
            Text(detail.ticket.identifier)
                .font(Theme.metaFont.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func titleField(_ detail: TicketDetail) -> some View {
        TextField("Title", text: $titleDraft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Theme.titleFont)
            .foregroundStyle(Theme.textPrimary)
            .focused($titleFocused)
            .onSubmit { saveTitle(detail) }
            .onChange(of: titleFocused) {
                if !titleFocused { saveTitle(detail) }
            }
    }

    private func saveTitle(_ detail: TicketDetail) {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            titleDraft = detail.ticket.title
            return
        }
        guard trimmed != detail.ticket.title else { return }
        Task { await app.perform { try await app.store.updateTicket(id: ticketID, TicketPatch(title: trimmed)) } }
    }

    // MARK: Description

    @ViewBuilder
    private func descriptionSection(_ detail: TicketDetail) -> some View {
        if isEditingDescription {
            TextEditor(text: $descriptionDraft)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(8)
                .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, lineWidth: 1))
                .focused($descriptionFocused)
                .onChange(of: descriptionFocused) {
                    if !descriptionFocused { finishEditingDescription() }
                }
                .onChange(of: descriptionDraft) { scheduleDescriptionSave() }
                .accessibilityLabel("Description (Markdown)")
        } else if detail.ticket.description.isEmpty {
            Text("Add description…")
                .font(Theme.rowFont)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { beginEditingDescription() }
        } else {
            MarkdownView(
                detail.ticket.description,
                knownTickets: app.knownTicketIdentifiers,
                style: Theme.markdownStyle,
                highlighter: HighlightSwiftHighlighter.shared,
                onSourceChange: { updated in
                    Task { await app.perform { try await app.store.updateTicket(id: ticketID, TicketPatch(description: updated)) } }
                }
            )
            .contentShape(Rectangle())
            .onTapGesture { beginEditingDescription() }
        }
    }

    private func beginEditingDescription() {
        descriptionDraft = detail?.ticket.description ?? ""
        isEditingDescription = true
        descriptionFocused = true
    }

    private func scheduleDescriptionSave() {
        descriptionSaveTask?.cancel()
        descriptionSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await persistDescription()
        }
    }

    private func persistDescription() async {
        guard let current = detail?.ticket.description, current != descriptionDraft else { return }
        await app.perform { try await app.store.updateTicket(id: ticketID, TicketPatch(description: descriptionDraft)) }
    }

    private func finishEditingDescription() {
        guard isEditingDescription else { return }
        descriptionSaveTask?.cancel()
        isEditingDescription = false
        Task { await persistDescription() }
    }

    // MARK: Sub-tickets

    private func childrenSection(_ detail: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Sub-tickets").font(Theme.headerFont).foregroundStyle(Theme.textPrimary)
                let counted = detail.children.filter { $0.status != .canceled }
                if !counted.isEmpty {
                    Text("\(counted.filter { $0.status == .done }.count)/\(counted.count)")
                        .font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    app.creation = CreationRequest(projectID: detail.ticket.projectId, parentID: detail.ticket.id)
                } label: {
                    Label("Add sub-ticket", systemImage: "plus").font(Theme.metaFont)
                }
                .buttonStyle(SubtleButtonStyle())
                .help("Add a sub-ticket with all its properties")
            }
            VStack(spacing: 0) {
                ForEach(detail.children) { child in
                    SubtaskRow(subtask: child)
                }
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(Theme.textTertiary).frame(width: 14)
                    TextField("Add sub-ticket…", text: $newSubtask)
                        .textFieldStyle(.plain)
                        .font(Theme.rowFont)
                        .onSubmit { addSubtask(to: detail) }
                }
                .padding(.horizontal, 10)
                .frame(height: Theme.rowHeight)
            }
            .background(Theme.bgSidebar, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
        }
    }

    private func addSubtask(to detail: TicketDetail) {
        let title = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newSubtask = ""
        Task {
            await app.perform {
                try await app.store.createTicket(NewTicket(title: title, projectId: detail.ticket.projectId, parentId: detail.ticket.id))
            }
        }
    }

    // MARK: Comments

    private func commentsSection(_ detail: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments").font(Theme.headerFont).foregroundStyle(Theme.textPrimary)
            ForEach(detail.comments) { comment in
                CommentView(comment: comment)
            }
            VStack(alignment: .trailing, spacing: 8) {
                TextField("Leave a comment… (Markdown)", text: $commentDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(3...10)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(commentFocused ? Theme.accent : Theme.border, lineWidth: 1))
                    .focused($commentFocused)
                    .accessibilityLabel("New comment (Markdown)")
                Button("Comment") { postComment() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func postComment() {
        let body = commentDraft
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        commentDraft = ""
        Task {
            if await app.perform({ try await app.store.addComment(ticketId: ticketID, body: body, author: .user) }) == nil {
                commentDraft = body
            }
        }
    }
}

private struct SubtaskRow: View {
    @Environment(AppModel.self) private var app
    let subtask: Ticket
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            StatusGlyph(status: subtask.status)
            Text(subtask.identifier)
                .font(Theme.metaFont.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            Text(subtask.title)
                .font(Theme.rowFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            PriorityGlyph(priority: subtask.priority)
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .background(hovering ? Theme.bgHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { app.open(ticket: subtask.id) }
        .contextMenu {
            Menu("Status") {
                StatusMenuItems(current: subtask.status) { status in
                    Task { await app.setStatus(status, for: subtask.id) }
                }
            }
            Button("Copy ID") { app.copyToPasteboard(subtask.identifier) }
            Divider()
            Button("Delete…", role: .destructive) { app.pendingDeletion = subtask.id }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(subtask.identifier), \(subtask.title), \(subtask.status.displayName)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct CommentView: View {
    @Environment(AppModel.self) private var app
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(comment.author == .agent ? "Agent" : "You")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(comment.author == .agent ? Theme.accent : Theme.textSecondary)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(
                        (comment.author == .agent ? Theme.accent.opacity(0.16) : Theme.bgSelected),
                        in: Capsule()
                    )
                    .accessibilityLabel(comment.author == .agent ? "Written by an agent" : "Written by you")
                Text(comment.createdAt.formatted(.relative(presentation: .named)))
                    .font(Theme.metaFont)
                    .foregroundStyle(Theme.textTertiary)
                    .help(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                Spacer()
            }
            MarkdownView(
                comment.body,
                knownTickets: app.knownTicketIdentifiers,
                style: Theme.markdownStyle,
                highlighter: HighlightSwiftHighlighter.shared,
                onSourceChange: { updated in
                    Task { await app.perform { try await app.store.updateComment(id: comment.id, body: updated) } }
                }
            )
        }
        .padding(12)
        .background(Theme.bgSidebar, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
    }
}

// MARK: - Properties

private struct PropertiesPanel: View {
    @Environment(AppModel.self) private var app
    let detail: TicketDetail
    @State private var showingParentPicker = false

    private var ticket: Ticket { detail.ticket }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Properties").font(Theme.headerFont).foregroundStyle(Theme.textSecondary)

                property("Status") {
                    Menu {
                        StatusMenuItems(current: ticket.status) { status in
                            Task { await app.setStatus(status, for: ticket.id) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            StatusGlyph(status: ticket.status)
                            Text(ticket.status.displayName)
                        }
                    }
                }
                property("Priority") {
                    Menu {
                        PriorityMenuItems(current: ticket.priority) { priority in
                            Task { await app.setPriority(priority, for: ticket.id) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            PriorityGlyph(priority: ticket.priority)
                            Text(ticket.priority.displayName)
                        }
                    }
                }
                property("Project") {
                    Menu {
                        ForEach(app.projects) { project in
                            Button {
                                Task { await app.move(ticket.id, toProject: project.id) }
                            } label: {
                                Label(project.name, systemImage: project.id == ticket.projectId ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hexString: detail.project.color)).frame(width: 9, height: 9)
                            Text(detail.project.name)
                        }
                    }
                }
                property("Parent") {
                    Button {
                        showingParentPicker = true
                    } label: {
                        Text(detail.parent.map { "\($0.identifier) \($0.title)" } ?? "No parent")
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(detail.parent == nil ? Theme.textTertiary : Theme.textPrimary)
                    }
                    .popover(isPresented: $showingParentPicker, arrowEdge: .leading) {
                        TicketSearchList(excluding: [ticket.id]) { parentID in
                            showingParentPicker = false
                            Task { await app.setParent(parentID, for: [ticket.id]) }
                        }
                        .environment(app)
                    }
                }

                Rectangle().fill(Theme.border).frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    dateRow("Created", ticket.createdAt)
                    dateRow("Updated", ticket.updatedAt)
                    if let completed = ticket.completedAt { dateRow("Completed", completed) }
                }
            }
            .padding(16)
        }
        .background(Theme.bgSidebar)
    }

    private func property<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(Theme.metaFont).foregroundStyle(Theme.textTertiary)
            content()
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .font(Theme.rowFont)
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .contain)
    }

    private func dateRow(_ name: String, _ date: Date) -> some View {
        HStack {
            Text(name).font(Theme.metaFont).foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.metaFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
