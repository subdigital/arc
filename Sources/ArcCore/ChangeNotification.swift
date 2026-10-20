import Foundation

/// Cross-process "the database changed" signal. Writers other than the app post it after each
/// successful write; the app listens for it (see design.md §5).
public enum ArcChange {
    public static let notificationName = Notification.Name("com.ficklebits.arc.databaseDidChange")

    /// Set (to anything) to skip the notification, e.g. so test processes do not wake unrelated listeners.
    public static let suppressEnvironmentKey = "ARC_NO_NOTIFY"

    public static func post() {
        if ProcessInfo.processInfo.environment[suppressEnvironmentKey] != nil { return }
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
