import Foundation

/// Shared JSON settings so the CLI and the MCP server produce identical output.
public enum ArcJSON {
    public static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func string<T: Encodable>(_ value: T, pretty: Bool = false) throws -> String {
        String(decoding: try makeEncoder(pretty: pretty).encode(value), as: UTF8.self)
    }
}

public struct ProjectDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var color: String
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(_ project: Project) {
        id = project.id
        name = project.name
        description = project.description
        color = project.color
        archived = project.isArchived
        createdAt = project.createdAt
        updatedAt = project.updatedAt
    }
}

public struct ProjectRefDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
}

public struct TicketRefDTO: Codable, Sendable, Equatable {
    public var identifier: String
    public var title: String
    public var status: String

    public init(_ ticket: Ticket) {
        identifier = ticket.identifier
        title = ticket.title
        status = ticket.status.rawValue
    }

    public init(_ ref: TicketRef) {
        identifier = ref.identifier
        title = ref.title
        status = ref.status.rawValue
    }
}

public struct CommentDTO: Codable, Sendable, Equatable {
    public var id: String
    public var author: String
    public var body: String
    public var createdAt: Date

    public init(_ comment: Comment) {
        id = comment.id
        author = comment.author.rawValue
        body = comment.body
        createdAt = comment.createdAt
    }
}

public struct ChildProgressDTO: Codable, Sendable, Equatable {
    public var done: Int
    public var total: Int
}

/// One shape for every ticket-returning command. `parent` and `completedAt` are always
/// present (null when unset). List results leave out `description`, `children` and `comments`
/// entirely; `show` and writes include them.
public struct TicketDTO: Codable, Sendable, Equatable {
    public var identifier: String
    public var title: String
    public var description: String?
    public var status: String
    public var priority: String
    public var project: ProjectRefDTO
    public var parent: TicketRefDTO?
    public var childProgress: ChildProgressDTO?
    public var children: [TicketRefDTO]?
    public var comments: [CommentDTO]?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case identifier, title, description, status, priority, project, parent
        case childProgress, children, comments, createdAt, updatedAt, completedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(project, forKey: .project)
        try container.encode(parent, forKey: .parent)
        try container.encodeIfPresent(childProgress, forKey: .childProgress)
        try container.encodeIfPresent(children, forKey: .children)
        try container.encodeIfPresent(comments, forKey: .comments)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(completedAt, forKey: .completedAt)
    }

    public init(_ summary: TicketSummary, projectId: String) {
        let ticket = summary.ticket
        identifier = ticket.identifier
        title = ticket.title
        description = nil
        status = ticket.status.rawValue
        priority = ticket.priority.name
        project = ProjectRefDTO(id: projectId, name: summary.projectName)
        parent = summary.parent.map(TicketRefDTO.init)
        childProgress = summary.childCount > 0
            ? ChildProgressDTO(done: summary.childrenDone, total: summary.childCount)
            : nil
        children = nil
        comments = nil
        createdAt = ticket.createdAt
        updatedAt = ticket.updatedAt
        completedAt = ticket.completedAt
    }

    public init(_ detail: TicketDetail) {
        let ticket = detail.ticket
        identifier = ticket.identifier
        title = ticket.title
        description = ticket.description
        status = ticket.status.rawValue
        priority = ticket.priority.name
        project = ProjectRefDTO(id: detail.project.id, name: detail.project.name)
        parent = detail.parent.map(TicketRefDTO.init)
        childProgress = nil
        children = detail.children.map(TicketRefDTO.init)
        comments = detail.comments.map(CommentDTO.init)
        createdAt = ticket.createdAt
        updatedAt = ticket.updatedAt
        completedAt = ticket.completedAt
    }
}

public struct ParentProgressDTO: Codable, Sendable, Equatable {
    public var identifier: String
    public var title: String
    public var status: String
    public var project: String
    public var done: Int
    public var total: Int

    public init(_ progress: ParentProgress) {
        identifier = progress.ticket.identifier
        title = progress.ticket.title
        status = progress.ticket.status.rawValue
        project = progress.projectName
        done = progress.done
        total = progress.total
    }
}
