import ArcCore
import Foundation
import Testing
@testable import ArcApp

@MainActor
@Suite struct ChangeFeedTests {
    @Test func writeFromAnotherStoreTicksTheFeedWithinTwoSeconds() async throws {
        let path = temporaryDatabasePath()
        let app = try ArcStore(path: path)
        let agent = try ArcStore(path: path)
        let feed = ChangeFeed(store: app, isActive: { true })
        feed.start()
        defer { feed.stop() }

        try await Task.sleep(for: .milliseconds(200)) // let the poller take its baseline
        let before = feed.generation
        let started = ContinuousClock.now
        _ = try await agent.createProject(name: "From the agent")

        let ticked = await waitUntil(timeout: .seconds(2)) { feed.generation > before }
        #expect(ticked, "the feed did not tick within 2 s of an external write")
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test func inProcessWriteTicksQuickly() async throws {
        let store = try ArcStore(path: temporaryDatabasePath())
        let feed = ChangeFeed(store: store, pollInterval: .seconds(60), isActive: { true })
        feed.start()
        defer { feed.stop() }

        let before = feed.generation
        _ = try await store.createProject(name: "Local")
        #expect(await waitUntil(timeout: .milliseconds(800)) { feed.generation > before })
    }

    @Test func distributedNotificationTicksTheFeed() async throws {
        let store = try ArcStore(path: temporaryDatabasePath())
        let feed = ChangeFeed(store: store, pollInterval: .seconds(60), isActive: { true })
        feed.start()
        defer { feed.stop() }

        let before = feed.generation
        ArcChange.post()
        #expect(await waitUntil(timeout: .seconds(2)) { feed.generation > before })
    }

    @Test func burstsAreCoalesced() async throws {
        let store = try ArcStore(path: temporaryDatabasePath())
        let feed = ChangeFeed(store: store, pollInterval: .seconds(60), debounce: .milliseconds(150), listensForSystemSignals: false, isActive: { true })
        feed.start()
        defer { feed.stop() }

        let before = feed.generation
        for _ in 0..<5 { feed.signal() }
        #expect(await waitUntil(timeout: .seconds(1)) { feed.generation > before })
        try await Task.sleep(for: .milliseconds(300))
        #expect(feed.generation == before + 1)
    }

    @Test func pollingPausesWhileInactive() async throws {
        let path = temporaryDatabasePath()
        let app = try ArcStore(path: path)
        let agent = try ArcStore(path: path)
        let feed = ChangeFeed(store: app, pollInterval: .milliseconds(100), listensForSystemSignals: false, isActive: { false })
        feed.start()
        defer { feed.stop() }

        try await Task.sleep(for: .milliseconds(200))
        let before = feed.generation
        _ = try await agent.createProject(name: "Quiet")
        try await Task.sleep(for: .milliseconds(600))
        #expect(feed.generation == before)
    }
}
