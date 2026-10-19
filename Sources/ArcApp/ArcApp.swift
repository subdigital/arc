import AppKit
import ArcCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Always dark, whatever the system appearance is; this also covers sheets, menus and popovers.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Launched outside a .app bundle (swift run, or Xcode running the bare executable), the
        // process defaults to a background policy: no Dock icon, no key window, no keyboard focus.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ArcApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel?
    @State private var startupError: String?

    init() {
        do {
            let model = AppModel(store: try ArcStore())
            model.start()
            _model = State(initialValue: model)
        } catch {
            _startupError = State(initialValue: (error as? ArcError)?.message ?? error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup("Arc") {
            Group {
                if let model {
                    MainWindow().environment(model)
                } else {
                    StartupErrorView(message: startupError ?? "Arc could not open its database.")
                }
            }
            .frame(minWidth: 820, minHeight: 480)
            .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    model?.creation = CreationRequest(projectID: nil)
                }
                .keyboardShortcut("n")
                Button("New Project") {
                    model?.projectEditor = ProjectEditorRequest(mode: .create)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Back") { model?.navigateBack() }
                    .keyboardShortcut("[")
                    .disabled(!(model?.canGoBack ?? false))
                Button("Forward") { model?.navigateForward() }
                    .keyboardShortcut("]")
                    .disabled(!(model?.canGoForward ?? false))
            }
            CommandGroup(after: .toolbar) {
                Button("Switch Between List and Board") {
                    model?.requestLayoutToggle()
                }
                .keyboardShortcut("b")
            }
        }

        .commands {
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { model?.showingShortcuts = true }
                    .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }

        Settings {
            if let model {
                SettingsView().environment(model).preferredColorScheme(.dark)
            }
        }
    }
}

private struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Text("Arc can't open its database").font(.system(size: 15, weight: .semibold))
            Text(message).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgContent)
    }
}
