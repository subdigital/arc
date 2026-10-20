import ArcAgentKit
import ArgumentParser

struct ProjectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "Manage projects.",
        subcommands: [List.self, Create.self, Update.self, Archive.self, Unarchive.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List projects.")
        @OptionGroup var global: GlobalOptions
        @Flag(name: .long, help: "Include archived projects.") var all = false

        func run() async throws {
            try await CLI.execute(global, render: HumanFormat.projects) { [all] in try await $0.listProjects(includeArchived: all) }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a project.")
        @OptionGroup var global: GlobalOptions
        @Argument(help: "The project name (unique, ignoring case).") var name: String
        @Option(help: "A short description.") var description: String?
        @Option(help: "A hex color such as #5E6AD2.") var color: String?
        @Option(help: "An emoji or SF Symbol name.") var icon: String?

        func run() async throws {
            try await CLI.execute(global, render: HumanFormat.project) { [name, description, color, icon] in
                try await $0.createProject(name: name, description: description, color: color, icon: icon)
            }
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rename or edit a project.")
        @OptionGroup var global: GlobalOptions
        @Argument(help: "The project name.") var project: String
        @Option(help: "The new name.") var name: String?
        @Option(help: "The new description.") var description: String?
        @Option(help: "A hex color such as #5E6AD2.") var color: String?
        @Option(help: "An emoji or SF Symbol name (empty removes it).") var icon: String?

        func run() async throws {
            try await CLI.execute(global, render: HumanFormat.project) { [project, name, description, color, icon] in
                try await $0.updateProject(project, name: name, description: description, color: color, icon: icon)
            }
        }
    }

    struct Archive: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Archive a project (its tickets are kept).")
        @OptionGroup var global: GlobalOptions
        @Argument(help: "The project name.") var project: String

        func run() async throws {
            try await CLI.execute(global, render: HumanFormat.project) { [project] in
                try await $0.setProjectArchived(project, archived: true)
            }
        }
    }

    struct Unarchive: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restore an archived project.")
        @OptionGroup var global: GlobalOptions
        @Argument(help: "The project name.") var project: String

        func run() async throws {
            try await CLI.execute(global, render: HumanFormat.project) { [project] in
                try await $0.setProjectArchived(project, archived: false)
            }
        }
    }
}
