import ArcAgentKit
import ArcCore
import ArgumentParser
import Foundation

struct ImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import data from another tracker.",
        subcommands: [Linear.self]
    )

    struct Linear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "linear",
            abstract: "Import a Linear export folder (projects.json, issues-*.json).",
            discussion: """
                Safe to run again: new items are created, changed ones updated, unchanged ones skipped, and tickets you \
                edited in Arc since the last import are left alone (see --force). Use --dry-run first to see what would \
                happen; the checks run either way and the exit status is 1 if any of them fail. \
                --reset removes everything a previous import created (it asks for --yes) so you can start over.
                """
        )
        @OptionGroup var global: GlobalOptions
        @Argument(help: "The export folder.") var folder: String?
        @Flag(name: .long, help: "Do everything, report, then roll back.") var dryRun = false
        @Flag(name: .long, help: "Also overwrite tickets edited in Arc since the last import.") var force = false
        @Flag(name: .long, help: "Do not download Linear-hosted uploads.") var noDownload = false
        @Flag(name: .long, help: "Remove everything a previous import created instead of importing.") var reset = false
        @Flag(name: .long, help: "Confirm --reset.") var yes = false
        @Option(help: "Project name for issues that have none in Linear (default: the team's name).") var unassignedProject: String?

        func run() async throws {
            do {
                let store = try ArcStore()
                let report: LinearImportReport
                if reset {
                    guard yes || dryRun else {
                        throw ArcError.invalidArgument("Refusing to remove imported data without --yes (or use --dry-run to preview).")
                    }
                    report = try await LinearImporter.reset(store: store, dryRun: dryRun)
                } else {
                    guard let folder else { throw ArcError.invalidArgument("Give the export folder to import.") }
                    let directory = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
                    report = try await LinearImporter.run(store: store, options: LinearImportOptions(
                        directory: directory, dryRun: dryRun, force: force, downloadFiles: !noDownload, unassignedProjectName: unassignedProject
                    ))
                }
                if !report.dryRun { ArcChange.post() }
                if global.json {
                    print(try ArcJSON.string(ImportReportDTO(report)))
                } else {
                    print(report.summary)
                }
                if !report.succeeded { throw ExitCode.failure }
            } catch let code as ExitCode {
                throw code
            } catch {
                try CLI.fail(error, json: global.json)
            }
        }
    }
}

struct ImportReportDTO: Codable {
    struct Counts: Codable {
        var created: Int, updated: Int, unchanged: Int, editedLocally: Int, removed: Int
        init(_ counts: ImportCounts) {
            created = counts.created; updated = counts.updated; unchanged = counts.unchanged
            editedLocally = counts.editedLocally; removed = counts.removed
        }
    }
    var dryRun: Bool
    var succeeded: Bool
    var projects: Counts, milestones: Counts, labels: Counts, tickets: Counts, comments: Counts, attachments: Counts, relations: Counts
    var filesDownloaded: Int, filesFailed: Int, verifiedTickets: Int
    var warnings: [String]
    var errors: [String]

    init(_ report: LinearImportReport) {
        dryRun = report.dryRun; succeeded = report.succeeded
        projects = .init(report.projects); milestones = .init(report.milestones); labels = .init(report.labels)
        tickets = .init(report.tickets); comments = .init(report.comments); attachments = .init(report.attachments)
        relations = .init(report.relations)
        filesDownloaded = report.filesDownloaded; filesFailed = report.filesFailed; verifiedTickets = report.verifiedTickets
        warnings = report.warnings; errors = report.errors
    }
}
