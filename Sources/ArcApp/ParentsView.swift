import ArcCore
import SwiftUI

/// The Parents sidebar entry: tickets that have children, grouped by project, with progress.
struct ParentsOverview: View {
    @Environment(AppModel.self) private var app
    @State private var parents: [ParentProgress] = []
    @State private var loaded = false

    private var groups: [(project: String, parents: [ParentProgress])] {
        var order: [String] = []
        var byProject: [String: [ParentProgress]] = [:]
        for parent in parents {
            if byProject[parent.projectName] == nil { order.append(parent.projectName) }
            byProject[parent.projectName, default: []].append(parent)
        }
        return order.map { ($0, byProject[$0] ?? []) }
    }

    var body: some View {
        Group {
            if loaded && parents.isEmpty {
                EmptyStateView(
                    title: "No parent tickets yet",
                    message: "Give a ticket a parent to group related work under it.",
                    buttonTitle: "New Ticket"
                ) {
                    app.creation = CreationRequest(projectID: nil)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.project) { group in
                            Section {
                                ForEach(group.parents) { parent in
                                    ParentRow(parent: parent)
                                }
                            } header: {
                                HStack {
                                    Text(group.project).font(Theme.headerFont).foregroundStyle(Theme.textPrimary)
                                    Text("\(group.parents.count)").font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(Theme.bgSidebar)
                            }
                        }
                    }
                }
            }
        }
        .background(Theme.bgContent)
        .navigationTitle("Parents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.creation = CreationRequest(projectID: nil)
                } label: {
                    Label("New Ticket", systemImage: "plus")
                }
            }
        }
        .task(id: app.feed.generation) {
            if let loadedParents = try? await app.store.parentsWithProgress() {
                parents = loadedParents
                loaded = true
            }
        }
    }
}

private struct ParentRow: View {
    @Environment(AppModel.self) private var app
    let parent: ParentProgress
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(parent.ticket.identifier)
                .font(Theme.metaFont.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 52, alignment: .leading)
            StatusGlyph(status: parent.ticket.status)
            Text(parent.ticket.title)
                .font(Theme.rowFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)
            ProgressBar(done: parent.done, total: parent.total)
                .frame(width: 120)
            Text("\(parent.done)/\(parent.total)")
                .font(Theme.metaFont.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.rowHeight)
        .background(hovering ? Theme.bgHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { app.path.append(.children(parent.ticket.id)) }
        .contextMenu {
            Button("Open Details") { app.open(ticket: parent.ticket.id) }
            Button("Copy ID") { app.copyToPasteboard(parent.ticket.identifier) }
            Divider()
            Button("Delete…", role: .destructive) { app.pendingDeletion = parent.ticket.id }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(parent.ticket.identifier), \(parent.ticket.title), \(parent.done) of \(parent.total) done")
        .accessibilityAddTraits(.isButton)
    }
}

struct ProgressBar: View {
    let done: Int
    let total: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.bgSelected)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: total == 0 ? 0 : geometry.size.width * CGFloat(done) / CGFloat(total))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
