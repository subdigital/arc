import ArcCore
import Foundation

func temporaryDatabasePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("arc-app-tests-\(UUID().uuidString)")
        .appendingPathComponent("arc.sqlite")
        .path
}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return condition()
}
