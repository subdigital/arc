import Foundation
import GRDB

public enum TicketStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible, Comparable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case inReview = "in_review"
    case done
    case canceled

    /// Workflow order: Backlog, Todo, In Progress, In Review, Done, Canceled.
    public static var workflowOrder: [TicketStatus] { allCases }

    public var displayName: String {
        switch self {
        case .backlog: "Backlog"
        case .todo: "Todo"
        case .inProgress: "In Progress"
        case .inReview: "In Review"
        case .done: "Done"
        case .canceled: "Canceled"
        }
    }

    public var isClosed: Bool { self == .done || self == .canceled }
    public var isOpen: Bool { !isClosed }

    public static var openStatuses: [TicketStatus] { allCases.filter(\.isOpen) }
    public static var closedStatuses: [TicketStatus] { allCases.filter(\.isClosed) }

    public var workflowIndex: Int { Self.allCases.firstIndex(of: self)! }

    public static func < (lhs: TicketStatus, rhs: TicketStatus) -> Bool {
        lhs.workflowIndex < rhs.workflowIndex
    }
}

public enum TicketPriority: Int, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case none = 0
    case urgent = 1
    case high = 2
    case medium = 3
    case low = 4

    public var name: String {
        switch self {
        case .none: "none"
        case .urgent: "urgent"
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        }
    }

    public var displayName: String { name.capitalized }

    /// Sorting rank: Urgent, High, Medium, Low, None.
    public var sortRank: Int {
        switch self {
        case .urgent: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        case .none: 4
        }
    }
}

public enum CommentAuthor: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case user, agent
}

public struct Project: Codable, FetchableRecord, PersistableRecord, Sendable, Hashable, Identifiable {
    public static let databaseTableName = "project"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseDateDecodingStrategy = DatabaseDateDecodingStrategy.timeIntervalSince1970
    public static let databaseDateEncodingStrategy = DatabaseDateEncodingStrategy.timeIntervalSince1970

    public var id: String
    public var name: String
    public var nameKey: String
    public var description: String
    public var color: String
    /// An emoji or SF Symbol name shown next to the name.
    public var icon: String?
    public var externalId: String?
    public var archivedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public var isArchived: Bool { archivedAt != nil }
}

public struct Ticket: Codable, FetchableRecord, PersistableRecord, Sendable, Hashable, Identifiable {
    public static let databaseTableName = "ticket"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseDateDecodingStrategy = DatabaseDateDecodingStrategy.timeIntervalSince1970
    public static let databaseDateEncodingStrategy = DatabaseDateEncodingStrategy.timeIntervalSince1970

    public var id: String
    /// Key prefix: `ARC` for tickets created here, the source's key (e.g. `FIC`) for imported ones.
    public var prefix: String
    public var number: Int
    public var projectId: String
    public var parentId: String?
    public var title: String
    public var description: String
    public var status: TicketStatus
    public var priority: TicketPriority
    public var sortKey: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var canceledAt: Date?
    public var archivedAt: Date?
    public var milestoneId: String?
    /// Set for imported tickets (`linear:issue:<id>`), so re-running an import updates instead of duplicating.
    public var externalId: String?

    public var identifier: String { "\(prefix)-\(number)" }
}

public struct Comment: Codable, FetchableRecord, PersistableRecord, Sendable, Hashable, Identifiable {
    public static let databaseTableName = "comment"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseDateDecodingStrategy = DatabaseDateDecodingStrategy.timeIntervalSince1970
    public static let databaseDateEncodingStrategy = DatabaseDateEncodingStrategy.timeIntervalSince1970

    public var id: String
    public var ticketId: String
    public var body: String
    public var author: CommentAuthor
    public var createdAt: Date
    /// Replies point at the comment they answer.
    public var parentId: String?
    /// Who wrote it, when that is a specific person (imported comments keep their author's name).
    public var authorName: String?
    public var updatedAt: Date?
    public var externalId: String?
}

public struct Milestone: Codable, FetchableRecord, PersistableRecord, Sendable, Hashable, Identifiable {
    public static let databaseTableName = "milestone"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseDateDecodingStrategy = DatabaseDateDecodingStrategy.timeIntervalSince1970
    public static let databaseDateEncodingStrategy = DatabaseDateEncodingStrategy.timeIntervalSince1970

    public var id: String
    public var projectId: String
    public var name: String
    public var description: String
    public var targetDate: Date?
    public var sortOrder: Double
    public var externalId: String?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct TicketLabel: Codable, FetchableRecord, PersistableRecord, Sendable, Hashable, Identifiable {
    public static let databaseTableName = "label"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseDateDecodingStrategy = DatabaseDateDecodingStrategy.timeIntervalSince1970
    public static let databaseDateEncodingStrategy = DatabaseDateEncodingStrategy.timeIntervalSince1970

    public var id: String
    public var name: String
    public var nameKey: String
    public var color: String
    public var description: String
    public var externalId: String?
    public var createdAt: Date
}

public enum RelationType: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case blocks, related, duplicate
}

/// A stored relation row. `blocks` and `duplicate` read "from → to"; `related` has no direction.
public struct TicketRelation: Codable, FetchableRecord, PersistableRecord, Sendable, Hashable, Identifiable {
    public static let databaseTableName = "relation"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseDateDecodingStrategy = DatabaseDateDecodingStrategy.timeIntervalSince1970
    public static let databaseDateEncodingStrategy = DatabaseDateEncodingStrategy.timeIntervalSince1970

    public var id: String
    public var fromId: String
    public var toId: String
    public var type: RelationType
    public var createdAt: Date
}

public enum AttachmentKind: String, Codable, Sendable, DatabaseValueConvertible {
    case link, file
}

public struct Attachment: Codable, FetchableRecord, PersistableRecord, Sendable, Hashable, Identifiable {
    public static let databaseTableName = "attachment"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseDateDecodingStrategy = DatabaseDateDecodingStrategy.timeIntervalSince1970
    public static let databaseDateEncodingStrategy = DatabaseDateEncodingStrategy.timeIntervalSince1970

    public var id: String
    public var ticketId: String
    public var kind: AttachmentKind
    public var title: String
    /// Links: the target. Files: where the file came from, when known.
    public var url: String?
    /// Files: path relative to the attachments folder next to the database.
    public var path: String?
    public var mimeType: String?
    public var size: Int?
    public var externalId: String?
    public var createdAt: Date

    public var isImage: Bool { (mimeType ?? "").hasPrefix("image/") }
}
