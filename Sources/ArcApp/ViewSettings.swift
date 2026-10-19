import ArcCore
import Foundation

/// What the content area is showing; the key for per-entry view settings.
enum Scope: Hashable, Sendable {
    case allTasks
    case project(String)
    case epic(String)

    var storageKey: String {
        switch self {
        case .allTasks: "all"
        case .project(let id): "project:\(id)"
        case .epic(let id): "epic:\(id)"
        }
    }
}

enum TicketLayout: String, Codable, CaseIterable, Sendable {
    case list, board

    var toggled: TicketLayout { self == .list ? .board : .list }
}

/// Layout and filters for one sidebar entry. Remembered across launches.
struct ViewSettings: Codable, Equatable, Sendable {
    var layout: TicketLayout = .list
    /// All Tasks only: restrict to these projects (empty = every active project).
    var projectFilter: Set<String> = []
    var epicFilter: String?
    var priorityFilter: Set<Int> = []
    var showSubtasks = true
    /// Board only: whether the Canceled column is shown.
    var showCanceled = false
    /// List groups the user has collapsed. Done and Canceled start collapsed.
    var collapsedStatuses: Set<TicketStatus> = [.done, .canceled]

    var hasActiveFilters: Bool {
        !projectFilter.isEmpty || epicFilter != nil || !priorityFilter.isEmpty || !showSubtasks
    }
}

/// Persists `ViewSettings` per scope as one JSON dictionary in `UserDefaults`.
struct ViewSettingsStore {
    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String = "arc.viewSettings.v1") {
        self.defaults = defaults
        self.key = key
    }

    private func load() -> [String: ViewSettings] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ViewSettings].self, from: data)
        else { return [:] }
        return decoded
    }

    func settings(for scope: Scope) -> ViewSettings {
        load()[scope.storageKey] ?? ViewSettings()
    }

    func save(_ settings: ViewSettings, for scope: Scope) {
        var all = load()
        all[scope.storageKey] = settings
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }
}
