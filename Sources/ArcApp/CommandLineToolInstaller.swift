import Foundation

/// Installs the bundled `arc` executable by symlinking it into a directory on the user's PATH.
/// Tries `/usr/local/bin` first and falls back to `~/.local/bin`. Never asks for privileges.
struct CommandLineToolInstaller {
    struct Installed: Equatable {
        var linkURL: URL
        var isDirectoryOnPath: Bool
    }

    enum InstallError: LocalizedError, Equatable {
        case toolNotFound
        case blockedByFile(String)
        case noWritableDirectory

        var errorDescription: String? {
            switch self {
            case .toolNotFound:
                "The command-line tool is not part of this build. Run scripts/bundle.sh and open build/Arc.app."
            case .blockedByFile(let path):
                "\(path) already exists and is not a link created by Arc. Remove it or install manually."
            case .noWritableDirectory:
                "Could not write to /usr/local/bin or ~/.local/bin."
            }
        }
    }

    var source: URL?
    var candidateDirectories: [URL]
    var pathVariable: String
    var fileManager: FileManager = .default

    static func standard(
        bundle: Bundle = .main,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        pathVariable: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> CommandLineToolInstaller {
        CommandLineToolInstaller(
            source: bundledTool(in: bundle),
            candidateDirectories: [
                URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
                home.appendingPathComponent(".local/bin", isDirectory: true),
            ],
            pathVariable: pathVariable
        )
    }

    /// `Arc.app/Contents/Helpers/arc`, or an `arc` next to the executable when running unbundled.
    static func bundledTool(in bundle: Bundle) -> URL? {
        let helper = bundle.bundleURL.appendingPathComponent("Contents/Helpers/arc")
        if FileManager.default.isExecutableFile(atPath: helper.path) { return helper }
        let sibling = bundle.executableURL?.deletingLastPathComponent().appendingPathComponent("arc")
        if let sibling, FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        return nil
    }

    func isOnPath(_ directory: URL) -> Bool {
        let target = directory.standardizedFileURL.path
        return pathVariable.split(separator: ":").contains { URL(fileURLWithPath: String($0)).standardizedFileURL.path == target }
    }

    /// Where an installed link currently points, if `arc` is already linked in one of the candidates.
    func existingInstall() -> Installed? {
        for directory in candidateDirectories {
            let link = directory.appendingPathComponent("arc")
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path), destination == source?.path {
                return Installed(linkURL: link, isDirectoryOnPath: isOnPath(directory))
            }
        }
        return nil
    }

    func install() throws -> Installed {
        guard let source else { throw InstallError.toolNotFound }
        var blocker: InstallError?
        for directory in candidateDirectories {
            let link = directory.appendingPathComponent("arc")
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != nil {
                    try fileManager.removeItem(at: link)
                } else if fileManager.fileExists(atPath: link.path) {
                    blocker = .blockedByFile(link.path)
                    continue
                }
                try fileManager.createSymbolicLink(at: link, withDestinationURL: source)
                return Installed(linkURL: link, isDirectoryOnPath: isOnPath(directory))
            } catch {
                continue // not writable: try the next directory
            }
        }
        throw blocker ?? InstallError.noWritableDirectory
    }
}
