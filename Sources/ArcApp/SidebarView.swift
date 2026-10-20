import ArcCore
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

/// A project's icon: its emoji or SF Symbol (Linear icon names are mapped), tinted with the project color,
/// or the plain color dot when there is none.
struct ProjectIcon: View {
    let project: Project
    var size: CGFloat = 13

    private static let symbols = [
        "Subscribe": "bell", "SouthAmerica": "globe.americas", "Sound": "waveform", "Boombox": "hifispeaker",
        "Bitcoin": "bitcoinsign.circle", "Rocket": "paperplane", "Bug": "ladybug", "Code": "chevron.left.forwardslash.chevron.right",
        "Database": "cylinder", "Phone": "iphone", "Mobile": "iphone", "Server": "server.rack", "Star": "star", "Heart": "heart",
    ]

    var body: some View {
        let tint = Color(hexString: project.color)
        if let icon = project.icon, !icon.isEmpty {
            if let symbol = Self.symbols[icon] ?? (icon.contains(".") ? icon : nil) {
                Image(systemName: symbol).font(.system(size: size - 2)).foregroundStyle(tint)
            } else if icon.unicodeScalars.contains(where: { !$0.isASCII }) {
                Text(icon).font(.system(size: size - 2))
            } else {
                Circle().fill(tint).frame(width: 9, height: 9)
            }
        } else {
            Circle().fill(tint).frame(width: 9, height: 9)
        }
    }
}

struct ProjectEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: ProjectEditorRequest
    @State private var name = ""
    @State private var icon = ""
    @FocusState private var focused: Bool

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
            TextField("Icon (an emoji or SF Symbol name, optional)", text: $icon)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
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
            if case .rename(let project) = request.mode { name = project.name; icon = project.icon ?? "" }
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
