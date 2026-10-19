import AppKit
import ArcCore
import ArcMarkdown
import SwiftUI
import Testing
@testable import ArcApp

/// Renders key views to PNGs for eyeballing. Only runs when ARC_SNAPSHOT_DIR is set:
///   ARC_SNAPSHOT_DIR=/tmp/arc-snapshots swift test --filter SnapshotTests
@MainActor
@Suite(.serialized) struct SnapshotTests {
    private var directory: URL? {
        ProcessInfo.processInfo.environment["ARC_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func render<V: View>(_ name: String, width: CGFloat, height: CGFloat? = nil, @ViewBuilder _ view: () -> V) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let content = view()
            .frame(width: width, height: height, alignment: .topLeading)
            .background(Theme.bgContent)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            Issue.record("could not render \(name)")
            return
        }
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    @Test func glyphGallery() throws {
        try render("glyphs", width: 520) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 22) {
                    ForEach(TicketStatus.allCases, id: \.self) { status in
                        VStack(spacing: 6) {
                            StatusGlyph(status: status, size: 28)
                            Text(status.displayName).font(Theme.metaFont)
                        }
                    }
                }
                HStack(spacing: 22) {
                    ForEach(TicketPriority.allCases, id: \.self) { priority in
                        VStack(spacing: 6) {
                            PriorityGlyph(priority: priority, size: 28)
                            Text(priority.displayName).font(Theme.metaFont)
                        }
                    }
                }
                HStack(spacing: 10) {
                    ForEach(TicketStatus.allCases, id: \.self) { StatusGlyph(status: $0) }
                    ForEach(TicketPriority.allCases, id: \.self) { PriorityGlyph(priority: $0) }
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(20)
        }
    }

    @Test func markdownKitchenSink() async throws {
        guard directory != nil else { return }
        let source = """
        # Heading 1
        ## Heading 2
        ###### Heading 6

        Paragraph with **bold**, *italic*, ~~strike~~, `inline code`, a [link](https://example.com) and https://bare.example.com/path.
        See ARC-12 and `ARC-12`.

        - bullet
          - nested bullet
        1. numbered
        2. second

        - [ ] todo item
        - [x] done item

        > quoted text
        > continues here

        ---

        ```swift
        // comment
        let greeting = "hello"
        func add(_ a: Int, _ b: Int) -> Int { a + b }
        ```

        | Left | Right |
        | :--- | ----: |
        | a | 1 |
        | longer cell | 22 |

        <div>raw html shown as text</div>
        """
        // Pre-warm the highlighter so the snapshot shows colors.
        _ = await HighlightSwiftHighlighter.shared.highlight("let x = 1", language: "swift")
        try render("markdown", width: 640) {
            MarkdownView(source, knownTickets: [12], style: Theme.markdownStyle, onSourceChange: { _ in })
                .padding(20)
        }
    }

    @Test func listAndBoard() async throws {
        guard let directory else { return }
        let store = try ArcStore(path: temporaryDatabasePath())
        let website = try await store.createProject(name: "Website")
        let epic = try await store.createTicket(NewTicket(title: "Launch the new site", kind: .epic, projectId: website.id, status: .inProgress))
        let footer = try await store.createTicket(NewTicket(title: "Build footer", projectId: website.id, epicId: epic.id, status: .inProgress, priority: .high))
        try await store.createTicket(NewTicket(title: "Add tests", kind: .subtask, parentId: footer.id, status: .inProgress))
        try await store.createTicket(NewTicket(title: "Check accessibility", kind: .subtask, parentId: footer.id, status: .done))
        try await store.createTicket(NewTicket(title: "Hero image", projectId: website.id, epicId: epic.id, priority: .medium))
        try await store.createTicket(NewTicket(title: "Write launch copy", projectId: website.id, status: .inReview, priority: .urgent))
        try await store.createTicket(NewTicket(title: "Pick a typeface", projectId: website.id, status: .backlog))
        try await store.createTicket(NewTicket(title: "Old banner", projectId: website.id, epicId: epic.id, status: .done))

        let settingsStore = ViewSettingsStore(defaults: UserDefaults(suiteName: "arc-snap-\(UUID().uuidString)")!)
        let appModel = AppModel(store: store, settingsStore: settingsStore)
        await appModel.reload()
        let model = TicketListModel(scope: .allTasks, store: store, settingsStore: settingsStore)
        model.settings.collapsedStatuses = []
        await model.reload()

        // ImageRenderer cannot draw ScrollView content, so compose the pieces by hand.
        try render("list", width: 960) {
            VStack(spacing: 0) {
                ForEach(model.listGroups) { group in
                    GroupHeader(group: group, isCollapsed: false) {}
                    ForEach(group.rows) { row in
                        TicketRowView(item: row, showProject: true, isSelected: row.summary.ticket.title == "Build footer", isChecked: false, order: [])
                    }
                }
            }
            .environment(appModel)
        }
        model.settings.layout = .board
        try render("board", width: 1500) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(model.boardColumns) { column in
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            StatusGlyph(status: column.status)
                            Text(column.status.displayName).font(Theme.headerFont).foregroundStyle(Theme.textPrimary)
                            Text("\(column.cards.count)").font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }
                        ForEach(column.cards) { card in
                            BoardCardView(summary: card, column: column, showProject: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .frame(width: 280, height: 360, alignment: .top)
                    .background(Theme.bgSidebar, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .environment(appModel)
        }
        try render("filterbar", width: 960) {
            FilterBar(model: model).environment(appModel)
        }
        _ = directory
    }
}
