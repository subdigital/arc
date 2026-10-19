import ArcAgentKit
import ArcCore
import ArgumentParser
import Foundation

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run the Arc MCP server over stdio.",
        discussion: "Register it with an agent, for example: claude mcp add arc -- arc mcp"
    )

    func run() async throws {
        do {
            try await ArcMCPServer.run(operations: ArcOperations(store: try ArcStore()))
        } catch {
            // stdout belongs to the protocol; report on stderr only.
            try CLI.fail(error, json: false)
        }
    }
}

struct SkillCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skill",
        abstract: "Manage the Arc agent skill.",
        subcommands: [Install.self]
    )

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install the Arc skill (SKILL.md) for coding agents.",
            discussion: "Writes <dir>/arc/SKILL.md; <dir> defaults to ~/.claude/skills. An existing, different file is kept unless --force."
        )
        @OptionGroup var global: GlobalOptions
        @Option(help: "The skills directory to install into.") var dir: String?
        @Flag(name: .long, help: "Overwrite an existing, different SKILL.md.") var force = false

        func run() async throws {
            do {
                let directory = dir.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
                let result = try ArcSkill.install(into: directory, force: force)
                if global.json {
                    print(try ArcJSON.string(result))
                } else {
                    print(result.path)
                }
            } catch {
                try CLI.fail(error, json: global.json)
            }
        }
    }
}
