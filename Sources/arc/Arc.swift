import ArgumentParser

@main
struct Arc: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "arc",
        abstract: "Arc issue tracker: projects and tickets with parents and children for you and your coding agents.",
        discussion: """
            Tickets are referred to by identifier (ARC-12, arc-12, FIC-7 for imported tickets, or just 12 for ARC-12). Projects are referred to by name.
            Pass --json to any data command for machine-readable output.
            """,
        subcommands: [
            ProjectCommand.self,
            ListCommand.self,
            ShowCommand.self,
            CreateCommand.self,
            UpdateCommand.self,
            CommentCommand.self,
            DeleteCommand.self,
            ImportCommand.self,
            MCPCommand.self,
            SkillCommand.self,
        ]
    )
}
