import ArcCore
import SwiftUI

/// Search-as-you-type list of tickets, used to choose a parent.
struct TicketSearchList: View {
    @Environment(AppModel.self) private var app
    var excluding: Set<String> = []
    /// Offers a "No parent" row that picks `nil`.
    var allowsClear = true
    let onPick: (String?) -> Void

    @State private var text = ""
    @State private var results: [TicketSummary] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search tickets…", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.rowFont)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .focused($focused)
                .onSubmit { if let first = results.first { onPick(first.ticket.id) } }
            Divider().overlay(Theme.border)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if allowsClear {
                        row(title: "No parent", identifier: nil, status: nil) { onPick(nil) }
                    }
                    ForEach(results) { summary in
                        row(title: summary.ticket.title, identifier: summary.ticket.identifier, status: summary.ticket.status) {
                            onPick(summary.ticket.id)
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 300)
        .background(Theme.bgContent)
        .onAppear { focused = true }
        .task(id: text) {
            // Typing debounces; the first load (empty text) runs immediately.
            if !text.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled else { return }
            let query = TicketQuery(text: text, includeClosed: true, limit: 40)
            if let found = try? await app.store.tickets(matching: query) {
                results = found.filter { !excluding.contains($0.ticket.id) }
            }
        }
    }

    private func row(title: String, identifier: String?, status: TicketStatus?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let status { StatusGlyph(status: status) } else { Color.clear.frame(width: 14, height: 14) }
                Text(identifier ?? "")
                    .font(Theme.metaFont.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 58, alignment: .leading)
                Text(title).font(Theme.rowFont).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Sheet that sets the parent of the tickets in `app.parentPicking`.
struct ParentPickerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ticketIDs: [String]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(ticketIDs.count == 1 ? "Set parent" : "Set parent for \(ticketIDs.count) tickets")
                    .font(Theme.headerFont)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider().overlay(Theme.border)
            TicketSearchList(excluding: Set(ticketIDs)) { parentID in
                dismiss()
                Task { await app.setParent(parentID, for: ticketIDs) }
            }
        }
        .background(Theme.bgContent)
        .preferredColorScheme(.dark)
    }
}
