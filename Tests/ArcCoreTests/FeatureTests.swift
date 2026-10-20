import Foundation
import GRDB
import Testing
@testable import ArcCore

@Suite struct FeatureTests {
    private func failure(_ body: () async throws -> Void) async -> ArcError? {
        do { try await body(); return nil } catch { return error as? ArcError }
    }

    // MARK: Labels

    @Test func labelsAreCreatedOnDemandAndMatchedIgnoringCase() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let one = try await store.task("one", in: project)
        let two = try await store.task("two", in: project)
        #expect(try await store.labels().isEmpty)

        let set = try await store.setLabels(ticketId: one.id, names: ["Bug", "mobile", "bug"])
        #expect(set.map(\.name) == ["Bug", "mobile"])
        try await store.addLabel(ticketId: two.id, name: "BUG")
        #expect(try await store.labels().count == 2, "the same label, whatever the case")
        #expect(try await store.labels(ticketId: two.id).map(\.name) == ["Bug"])
        #expect(Set(try await store.labels().map(\.color)).allSatisfy { $0.hasPrefix("#") })

        let bug = try #require(try await store.labels().first { $0.name == "Bug" })
        let rows = try await store.tickets(matching: TicketQuery(labelIds: [bug.id]))
        #expect(Set(rows.map(\.ticket.number)) == [one.number, two.number])
        #expect(rows.first { $0.ticket.id == one.id }?.labels.map(\.name) == ["Bug", "mobile"])

        try await store.removeLabel(ticketId: one.id, labelId: bug.id)
        #expect(try await store.tickets(matching: TicketQuery(labelIds: [bug.id])).map(\.ticket.id) == [two.id])
        let renameClash = await failure { _ = try await store.updateLabel(id: bug.id, name: "mobile") }
        #expect(renameClash?.code == .conflict)
        let blank = await failure { _ = try await store.setLabels(ticketId: one.id, names: ["  "]) }
        #expect(blank?.code == .invalidArgument)
    }

    // MARK: Relations

    @Test func relationsShowFromBothSidesAndBlockedFollowsTheBlocker() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let blocker = try await store.task("blocker", in: project)
        let blocked = try await store.task("blocked", in: project)
        let other = try await store.task("other", in: project)

        try await store.addRelation(from: blocker.id, to: blocked.id, type: .blocks)
        try await store.addRelation(from: blocker.id, to: blocked.id, type: .blocks) // idempotent
        try await store.addRelation(from: other.id, to: blocker.id, type: .related)
        try await store.addRelation(from: blocked.id, to: other.id, type: .duplicate)

        let fromBlocker = try await store.relations(ticketId: blocker.id)
        #expect(fromBlocker.blocks.map(\.number) == [blocked.number])
        #expect(fromBlocker.related.map(\.number) == [other.number])
        let fromBlocked = try await store.relations(ticketId: blocked.id)
        #expect(fromBlocked.blockedBy.map(\.number) == [blocker.number])
        #expect(fromBlocked.duplicateOf.map(\.number) == [other.number])
        #expect(try await store.relations(ticketId: other.id).duplicatedBy.map(\.number) == [blocked.number])
        #expect(try await store.relations(ticketId: other.id).related.map(\.number) == [blocker.number], "related is symmetric")

        #expect(try await store.ticketSummary(id: blocked.id).isBlocked)
        #expect(try await store.ticketDetail(id: blocked.id).relations.openBlockers.count == 1)
        try await store.updateTicket(id: blocker.id, TicketPatch(status: .done))
        #expect(try await store.ticketSummary(id: blocked.id).isBlocked == false, "a finished blocker no longer blocks")

        try await store.removeRelation(from: blocker.id, to: blocked.id, type: .blocks)
        #expect(try await store.relations(ticketId: blocked.id).blockedBy.isEmpty)
        try await store.deleteTicket(id: other.id)
        #expect(try await store.relations(ticketId: blocker.id).related.isEmpty, "deleting a ticket removes its relations")
    }

    @Test func blockingCyclesAndSelfRelationsAreRejected() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let a = try await store.task("a", in: project)
        let b = try await store.task("b", in: project)
        let c = try await store.task("c", in: project)
        try await store.addRelation(from: a.id, to: b.id, type: .blocks)
        try await store.addRelation(from: b.id, to: c.id, type: .blocks)
        let cycle = await failure { _ = try await store.addRelation(from: c.id, to: a.id, type: .blocks) }
        #expect(cycle?.code == .invalidArgument)
        let selfRelation = await failure { _ = try await store.addRelation(from: a.id, to: a.id, type: .related) }
        #expect(selfRelation?.code == .invalidArgument)
        // Non-blocking relations may loop.
        try await store.addRelation(from: c.id, to: a.id, type: .related)
    }

    // MARK: Milestones

    @Test func milestonesBelongToProjectsAndTickets() async throws {
        let store = try makeStore()
        let a = try await store.createProject(name: "A")
        let b = try await store.createProject(name: "B")
        let beta = try await store.createMilestone(projectId: a.id, name: "Beta", targetDate: Date(timeIntervalSince1970: 1_800_000_000))
        let launch = try await store.createMilestone(projectId: a.id, name: "Launch")
        #expect(try await store.milestones(projectId: a.id).map(\.name) == ["Beta", "Launch"])
        #expect(try await store.resolveMilestone("LAUNCH", projectId: a.id).id == launch.id)

        let ticket = try await store.task("t", in: a)
        let assigned = try await store.updateTicket(id: ticket.id, TicketPatch(milestoneId: .set(beta.id)))
        #expect(assigned.milestoneId == beta.id)
        #expect(try await store.ticketSummary(id: ticket.id).milestoneName == "Beta")
        #expect(try await store.tickets(matching: TicketQuery(milestoneId: beta.id)).map(\.ticket.id) == [ticket.id])

        let other = try await store.milestone(id: beta.id)
        let foreign = try await store.task("x", in: b)
        let wrong = await failure { _ = try await store.updateTicket(id: foreign.id, TicketPatch(milestoneId: .set(other.id))) }
        #expect(wrong?.code == .invalidArgument)

        let moved = try await store.updateTicket(id: ticket.id, TicketPatch(projectId: b.id))
        #expect(moved.milestoneId == nil, "moving to another project clears the milestone")
        try await store.updateTicket(id: ticket.id, TicketPatch(projectId: a.id, milestoneId: .set(beta.id)))
        try await store.deleteMilestone(id: beta.id)
        #expect(try await store.ticket(id: ticket.id).milestoneId == nil)
    }

    // MARK: Comments

    @Test func repliesPointAtTheirParentOnTheSameTicket() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let one = try await store.task("one", in: project)
        let two = try await store.task("two", in: project)
        let root = try await store.addComment(ticketId: one.id, body: "root", author: .user, authorName: "Sam")
        let reply = try await store.addComment(ticketId: one.id, body: "reply", author: .agent, parentId: root.id)
        #expect(reply.parentId == root.id && root.authorName == "Sam")
        let wrong = await failure { _ = try await store.addComment(ticketId: two.id, body: "x", author: .user, parentId: root.id) }
        #expect(wrong?.code == .invalidArgument)
        let edited = try await store.updateComment(id: root.id, body: "root (edited)")
        #expect(edited.updatedAt != nil)
        try await store.deleteTicket(id: one.id)
        #expect(try await store.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM comment") } == 0)
    }

    // MARK: Attachments

    @Test func linksAndFilesAreStoredNextToTheDatabase() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A")
        let ticket = try await store.task("t", in: project)

        let link = try await store.addLink(ticketId: ticket.id, title: nil, url: "https://github.com/x/y/pull/1")
        #expect(link.title == "github.com" && link.kind == .link)
        let bad = await failure { _ = try await store.addLink(ticketId: ticket.id, title: nil, url: "not a url") }
        #expect(bad?.code == .invalidArgument)

        let file = try await store.addFile(ticketId: ticket.id, data: Data("hello".utf8), filename: "notes/..//my file.png")
        #expect(file.kind == .file && file.size == 5 && file.isImage)
        let url = try #require(store.fileURL(for: file))
        #expect(url.path.hasPrefix(store.attachmentsDirectory.path))
        #expect(try Data(contentsOf: url) == Data("hello".utf8))
        #expect(!file.path!.contains(".."), "filenames are sanitized")
        #expect(try await store.attachments(ticketId: ticket.id).count == 2)

        try await store.removeAttachment(id: file.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let kept = try await store.addFile(ticketId: ticket.id, data: Data("x".utf8), filename: "a.txt")
        let keptURL = try #require(store.fileURL(for: kept))
        try await store.deleteTicket(id: ticket.id)
        #expect(!FileManager.default.fileExists(atPath: keptURL.path), "deleting a ticket deletes its files")
    }

    // MARK: Timestamps and icons

    @Test func projectIconsCanBeSetAndCleared() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "A", icon: "🎸")
        #expect(project.icon == "🎸")
        #expect(try await store.updateProject(id: project.id, icon: "").icon == nil)
        #expect(try await store.updateProject(id: project.id, icon: "hifispeaker").icon == "hifispeaker")
        #expect(ProjectDTO(project).icon == "🎸")
    }

    @Test func creatingStartedOrClosedTicketsSetsTheirDates() async throws {
        let clock = TestClock()
        let store = try makeStore(now: clock.callback)
        let project = try await store.createProject(name: "A")
        let doing = try await store.task("doing", in: project, status: .inProgress)
        #expect(doing.startedAt == clock.now && doing.completedAt == nil)
        let done = try await store.task("done", in: project, status: .done)
        #expect(done.completedAt == clock.now && done.startedAt == nil)
        let canceled = try await store.task("canceled", in: project, status: .canceled)
        #expect(canceled.canceledAt == clock.now && canceled.completedAt == nil)
    }
}
