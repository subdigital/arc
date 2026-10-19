import Foundation
import Testing

/// Drives `arc mcp` over real pipes, one JSON-RPC message per line.
final class MCPSession: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var nextID = 1
    private(set) var rawLines: [String] = []

    init(db: String) throws {
        signal(SIGPIPE, SIG_IGN) // a dead server should fail the test, not kill the runner
        process.executableURL = arcExecutableURL
        process.arguments = ["mcp"]
        var environment = ProcessInfo.processInfo.environment
        environment["ARC_DB_PATH"] = db
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        try output.fileHandleForWriting.close()
        try input.fileHandleForReading.close()
        // A hung server must fail the test rather than block the run.
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [process] in
            if process.isRunning { process.terminate() }
        }
    }

    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func readLine() throws -> String? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return String(decoding: line, as: UTF8.self)
            }
            // availableData returns as soon as any bytes arrive; read(upToCount:) would wait for the full count.
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { return nil }
            buffer.append(chunk)
        }
    }

    /// Sends a request and returns the response with the matching id.
    func request(_ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        while let line = try readLine() {
            rawLines.append(line)
            let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], "stdout line is not a JSON object: \(line)")
            if object["id"] as? Int == id { return object }
        }
        Issue.record("server closed stdout before answering \(method)")
        return [:]
    }

    func initialize() throws -> [String: Any] {
        let response = try request("initialize", [
            "protocolVersion": "2025-03-26",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "arc-tests", "version": "1"],
        ])
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        return response
    }

    func callTool(_ name: String, _ arguments: [String: Any]) throws -> (text: String, isError: Bool) {
        let response = try request("tools/call", ["name": name, "arguments": arguments])
        let result = try #require(response["result"] as? [String: Any])
        let content = try #require((result["content"] as? [[String: Any]])?.first)
        return (content["text"] as? String ?? "", result["isError"] as? Bool ?? false)
    }

    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }
}

@Suite struct MCPServerTests {
    @Test func handshakeListToolsAndCallTool() throws {
        let db = temporaryDatabasePath()
        let session = try MCPSession(db: db)
        defer { session.close() }

        let initialize = try session.initialize()
        let result = try #require(initialize["result"] as? [String: Any])
        let serverInfo = try #require(result["serverInfo"] as? [String: Any])
        #expect(serverInfo["name"] as? String == "arc")
        let instructions = try #require(result["instructions"] as? String)
        #expect(instructions.contains("project contains epics and tasks"))
        #expect(instructions.contains("in_progress"))
        #expect(((result["capabilities"] as? [String: Any])?["tools"]) != nil)

        let list = try session.request("tools/list")
        let tools = try #require((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.count == 7)
        #expect(Set(tools.compactMap { $0["name"] as? String }) == [
            "list_projects", "create_project", "list_tickets", "get_ticket", "create_ticket", "update_ticket", "add_comment",
        ])
        #expect(tools.allSatisfy { ($0["inputSchema"] as? [String: Any])?["type"] as? String == "object" })

        let project = try session.callTool("create_project", ["name": "API"])
        #expect(!project.isError)
        let created = try session.callTool("create_ticket", ["title": "Add OAuth", "project": "API"])
        #expect(!created.isError)
        let ticket = try #require(try JSONSerialization.jsonObject(with: Data(created.text.utf8)) as? [String: Any])
        #expect(ticket["identifier"] as? String == "ARC-1")

        // The ticket is really in the shared database.
        let shown = try runArc(["show", "ARC-1", "--json"], db: db)
        #expect(shown.status == 0)
        #expect(try shown.json()["title"] as? String == "Add OAuth")
    }

    @Test func toolErrorsAreMarkedAsErrors() throws {
        let session = try MCPSession(db: temporaryDatabasePath())
        defer { session.close() }
        _ = try session.initialize()
        _ = try session.callTool("create_project", ["name": "API"])
        _ = try session.callTool("create_ticket", ["title": "Epic", "project": "API", "kind": "epic"])
        let failure = try session.callTool("create_ticket", ["title": "Sub", "kind": "subtask", "parent": "ARC-1"])
        #expect(failure.isError)
        #expect(failure.text.contains("Subtasks can only belong to tasks"))
    }

    @Test func stdoutCarriesOnlyProtocolMessages() throws {
        let session = try MCPSession(db: temporaryDatabasePath())
        defer { session.close() }
        _ = try session.initialize()
        _ = try session.request("tools/list")
        _ = try session.callTool("list_projects", [:])
        #expect(!session.rawLines.isEmpty)
        for line in session.rawLines {
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            #expect(object?["jsonrpc"] as? String == "2.0", "unexpected stdout line: \(line)")
        }
    }
}
