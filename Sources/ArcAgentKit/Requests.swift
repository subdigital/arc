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
    public var status: StringList?
    public var priority: StringList?
    public var parent: String?
    public var label: StringList?
    public var milestone: String?
    public var query: String?
    public var includeClosed: Bool?
    public var limit: Int?

    enum CodingKeys: String, CodingKey {
        case project, status, priority, parent, label, milestone, query, limit
        case includeClosed = "include_closed"
    }

    public init(
        project: String? = nil, status: StringList? = nil, priority: StringList? = nil,
        parent: String? = nil, label: StringList? = nil, milestone: String? = nil,
        query: String? = nil, includeClosed: Bool? = nil, limit: Int? = nil
    ) {
        self.label = label
        self.milestone = milestone
        self.project = project
        self.status = status
        self.priority = priority
        self.parent = parent
        self.query = query
        self.includeClosed = includeClosed
        self.limit = limit
    }
}

public struct CreateTicketRequest: Codable, Sendable, Equatable {
    public var title: String
    public var project: String?
    public var description: String?
    public var parent: String?
    public var status: String?
    public var priority: String?
    public var labels: StringList?
    public var milestone: String?

    public init(
        title: String, project: String? = nil, description: String? = nil,
        parent: String? = nil, status: String? = nil, priority: String? = nil,
        labels: StringList? = nil, milestone: String? = nil
    ) {
        self.labels = labels
        self.milestone = milestone
        self.title = title
        self.project = project
        self.description = description
        self.parent = parent
        self.status = status
        self.priority = priority
    }
}

/// `parent` and `milestone` accept `"none"` (or an empty string) to clear the field; `labels` replaces the
/// ticket's labels (an empty list removes them all), creating any label that does not exist yet.
public struct UpdateTicketRequest: Codable, Sendable, Equatable {
    public var ticket: String
    public var title: String?
    public var description: String?
    public var status: String?
    public var priority: String?
    public var project: String?
    public var parent: String?
    public var labels: StringList?
    public var milestone: String?

    public init(
        ticket: String, title: String? = nil, description: String? = nil,
        status: String? = nil, priority: String? = nil, project: String? = nil, parent: String? = nil,
        labels: StringList? = nil, milestone: String? = nil
    ) {
        self.labels = labels
        self.milestone = milestone
        self.ticket = ticket
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.project = project
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

/// How the first ticket relates to the second: `blocks`, `blocked_by`, `related` or `duplicate_of`.
public struct RelationRequest: Codable, Sendable, Equatable {
    public var ticket: String
    public var relation: String
    public var other: String

    public init(ticket: String, relation: String, other: String) {
        self.ticket = ticket
        self.relation = relation
        self.other = other
    }
}

public struct AddLinkRequest: Codable, Sendable, Equatable {
    public var ticket: String
    public var url: String
    public var title: String?

    public init(ticket: String, url: String, title: String? = nil) {
        self.ticket = ticket
        self.url = url
        self.title = title
    }
}
