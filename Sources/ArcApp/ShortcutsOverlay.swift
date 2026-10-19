import SwiftUI

/// All keyboard shortcuts, grouped. Opened with `?`; Esc (or `?` again) closes it.
struct ShortcutsOverlay: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    private struct Section: Identifiable {
        var title: String
        var items: [(keys: String, label: String)]
        var id: String { title }
    }

    private let sections: [Section] = [
        Section(title: "Anywhere", items: [
            ("C", "New task"),
            ("⌘N", "New task"),
            ("⇧⌘N", "New project"),
            ("⌘B", "Switch between list and board"),
            ("?", "Show this panel"),
            ("⌘,", "Settings"),
        ]),
        Section(title: "List and board", items: [
            ("↑ ↓  or  K J", "Move selection"),
            ("← →", "Move between board columns"),
            ("↩", "Open the selected ticket"),
            ("S", "Change status"),
            ("P", "Change priority"),
            ("⌘⌫", "Delete (asks first)"),
        ]),
        Section(title: "Ticket page", items: [
            ("Esc", "Go back"),
            ("⌘↩", "Post comment"),
            ("⌘⌫", "Delete (asks first)"),
        ]),
        Section(title: "New ticket form", items: [
            ("⌘↩", "Create"),
            ("Esc", "Cancel"),
        ]),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Keyboard shortcuts").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("Esc to close").font(Theme.metaFont).foregroundStyle(Theme.textTertiary)
                }
                Grid(alignment: .topLeading, horizontalSpacing: 40, verticalSpacing: 20) {
                    GridRow {
                        column(sections[0])
                        column(sections[1])
                    }
                    GridRow {
                        column(sections[2])
                        column(sections[3])
                    }
                }
            }
            .padding(24)
            .frame(width: 620)
            .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in
            if press.key == .escape || press.characters == "?" {
                close()
            }
            return .handled // modal: nothing underneath should see keys
        }
        .accessibilityAddTraits(.isModal)
    }

    private func close() { app.showingShortcuts = false }

    private func column(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title).font(Theme.headerFont).foregroundStyle(Theme.textSecondary)
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Text(item.keys)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 24, minHeight: 20)
                        .background(Theme.bgSelected, in: RoundedRectangle(cornerRadius: 4))
                    Text(item.label).font(Theme.rowFont).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            Text(message).font(Theme.rowFont).foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Theme.bgElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}
