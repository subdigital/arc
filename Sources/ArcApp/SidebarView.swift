import ArcCore
import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @State private var archivedExpanded = false
    @State private var projectPendingDeletion: Project?

    var body: some View {
        @Bindable var app = app
        List(selection: $app.selection) {
            Section {
                Label("All Tasks", systemImage: "tray.full")
                    .tag(SidebarSelection.allTasks)
                Label("Parents", systemImage: "square.stack.3d.up")
                    .tag(SidebarSelection.parents)
            }

            Section {
                ForEach(app.projects) { project in
                    ProjectRow(project: project)
                        .tag(SidebarSelection.project(project.id))
                        .contextMenu { projectMenu(project) }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button {
                        app.projectEditor = ProjectEditorRequest(mode: .create)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                    .help("New project")
                    .accessibilityLabel("New project")
                }
            }

            if !app.archivedProjects.isEmpty {
                Section {
                    DisclosureGroup("Archived", isExpanded: $archivedExpanded) {
                        ForEach(app.archivedProjects) { project in
                            ProjectRow(project: project)
                                .opacity(0.65)
                                .tag(SidebarSelection.project(project.id))
                                .contextMenu { projectMenu(project) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.bgSidebar)
        .confirmationDialog(
            "Delete \"\(projectPendingDeletion?.name ?? "")\"?",
            isPresented: Binding(get: { projectPendingDeletion != nil }, set: { if !$0 { projectPendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: projectPendingDeletion
        ) { project in
            Button("Delete Project and Its Tickets", role: .destructive) {
                Task { await app.perform { try await app.store.deleteProject(id: project.id) } }
            }
        } message: { _ in
            Text("This permanently deletes the project, all of its tickets and their comments.")
        }
    }

    @ViewBuilder
    private func projectMenu(_ project: Project) -> some View {
        Button("Edit…") { app.projectEditor = ProjectEditorRequest(mode: .rename(project)) }
        if project.isArchived {
            Button("Unarchive") {
                Task { await app.perform { try await app.store.setProjectArchived(id: project.id, archived: false) } }
            }
        } else {
            Button("Archive") {
                Task { await app.perform { try await app.store.setProjectArchived(id: project.id, archived: true) } }
            }
        }
        Divider()
        Button("Delete…", role: .destructive) { projectPendingDeletion = project }
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        Label {
            Text(project.name)
        } icon: {
            ProjectIcon(project: project)
        }
    }
}

/// A project's icon: its emoji or SF Symbol, tinted with the project color, or the plain color dot when there is none
/// (or the name is not a symbol this system knows).
struct ProjectIcon: View {
    let project: Project
    var size: CGFloat = 13

    var body: some View {
        IconView(icon: project.icon, tint: Color(hexString: project.color), size: size)
    }
}

struct IconView: View {
    let icon: String?
    let tint: Color
    var size: CGFloat = 13

    var body: some View {
        let name = ProjectIcons.normalized(icon ?? "")
        if name.isEmpty {
            Circle().fill(tint).frame(width: 9, height: 9)
        } else if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            Image(systemName: name).font(.system(size: size - 2)).foregroundStyle(tint)
        } else if name.unicodeScalars.contains(where: { !$0.isASCII }) {
            Text(name).font(.system(size: size - 2))
        } else {
            Circle().fill(tint).frame(width: 9, height: 9)
        }
    }
}

/// Pick an SF Symbol from a grid, or type an emoji.
struct IconPicker: View {
    @Binding var icon: String
    let tint: Color
    @State private var showing = false
    @State private var emoji = ""

    var body: some View {
        HStack(spacing: 10) {
            Button { showing = true } label: {
                HStack(spacing: 8) {
                    IconView(icon: icon, tint: tint, size: 16).frame(width: 18)
                    Text(icon.isEmpty ? "Choose icon" : "Change icon").font(Theme.rowFont)
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Theme.bgSelected.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showing, arrowEdge: .bottom) { picker }
            if !icon.isEmpty {
                Button("Remove") { icon = "" }.buttonStyle(SubtleButtonStyle())
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8), spacing: 4) {
                    ForEach(ProjectIcons.symbols, id: \.self) { symbol in
                        Button {
                            icon = symbol
                            showing = false
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 15))
                                .foregroundStyle(icon == symbol ? Theme.accent : tint)
                                .frame(width: 34, height: 30)
                                .background(icon == symbol ? Theme.accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                        .accessibilityLabel(symbol)
                    }
                }
            }
            .frame(height: 190)
            Divider().overlay(Theme.border)
            HStack {
                TextField("Or type an emoji", text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(useEmoji)
                Button("Use", action: useEmoji)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(emoji.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(Theme.bgElevated)
    }

    private func useEmoji() {
        let value = emoji.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        icon = value
        emoji = ""
        showing = false
    }
}

struct ProjectEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: ProjectEditorRequest
    @State private var name = ""
    @State private var icon = ""
    @FocusState private var focused: Bool

    private var tintHex: String {
        if case .rename(let project) = request.mode { project.color } else { "#5E6AD2" }
    }

    private var title: String {
        if case .rename = request.mode { "Edit Project" } else { "New Project" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .semibold))
            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            IconPicker(icon: $icon, tint: Color(hexString: tintHex))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SubtleButtonStyle())
                Button(saveTitle, action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.bgElevated)
        .onAppear {
            if case .rename(let project) = request.mode { name = project.name; icon = ProjectIcons.normalized(project.icon ?? "") }
            focused = true
        }
    }

    private var saveTitle: String {
        if case .rename = request.mode { "Save" } else { "Create" }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            let succeeded: Bool
            switch request.mode {
            case .create:
                if let project = await app.perform({ try await app.store.createProject(name: trimmed, icon: icon.isEmpty ? nil : icon) }) {
                    app.selection = .project(project.id)
                    succeeded = true
                } else { succeeded = false }
            case .rename(let project):
                succeeded = await app.perform { try await app.store.updateProject(id: project.id, name: trimmed, icon: icon) } != nil
            }
            if succeeded { dismiss() }
        }
    }
}
