import Foundation
import GRDB

/// The single error type surfaced by ArcCore. The `code` is stable and machine-readable;
/// the `message` is meant for humans (and agents).
public struct ArcError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Code: String, Sendable, Codable, CaseIterable {
        case notFound = "not_found"
        case invalidArgument = "invalid_argument"
        case conflict
        case databaseBusy = "database_busy"
        case schemaTooNew = "schema_too_new"
        case `internal`
    }

    public let code: Code
    public let message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { message }

    public static func notFound(_ message: String) -> ArcError { .init(.notFound, message) }
    public static func invalidArgument(_ message: String) -> ArcError { .init(.invalidArgument, message) }
    public static func conflict(_ message: String) -> ArcError { .init(.conflict, message) }
    public static func databaseBusy() -> ArcError {
        .init(.databaseBusy, "The Arc database is busy (locked by another process). Try again.")
    }
    public static func schemaTooNew() -> ArcError {
        .init(.schemaTooNew, "This database requires a newer version of Arc. Update Arc and try again.")
    }

    /// Maps arbitrary errors thrown by GRDB/SQLite into an `ArcError`.
    static func wrapping(_ error: Error) -> ArcError {
        if let error = error as? ArcError { return error }
        if let dbError = error as? DatabaseError {
            switch dbError.resultCode.primaryResultCode {
            case .SQLITE_BUSY, .SQLITE_LOCKED:
                return .databaseBusy()
            default:
                return .init(.internal, dbError.description)
            }
        }
        return .init(.internal, String(describing: error))
    }
}

/// The JSON body printed for errors when `--json` is in effect.
public struct ArcErrorDTO: Codable, Sendable, Equatable {
    public struct Body: Codable, Sendable, Equatable {
        public let code: String
        public let message: String
    }

    public let error: Body

    public init(_ error: ArcError) {
        self.error = Body(code: error.code.rawValue, message: error.message)
    }
}
