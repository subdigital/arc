import AppKit
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
        .sheet(isPresented: Binding(get: { app.parentPicking != nil }, set: { if !$0 { app.parentPicking = nil } })) {
            ParentPickerSheet(ticketIDs: app.parentPicking ?? []).environment(app)
        }
        .sheet(item: $app.projectEditor) { request in
            ProjectEditorSheet(request: request).environment(app).preferredColorScheme(.dark)
        }
        .alert(item: $app.error) { error in
            Alert(title: Text("Something went wrong"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog(
            app.pendingDeletionIDs.count > 1 ? "Delete \(app.pendingDeletionIDs.count) tickets?" : "Delete this ticket?",
            isPresented: Binding(get: { !app.pendingDeletionIDs.isEmpty }, set: { if !$0 { app.pendingDeletionIDs = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = app.pendingDeletionIDs
                app.pendingDeletionIDs = []
                Task { await app.bulkDelete(ids) }
            }
            Button("Cancel", role: .cancel) { app.pendingDeletionIDs = [] }
        } message: {
            Text("Deleting a ticket also deletes its comments; its sub-tickets are kept. This cannot be undone.")
        }
        .environment(\.openURL, OpenURLAction { url in
            if let identifier = MarkdownLinks.ticketIdentifier(from: url) {
                Task { await app.open(ticketIdentifier: identifier) }
                return .handled
            }
            return .systemAction
        })
        .overlay {
            if app.showingShortcuts {
                ShortcutsOverlay().environment(app).transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let toast = app.toast {
                ToastView(message: toast.message)
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: app.showingShortcuts)
        .animation(.easeOut(duration: 0.2), value: app.toast)
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
                        case .children(let id): TicketsView(scope: .children(id), app: app).id(id)
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
        case .parents: ParentsOverview()
        }
    }
}

/// True while a text field or text editor has keyboard focus; bare-letter shortcuts must not fire then.
@MainActor
var isEditingText: Bool {
    NSApp.keyWindow?.firstResponder is NSText
}
