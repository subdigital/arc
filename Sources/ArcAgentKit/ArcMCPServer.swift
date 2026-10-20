import ArcCore
import Foundation
import MCP

/// `arc mcp`: a Model Context Protocol server over stdio. Nothing else may write to stdout
/// while it runs; diagnostics go to stderr.
public enum ArcMCPServer {
    public static let version = "0.1.0"

    public static let instructions = """
        Arc is a local issue tracker shared by the user and their coding agents.

        Hierarchy: a project contains tickets, and any ticket may have a parent ticket (to any depth, even in \
        another project), so a ticket with children plays the role of an epic or a task with subtasks. \
        Every ticket has a permanent identifier like ARC-12; tickets imported from elsewhere keep their own key (FIC-123). \
        Tickets can have labels (created on first use), a milestone of their project, links and files, and relations to other \
        tickets (blocks / blocked by / related / duplicate), which add_relation and remove_relation manage.

        Statuses: backlog, todo, in_progress, in_review, done, canceled. Priorities: none, urgent, high, medium, low.

        Workflow: find work with list_tickets (open tickets by default) and read it with get_ticket; \
        set it to in_progress with update_ticket before you start; leave progress notes with add_comment; \
        when finished set it to in_review (or done if the user said so). To drop work, set canceled; there is no delete tool. \
        Descriptions and comments are GitHub Flavored Markdown (task lists, fenced code blocks with a language, ARC-12 references).
        """

    public static func run(operations: ArcOperations) async throws {
        let server = Server(
            name: "arc",
            version: version,
            title: "Arc",
            instructions: instructions,
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: ArcTools.all.map(\.mcpTool))
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            let arguments = try JSONEncoder().encode(parameters.arguments ?? [:])
            let outcome = await ArcTools.call(parameters.name, arguments: arguments, operations: operations)
            return .init(content: [.text(text: outcome.text, annotations: nil, _meta: nil)], isError: outcome.isError)
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}
