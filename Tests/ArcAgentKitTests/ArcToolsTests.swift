import ArcCore
import Foundation
import Testing
@testable import ArcAgentKit

@Suite struct ArcToolsTests {
    private func operations() throws -> ArcOperations {
        ArcOperations(store: try ArcStore(path: temporaryDatabasePath()), didWrite: {})
    }

    private func call(_ name: String, _ arguments: [String: Any] = [:], _ operations: ArcOperations) async throws -> (ToolOutcome, Any) {
        let data = try JSONSerialization.data(withJSONObject: arguments)
        let outcome = await ArcTools.call(name, arguments: data, operations: operations)
        let parsed = try JSONSerialization.jsonObject(with: Data(outcome.text.utf8), options: [.fragmentsAllowed])
        return (outcome, parsed)
    }

    @Test func exposesExactlyTheSevenSpecifiedToolsAndNoDelete() {
        #expect(ArcTools.all.map(\.name) == [
            "list_projects", "create_project", "list_tickets", "get_ticket", "create_ticket", "update_ticket", "add_comment",
        ])
        #expect(!ArcTools.all.contains { $0.name.contains("delete") })
    }

    @Test func everyToolDocumentsEveryParameter() throws {
        for tool in ArcTools.all {
            #expect(!tool.description.isEmpty)
            let schema = try #require(tool.inputSchema.objectValue)
            #expect(schema["type"]?.stringValue == "object")
            let properties = try #require(schema["properties"]?.objectValue)
            for (name, definition) in properties {
                let description = definition.objectValue?["description"]?.stringValue
                #expect(description?.isEmpty == false, "\(tool.name).\(name) has no description")
            }
            for required in schema["required"]?.arrayValue ?? [] {
                #expect(properties[required.stringValue ?? ""] != nil, "\(tool.name) requires unknown '\(required)'")
            }
        }
        let listTickets = try #require(ArcTools.tool(named: "list_tickets")?.inputSchema.objectValue?["properties"]?.objectValue)
        #expect(Set(listTickets.keys) == ["project", "kind", "status", "priority", "epic", "parent", "query", "include_closed", "limit"])
    }

    @Test func createListGetUpdateAndCommentFlow() async throws {
        let ops = try operations()
        let (projectOutcome, project) = try await call("create_project", ["name": "API"], ops)
        #expect(!projectOutcome.isError)
        #expect((project as? [String: Any])?["name"] as? String == "API")

        let (createOutcome, created) = try await call("create_ticket", ["title": "Add OAuth", "project": "api", "priority": "high"], ops)
        #expect(!createOutcome.isError)
        #expect((created as? [String: Any])?["identifier"] as? String == "ARC-1")

        let (_, projects) = try await call("list_projects", [:], ops)
        #expect((projects as? [[String: Any]])?.count == 1)

        let (_, updated) = try await call("update_ticket", ["ticket": "arc-1", "status": "In Progress"], ops)
        #expect((updated as? [String: Any])?["status"] as? String == "in_progress")

        let (commentOutcome, comment) = try await call("add_comment", ["ticket": "1", "body": "Working on it"], ops)
        #expect(!commentOutcome.isError)
        #expect(((comment as? [String: Any])?["comment"] as? [String: Any])?["author"] as? String == "agent")

        let (_, ticket) = try await call("get_ticket", ["ticket": "ARC-1"], ops)
        let fields = try #require(ticket as? [String: Any])
        #expect((fields["comments"] as? [[String: Any]])?.count == 1)
        #expect(fields["description"] as? String == "")

        let (_, listed) = try await call("list_tickets", ["project": "API", "status": "in_progress"], ops)
        #expect((listed as? [[String: Any]])?.map { $0["identifier"] as? String } == ["ARC-1"])
    }

    @Test func includeClosedDefaultsToFalse() async throws {
        let ops = try operations()
        _ = try await call("create_project", ["name": "API"], ops)
        _ = try await call("create_ticket", ["title": "open", "project": "API"], ops)
        _ = try await call("create_ticket", ["title": "closed", "project": "API", "status": "done"], ops)

        let (_, open) = try await call("list_tickets", [:], ops)
        #expect((open as? [[String: Any]])?.count == 1)
        let (_, all) = try await call("list_tickets", ["include_closed": true], ops)
        #expect((all as? [[String: Any]])?.count == 2)
        let (_, statusList) = try await call("list_tickets", ["status": ["todo", "done"]], ops)
        #expect((statusList as? [[String: Any]])?.count == 2)
    }

    @Test func invalidSubtaskParentIsAnError() async throws {
        let ops = try operations()
        _ = try await call("create_project", ["name": "API"], ops)
        _ = try await call("create_ticket", ["title": "Epic", "project": "API", "kind": "epic"], ops)
        let (outcome, body) = try await call("create_ticket", ["title": "Sub", "kind": "subtask", "parent": "ARC-1"], ops)
        #expect(outcome.isError)
        let error = try #require((body as? [String: Any])?["error"] as? [String: Any])
        #expect(error["code"] as? String == "invalid_argument")
        #expect((error["message"] as? String)?.contains("Subtasks can only belong to tasks") == true)
    }

    @Test func argumentProblemsAreReportedNotThrown() async throws {
        let ops = try operations()
        let (missing, missingBody) = try await call("create_ticket", [:], ops)
        #expect(missing.isError)
        #expect(((missingBody as? [String: Any])?["error"] as? [String: Any])?["message"] as? String == "Missing required argument 'title'.")

        let (wrongType, _) = try await call("create_project", ["name": 5], ops)
        #expect(wrongType.isError)

        let (unknownTool, _) = try await call("delete_ticket", ["ticket": "ARC-1"], ops)
        #expect(unknownTool.isError)

        let (notFound, notFoundBody) = try await call("get_ticket", ["ticket": "ARC-404"], ops)
        #expect(notFound.isError)
        #expect(((notFoundBody as? [String: Any])?["error"] as? [String: Any])?["code"] as? String == "not_found")

        let empty = await ArcTools.call("list_projects", arguments: Data(), operations: ops)
        #expect(!empty.isError, "an empty argument payload counts as {}")
    }

    @Test func writesNotifyButReadsDoNot() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func bump() { lock.withLock { value += 1 } }
            var count: Int { lock.withLock { value } }
        }
        let counter = Counter()
        let ops = ArcOperations(store: try ArcStore(path: temporaryDatabasePath()), didWrite: { counter.bump() })
        _ = try await call("create_project", ["name": "API"], ops)
        _ = try await call("create_ticket", ["title": "T", "project": "API"], ops)
        _ = try await call("list_tickets", [:], ops)
        _ = try await call("get_ticket", ["ticket": "1"], ops)
        _ = try await call("add_comment", ["ticket": "1", "body": "x"], ops)
        #expect(counter.count == 3)
    }
}
