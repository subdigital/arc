import Foundation
import Testing
@testable import ArcAgentKit

@Suite struct SkillTests {
    private static let skillFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("skills/arc/SKILL.md")

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("arc-skill-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func embeddedConstantMatchesFileByteForByte() throws {
        let fileData = try Data(contentsOf: Self.skillFile)
        #expect(Data(ArcSkill.content.utf8) == fileData,
                "SKILL.md changed: run scripts/embed-skill.sh to regenerate Sources/ArcAgentKit/SkillText.swift")
    }

    @Test func skillHasFrontmatterAndWorkflow() {
        let text = ArcSkill.content
        #expect(text.hasPrefix("---\nname: arc\ndescription: "))
        let frontmatterEnd = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex)
        #expect(frontmatterEnd != nil)
        for needle in [
            "ARC-12", "in_progress", "in_review", "backlog", "canceled",
            "GitHub Flavored Markdown", "- [ ]", "list_tickets", "update_ticket", "add_comment",
            "arc list", "--json", "claude mcp add arc -- arc mcp", "never reused",
        ] {
            #expect(text.contains(needle), "skill should mention \(needle)")
        }
        #expect(text.contains("Claim it"))
        #expect(!text.contains(" \n"), "no trailing whitespace")
    }

    @Test func installWritesSkillAndReportsPath() throws {
        let directory = try temporaryDirectory()
        let result = try ArcSkill.install(into: directory)
        #expect(result.outcome == .installed)
        #expect(result.path == directory.appendingPathComponent("arc/SKILL.md").path)
        #expect(try String(contentsOfFile: result.path, encoding: .utf8) == ArcSkill.content)
    }

    @Test func reinstallIsANoOp() throws {
        let directory = try temporaryDirectory()
        try ArcSkill.install(into: directory)
        #expect(try ArcSkill.install(into: directory).outcome == .unchanged)
    }

    @Test func differingFileIsKeptWithoutForce() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("arc/SKILL.md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "my edits".write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) { try ArcSkill.install(into: directory) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "my edits")

        let forced = try ArcSkill.install(into: directory, force: true)
        #expect(forced.outcome == .overwritten)
        #expect(try String(contentsOf: file, encoding: .utf8) == ArcSkill.content)
    }

    @Test func cliInstallsIntoDir() throws {
        let directory = try temporaryDirectory()
        let db = temporaryDatabasePath()
        let result = try runArc(["skill", "install", "--dir", directory.path], db: db)
        #expect(result.status == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == directory.appendingPathComponent("arc/SKILL.md").path)

        try "changed".write(to: directory.appendingPathComponent("arc/SKILL.md"), atomically: true, encoding: .utf8)
        let refused = try runArc(["skill", "install", "--dir", directory.path, "--json"], db: db)
        #expect(refused.status == 1)
        #expect((try refused.json()["error"] as? [String: Any])?["code"] as? String == "conflict")
        #expect(try runArc(["skill", "install", "--dir", directory.path, "--force"], db: db).status == 0)
    }

    @Test func defaultLocationIsUnderTheHomeDirectory() throws {
        let home = try temporaryDirectory()
        let result = try runArc(["skill", "install"], db: temporaryDatabasePath(), home: home.path)
        #expect(result.status == 0)
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/skills/arc/SKILL.md").path))
    }
}
