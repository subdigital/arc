import ArcCore
import Foundation
import Testing

@Suite struct CLITests {
    @Test func helpPrintsUsageAndExitsZero() throws {
        let db = temporaryDatabasePath()
        let result = try runArc(["create", "--help"], db: db)
        #expect(result.status == 0)
        for option in ["--title", "--project", "--description", "--parent", "--status", "--priority", "--json"] {
            #expect(result.stdout.contains(option), "missing \(option)")
        }
        #expect(!FileManager.default.fileExists(atPath: db), "--help must not touch the database")
    }

    @Test func everySubcommandHasHelp() throws {
        let db = temporaryDatabasePath()
        let commands: [[String]] = [
            ["project", "list"], ["project", "create"], ["project", "update"], ["project", "archive"], ["project", "unarchive"],
            ["list"], ["show"], ["create"], ["update"], ["comment"], ["delete"],
        ]
        for command in commands {
            let result = try runArc(command + ["--help"], db: db)
            #expect(result.status == 0, "\(command)")
            #expect(result.stdout.contains("USAGE"), "\(command)")
        }
    }

    @Test func usageErrorsExit64() throws {
        let db = temporaryDatabasePath()
        #expect(try runArc(["bogus"], db: db).status == 64)
        #expect(try runArc(["create"], db: db).status == 64)
    }

    @Test func projectLifecycleWithJSON() throws {
        let db = temporaryDatabasePath()
        let created = try runArc(["project", "create", "Website", "--description", "Marketing", "--json"], db: db)
        #expect(created.status == 0)
        let project = try created.json()
        #expect(project["name"] as? String == "Website")
        #expect(project["archived"] as? Bool == false)

        let renamed = try runArc(["project", "update", "website", "--name", "Site", "--json"], db: db)
        #expect(try renamed.json()["name"] as? String == "Site")

        let duplicate = try runArc(["project", "create", "SITE", "--json"], db: db)
        #expect(duplicate.status == 1)
        #expect((try duplicate.json()["error"] as? [String: Any])?["code"] as? String == "conflict")

        _ = try runArc(["project", "archive", "Site"], db: db)
        #expect(try runArc(["project", "list", "--json"], db: db).jsonArray().isEmpty)
        #expect(try runArc(["project", "list", "--all", "--json"], db: db).jsonArray().count == 1)
        let restored = try runArc(["project", "unarchive", "Site", "--json"], db: db)
        #expect(try restored.json()["archived"] as? Bool == false)
        #expect(try runArc(["project", "list"], db: db).stdout.contains("Site"))
    }

    @Test func listExcludesClosedByDefault() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        for title in ["a", "b"] { try runArc(["create", "--project", "Website", "--title", title], db: db) }
        for title in ["c", "d", "e"] { try runArc(["create", "--project", "Website", "--title", title, "--status", "done"], db: db) }

        let open = try runArc(["list", "--project", "Website", "--json"], db: db).jsonArray()
        #expect(open.count == 2)
        #expect(open.allSatisfy { $0["status"] as? String == "todo" })
        // List rows leave out the heavy fields but keep the null-able references.
        #expect(open[0]["description"] == nil)
        let everything = try runArc(["list", "--project", "Website", "--all", "--json"], db: db).jsonArray()
        #expect(everything.count == 5)
        let doneOnly = try runArc(["list", "--status", "done", "--json"], db: db).jsonArray()
        #expect(doneOnly.count == 3)
        let limited = try runArc(["list", "--all", "--limit", "2", "--json"], db: db).jsonArray()
        #expect(limited.count == 2)
    }

    @Test func listFilters() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        try runArc(["project", "create", "API"], db: db)
        try runArc(["create", "--project", "Website", "--title", "Launch"], db: db)                                   // 1
        try runArc(["create", "--project", "Website", "--title", "Footer", "--parent", "ARC-1", "--priority", "high"], db: db) // 2
        try runArc(["create", "--parent", "2", "--title", "Footer links"], db: db)                                     // 3
        try runArc(["create", "--project", "API", "--title", "OAuth", "--status", "in_progress"], db: db)             // 4

        func identifiers(_ args: [String]) throws -> [String] {
            try runArc(["list"] + args + ["--json"], db: db).jsonArray().compactMap { $0["identifier"] as? String }
        }
        #expect(try identifiers(["--priority", "high"]) == ["ARC-2"])
        #expect(try identifiers(["--parent", "ARC-2"]) == ["ARC-3"])
        #expect(try identifiers(["--status", "In Progress"]) == ["ARC-4"])
        #expect(try identifiers(["--query", "oauth"]) == ["ARC-4"])
        #expect(try identifiers(["--project", "api"]) == ["ARC-4"])
    }

    @Test func showIncludesEveryField() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        try runArc(["create", "--project", "Website", "--title", "Launch"], db: db)
        try runArc(["create", "--project", "Website", "--title", "Footer", "--parent", "1", "--description", "Body"], db: db)
        try runArc(["create", "--parent", "2", "--title", "Links"], db: db)
        try runArc(["comment", "ARC-2", "hello"], db: db)

        let task = try runArc(["show", "ARC-2", "--json"], db: db).json()
        for key in ["identifier", "title", "description", "status", "priority", "project", "parent",
                    "children", "comments", "createdAt", "updatedAt", "completedAt"] {
            #expect(task.keys.contains(key), "missing \(key)")
        }
        #expect(task["identifier"] as? String == "ARC-2")
        #expect((task["parent"] as? [String: Any])?["identifier"] as? String == "ARC-1")
        #expect(task["completedAt"] is NSNull)
        #expect((task["children"] as? [[String: Any]])?.count == 1)
        #expect((task["comments"] as? [[String: Any]])?.first?["author"] as? String == "agent")
        #expect(((task["project"] as? [String: Any])?["name"]) as? String == "Website")

        let human = try runArc(["show", "arc-2"], db: db)
        #expect(human.status == 0)
        #expect(human.stdout.contains("ARC-2  Footer"))
        #expect(human.stdout.contains("hello"))
    }

    @Test func notFoundExitsNonZeroWithErrorObject() throws {
        let db = temporaryDatabasePath()
        let result = try runArc(["show", "ARC-99999", "--json"], db: db)
        #expect(result.status != 0)
        let error = try #require(try result.json()["error"] as? [String: Any])
        #expect(error["code"] as? String == "not_found")

        let human = try runArc(["show", "ARC-99999"], db: db)
        #expect(human.status == 1)
        #expect(human.stdout.isEmpty)
        #expect(human.stderr.contains("not found"))
    }

    @Test func unknownProjectListsExistingNames() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        try runArc(["project", "create", "API"], db: db)
        let result = try runArc(["create", "--project", "Nope", "--title", "X", "--json"], db: db)
        #expect(result.status == 1)
        let error = try #require(try result.json()["error"] as? [String: Any])
        #expect(error["code"] as? String == "not_found")
        let message = try #require(error["message"] as? String)
        #expect(message.contains("Website") && message.contains("API"))
    }

    @Test func humanStyleStatusAndPriority() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        try runArc(["create", "--project", "Website", "--title", "T"], db: db)
        let updated = try runArc(["update", "arc-1", "--status", "In Progress", "--priority", "URGENT", "--json"], db: db).json()
        #expect(updated["status"] as? String == "in_progress")
        #expect(updated["priority"] as? String == "urgent")
        let bad = try runArc(["update", "arc-1", "--status", "finished", "--json"], db: db)
        #expect(bad.status == 1)
        #expect((try bad.json()["error"] as? [String: Any])?["code"] as? String == "invalid_argument")
    }

    @Test func createChildWithOnlyParent() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        try runArc(["create", "--project", "Website", "--title", "Parent"], db: db)
        let result = try runArc(["create", "--parent", "ARC-1", "--title", "Add tests", "--json"], db: db)
        #expect(result.status == 0)
        let child = try result.json()
        #expect(child["identifier"] as? String == "ARC-2")
        #expect(((child["project"] as? [String: Any])?["name"]) as? String == "Website")
        #expect((child["parent"] as? [String: Any])?["identifier"] as? String == "ARC-1")
    }

    @Test func nestingHasNoDepthLimitButCyclesAreRejected() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        try runArc(["create", "--project", "Website", "--title", "Parent"], db: db)
        try runArc(["create", "--parent", "1", "--title", "Child"], db: db)
        let grandchild = try runArc(["create", "--parent", "2", "--title", "Grandchild", "--json"], db: db)
        #expect(grandchild.status == 0)
        let cycle = try runArc(["update", "1", "--parent", "3", "--json"], db: db)
        #expect(cycle.status == 1)
        let message = (try cycle.json()["error"] as? [String: Any])?["message"] as? String
        #expect(message?.contains("descendant") == true)
    }

    @Test func importedKeysAreAcceptedAndBareNumbersMeanArc() throws {
        let db = temporaryDatabasePath()
        let missing = try runArc(["show", "fic-7", "--json"], db: db)
        #expect(missing.status == 1)
        #expect((try missing.json()["error"] as? [String: Any])?["message"] as? String == "Ticket FIC-7 not found.")
    }

    @Test func descriptionFromStdin() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        let created = try runArc(
            ["create", "--project", "Website", "--title", "T", "--description", "-", "--json"],
            db: db, stdin: "## Notes\n- [ ] one\n"
        ).json()
        #expect(created["description"] as? String == "## Notes\n- [ ] one")

        let updated = try runArc(["update", "ARC-1", "--description", "-", "--json"], db: db, stdin: "Replaced *text*\n").json()
        #expect(updated["description"] as? String == "Replaced *text*")
        let stored = try runArc(["show", "1", "--json"], db: db).json()
        #expect(stored["description"] as? String == "Replaced *text*")
    }

    @Test func clearingParent() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        try runArc(["create", "--project", "Website", "--title", "E"], db: db)
        try runArc(["create", "--project", "Website", "--title", "T", "--parent", "1"], db: db)
        let cleared = try runArc(["update", "2", "--parent", "none", "--json"], db: db).json()
        #expect(cleared["parent"] is NSNull)
    }

    @Test func commentRecordsAgentAuthorAndReadsStdin() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        try runArc(["create", "--project", "Website", "--title", "T"], db: db)
        let inline = try runArc(["comment", "ARC-1", "Parser done, starting tests", "--json"], db: db)
        #expect(inline.status == 0)
        #expect(((try inline.json()["comment"]) as? [String: Any])?["author"] as? String == "agent")
        try runArc(["comment", "1", "-"], db: db, stdin: "Multi\nline\n")
        let comments = try #require(try runArc(["show", "1", "--json"], db: db).json()["comments"] as? [[String: Any]])
        #expect(comments.map { $0["body"] as? String } == ["Parser done, starting tests", "Multi\nline"])
        #expect(comments.allSatisfy { $0["author"] as? String == "agent" })

        let blank = try runArc(["comment", "1", "   ", "--json"], db: db)
        #expect(blank.status == 1)
    }

    @Test func deleteRequiresYes() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        try runArc(["create", "--project", "Website", "--title", "T"], db: db)

        let refused = try runArc(["delete", "ARC-1"], db: db)
        #expect(refused.status == 1)
        #expect(refused.stderr.contains("--yes"))
        #expect(try runArc(["show", "ARC-1"], db: db).status == 0, "nothing should be deleted")

        let jsonRefused = try runArc(["delete", "ARC-1", "--json"], db: db)
        #expect(jsonRefused.status == 1)
        #expect((try jsonRefused.json()["error"] as? [String: Any])?["message"] as? String != nil)

        let deleted = try runArc(["delete", "ARC-1", "--yes", "--json"], db: db)
        #expect(deleted.status == 0)
        #expect(try deleted.json()["deleted"] as? Bool == true)
        #expect(try runArc(["show", "ARC-1"], db: db).status == 1)
    }

    @Test func newerSchemaIsRefused() throws {
        let db = temporaryDatabasePath()
        try runArc(["project", "create", "Website"], db: db)
        let sqlite = Process()
        sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        sqlite.arguments = [db, "INSERT INTO grdb_migrations (identifier) VALUES ('v999');"]
        try sqlite.run()
        sqlite.waitUntilExit()
        let result = try runArc(["list", "--json"], db: db)
        #expect(result.status != 0)
        let error = try #require(try result.json()["error"] as? [String: Any])
        #expect(error["code"] as? String == "schema_too_new")
        #expect((error["message"] as? String)?.contains("newer version of Arc") == true)
    }
}
