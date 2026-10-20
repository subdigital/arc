import Foundation
import GRDB
import Testing
@testable import ArcCore

@Suite struct LinearImportTests {
    /// A small export: two projects (one completed, one with a milestone), a parent/child pair, labels,
    /// relations, a threaded comment, a link attachment, and an issue without a project.
    private func makeExport(tweak: (inout [[String: Any]]) -> Void = { _ in }) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("linear-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let projects: [[String: Any]] = [
            ["id": "P-FIC-1", "name": "Alpha", "summary": "First", "icon": "Boombox", "color": "#112233",
             "status": ["type": "started"], "createdAt": "2024-01-01T00:00:00.000Z", "updatedAt": "2024-02-01T00:00:00.000Z",
             "milestones": [["id": "m1", "name": "Beta", "description": "", "sortOrder": 1.0, "targetDate": "2024-06-01"]]],
            ["id": "P-FIC-2", "name": "Old", "summary": "", "status": ["type": "completed"],
             "completedAt": "2024-03-01T00:00:00.000Z", "createdAt": "2023-01-01T00:00:00.000Z", "updatedAt": "2024-03-01T00:00:00.000Z",
             "milestones": []],
        ]
        func issue(_ n: Int, title: String, status: String, type: String, project: String?, parent: String? = nil,
                   labels: [String] = [], relations: [String: Any] = [:], comments: [[String: Any]] = [],
                   completed: String? = nil, milestone: [String: Any]? = nil) -> [String: Any] {
            var value: [String: Any] = [
                "id": "FIC-\(n)", "uuid": "uuid-\(n)", "title": title, "description": "Body of \(n) mentions FIC-1",
                "priority": ["value": 2, "name": "High"], "url": "https://linear.app/x/issue/FIC-\(n)",
                "createdAt": "2024-01-0\(n)T10:00:00.000Z", "updatedAt": "2024-01-1\(n)T10:00:00.000Z",
                "status": status, "statusType": type, "labels": labels, "attachments": [["id": "a\(n)", "title": "PR \(n)", "url": "https://github.com/x/pull/\(n)"]],
                "relations": relations, "comments": comments,
            ]
            if let project { value["project"] = project }
            if let parent { value["parentId"] = parent }
            if let completed { value["completedAt"] = completed }
            if let milestone { value["projectMilestone"] = milestone }
            return value
        }
        var issues: [[String: Any]] = [
            issue(1, title: "Parent", status: "In Progress", type: "started", project: "Alpha", labels: ["Bug", "mobile"],
                  relations: ["blocks": [["id": "FIC-2"]]], milestone: ["id": "m1", "name": "Beta"]),
            issue(2, title: "Child", status: "Done", type: "completed", project: "Alpha", parent: "FIC-1", labels: ["bug"],
                  relations: ["blockedBy": [["id": "FIC-1"]], "relatedTo": [["id": "FIC-3"]]],
                  comments: [
                    ["id": "c1", "body": "First", "createdAt": "2024-01-05T10:00:00.000Z", "updatedAt": "2024-01-05T10:00:00.000Z", "parentId": NSNull(), "author": ["name": "ben@example.com"]],
                    ["id": "c2", "body": "Reply", "createdAt": "2024-01-06T10:00:00.000Z", "updatedAt": "2024-01-06T10:00:00.000Z", "parentId": "c1", "author": ["name": "sam"]],
                  ], completed: "2024-01-20T10:00:00.000Z"),
            issue(3, title: "Orphan", status: "Duplicate", type: "canceled", project: "Old",
                  relations: ["relatedTo": [["id": "FIC-2"]], "duplicateOf": ["id": "FIC-1"]]),
            issue(4, title: "No project", status: "Backlog", type: "backlog", project: nil),
        ]
        tweak(&issues)
        try JSONSerialization.data(withJSONObject: projects).write(to: directory.appendingPathComponent("projects.json"))
        try JSONSerialization.data(withJSONObject: issues).write(to: directory.appendingPathComponent("issues-0001-0010.json"))
        try JSONSerialization.data(withJSONObject: [["id": "t", "key": "FIC", "name": "Fickle bits"]]).write(to: directory.appendingPathComponent("teams.json"))
        return directory
    }

    private func options(_ directory: URL, dryRun: Bool = false, force: Bool = false) -> LinearImportOptions {
        LinearImportOptions(directory: directory, dryRun: dryRun, force: force, downloadFiles: false)
    }

    @Test func importsTheWholeModel() async throws {
        let store = try makeStore()
        let report = try await LinearImporter.run(store: store, options: options(try makeExport()))
        #expect(report.succeeded, "\(report.errors)")
        #expect(report.tickets.created == 4 && report.projects.created == 3 && report.milestones.created == 1)
        #expect(report.verifiedTickets == 4)

        let parent = try await store.resolveTicket("FIC-1")
        let child = try await store.resolveTicket("fic-2")
        #expect(child.parentId == parent.id)
        #expect(child.status == .done && child.completedAt != nil)
        #expect(child.createdAt == ISO8601DateFormatter().date(from: "2024-01-02T10:00:00Z"))
        #expect(try await store.resolveTicket("FIC-3").status == .canceled)

        let detail = try await store.ticketDetail(id: parent.id)
        #expect(detail.labels.map(\.name) == ["Bug", "mobile"])
        #expect(detail.milestone?.name == "Beta")
        #expect(detail.relations.blocks.map(\.identifier) == ["FIC-2"])
        #expect(detail.relations.duplicatedBy.map(\.identifier) == ["FIC-3"])
        #expect(detail.attachments.map(\.title).contains("PR 1"))
        #expect(detail.attachments.contains { $0.title == "Open FIC-1 in Linear" })

        let childDetail = try await store.ticketDetail(id: child.id)
        #expect(childDetail.relations.blockedBy.map(\.identifier) == ["FIC-1"])
        #expect(childDetail.relations.related.map(\.identifier) == ["FIC-3"])
        #expect(childDetail.comments.count == 2)
        #expect(childDetail.comments[1].parentId == childDetail.comments[0].id)
        #expect(childDetail.comments[1].authorName == "sam")

        // Projects stay active (even completed ones); the ticket without a project goes to the team's project.
        let projects = try await store.projects(includeArchived: true)
        #expect(Set(projects.map(\.name)) == ["Alpha", "Old", "Fickle bits"])
        #expect(projects.allSatisfy { !$0.isArchived })
        #expect(projects.first { $0.name == "Alpha" }?.icon == "hifispeaker")
        #expect(try await store.resolveTicket("FIC-4").projectId == projects.first { $0.name == "Fickle bits" }?.id)

        // New ARC tickets still count from 1 and do not collide.
        let alpha = try await store.resolveProject("Alpha")
        #expect(try await store.task("Native", in: alpha).identifier == "ARC-1")
    }

    @Test func runningAgainChangesNothing() async throws {
        let store = try makeStore()
        let directory = try makeExport()
        _ = try await LinearImporter.run(store: store, options: options(directory))
        let again = try await LinearImporter.run(store: store, options: options(directory))
        #expect(again.succeeded)
        #expect(again.tickets == ImportCounts(created: 0, updated: 0, unchanged: 4, editedLocally: 0, removed: 0))
        #expect(again.projects.created == 0 && again.comments.created == 0 && again.relations.created == 0 && again.attachments.created == 0)
        #expect(again.labels.created == 0)
        #expect(try await store.tickets(matching: TicketQuery(includeClosed: true, includeArchivedProjects: true)).count == 4)
    }

    @Test func dryRunWritesNothing() async throws {
        let store = try makeStore()
        let report = try await LinearImporter.run(store: store, options: options(try makeExport(), dryRun: true))
        #expect(report.dryRun && report.tickets.created == 4 && report.verifiedTickets == 4)
        #expect(try await store.projects(includeArchived: true).isEmpty)
        #expect(try await store.ticketIdentifiers().isEmpty)
        #expect(try await store.labels().isEmpty)
    }

    @Test func changesInTheExportAreAppliedOnTheNextRun() async throws {
        let store = try makeStore()
        _ = try await LinearImporter.run(store: store, options: options(try makeExport()))
        let changed = try makeExport { issues in
            issues[0]["title"] = "Parent (renamed)"
            issues[0]["labels"] = ["Bug"]
            issues[1]["comments"] = [issues[1]["comments"] as! [[String: Any]]][0].dropLast().map { $0 }
            issues[0]["relations"] = [String: Any]()
            issues[1]["relations"] = [String: Any]()
            issues.append([
                "id": "FIC-5", "uuid": "uuid-5", "title": "New one", "description": "", "priority": 0, "project": "Alpha",
                "status": "Todo", "statusType": "unstarted", "labels": [], "attachments": [], "relations": [String: Any](), "comments": [],
                "createdAt": "2024-02-01T00:00:00.000Z", "updatedAt": "2024-02-01T00:00:00.000Z",
            ])
        }
        let report = try await LinearImporter.run(store: store, options: options(changed))
        #expect(report.succeeded, "\(report.errors)")
        #expect(report.tickets.created == 1 && report.tickets.updated == 2)
        let parent = try await store.resolveTicket("FIC-1")
        #expect(parent.title == "Parent (renamed)")
        let detail = try await store.ticketDetail(id: parent.id)
        #expect(detail.labels.map(\.name) == ["Bug"])
        #expect(detail.relations.blocks.isEmpty)
        let child = try await store.resolveTicket("FIC-2")
        #expect(try await store.comments(ticketId: child.id).count == 1)
        #expect(report.relations.removed >= 1)
    }

    @Test func ticketsEditedInArcAreLeftAloneUnlessForced() async throws {
        let clock = TestClock()
        let store = try makeStore(now: clock.callback)
        let directory = try makeExport()
        _ = try await LinearImporter.run(store: store, options: options(directory))
        let ticket = try await store.resolveTicket("FIC-1")
        clock.advance()
        try await store.updateTicket(id: ticket.id, TicketPatch(title: "My own title"))
        // Add something of mine too: a comment and a relation the export knows nothing about.
        try await store.addComment(ticketId: ticket.id, body: "mine", author: .user)

        let changed = try makeExport { $0[0]["description"] = "New description from Linear" }
        let report = try await LinearImporter.run(store: store, options: options(changed))
        #expect(report.tickets.editedLocally == 1)
        #expect(report.warnings.contains { $0.contains("FIC-1 was edited in Arc") })
        #expect(try await store.ticket(id: ticket.id).title == "My own title")
        #expect(try await store.ticket(id: ticket.id).description != "New description from Linear")

        let forced = try await LinearImporter.run(store: store, options: options(changed, force: true))
        #expect(forced.succeeded)
        #expect(try await store.ticket(id: ticket.id).title == "Parent")
        #expect(try await store.comments(ticketId: ticket.id).map(\.body) == ["mine"], "comments made in Arc survive")
    }

    @Test func keysTakenByOtherTicketsAreReportedNotOverwritten() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "Mine")
        let now = Date()
        try await store.pool.write { db in
            try db.execute(sql: """
                INSERT INTO ticket (id, prefix, number, project_id, title, status, priority, sort_key, created_at, updated_at)
                VALUES ('x', 'FIC', 2, ?, 'Squatter', 'todo', 0, 0, ?, ?)
                """, arguments: [project.id, now, now])
        }
        let report = try await LinearImporter.run(store: store, options: options(try makeExport()))
        #expect(!report.succeeded)
        #expect(report.errors.contains { $0.contains("FIC-2 already exists") })
        #expect(try await store.ticket(id: "x").title == "Squatter")
    }

    @Test func aProjectWithTheSameNameIsAdoptedNotDuplicated() async throws {
        let store = try makeStore()
        let existing = try await store.createProject(name: "alpha")
        let mine = try await store.task("Mine", in: existing)
        let report = try await LinearImporter.run(store: store, options: options(try makeExport()))
        #expect(report.succeeded, "\(report.errors)")
        #expect(report.warnings.contains { $0.contains("already existed") })
        let names = try await store.projects(includeArchived: true).map(\.name)
        #expect(!names.contains { $0.contains("Linear") })
        #expect(try await store.resolveTicket("FIC-1").projectId == existing.id)
        #expect(try await store.ticket(id: mine.id).projectId == existing.id)
        let again = try await LinearImporter.run(store: store, options: options(try makeExport()))
        #expect(again.projects.unchanged == 3 && again.projects.created == 0)
    }

    @Test func embeddedUploadsBecomeMarkdownLinksAndImages() async throws {
        let store = try makeStore()
        let embed = #"<linear-embed node-type="file">{"uploadState":"finished","href":"https:\/\/uploads.linear.app\/w\/f\/3cb0","name":"Party [2026].st4p","size":2063}</linear-embed>"#
        let image = #"<linear-embed node-type="image">{"src":"https://uploads.linear.app/w/f/pic.png","alt":"x","title":"Screenshot.png"}</linear-embed>"#
        let directory = try makeExport { $0[0]["description"] = "Before\n\n\(embed)\n\nMiddle \(image) after" }
        let report = try await LinearImporter.run(store: store, options: options(directory))
        #expect(report.succeeded, "\(report.errors)")
        let description = try await store.resolveTicket("FIC-1").description
        #expect(description == "Before\n\n[Party \\[2026\\].st4p](https://uploads.linear.app/w/f/3cb0)\n\nMiddle ![Screenshot.png](https://uploads.linear.app/w/f/pic.png) after")
        #expect(!description.contains("linear-embed"))
    }

    @Test func resetRemovesOnlyWhatTheImportCreated() async throws {
        let store = try makeStore()
        _ = try await LinearImporter.run(store: store, options: options(try makeExport()))
        let alpha = try await store.resolveProject("Alpha")
        let mine = try await store.task("Mine", in: alpha)
        try await store.addLabel(ticketId: mine.id, name: "bug") // a label the import also uses

        let report = try await LinearImporter.reset(store: store)
        #expect(report.tickets.removed == 4)
        #expect(try await store.ticketIdentifiers() == [mine.identifier])
        let names = try await store.projects(includeArchived: true).map(\.name)
        #expect(names == ["Alpha"], "a project holding my ticket is kept")
        let remainingLabels = try await store.labels().map { $0.name.lowercased() }
        #expect(remainingLabels == ["bug"], "labels in use survive")
        #expect(report.warnings.contains { $0.contains("Alpha") })

        // And it can be imported again afterwards.
        let again = try await LinearImporter.run(store: store, options: options(try makeExport()))
        #expect(again.succeeded, "\(again.errors)")
        #expect(again.tickets.created == 4)
    }
}
