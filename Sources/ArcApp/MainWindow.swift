import ArcCore
import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            ContentRoot()
        }
        .background(Theme.bgContent)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .task(id: app.feed.generation) { await app.reload() }
        .sheet(item: $app.creation) { request in
            CreateTicketSheet(request: request).environment(app).preferredColorScheme(.dark)
        }
        .sheet(item: $app.projectEditor) { request in
            ProjectEditorSheet(request: request).environment(app).preferredColorScheme(.dark)
        }
        .alert(item: $app.error) { error in
            Alert(title: Text("Something went wrong"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog(
            "Delete this ticket?",
            isPresented: Binding(get: { app.pendingDeletion != nil }, set: { if !$0 { app.pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = app.pendingDeletion { Task { await app.delete(ticket: id) } }
                app.pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { app.pendingDeletion = nil }
        } message: {
            Text("Deleting a task also deletes its subtasks and all comments. This cannot be undone.")
        }
        .environment(\.openURL, OpenURLAction { url in
            if let number = MarkdownLinks.ticketNumber(from: url) {
                Task { await app.open(ticketNumber: number) }
                return .handled
            }
            return .systemAction
        })
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.isEmpty, press.characters == "c" else { return .ignored }
            app.creation = CreationRequest(projectID: currentProjectID)
            return .handled
        }
    }

    private var currentProjectID: String? {
        if case .project(let id) = app.selection { id } else { nil }
    }
}

private struct ContentRoot: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        if app.hasLoaded && app.projects.isEmpty && app.archivedProjects.isEmpty {
            EmptyStateView(
                title: "Welcome to Arc",
                message: "Create your first project to start tracking work.",
                buttonTitle: "Create Project"
            ) {
                app.projectEditor = ProjectEditorRequest(mode: .create)
            }
            .background(Theme.bgContent)
        } else {
            NavigationStack(path: $app.path) {
                root
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .ticket(let id): TicketDetailView(ticketID: id)
                        case .epic(let id): TicketsView(scope: .epic(id), app: app).id(id)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var root: some View {
        switch app.selection {
        case .allTasks: TicketsView(scope: .allTasks, app: app).id("all")
        case .project(let id): TicketsView(scope: .project(id), app: app).id(id)
        case .epics: EpicsOverview()
        }
    }
}
