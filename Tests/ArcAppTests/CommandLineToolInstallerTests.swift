import Foundation
import Testing
@testable import ArcApp

@Suite struct CommandLineToolInstallerTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("arc-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fakeTool(in directory: URL) throws -> URL {
        let tool = directory.appendingPathComponent("arc-source")
        try "#!/bin/sh\necho hi\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return tool
    }

    @Test func linksIntoTheFirstWritableDirectory() throws {
        let root = try scratch()
        let tool = try fakeTool(in: root)
        let first = root.appendingPathComponent("first/bin")
        let installer = CommandLineToolInstaller(source: tool, candidateDirectories: [first], pathVariable: "/usr/bin:\(first.path)")
        let result = try installer.install()
        #expect(result.linkURL == first.appendingPathComponent("arc"))
        #expect(result.isDirectoryOnPath)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: result.linkURL.path) == tool.path)
        #expect(installer.existingInstall() == result)
    }

    @Test func fallsBackWhenTheFirstDirectoryIsNotWritable() throws {
        let root = try scratch()
        let tool = try fakeTool(in: root)
        // A regular file where a directory is needed makes the first candidate unusable.
        let blocked = root.appendingPathComponent("blocked")
        try "x".write(to: blocked, atomically: true, encoding: .utf8)
        let fallback = root.appendingPathComponent("home/.local/bin")
        let installer = CommandLineToolInstaller(
            source: tool,
            candidateDirectories: [blocked.appendingPathComponent("bin"), fallback],
            pathVariable: "/usr/bin"
        )
        let result = try installer.install()
        #expect(result.linkURL == fallback.appendingPathComponent("arc"))
        #expect(!result.isDirectoryOnPath, "the pane must warn when the directory is not on PATH")
    }

    @Test func replacesAStaleLinkButNeverARealFile() throws {
        let root = try scratch()
        let tool = try fakeTool(in: root)
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("arc"), withDestinationURL: URL(fileURLWithPath: "/nonexistent"))

        let installer = CommandLineToolInstaller(source: tool, candidateDirectories: [bin], pathVariable: "")
        _ = try installer.install()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: bin.appendingPathComponent("arc").path) == tool.path)

        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "real file".write(to: other.appendingPathComponent("arc"), atomically: true, encoding: .utf8)
        let blocked = CommandLineToolInstaller(source: tool, candidateDirectories: [other], pathVariable: "")
        #expect(throws: CommandLineToolInstaller.InstallError.blockedByFile(other.appendingPathComponent("arc").path)) {
            try blocked.install()
        }
        #expect(try String(contentsOf: other.appendingPathComponent("arc"), encoding: .utf8) == "real file")
    }

    @Test func missingToolIsReported() {
        let installer = CommandLineToolInstaller(source: nil, candidateDirectories: [], pathVariable: "")
        #expect(throws: CommandLineToolInstaller.InstallError.toolNotFound) { try installer.install() }
    }

    @Test func pathDetectionIgnoresTrailingSlashesAndEmptyEntries() {
        let installer = CommandLineToolInstaller(
            source: nil, candidateDirectories: [], pathVariable: ":/usr/local/bin/::/opt/homebrew/bin"
        )
        #expect(installer.isOnPath(URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)))
        #expect(!installer.isOnPath(URL(fileURLWithPath: "/home/me/.local/bin", isDirectory: true)))
    }

    @Test func findsTheBundledHelper() throws {
        let root = try scratch()
        let app = root.appendingPathComponent("Fake.app")
        let helpers = app.appendingPathComponent("Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        _ = try fakeTool(in: helpers)
        try FileManager.default.moveItem(at: helpers.appendingPathComponent("arc-source"), to: helpers.appendingPathComponent("arc"))
        let bundle = try #require(Bundle(url: app) ?? Bundle(path: app.path))
        #expect(CommandLineToolInstaller.bundledTool(in: bundle)?.lastPathComponent == "arc")
    }
}
