import ArcAgentKit
import ArcCore
import ArgumentParser
import Foundation

struct RelateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "relate",
        abstract: "Relate two tickets.",
        discussion: "Examples: arc relate ARC-3 blocks ARC-4, arc relate ARC-3 blocked_by FIC-9, arc relate ARC-3 related ARC-8, arc relate ARC-3 duplicate_of ARC-2."
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "The ticket.") var ticket: String
    @Argument(help: "blocks, blocked_by, related, duplicate_of or duplicated_by.") var relation: String
    @Argument(help: "The other ticket.") var other: String

    func run() async throws {
        let request = RelationRequest(ticket: ticket, relation: relation, other: other)
        try await CLI.execute(global, render: HumanFormat.ticket) { try await $0.addRelation(request) }
    }
}

struct UnrelateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "unrelate", abstract: "Remove a relation between two tickets.")
    @OptionGroup var global: GlobalOptions
    @Argument(help: "The ticket.") var ticket: String
    @Argument(help: "blocks, blocked_by, related, duplicate_of or duplicated_by.") var relation: String
    @Argument(help: "The other ticket.") var other: String

    func run() async throws {
        let request = RelationRequest(ticket: ticket, relation: relation, other: other)
        try await CLI.execute(global, render: HumanFormat.ticket) { try await $0.removeRelation(request) }
    }
}

struct AttachCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Attach a link or a file to a ticket.",
        discussion: "Files are copied into the attachments folder next to the database."
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "The ticket.") var ticket: String
    @Option(help: "A URL to attach as a link.") var url: String?
    @Option(help: "A title for the link.") var title: String?
    @Option(help: "A file to copy in.") var file: String?

    func run() async throws {
        guard (url == nil) != (file == nil) else {
            try CLI.fail(ArcError.invalidArgument("Give exactly one of --url or --file."), json: global.json)
        }
        try await CLI.execute(global, render: HumanFormat.ticket) { [ticket, url, title, file] in
            if let url { return try await $0.addLink(AddLinkRequest(ticket: ticket, url: url, title: title)) }
            return try await $0.addFile(ticket: ticket, path: file!)
        }
    }
}

struct MilestoneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "milestone",
        abstract: "Manage a project's milestones.",
        subcommands: [List.self, Create.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List a project's milestones.")
        @OptionGroup var global: GlobalOptions
        @Argument(help: "The project name.") var project: String

        func run() async throws {
            try await CLI.execute(global, render: HumanFormat.milestones) { [project] in try await $0.listMilestones(project: project) }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a milestone to a project.")
        @OptionGroup var global: GlobalOptions
        @Argument(help: "The project name.") var project: String
        @Argument(help: "The milestone name.") var name: String
        @Option(help: "A description.") var description: String?
        @Option(help: "A target date, YYYY-MM-DD.") var target: String?

        func run() async throws {
            var date: Date?
            if let target {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                guard let parsed = formatter.date(from: target) else {
                    try CLI.fail(ArcError.invalidArgument("'\(target)' is not a date like 2026-12-31."), json: global.json)
                }
                date = parsed
            }
            try await CLI.execute(global, render: { (m: MilestoneDTO) in "Created milestone \(m.name)" }) { [project, name, description, date] in
                try await $0.createMilestone(project: project, name: name, description: description, targetDate: date)
            }
        }
    }
}

struct LabelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "label",
        abstract: "List the labels in use. (Labels are created when you first use them on a ticket.)",
        subcommands: [List.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List labels.")
        @OptionGroup var global: GlobalOptions

        func run() async throws {
            try await CLI.execute(global, render: HumanFormat.labels) { try await $0.listLabels() }
        }
    }
}
