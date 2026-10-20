import AppKit
import ArcCore
import Foundation
import Observation

/// What the sidebar has selected.
enum SidebarSelection: Hashable, Sendable {
    case allTasks
    case epics
    case project(String)

    var scope: Scope? {
        switch self {
        case .allTasks: .allTasks
        case .epics: nil
        case .project(let id): .project(id)
        }
    }
}

/// Pushed onto the content `NavigationStack`.
enum Route: Hashable, Sendable {
    case ticket(String)
    case epic(String)
}

/// Which ticket property picker the keyboard asked for (S / P).
struct PickerRequest: Equatable, Identifiable {
    enum Kind { case status, priority }
    var ticketIDs: [String]
    var kind: Kind

    var id: String { "\(ticketIDs.joined(separator: ","))-\(kind)" }
}

/// A place in the app's navigation history.
struct NavigationState: Equatable {
    var selection: SidebarSelection
    var path: [Route]
}

@MainActor
@Observable
final class AppModel {
    let store: ArcStore
    let feed: ChangeFeed
    let settingsStore: ViewSettingsStore

    var selection: SidebarSelection = .allTasks {
        didSet {
            if selection != oldValue { path = []; checkedTicketIDs = [] }
            recordNavigation()
        }
    }
    var path: [Route] = [] {
        didSet { recordNavigation() }
    }

    // MARK: Navigation history (Back / Forward)

    @ObservationIgnored private var history = [NavigationState(selection: .allTasks, path: [])]
    @ObservationIgnored private var historyIndex = 0
    @ObservationIgnored private var isRestoringHistory = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    private func recordNavigation() {
        guard !isRestoringHistory else { return }
        let state = NavigationState(selection: selection, path: path)
        guard state != history[historyIndex] else { return }
        history.removeSubrange((historyIndex + 1)...)
        history.append(state)
        if history.count > 200 { history.removeFirst() }
        historyIndex = history.count - 1
        updateHistoryFlags()
    }

    private func updateHistoryFlags() {
        canGoBack = historyIndex > 0
        canGoForward = historyIndex < history.count - 1
    }

    func navigateBack() { restore(historyIndex - 1) }
    func navigateForward() { restore(historyIndex + 1) }

    private func restore(_ index: Int) {
        guard history.indices.contains(index) else { return }
        historyIndex = index
        isRestoringHistory = true
        selection = history[index].selection
        path = history[index].path
        isRestoringHistory = false
        updateHistoryFlags()
    }

    private(set) var projects: [Project] = []
    private(set) var archivedProjects: [Project] = []
    /// Numbers of every existing ticket: only these `ARC-n` references become links.
    private(set) var knownTicketNumbers: Set<Int> = []
    private(set) var hasLoaded = false
    /// Epics by project id, for the Epic submenu and pickers.
    private(set) var epicsByProject: [String: [Ticket]] = [:]

    var creation: CreationRequest?
    var projectEditor: ProjectEditorRequest?
    var error: PresentedError?
    var picker: PickerRequest?
    /// The ticket the keyboard (or a click) last targeted in a list or board.
    var selectedTicketID: String?
    var pendingDeletionIDs: [String] = []
    /// Convenience for the single-ticket call sites.
    var pendingDeletion: String? {
        get { pendingDeletionIDs.count == 1 ? pendingDeletionIDs.first : nil }
        set { pendingDeletionIDs = newValue.map { [$0] } ?? [] }
    }
    /// Rows ticked for bulk actions (the cursor is `selectedTicketID`).
    var checkedTicketIDs: Set<String> = []
    @ObservationIgnored var selectionAnchor: String?
    var showingShortcuts = false
    private(set) var toast: Toast?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    /// Bumped to ask the visible ticket list to toggle between list and board.
    private(set) var layoutToggleRequests = 0

    init(store: ArcStore, settingsStore: ViewSettingsStore = ViewSettingsStore()) {
        self.store = store
        self.settingsStore = settingsStore
        self.feed = ChangeFeed(store: store)
    }

    func start() {
        feed.start()
        installKeyMonitor()
    }

    /// Window-level shortcuts that must work whatever has keyboard focus (and never beep):
    /// C, ?, and browser-style Back/Forward on ⌘← / ⌘→.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            nonisolated(unsafe) let event = event // delivered on the main thread
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window = NSApp.keyWindow, window.sheetParent == nil, window.attachedSheet == nil,
              window.firstResponder as? NSText == nil, !showingShortcuts, creation == nil, projectEditor == nil
        else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            switch event.keyCode {
            case 123: navigateBack(); return true      // ⌘←
            case 124: navigateForward(); return true   // ⌘→
            default: return false
            }
        }
        guard flags.subtracting(.shift).isEmpty, let characters = event.characters else { return false }
        switch characters {
        case "c" where flags.isEmpty:
            var projectID: String?
            if case .project(let id) = selection { projectID = id }
            creation = CreationRequest(projectID: projectID)
            return true
        case "?":
            showingShortcuts = true
            return true
        default:
            return false
        }
    }

    /// Shows a short confirmation in the corner of the window.
    func showToast(_ message: String) {
        let toast = Toast(message: message)
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }

    func requestLayoutToggle() { layoutToggleRequests += 1 }

    // MARK: Loading

    func reload() async {
        do {
            let allProjects = try await store.projects(includeArchived: true)
            projects = allProjects.filter { !$0.isArchived }
            archivedProjects = allProjects.filter(\.isArchived)
            knownTicketNumbers = try await store.ticketNumbers()
            let epics = try await store.tickets(matching: TicketQuery(
                kinds: [.epic], includeClosed: true, includeArchivedProjects: true
            ))
            epicsByProject = Dictionary(grouping: epics.map(\.ticket), by: \.projectId)
            hasLoaded = true

            // A selected project that was deleted or archived elsewhere falls back to All Tasks.
            if case .project(let id) = selection, !projects.contains(where: { $0.id == id }) {
                selection = .allTasks
            }
        } catch {
            present(error)
        }
    }

    func project(id: String) -> Project? {
        projects.first { $0.id == id } ?? archivedProjects.first { $0.id == id }
    }

    // MARK: Navigation

    func open(ticket id: String) {
        if path.last != .ticket(id) { path.append(.ticket(id)) }
    }

    func open(ticketNumber number: Int) async {
        do {
            let ticket = try await store.resolveTicket(String(number))
            open(ticket: ticket.id)
        } catch {
            present(error)
        }
    }

    func goBack() {
        if !path.isEmpty { path.removeLast() }
    }

    // MARK: Errors

    func present(_ error: Error) {
        let message = (error as? ArcError)?.message ?? error.localizedDescription
        self.error = PresentedError(message: message)
    }

    /// Runs a store operation and reports failure in an alert instead of throwing.
    @discardableResult
    func perform<T>(_ operation: () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            present(error)
            return nil
        }
    }

    // MARK: Common ticket actions (shared by list, board, context menus and keyboard)

    func setStatus(_ status: TicketStatus, for id: String) async {
        await perform { try await store.updateTicket(id: id, TicketPatch(status: status)) }
    }

    func setPriority(_ priority: TicketPriority, for id: String) async {
        await perform { try await store.updateTicket(id: id, TicketPatch(priority: priority)) }
    }

    func setEpic(_ epicID: String?, for id: String) async {
        await perform { try await store.updateTicket(id: id, TicketPatch(epicId: .set(epicID))) }
    }

    func move(_ id: String, toProject projectID: String) async {
        await perform { try await store.updateTicket(id: id, TicketPatch(projectId: projectID)) }
    }

    func delete(ticket id: String) async {
        checkedTicketIDs.remove(id)
        if await perform({ try await store.deleteTicket(id: id) }) != nil {
            path.removeAll { $0 == .ticket(id) }
            if selectedTicketID == id { selectedTicketID = nil }
        }
    }

    // MARK: Multi-select

    func toggleChecked(_ id: String) {
        if checkedTicketIDs.contains(id) { checkedTicketIDs.remove(id) } else { checkedTicketIDs.insert(id) }
        selectionAnchor = id
    }

    /// Ticks every row between the anchor and `id` (inclusive), in display order.
    func checkRange(to id: String, order: [String]) {
        guard let anchor = selectionAnchor ?? selectedTicketID,
              let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id)
        else { return toggleChecked(id) }
        checkedTicketIDs.formUnion(order[min(from, to)...max(from, to)])
    }

    /// The tickets an action should apply to: the ticked rows, or else the cursor row.
    var actionTargets: [String] {
        if !checkedTicketIDs.isEmpty { return Array(checkedTicketIDs) }
        return selectedTicketID.map { [$0] } ?? []
    }

    /// The tickets a right-click on `id` should affect: all ticked rows when `id` is one of them.
    func contextTargets(for id: String) -> [String] {
        checkedTicketIDs.contains(id) ? Array(checkedTicketIDs) : [id]
    }

    /// Applies `patch` to each ticket; reports how many could not be changed.
    func bulkUpdate(_ ids: [String], _ patch: TicketPatch, done: String) async {
        var failures: [String] = []
        for id in ids {
            do {
                try await store.updateTicket(id: id, patch)
            } catch {
                failures.append((error as? ArcError)?.message ?? error.localizedDescription)
            }
        }
        let succeeded = ids.count - failures.count
        if succeeded > 0 { showToast("\(done) \(succeeded) \(succeeded == 1 ? "ticket" : "tickets")") }
        if let first = failures.first {
            present(ArcError.invalidArgument(failures.count == 1 ? first : "\(failures.count) tickets could not be changed. \(first)"))
        }
    }

    func bulkDelete(_ ids: [String]) async {
        var deleted = 0
        for id in ids {
            if await perform({ try await store.deleteTicket(id: id) }) != nil { deleted += 1 }
            path.removeAll { $0 == .ticket(id) }
        }
        checkedTicketIDs.subtract(ids)
        if let selected = selectedTicketID, ids.contains(selected) { selectedTicketID = nil }
        if deleted > 0 { showToast("Deleted \(deleted) \(deleted == 1 ? "ticket" : "tickets")") }
    }

    /// Applies a status/priority picked from a `PickerPopover` to every ticket in the request.
    func applyPick(_ index: Int, for request: PickerRequest) async {
        switch request.kind {
        case .status:
            guard let status = TicketStatus.allCases[safe: index] else { return }
            await bulkUpdate(request.ticketIDs, TicketPatch(status: status), done: "Updated")
        case .priority:
            guard let priority = TicketPriority.menuOrder[safe: index] else { return }
            await bulkUpdate(request.ticketIDs, TicketPatch(priority: priority), done: "Updated")
        }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct PresentedError: Identifiable {
    let id = UUID()
    let message: String
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
}

struct CreationRequest: Identifiable {
    let id = UUID()
    var projectID: String?
    var kind: TicketKind = .task
    var parentID: String?
    var epicID: String?
    var status: TicketStatus = .todo
    var priority: TicketPriority = .none
    /// Set when the form was reopened by "Create more": the toggle starts on.
    var createMore = false
}

struct ProjectEditorRequest: Identifiable {
    enum Mode { case create, rename(Project) }
    let id = UUID()
    var mode: Mode
}
