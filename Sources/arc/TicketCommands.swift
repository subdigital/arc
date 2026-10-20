import ArcAgentKit
import ArcCore
import ArgumentParser

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List tickets (open ones by default), ordered by status then manual order."
    )
    @OptionGroup var global: GlobalOptions
    @Option(help: "Only tickets in this project (name).") var project: String?
    @Option(name: .long, help: "Only this status, e.g. todo or \"In Progress\". Repeatable.") var status: [String] = []
    @Option(name: .long, help: "Only this priority: none, urgent, high, medium, low. Repeatable.") var priority: [String] = []
    @Option(help: "Only direct children of this ticket (identifier).") var parent: String?
    @Option(help: "Free-text search over title, description and identifier.") var query: String?
    @Flag(name: .long, help: "Include Done and Canceled tickets.") var all = false
    @Option(help: "Return at most this many tickets.") var limit: Int?

    func run() async throws {
        let request = ListTicketsRequest(
            project: project,
            status: status.isEmpty ? nil : StringList(status),
            priority: priority.isEmpty ? nil : StringList(priority),
            parent: parent, query: query,
            includeClosed: all, limit: limit
        )
        try await CLI.execute(global, render: HumanFormat.tickets) { try await $0.listTickets(request) }
    }
}

struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show one ticket with its children and comments."
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "The ticket: ARC-12, arc-12, FIC-7 or 12 (meaning ARC-12).") var ticket: String

    func run() async throws {
        try await CLI.execute(global, render: HumanFormat.ticket) { [ticket] in try await $0.getTicket(ticket) }
    }
}

struct CreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a ticket.",
        discussion: "A project is required unless --parent is given; the new ticket then defaults to its parent's project."
    )
    @OptionGroup var global: GlobalOptions
    @Option(name: [.short, .long], help: "The title.") var title: String
    @Option(help: "The project (name).") var project: String?
    @Option(help: "Markdown description. Use - to read it from stdin.") var description: String?
    @Option(help: "The parent ticket (identifier).") var parent: String?
    @Option(help: "backlog, todo, in_progress, in_review, done or canceled. Defaults to todo.") var status: String?
    @Option(help: "none, urgent, high, medium or low. Defaults to none.") var priority: String?

    func run() async throws {
        do {
            let request = CreateTicketRequest(
                title: title, project: project, description: try CLI.resolveStdin(description),
                parent: parent, status: status, priority: priority
            )
            try await CLI.execute(global, render: HumanFormat.ticket) { try await $0.createTicket(request) }
        } catch let error as ArcError {
            try CLI.fail(error, json: global.json)
        }
    }
}

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Change a ticket's fields.",
        discussion: "Use --parent none to make a ticket top-level."
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "The ticket: ARC-12, arc-12, FIC-7 or 12 (meaning ARC-12).") var ticket: String
    @Option(name: [.short, .long], help: "The new title.") var title: String?
    @Option(help: "New Markdown description. Use - to read it from stdin.") var description: String?
    @Option(help: "backlog, todo, in_progress, in_review, done or canceled.") var status: String?
    @Option(help: "none, urgent, high, medium or low.") var priority: String?
    @Option(help: "Move to this project (name).") var project: String?
    @Option(help: "The parent ticket (identifier), or none.") var parent: String?

    func run() async throws {
        do {
            let request = UpdateTicketRequest(
                ticket: ticket, title: title, description: try CLI.resolveStdin(description),
                status: status, priority: priority, project: project, parent: parent
            )
            try await CLI.execute(global, render: HumanFormat.ticket) { try await $0.updateTicket(request) }
        } catch let error as ArcError {
            try CLI.fail(error, json: global.json)
        }
    }
}

struct CommentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "comment",
        abstract: "Add a comment (recorded as written by an agent)."
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "The ticket: ARC-12, arc-12, FIC-7 or 12 (meaning ARC-12).") var ticket: String
    @Argument(help: "The Markdown comment. Use - to read it from stdin.") var body: String

    func run() async throws {
        do {
            let text = try CLI.resolveStdin(body) ?? body
            try await CLI.execute(global, render: HumanFormat.comment) { [ticket] in
                try await $0.addComment(ticket: ticket, body: text)
            }
        } catch let error as ArcError {
            try CLI.fail(error, json: global.json)
        }
    }
}

struct DeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Permanently delete a ticket and its comments (its children are kept).",
        discussion: "Requires --yes. To drop work without deleting it, set the status to canceled instead."
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "The ticket: ARC-12, arc-12, FIC-7 or 12 (meaning ARC-12).") var ticket: String
    @Flag(name: .long, help: "Confirm the deletion.") var yes = false

    func run() async throws {
        guard yes else {
            try CLI.fail(ArcError.invalidArgument("Refusing to delete \(ticket) without --yes."), json: global.json)
        }
        try await CLI.execute(global, render: HumanFormat.deleted) { [ticket] in try await $0.deleteTicket(ticket) }
    }
}
