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
    public var icon: String?
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(_ project: Project) {
        id = project.id
        name = project.name
        description = project.description
        color = project.color
        icon = project.icon
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
    /// A specific person's name, when the comment was imported from somewhere that records one.
    public var authorName: String?
    /// The comment this one replies to.
    public var replyTo: String?
    public var body: String
    public var createdAt: Date

    public init(_ comment: Comment) {
        id = comment.id
        author = comment.author.rawValue
        authorName = comment.authorName
        replyTo = comment.parentId
        body = comment.body
        createdAt = comment.createdAt
    }
}

public struct AttachmentDTO: Codable, Sendable, Equatable {
    public var id: String
    public var kind: String
    public var title: String
    public var url: String?
    /// Absolute path of the stored copy, for files.
    public var path: String?
    public var mimeType: String?

    public init(_ attachment: Attachment, directory: URL? = nil) {
        id = attachment.id
        kind = attachment.kind.rawValue
        title = attachment.title
        url = attachment.url
        path = attachment.path.map { directory?.appendingPathComponent($0).path ?? $0 }
        mimeType = attachment.mimeType
    }
}

public struct RelationsDTO: Codable, Sendable, Equatable {
    public var blocks: [TicketRefDTO]
    public var blockedBy: [TicketRefDTO]
    public var related: [TicketRefDTO]
    public var duplicateOf: [TicketRefDTO]
    public var duplicatedBy: [TicketRefDTO]

    public init(_ relations: TicketRelations) {
        blocks = relations.blocks.map(TicketRefDTO.init)
        blockedBy = relations.blockedBy.map(TicketRefDTO.init)
        related = relations.related.map(TicketRefDTO.init)
        duplicateOf = relations.duplicateOf.map(TicketRefDTO.init)
        duplicatedBy = relations.duplicatedBy.map(TicketRefDTO.init)
    }
}

public struct MilestoneDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var targetDate: Date?

    public init(_ milestone: Milestone) {
        id = milestone.id
        name = milestone.name
        description = milestone.description
        targetDate = milestone.targetDate
    }
}

public struct LabelDTO: Codable, Sendable, Equatable {
    public var name: String
    public var color: String

    public init(_ label: Label) {
        name = label.name
        color = label.color
    }
}

public struct ChildProgressDTO: Codable, Sendable, Equatable {
    public var done: Int
    public var total: Int
}

/// One shape for every ticket-returning command. `parent`, `milestone` and the four date fields are always
/// present (null when unset), and so is `labels`. List results leave out `description`, `children`,
/// `comments`, `relations` and `attachments`
/// entirely; `show` and writes include them.
public struct TicketDTO: Codable, Sendable, Equatable {
    public var identifier: String
    public var title: String
    public var description: String?
    public var status: String
    public var priority: String
    public var project: ProjectRefDTO
    public var parent: TicketRefDTO?
    public var milestone: String?
    public var labels: [LabelDTO]
    /// True while a ticket that blocks this one is still open.
    public var blocked: Bool?
    public var childProgress: ChildProgressDTO?
    public var children: [TicketRefDTO]?
    public var relations: RelationsDTO?
    public var attachments: [AttachmentDTO]?
    public var comments: [CommentDTO]?
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var canceledAt: Date?
    public var archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case identifier, title, description, status, priority, project, parent, milestone, labels, blocked
        case childProgress, children, relations, attachments, comments
        case createdAt, updatedAt, startedAt, completedAt, canceledAt, archivedAt
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
        try container.encode(milestone, forKey: .milestone)
        try container.encode(labels, forKey: .labels)
        try container.encodeIfPresent(blocked, forKey: .blocked)
        try container.encodeIfPresent(childProgress, forKey: .childProgress)
        try container.encodeIfPresent(children, forKey: .children)
        try container.encodeIfPresent(relations, forKey: .relations)
        try container.encodeIfPresent(attachments, forKey: .attachments)
        try container.encodeIfPresent(comments, forKey: .comments)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(canceledAt, forKey: .canceledAt)
        try container.encode(archivedAt, forKey: .archivedAt)
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
        milestone = summary.milestoneName
        labels = summary.labels.map(LabelDTO.init)
        blocked = summary.isBlocked
        childProgress = summary.childCount > 0
            ? ChildProgressDTO(done: summary.childrenDone, total: summary.childCount)
            : nil
        children = nil
        relations = nil
        attachments = nil
        comments = nil
        createdAt = ticket.createdAt
        updatedAt = ticket.updatedAt
        startedAt = ticket.startedAt
        completedAt = ticket.completedAt
        canceledAt = ticket.canceledAt
        archivedAt = ticket.archivedAt
    }

    public init(_ detail: TicketDetail, attachmentsDirectory: URL? = nil) {
        let ticket = detail.ticket
        identifier = ticket.identifier
        title = ticket.title
        description = ticket.description
        status = ticket.status.rawValue
        priority = ticket.priority.name
        project = ProjectRefDTO(id: detail.project.id, name: detail.project.name)
        parent = detail.parent.map(TicketRefDTO.init)
        milestone = detail.milestone?.name
        labels = detail.labels.map(LabelDTO.init)
        blocked = !detail.relations.openBlockers.isEmpty
        childProgress = nil
        children = detail.children.map(TicketRefDTO.init)
        relations = detail.relations.isEmpty ? nil : RelationsDTO(detail.relations)
        attachments = detail.attachments.isEmpty ? nil : detail.attachments.map { AttachmentDTO($0, directory: attachmentsDirectory) }
        comments = detail.comments.map(CommentDTO.init)
        createdAt = ticket.createdAt
        updatedAt = ticket.updatedAt
        startedAt = ticket.startedAt
        completedAt = ticket.completedAt
        canceledAt = ticket.canceledAt
        archivedAt = ticket.archivedAt
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
