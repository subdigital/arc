import Foundation

/// Cross-process "the database changed" signal. Writers other than the app post it after each
/// successful write; the app listens for it (see design.md §5).
public enum ArcChange {
    public static let notificationName = Notification.Name("com.ficklebits.arc.databaseDidChange")

    public static func post() {
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
