import Foundation
import Testing
@testable import ArcCore

@Suite struct ConcurrencyTests {
    @Test func twoStoresOnTheSameFileAllocateUniqueNumbers() async throws {
        let path = temporaryDatabasePath()
        let first = try ArcStore(path: path)
        let second = try ArcStore(path: path)
        let project = try await first.createProject(name: "Shared")
        let projectId = project.id

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    _ = try await first.createTicket(NewTicket(title: "first \(index)", projectId: projectId))
                }
                group.addTask {
                    _ = try await second.createTicket(NewTicket(title: "second \(index)", projectId: projectId))
                }
            }
            try await group.waitForAll()
        }

        let all = try await first.tickets(matching: TicketQuery(includeClosed: true))
        #expect(all.count == 200)
        #expect(Set(all.map(\.ticket.number)) == Set(1...200))
    }

    @Test func writesFromOneStoreAreVisibleToTheOther() async throws {
        let path = temporaryDatabasePath()
        let writer = try ArcStore(path: path)
        let reader = try ArcStore(path: path)
        let project = try await writer.createProject(name: "A")
        #expect(try await reader.projects().map(\.id) == [project.id])
    }
}
