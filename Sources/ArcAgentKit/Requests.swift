import ArcCore
import Foundation

/// Accepts `"todo"` or `["todo", "done"]` so agents can be sloppy about single values.
public struct StringList: Codable, Sendable, Equatable, ExpressibleByArrayLiteral {
    public var values: [String]

    public init(_ values: [String]) { self.values = values }
    public init(arrayLiteral elements: String...) { values = elements }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = [single]
        } else {
            values = try container.decode([String].self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

public struct ListTicketsRequest: Codable, Sendable, Equatable {
    public var project: String?
    public var kind: StringList?
    public var status: StringList?
    public var priority: StringList?
    public var epic: String?
    public var parent: String?
    public var query: String?
    public var includeClosed: Bool?
    public var limit: Int?

    enum CodingKeys: String, CodingKey {
        case project, kind, status, priority, epic, parent, query, limit
        case includeClosed = "include_closed"
    }

    public init(
        project: String? = nil, kind: StringList? = nil, status: StringList? = nil, priority: StringList? = nil,
        epic: String? = nil, parent: String? = nil, query: String? = nil, includeClosed: Bool? = nil, limit: Int? = nil
    ) {
        self.project = project
        self.kind = kind
        self.status = status
        self.priority = priority
        self.epic = epic
        self.parent = parent
        self.query = query
        self.includeClosed = includeClosed
        self.limit = limit
    }
}

public struct CreateTicketRequest: Codable, Sendable, Equatable {
    public var title: String
    public var project: String?
    public var kind: String?
    public var description: String?
    public var epic: String?
    public var parent: String?
    public var status: String?
    public var priority: String?

    public init(
        title: String, project: String? = nil, kind: String? = nil, description: String? = nil,
        epic: String? = nil, parent: String? = nil, status: String? = nil, priority: String? = nil
    ) {
        self.title = title
        self.project = project
        self.kind = kind
        self.description = description
        self.epic = epic
        self.parent = parent
        self.status = status
        self.priority = priority
    }
}

/// `epic` and `parent` accept `"none"` (or an empty string) to clear the field.
public struct UpdateTicketRequest: Codable, Sendable, Equatable {
    public var ticket: String
    public var title: String?
    public var description: String?
    public var kind: String?
    public var status: String?
    public var priority: String?
    public var project: String?
    public var epic: String?
    public var parent: String?

    public init(
        ticket: String, title: String? = nil, description: String? = nil, kind: String? = nil,
        status: String? = nil, priority: String? = nil, project: String? = nil, epic: String? = nil, parent: String? = nil
    ) {
        self.ticket = ticket
        self.title = title
        self.description = description
        self.kind = kind
        self.status = status
        self.priority = priority
        self.project = project
        self.epic = epic
        self.parent = parent
    }
}

public struct CommentResultDTO: Codable, Sendable, Equatable {
    public var ticket: String
    public var comment: CommentDTO

    public init(ticket: String, comment: CommentDTO) {
        self.ticket = ticket
        self.comment = comment
    }
}

public struct DeletedDTO: Codable, Sendable, Equatable {
    public var identifier: String
    public var deleted: Bool

    public init(identifier: String, deleted: Bool) {
        self.identifier = identifier
        self.deleted = deleted
    }
}
