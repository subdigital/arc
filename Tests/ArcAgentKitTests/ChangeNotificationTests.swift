import ArcCore
import Foundation
import Testing

@Suite struct ChangeNotificationTests {
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    @Test func cliWritePostsDistributedNotification() async throws {
        let db = temporaryDatabasePath()
        let flag = Flag()
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: ArcChange.notificationName, object: nil, queue: OperationQueue()
        ) { _ in flag.bump() }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        try runArc(["project", "create", "Website"], db: db)

        var waited = 0.0
        while flag.value == 0 && waited < 5 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 0.05
        }
        #expect(flag.value >= 1, "no notification observed after a CLI write")
    }
}
