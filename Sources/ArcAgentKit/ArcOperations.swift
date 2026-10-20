import ArcCore
import Foundation

/// Everything the CLI and the MCP server can do, expressed with human-style references and
/// returning DTOs. Both front ends call this, so they accept the same inputs and validate identically.
public struct ArcOperations: Sendable {
    public let store: ArcStore
    private let didWrite: @Sendable () -> Void

    /// `didWrite` runs after each successful write; by default it posts the distributed change notification.
    public init(store: ArcStore, didWrite: @escaping @Sendable () -> Void = { ArcChange.post() }) {
        self.store = store
        self.didWrite = didWrite
    }

    // MARK: Projects

    public func listProjects(includeArchived: Bool = false) async throws -> [ProjectDTO] {
        try await store.projects(includeArchived: includeArchived).map(ProjectDTO.init)
    }

    public func createProject(name: String, description: String? = nil, color: String? = nil) async throws -> ProjectDTO {
        let project = try await store.createProject(name: name, description: description ?? "", color: color)
        didWrite()
        return ProjectDTO(project)
    }

    public func updateProject(_ reference: String, name: String? = nil, description: String? = nil, color: String? = nil) async throws -> ProjectDTO {
        let current = try await store.resolveProject(reference)
        let project = try await store.updateProject(id: current.id, name: name, description: description, color: color)
        didWrite()
        return ProjectDTO(project)
    }

    public func setProjectArchived(_ reference: String, archived: Bool) async throws -> ProjectDTO {
        let current = try await store.resolveProject(reference)
        let project = try await store.setProjectArchived(id: current.id, archived: archived)
        didWrite()
        return ProjectDTO(project)
    }

    // MARK: Tickets

    public func listTickets(_ request: ListTicketsRequest = .init()) async throws -> [TicketDTO] {
        var query = TicketQuery(includeClosed: request.includeClosed ?? false, limit: request.limit)
        if let limit = request.limit, limit < 0 {
            throw ArcError.invalidArgument("limit must not be negative.")
        }
        if let project = request.project {
            query.projectIds = [try await store.resolveProject(project).id]
        }
        query.statuses = Set(try (request.status?.values ?? []).map(Reference.status))
        query.priorities = Set(try (request.priority?.values ?? []).map(Reference.priority))
        if let parent = request.parent { query.parentId = try await store.resolveTicket(parent).id }
        query.text = request.query

        let rows = try await store.tickets(matching: query)
        return rows.map { TicketDTO($0, projectId: $0.ticket.projectId) }
    }

    public func getTicket(_ reference: String) async throws -> TicketDTO {
        TicketDTO(try await store.ticketDetail(reference: reference))
    }

    public func createTicket(_ request: CreateTicketRequest) async throws -> TicketDTO {
        var new = NewTicket(title: request.title)
        if let project = request.project { new.projectId = try await store.resolveProject(project).id }
        if let parent = request.parent { new.parentId = try await store.resolveTicket(parent).id }
        if let description = request.description { new.description = description }
        if let status = request.status { new.status = try Reference.status(status) }
        if let priority = request.priority { new.priority = try Reference.priority(priority) }

        let ticket = try await store.createTicket(new)
        didWrite()
        return TicketDTO(try await store.ticketDetail(id: ticket.id))
    }

    public func updateTicket(_ request: UpdateTicketRequest) async throws -> TicketDTO {
        let current = try await store.resolveTicket(request.ticket)
        var patch = TicketPatch(title: request.title, description: request.description)
        if let status = request.status { patch.status = try Reference.status(status) }
        if let priority = request.priority { patch.priority = try Reference.priority(priority) }
        if let project = request.project { patch.projectId = try await store.resolveProject(project).id }
        if let parent = request.parent { patch.parentId = .set(try await resolveOptionalTicket(parent)) }

        let ticket = try await store.updateTicket(id: current.id, patch)
        didWrite()
        return TicketDTO(try await store.ticketDetail(id: ticket.id))
    }

    public func addComment(ticket reference: String, body: String) async throws -> CommentResultDTO {
        let ticket = try await store.resolveTicket(reference)
        let comment = try await store.addComment(ticketId: ticket.id, body: body, author: .agent)
        didWrite()
        return CommentResultDTO(ticket: ticket.identifier, comment: CommentDTO(comment))
    }

    public func deleteTicket(_ reference: String) async throws -> DeletedDTO {
        let ticket = try await store.resolveTicket(reference)
        try await store.deleteTicket(id: ticket.id)
        didWrite()
        return DeletedDTO(identifier: ticket.identifier, deleted: true)
    }

    private func resolveOptionalTicket(_ reference: String) async throws -> String? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "none" { return nil }
        return try await store.resolveTicket(trimmed).id
    }
}
