import AppKit
import ArcAgentKit
import ArcCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AgentsPane()
                .tabItem { Label("Agents", systemImage: "terminal") }
        }
        .frame(width: 560, height: 430)
    }
}

private struct AgentsPane: View {
    @Environment(AppModel.self) private var app
    @State private var installer = CommandLineToolInstaller.standard()
    @State private var installed: CommandLineToolInstaller.Installed?
    @State private var cliMessage: String?
    @State private var skillMessage: String?
    @State private var skillNeedsForce = false
    @State private var copied = false

    private var mcpCommand: String {
        if let installed, installed.isDirectoryOnPath { return "claude mcp add arc -- arc mcp" }
        let path = installed?.linkURL.path ?? installer.source?.path ?? "arc"
        return "claude mcp add arc -- \(path) mcp"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lets you and your agents run `arc` from any terminal.")
                        .font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
                    HStack {
                        Button("Install Command Line Tool") { installCLI() }
                            .disabled(installer.source == nil)
                        if installed != nil {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.green)
                                .font(Theme.metaFont)
                        }
                    }
                    if let installed {
                        Text(installed.linkURL.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        if installed.isDirectoryOnPath {
                            Label("\(installed.linkURL.deletingLastPathComponent().path) is on your PATH", systemImage: "checkmark")
                                .font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
                        } else {
                            Label(
                                "\(installed.linkURL.deletingLastPathComponent().path) is not on your PATH. Add it to your shell profile.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(Theme.metaFont).foregroundStyle(Theme.yellow)
                        }
                    }
                    if let cliMessage {
                        Text(cliMessage).font(Theme.metaFont).foregroundStyle(Theme.yellow)
                    }
                    if installer.source == nil {
                        Text("This build has no bundled `arc` tool. Use scripts/bundle.sh to build Arc.app.")
                            .font(Theme.metaFont).foregroundStyle(Theme.textTertiary)
                    }
                }
            } header: {
                Text("Command line")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Register Arc as an MCP server so agents can list and update tickets.")
                        .font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
                    HStack {
                        Text(mcpCommand)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 6))
                        Button(copied ? "Copied" : "Copy") {
                            app.copyToPasteboard(mcpCommand)
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                copied = false
                            }
                        }
                    }
                }
            } header: {
                Text("MCP server")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Teaches agents the ticket workflow. Installs to ~/.claude/skills/arc/SKILL.md.")
                        .font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
                    HStack {
                        Button("Install Skill") { installSkill(force: false) }
                        if skillNeedsForce {
                            Button("Overwrite") { installSkill(force: true) }
                        }
                    }
                    if let skillMessage {
                        Text(skillMessage).font(Theme.metaFont).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                    }
                }
            } header: {
                Text("Agent skill")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bgContent)
        .onAppear { installed = installer.existingInstall() }
    }

    private func installCLI() {
        do {
            installed = try installer.install()
            cliMessage = nil
        } catch {
            cliMessage = error.localizedDescription
        }
    }

    private func installSkill(force: Bool) {
        do {
            let result = try ArcSkill.install(force: force)
            skillNeedsForce = false
            skillMessage = switch result.outcome {
            case .installed: "Installed \(result.path)"
            case .unchanged: "Already up to date: \(result.path)"
            case .overwritten: "Overwrote \(result.path)"
            }
        } catch let error as ArcError where error.code == .conflict {
            skillNeedsForce = true
            skillMessage = error.message
        } catch {
            skillMessage = (error as? ArcError)?.message ?? error.localizedDescription
        }
    }
}
