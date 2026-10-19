import ArcCore
import Foundation

/// The agent skill shipped with Arc. `skills/arc/SKILL.md` is the source of truth; `SkillText.swift`
/// is generated from it by `scripts/embed-skill.sh` and a test keeps the two identical.
public enum ArcSkill {
    public static var content: String { text }

    public struct InstallResult: Codable, Sendable, Equatable {
        public enum Outcome: String, Codable, Sendable { case installed, unchanged, overwritten }
        public var path: String
        public var outcome: Outcome
    }

    /// `~/.claude/skills`, honoring `$HOME`.
    public static var defaultDirectory: URL {
        let home = ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(".claude/skills")
    }

    /// Writes `<directory>/arc/SKILL.md`. An existing file with different content is left alone unless `force`.
    @discardableResult
    public static func install(into directory: URL? = nil, force: Bool = false) throws -> InstallResult {
        let folder = (directory ?? defaultDirectory).appendingPathComponent("arc")
        let file = folder.appendingPathComponent("SKILL.md")
        var outcome = InstallResult.Outcome.installed

        if FileManager.default.fileExists(atPath: file.path) {
            let existing = try? String(contentsOf: file, encoding: .utf8)
            if existing == content {
                return InstallResult(path: file.path, outcome: .unchanged)
            }
            guard force else {
                throw ArcError.conflict("\(file.path) already exists with different content. Use --force to overwrite it.")
            }
            outcome = .overwritten
        }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            throw ArcError.invalidArgument("Could not write \(file.path): \(error.localizedDescription)")
        }
        return InstallResult(path: file.path, outcome: outcome)
    }
}
