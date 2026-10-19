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
    var ticketID: String
    var kind: Kind

    var id: String { "\(ticketID)-\(kind)" }
}

@MainActor
@Observable
final class AppModel {
    let store: ArcStore
    let feed: ChangeFeed
    let settingsStore: ViewSettingsStore

    var selection: SidebarSelection = .allTasks {
        didSet { if selection != oldValue { path = [] } }
    }
    var path: [Route] = []

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
    var pendingDeletion: String?

    /// Bumped to ask the visible ticket list to toggle between list and board.
    private(set) var layoutToggleRequests = 0

    init(store: ArcStore, settingsStore: ViewSettingsStore = ViewSettingsStore()) {
        self.store = store
        self.settingsStore = settingsStore
        self.feed = ChangeFeed(store: store)
    }

    func start() {
        feed.start()
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
        if await perform({ try await store.deleteTicket(id: id) }) != nil {
            path.removeAll { $0 == .ticket(id) }
            if selectedTicketID == id { selectedTicketID = nil }
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

struct CreationRequest: Identifiable {
    let id = UUID()
    var projectID: String?
    var kind: TicketKind = .task
    var parentID: String?
    var epicID: String?
}

struct ProjectEditorRequest: Identifiable {
    enum Mode { case create, rename(Project) }
    let id = UUID()
    var mode: Mode
}
