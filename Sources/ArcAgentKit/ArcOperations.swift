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

    public func createProject(name: String, description: String? = nil, color: String? = nil, icon: String? = nil) async throws -> ProjectDTO {
        let project = try await store.createProject(name: name, description: description ?? "", color: color, icon: icon)
        didWrite()
        return ProjectDTO(project)
    }

    public func updateProject(_ reference: String, name: String? = nil, description: String? = nil, color: String? = nil, icon: String? = nil) async throws -> ProjectDTO {
        let current = try await store.resolveProject(reference)
        let project = try await store.updateProject(id: current.id, name: name, description: description, color: color, icon: icon)
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
        if let names = request.label?.values, !names.isEmpty {
            let known = try await store.labels()
            query.labelIds = Set(try names.map { name in
                guard let label = known.first(where: { $0.nameKey == name.trimmingCharacters(in: .whitespaces).lowercased() }) else {
                    throw ArcError.notFound("Label '\(name)' not found. Existing labels: \(known.map(\.name).joined(separator: ", ")).")
                }
                return label.id
            })
        }
        if let milestone = request.milestone {
            guard let project = request.project else { throw ArcError.invalidArgument("Filtering by milestone needs a project.") }
            query.milestoneId = try await store.resolveMilestone(milestone, projectId: try await store.resolveProject(project).id).id
        }
        query.text = request.query

        let rows = try await store.tickets(matching: query)
        return rows.map { TicketDTO($0, projectId: $0.ticket.projectId) }
    }

    public func getTicket(_ reference: String) async throws -> TicketDTO {
        TicketDTO(try await store.ticketDetail(reference: reference), attachmentsDirectory: store.attachmentsDirectory)
    }

    public func createTicket(_ request: CreateTicketRequest) async throws -> TicketDTO {
        var new = NewTicket(title: request.title)
        if let project = request.project { new.projectId = try await store.resolveProject(project).id }
        if let parent = request.parent { new.parentId = try await store.resolveTicket(parent).id }
        if let description = request.description { new.description = description }
        if let status = request.status { new.status = try Reference.status(status) }
        if let priority = request.priority { new.priority = try Reference.priority(priority) }

        let ticket = try await store.createTicket(new)
        if let names = request.labels?.values, !names.isEmpty { try await store.setLabels(ticketId: ticket.id, names: names) }
        if let milestone = request.milestone, !isNone(milestone) {
            let found = try await store.resolveMilestone(milestone, projectId: ticket.projectId)
            try await store.updateTicket(id: ticket.id, TicketPatch(milestoneId: .set(found.id)))
        }
        didWrite()
        return try await detail(ticket.id)
    }

    public func updateTicket(_ request: UpdateTicketRequest) async throws -> TicketDTO {
        let current = try await store.resolveTicket(request.ticket)
        var patch = TicketPatch(title: request.title, description: request.description)
        if let status = request.status { patch.status = try Reference.status(status) }
        if let priority = request.priority { patch.priority = try Reference.priority(priority) }
        if let project = request.project { patch.projectId = try await store.resolveProject(project).id }
        if let parent = request.parent { patch.parentId = .set(try await resolveOptionalTicket(parent)) }

        // Milestones are resolved against the project the ticket will be in.
        if let milestone = request.milestone {
            if isNone(milestone) {
                patch.milestoneId = .set(nil)
            } else {
                let projectID = patch.projectId ?? current.projectId
                patch.milestoneId = .set(try await store.resolveMilestone(milestone, projectId: projectID).id)
            }
        }
        let ticket = try await store.updateTicket(id: current.id, patch)
        if let names = request.labels?.values { try await store.setLabels(ticketId: ticket.id, names: names) }
        didWrite()
        return try await detail(ticket.id)
    }

    public func addRelation(_ request: RelationRequest) async throws -> TicketDTO {
        try await changeRelation(request, add: true)
    }

    public func removeRelation(_ request: RelationRequest) async throws -> TicketDTO {
        try await changeRelation(request, add: false)
    }

    private func changeRelation(_ request: RelationRequest, add: Bool) async throws -> TicketDTO {
        let ticket = try await store.resolveTicket(request.ticket)
        let other = try await store.resolveTicket(request.other)
        let (from, to, type): (String, String, RelationType)
        switch Reference.normalize(request.relation) {
        case "blocks": (from, to, type) = (ticket.id, other.id, .blocks)
        case "blocked_by": (from, to, type) = (other.id, ticket.id, .blocks)
        case "related", "related_to": (from, to, type) = (ticket.id, other.id, .related)
        case "duplicate_of", "duplicates": (from, to, type) = (ticket.id, other.id, .duplicate)
        case "duplicated_by": (from, to, type) = (other.id, ticket.id, .duplicate)
        default:
            throw ArcError.invalidArgument("Unknown relation '\(request.relation)'. Use blocks, blocked_by, related, duplicate_of or duplicated_by.")
        }
        if add {
            try await store.addRelation(from: from, to: to, type: type)
        } else {
            try await store.removeRelation(from: from, to: to, type: type)
        }
        didWrite()
        return try await detail(ticket.id)
    }

    public func addLink(_ request: AddLinkRequest) async throws -> TicketDTO {
        let ticket = try await store.resolveTicket(request.ticket)
        try await store.addLink(ticketId: ticket.id, title: request.title, url: request.url)
        didWrite()
        return try await detail(ticket.id)
    }

    public func addFile(ticket reference: String, path: String) async throws -> TicketDTO {
        let ticket = try await store.resolveTicket(reference)
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw ArcError.notFound("No readable file at \(url.path).") }
        try await store.addFile(ticketId: ticket.id, file: url)
        didWrite()
        return try await detail(ticket.id)
    }

    // MARK: Milestones

    public func listMilestones(project: String) async throws -> [MilestoneDTO] {
        let project = try await store.resolveProject(project)
        return try await store.milestones(projectId: project.id).map(MilestoneDTO.init)
    }

    public func createMilestone(project: String, name: String, description: String? = nil, targetDate: Date? = nil) async throws -> MilestoneDTO {
        let project = try await store.resolveProject(project)
        let milestone = try await store.createMilestone(projectId: project.id, name: name, description: description ?? "", targetDate: targetDate)
        didWrite()
        return MilestoneDTO(milestone)
    }

    public func listLabels() async throws -> [LabelDTO] {
        try await store.labels().map(LabelDTO.init)
    }

    private func detail(_ id: String) async throws -> TicketDTO {
        TicketDTO(try await store.ticketDetail(id: id), attachmentsDirectory: store.attachmentsDirectory)
    }

    private func isNone(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || trimmed == "none"
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
