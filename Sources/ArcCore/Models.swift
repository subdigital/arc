import Foundation
import GRDB

public enum TicketKind: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case epic, task, subtask

    public var displayName: String { rawValue.capitalized }
}

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
    public var number: Int
    public var kind: TicketKind
    public var projectId: String
    public var epicId: String?
    public var parentId: String?
    public var title: String
    public var description: String
    public var status: TicketStatus
    public var priority: TicketPriority
    public var sortKey: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public var identifier: String { Reference.identifier(for: number) }
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
}
