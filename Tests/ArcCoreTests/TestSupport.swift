import Foundation
import GRDB
@testable import ArcCore

func temporaryDatabasePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("arc-tests-\(UUID().uuidString)")
        .appendingPathComponent("arc.sqlite")
        .path
}

func makeStore(now: @escaping @Sendable () -> Date = { Date() }) throws -> ArcStore {
    try ArcStore(path: temporaryDatabasePath(), now: now)
}

/// A clock the tests can advance.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }

    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval = 60) { lock.withLock { current = current.addingTimeInterval(seconds) } }
    var callback: @Sendable () -> Date { { [self] in now } }
}

extension ArcStore {
    @discardableResult
    func task(_ title: String, in project: Project, status: TicketStatus = .todo, epic: Ticket? = nil) async throws -> Ticket {
        try await createTicket(NewTicket(title: title, kind: .task, projectId: project.id, epicId: epic?.id, status: status))
    }

    @discardableResult
    func epic(_ title: String, in project: Project) async throws -> Ticket {
        try await createTicket(NewTicket(title: title, kind: .epic, projectId: project.id))
    }

    @discardableResult
    func subtask(_ title: String, of parent: Ticket) async throws -> Ticket {
        try await createTicket(NewTicket(title: title, kind: .subtask, parentId: parent.id))
    }

    func order(of status: TicketStatus) async throws -> [Int] {
        try await tickets(matching: TicketQuery(statuses: [status])).map(\.ticket.number)
    }
}
