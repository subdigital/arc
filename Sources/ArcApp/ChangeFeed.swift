import AppKit
import ArcCore
import Foundation
import GRDB
import Observation

/// Tells the UI when the database changed, no matter who changed it (design.md §5):
/// 1. commits made in this process (GRDB region observation),
/// 2. the distributed notification `arc` posts after each write,
/// 3. a once-a-second `PRAGMA data_version` poll, which catches everything else.
/// Signals are coalesced: `generation` goes up once per 100 ms burst. Views refetch when it changes.
@MainActor
@Observable
final class ChangeFeed {
    private(set) var generation = 0

    @ObservationIgnored private let store: ArcStore
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let isActive: @MainActor () -> Bool
    @ObservationIgnored private let listensForSystemSignals: Bool
    @ObservationIgnored private var observation: AnyDatabaseCancellable?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var versionConnection: DatabaseQueue?
    @ObservationIgnored private var lastVersion: Int?

    init(
        store: ArcStore,
        pollInterval: Duration = .seconds(1),
        debounce: Duration = .milliseconds(100),
        listensForSystemSignals: Bool = true,
        isActive: @escaping @MainActor () -> Bool = { NSApp?.isActive ?? true }
    ) {
        self.store = store
        self.pollInterval = pollInterval
        self.debounce = debounce
        self.listensForSystemSignals = listensForSystemSignals
        self.isActive = isActive
    }

    func start() {
        guard pollTask == nil else { return }

        observation = DatabaseRegionObservation(tracking: .fullDatabase).start(
            in: store.pool,
            onError: { _ in },
            onChange: { [weak self] _ in
                Task { @MainActor in self?.signal() }
            }
        )

        // The distributed notification is machine-wide, so anything else running (other tests, a real
        // Arc, the CLI) can post it. Tests that assert exact tick counts turn this off.
        if listensForSystemSignals {
            tokens.append(DistributedNotificationCenter.default().addObserver(
                forName: ArcChange.notificationName, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.signal() }
            })
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkNow() }
            })
        }

        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(5)
        versionConnection = try? DatabaseQueue(path: store.path, configuration: configuration)

        pollTask = Task { [weak self] in
            await self?.baseline()
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.isActive() { await self.poll() }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        observation = nil
        for token in tokens {
            DistributedNotificationCenter.default().removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        tokens = []
        versionConnection = nil
        lastVersion = nil
    }

    /// Requests a refresh; bursts within the debounce window produce one tick.
    func signal() {
        guard debounceTask == nil else { return }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounce ?? .milliseconds(100))
            guard let self, !Task.isCancelled else { return }
            self.debounceTask = nil
            self.generation += 1
        }
    }

    /// Polls immediately (used when the app becomes active again).
    func checkNow() {
        Task { await poll() }
    }

    private func baseline() async {
        lastVersion = await readVersion()
    }

    private func poll() async {
        guard let version = await readVersion() else { return }
        defer { lastVersion = version }
        if let lastVersion, lastVersion != version { signal() }
    }

    private func readVersion() async -> Int? {
        guard let connection = versionConnection else { return nil }
        // Off the main actor: a busy database must never stall the UI.
        return await Task.detached {
            try? connection.read { try Int.fetchOne($0, sql: "PRAGMA data_version") }
        }.value
    }
}
