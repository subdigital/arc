import ArcAgentKit
import ArcCore
import ArgumentParser
import Foundation

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Print the result as one JSON document (errors as {\"error\": {...}}).")
    var json = false
}

enum CLI {
    /// Opens the store, runs `body`, prints the result, and maps failures to exit status 1.
    static func execute<T: Encodable & Sendable>(
        _ options: GlobalOptions,
        render: (T) -> String,
        _ body: @Sendable (ArcOperations) async throws -> T
    ) async throws {
        do {
            let operations = ArcOperations(store: try ArcStore())
            let value = try await body(operations)
            if options.json {
                print(try ArcJSON.string(value))
            } else {
                print(render(value))
            }
        } catch {
            try fail(error, json: options.json)
        }
    }

    /// Reports `error` (JSON on stdout with `--json`, otherwise a message on stderr) and exits with status 1.
    static func fail(_ error: Error, json: Bool) throws -> Never {
        let arcError = (error as? ArcError) ?? ArcError(.internal, String(describing: error))
        if json {
            print((try? ArcJSON.string(ArcErrorDTO(arcError))) ?? #"{"error":{"code":"internal","message":"unknown"}}"#)
        } else {
            FileHandle.standardError.write(Data("arc: \(arcError.message)\n".utf8))
        }
        throw ExitCode.failure
    }

    /// Reads all of standard input, up to 1 MB.
    static func readStandardInput() throws -> String {
        let limit = 1_048_576
        let data = try FileHandle.standardInput.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else {
            throw ArcError.invalidArgument("Input from stdin is larger than 1 MB.")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// `-` means "read the value from stdin".
    static func resolveStdin(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard value == "-" else { return value }
        // A trailing newline from `echo` or a heredoc is not part of the intended text.
        var text = try readStandardInput()
        while text.hasSuffix("\n") { text.removeLast() }
        return text
    }
}
