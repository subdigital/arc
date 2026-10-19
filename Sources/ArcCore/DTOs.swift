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

public struct SubtaskProgressDTO: Codable, Sendable, Equatable {
    public var done: Int
    public var total: Int
}

/// One shape for every ticket-returning command. List results leave out `description`,
/// `subtasks` and `comments` (nil, so omitted from the JSON); `show` and writes include them.
public struct TicketDTO: Codable, Sendable, Equatable {
    public var identifier: String
    public var kind: String
    public var title: String
    public var description: String?
    public var status: String
    public var priority: String
    public var project: ProjectRefDTO
    public var epic: TicketRefDTO?
    public var parent: TicketRefDTO?
    public var subtaskProgress: SubtaskProgressDTO?
    public var subtasks: [TicketRefDTO]?
    public var comments: [CommentDTO]?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(_ summary: TicketSummary, projectId: String) {
        let ticket = summary.ticket
        identifier = ticket.identifier
        kind = ticket.kind.rawValue
        title = ticket.title
        description = nil
        status = ticket.status.rawValue
        priority = ticket.priority.name
        project = ProjectRefDTO(id: projectId, name: summary.projectName)
        epic = summary.epic.map(TicketRefDTO.init)
        parent = summary.parent.map(TicketRefDTO.init)
        subtaskProgress = summary.subtaskCount > 0
            ? SubtaskProgressDTO(done: summary.subtasksDone, total: summary.subtaskCount)
            : nil
        subtasks = nil
        comments = nil
        createdAt = ticket.createdAt
        updatedAt = ticket.updatedAt
        completedAt = ticket.completedAt
    }

    public init(_ detail: TicketDetail) {
        let ticket = detail.ticket
        identifier = ticket.identifier
        kind = ticket.kind.rawValue
        title = ticket.title
        description = ticket.description
        status = ticket.status.rawValue
        priority = ticket.priority.name
        project = ProjectRefDTO(id: detail.project.id, name: detail.project.name)
        epic = detail.epic.map(TicketRefDTO.init)
        parent = detail.parent.map(TicketRefDTO.init)
        subtaskProgress = nil
        subtasks = detail.subtasks.map(TicketRefDTO.init)
        comments = detail.comments.map(CommentDTO.init)
        createdAt = ticket.createdAt
        updatedAt = ticket.updatedAt
        completedAt = ticket.completedAt
    }
}

public struct EpicProgressDTO: Codable, Sendable, Equatable {
    public var identifier: String
    public var title: String
    public var status: String
    public var project: String
    public var done: Int
    public var total: Int

    public init(_ progress: EpicProgress) {
        identifier = progress.ticket.identifier
        title = progress.ticket.title
        status = progress.ticket.status.rawValue
        project = progress.projectName
        done = progress.done
        total = progress.total
    }
}
