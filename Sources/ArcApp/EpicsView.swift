import ArcCore
import SwiftUI

/// The Epics sidebar entry: epics grouped by project, with progress.
struct EpicsOverview: View {
    @Environment(AppModel.self) private var app
    @State private var epics: [EpicProgress] = []
    @State private var loaded = false

    private var groups: [(project: String, epics: [EpicProgress])] {
        var order: [String] = []
        var byProject: [String: [EpicProgress]] = [:]
        for epic in epics {
            if byProject[epic.projectName] == nil { order.append(epic.projectName) }
            byProject[epic.projectName, default: []].append(epic)
        }
        return order.map { ($0, byProject[$0] ?? []) }
    }

    var body: some View {
        Group {
            if loaded && epics.isEmpty {
                EmptyStateView(
                    title: "No epics yet",
                    message: "Epics group related tasks inside a project.",
                    buttonTitle: "New Epic"
                ) {
                    app.creation = CreationRequest(projectID: nil, kind: .epic)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.project) { group in
                            Section {
                                ForEach(group.epics) { epic in
                                    EpicRow(epic: epic)
                                }
                            } header: {
                                HStack {
                                    Text(group.project).font(Theme.headerFont).foregroundStyle(Theme.textPrimary)
                                    Text("\(group.epics.count)").font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
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
        .navigationTitle("Epics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.creation = CreationRequest(projectID: nil, kind: .epic)
                } label: {
                    Label("New Epic", systemImage: "plus")
                }
            }
        }
        .task(id: app.feed.generation) {
            if let loadedEpics = try? await app.store.epicsWithProgress() {
                epics = loadedEpics
                loaded = true
            }
        }
    }
}

private struct EpicRow: View {
    @Environment(AppModel.self) private var app
    let epic: EpicProgress
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(epic.ticket.identifier)
                .font(Theme.metaFont.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 52, alignment: .leading)
            StatusGlyph(status: epic.ticket.status)
            Text(epic.ticket.title)
                .font(Theme.rowFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)
            ProgressBar(done: epic.done, total: epic.total)
                .frame(width: 120)
            Text("\(epic.done)/\(epic.total)")
                .font(Theme.metaFont.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.rowHeight)
        .background(hovering ? Theme.bgHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { app.path.append(.epic(epic.ticket.id)) }
        .contextMenu {
            Button("Open Details") { app.open(ticket: epic.ticket.id) }
            Button("Copy ID") { app.copyToPasteboard(epic.ticket.identifier) }
            Divider()
            Button("Delete…", role: .destructive) { app.pendingDeletion = epic.ticket.id }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(epic.ticket.identifier), \(epic.ticket.title), \(epic.done) of \(epic.total) done")
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
