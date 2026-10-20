import ArcCore
import Foundation
import MCP

/// One MCP tool: its public description and schema, plus the handler that runs it.
/// Defined here, independent of the MCP SDK's server types, so the table survives SDK API changes.
public struct ArcTool: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: Value
    let handler: @Sendable (ArcOperations, Data) async throws -> String

    public var mcpTool: Tool {
        Tool(name: name, description: description, inputSchema: inputSchema)
    }
}

public struct ToolOutcome: Sendable, Equatable {
    public var text: String
    public var isError: Bool
}

public enum ArcTools {
    public static let all: [ArcTool] = [
        listProjects, createProject, listTickets, getTicket, createTicket, updateTicket, addComment,
    ]

    public static func tool(named name: String) -> ArcTool? { all.first { $0.name == name } }

    /// Runs a tool. Failures never throw: they come back as an error outcome carrying the error JSON.
    public static func call(_ name: String, arguments: Data, operations: ArcOperations) async -> ToolOutcome {
        guard let tool = tool(named: name) else {
            return failure(ArcError.invalidArgument("Unknown tool '\(name)'. Available: \(all.map(\.name).joined(separator: ", "))."))
        }
        do {
            return ToolOutcome(text: try await tool.handler(operations, arguments), isError: false)
        } catch {
            return failure(error)
        }
    }

    private static func failure(_ error: Error) -> ToolOutcome {
        let arcError = (error as? ArcError) ?? ArcError(.internal, String(describing: error))
        let text = (try? ArcJSON.string(ArcErrorDTO(arcError))) ?? arcError.message
        return ToolOutcome(text: text, isError: true)
    }

    // MARK: - Argument decoding

    private struct ListProjectsArguments: Decodable {
        var includeArchived: Bool?
        enum CodingKeys: String, CodingKey { case includeArchived = "include_archived" }
    }

    private struct CreateProjectArguments: Decodable {
        var name: String
        var description: String?
        var color: String?
    }

    private struct GetTicketArguments: Decodable {
        var ticket: String
    }

    private struct AddCommentArguments: Decodable {
        var ticket: String
        var body: String
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try ArcJSON.makeDecoder().decode(type, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw ArcError.invalidArgument("Missing required argument '\(key.stringValue)'.")
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw ArcError.invalidArgument("Invalid argument '\(path)': \(context.debugDescription)")
        } catch {
            throw ArcError.invalidArgument("Invalid arguments: \(error.localizedDescription)")
        }
    }

    private static func json<T: Encodable>(_ value: T) throws -> String { try ArcJSON.string(value) }

    // MARK: - Schema helpers

    private static func schema(_ properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = ["type": "object", "properties": .object(properties), "additionalProperties": false]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        return .object(schema)
    }

    private static func string(_ description: String, enum values: [String]? = nil) -> Value {
        var object: [String: Value] = ["type": "string", "description": .string(description)]
        if let values { object["enum"] = .array(values.map { .string($0) }) }
        return .object(object)
    }

    private static func stringOrList(_ description: String, values: [String]) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object(["type": "string", "enum": .array(values.map { .string($0) })]),
                .object(["type": "array", "items": .object(["type": "string", "enum": .array(values.map { .string($0) })])]),
            ]),
        ])
    }

    private static let statusNames = TicketStatus.allCases.map(\.rawValue)
    private static let priorityNames = TicketPriority.allCases.map(\.name)
    private static let ticketHelp = "ticket identifier such as ARC-12 or FIC-123 (case-insensitive; a bare number like 12 means ARC-12)"

    // MARK: - Tools

    static let listProjects = ArcTool(
        name: "list_projects",
        description: "List Arc projects. Archived projects are hidden unless include_archived is true. Project names are what other tools take in their 'project' argument.",
        inputSchema: schema(["include_archived": .object(["type": "boolean", "description": "Also list archived projects. Default false."])]),
        handler: { operations, data in
            let arguments = try decode(ListProjectsArguments.self, from: data)
            return try json(try await operations.listProjects(includeArchived: arguments.includeArchived ?? false))
        }
    )

    static let createProject = ArcTool(
        name: "create_project",
        description: "Create a project. Names are unique ignoring case. Only create a project when the user asks for one or none fits.",
        inputSchema: schema([
            "name": string("The project name."),
            "description": string("Optional short description."),
            "color": string("Optional hex color such as #5E6AD2."),
        ], required: ["name"]),
        handler: { operations, data in
            let arguments = try decode(CreateProjectArguments.self, from: data)
            return try json(try await operations.createProject(
                name: arguments.name, description: arguments.description, color: arguments.color
            ))
        }
    )

    static let listTickets = ArcTool(
        name: "list_tickets",
        description: """
            List tickets, ordered by status (backlog, todo, in_progress, in_review, done, canceled) then by the user's manual order. \
            Only open tickets are returned unless include_closed is true or a closed status is requested explicitly. \
            All filters combine with AND. Rows omit the description and comments; use get_ticket for those.
            """,
        inputSchema: schema([
            "project": string("Only tickets in this project (name, case-insensitive)."),
            "status": stringOrList("Only these statuses. Spaces and hyphens are accepted in place of underscores.", values: statusNames),
            "priority": stringOrList("Only these priorities.", values: priorityNames),
            "parent": string("Only direct children of this ticket, \(ticketHelp)."),
            "query": string("Case-insensitive text matched against title, description and identifier."),
            "include_closed": .object(["type": "boolean", "description": "Include done and canceled tickets. Default false."]),
            "limit": .object(["type": "integer", "minimum": 0, "description": "Return at most this many tickets."]),
        ]),
        handler: { operations, data in
            try json(try await operations.listTickets(try decode(ListTicketsRequest.self, from: data)))
        }
    )

    static let getTicket = ArcTool(
        name: "get_ticket",
        description: "Get one ticket with its full description, project, parent, children and comments.",
        inputSchema: schema(["ticket": string("The \(ticketHelp).")], required: ["ticket"]),
        handler: { operations, data in
            try json(try await operations.getTicket(try decode(GetTicketArguments.self, from: data).ticket))
        }
    )

    static let createTicket = ArcTool(
        name: "create_ticket",
        description: """
            Create a ticket and return it (including its new ARC-n identifier). \
            Any ticket may have a parent ticket (to any depth, in any project). A project is required unless parent is given, \
            in which case the new ticket defaults to the parent's project. Descriptions are GitHub Flavored Markdown.
            """,
        inputSchema: schema([
            "title": string("The title (required, not blank)."),
            "project": string("Project name. Required unless parent is given (then it defaults to the parent's project)."),
            "description": string("Markdown description."),
            "parent": string("Make the new ticket a child of this ticket, \(ticketHelp)."),
            "status": string("Defaults to todo.", enum: statusNames),
            "priority": string("Defaults to none.", enum: priorityNames),
        ], required: ["title"]),
        handler: { operations, data in
            try json(try await operations.createTicket(try decode(CreateTicketRequest.self, from: data)))
        }
    )

    static let updateTicket = ArcTool(
        name: "update_ticket",
        description: """
            Change fields of a ticket and return it. Only the fields you pass change. \
            Typical use: set status to in_progress when you start, in_review or done when finished, canceled to drop work. \
            There is no delete tool; cancel unwanted tickets instead. Pass parent as "none" to make a ticket top-level. \
            Moving a ticket to another project does not move its children.
            """,
        inputSchema: schema([
            "ticket": string("The \(ticketHelp)."),
            "title": string("New title."),
            "description": string("New Markdown description (replaces the old one)."),
            "status": string("New status.", enum: statusNames),
            "priority": string("New priority.", enum: priorityNames),
            "project": string("Move to this project (name)."),
            "parent": string("Parent ticket \(ticketHelp), or \"none\" to clear."),
        ], required: ["ticket"]),
        handler: { operations, data in
            try json(try await operations.updateTicket(try decode(UpdateTicketRequest.self, from: data)))
        }
    )

    static let addComment = ArcTool(
        name: "add_comment",
        description: "Add a comment to a ticket, recorded as written by an agent. Use it for progress notes, decisions and hand-off summaries. The body is GitHub Flavored Markdown.",
        inputSchema: schema([
            "ticket": string("The \(ticketHelp)."),
            "body": string("The Markdown comment (not blank)."),
        ], required: ["ticket", "body"]),
        handler: { operations, data in
            let arguments = try decode(AddCommentArguments.self, from: data)
            return try json(try await operations.addComment(ticket: arguments.ticket, body: arguments.body))
        }
    )
}
