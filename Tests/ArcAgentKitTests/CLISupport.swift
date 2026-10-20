import Foundation
import Testing

struct CLIResult {
    var status: Int32
    var stdout: String
    var stderr: String

    func json() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(stdout.utf8))
        return try #require(object as? [String: Any])
    }

    func jsonArray() throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: Data(stdout.utf8))
        return try #require(object as? [[String: Any]])
    }
}

/// Where `swift build` puts the `arc` executable for this package.
let arcExecutableURL: URL = {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return root.appendingPathComponent(".build/debug/arc")
}()

func temporaryDatabasePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("arc-cli-tests-\(UUID().uuidString)")
        .appendingPathComponent("arc.sqlite")
        .path
}

/// Runs the built `arc` binary against an isolated database.
@discardableResult
/// Change notifications are suppressed unless `notify` is true, so parallel tests do not wake each other's listeners.
func runArc(_ arguments: [String], db: String, stdin: String? = nil, home: String? = nil, notify: Bool = false) throws -> CLIResult {
    let process = Process()
    process.executableURL = arcExecutableURL
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment["ARC_DB_PATH"] = db
    if !notify { environment["ARC_NO_NOTIFY"] = "1" }
    if let home { environment["HOME"] = home }
    process.environment = environment

    // Output goes to files rather than pipes: no reader threads, and no deadlock on large output.
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("arc-run-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let outURL = scratch.appendingPathComponent("stdout"), errURL = scratch.appendingPathComponent("stderr")
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    FileManager.default.createFile(atPath: errURL.path, contents: nil)
    let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
    let input = Pipe()
    process.standardOutput = out
    process.standardError = err
    process.standardInput = input

    try process.run()
    try out.close()
    try err.close()
    try input.fileHandleForReading.close()
    if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
    try input.fileHandleForWriting.close()
    process.waitUntilExit()

    return CLIResult(
        status: process.terminationStatus,
        stdout: String(decoding: try Data(contentsOf: outURL), as: UTF8.self),
        stderr: String(decoding: try Data(contentsOf: errURL), as: UTF8.self)
    )
}
