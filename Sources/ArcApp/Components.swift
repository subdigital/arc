import ArcCore
import SwiftUI

extension TicketStatus {
    /// SF Symbol approximations for places (menus) that cannot show the custom glyphs.
    var menuSymbol: String {
        switch self {
        case .backlog: "circle.dashed"
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .inReview: "circle.inset.filled"
        case .done: "checkmark.circle.fill"
        case .canceled: "xmark.circle.fill"
        }
    }
}

extension TicketPriority {
    var menuSymbol: String {
        switch self {
        case .urgent: "exclamationmark.square.fill"
        case .high: "cellularbars"
        case .medium: "cellularbars"
        case .low: "cellularbars"
        case .none: "minus"
        }
    }

    /// Display order in menus: None first, then Urgent → Low.
    static let menuOrder: [TicketPriority] = [.none, .urgent, .high, .medium, .low]
}

extension Date {
    /// "Oct 19" style for list rows.
    var shortDate: String { formatted(.dateTime.month(.abbreviated).day()) }
}

// MARK: - Menu content shared by context menus, the detail page and toolbars

struct StatusMenuItems: View {
    var current: TicketStatus?
    var action: (TicketStatus) -> Void

    var body: some View {
        ForEach(TicketStatus.allCases, id: \.self) { status in
            Button {
                action(status)
            } label: {
                Label(status.displayName, systemImage: current == status ? "checkmark" : status.menuSymbol)
            }
        }
    }
}

struct PriorityMenuItems: View {
    var current: TicketPriority?
    var action: (TicketPriority) -> Void

    var body: some View {
        ForEach(TicketPriority.menuOrder, id: \.self) { priority in
            Button {
                action(priority)
            } label: {
                Label(priority.displayName, systemImage: current == priority ? "checkmark" : priority.menuSymbol)
            }
        }
    }
}

/// The right-click menu for a ticket row or card.
struct TicketContextMenu: ViewModifier {
    let summary: TicketSummary
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.contextMenu {
            let ticket = summary.ticket
            // Right-clicking a ticked row acts on every ticked row; any other row acts alone.
            let targets = app.contextTargets(for: ticket.id)
            let many = targets.count > 1
            Menu("Status") {
                StatusMenuItems(current: many ? nil : ticket.status) { status in
                    Task { await app.bulkUpdate(targets, TicketPatch(status: status), done: "Updated") }
                }
            }
            Menu("Priority") {
                PriorityMenuItems(current: many ? nil : ticket.priority) { priority in
                    Task { await app.bulkUpdate(targets, TicketPatch(priority: priority), done: "Updated") }
                }
            }
            Menu("Parent") {
                Button("Set Parent…") { app.parentPicking = targets }
                if many || ticket.parentId != nil {
                    Button("Remove Parent") { Task { await app.setParent(nil, for: targets) } }
                }
            }
            Menu("Move to Project") {
                ForEach(app.projects) { project in
                    Button(project.name) { Task { await app.bulkUpdate(targets, TicketPatch(projectId: project.id), done: "Moved") } }
                        .disabled(!many && project.id == ticket.projectId)
                }
            }
            Divider()
            if !many {
                Button("Copy ID") { app.copyToPasteboard(ticket.identifier) }
                Button("Copy Title with ID") { app.copyToPasteboard("\(ticket.identifier) \(ticket.title)") }
                Divider()
            }
            Button(many ? "Delete \(targets.count) Tickets…" : "Delete…", role: .destructive) { app.pendingDeletionIDs = targets }
        }
    }
}

extension View {
    func ticketContextMenu(_ summary: TicketSummary) -> some View {
        modifier(TicketContextMenu(summary: summary))
    }
}

// MARK: - Keyboard pickers (S / P)

/// A small popover listing statuses or priorities with their glyphs; number keys pick too.
struct PickerPopover: View {
    let request: PickerRequest
    let pick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch request.kind {
            case .status:
                ForEach(Array(TicketStatus.allCases.enumerated()), id: \.offset) { index, status in
                    row(index: index) { StatusGlyph(status: status) } label: { status.displayName }
                }
            case .priority:
                ForEach(Array(TicketPriority.menuOrder.enumerated()), id: \.offset) { index, priority in
                    row(index: index) { PriorityGlyph(priority: priority) } label: { priority.displayName }
                }
            }
        }
        .padding(6)
        .frame(width: 180)
        .background(Theme.bgElevated)
        .onKeyPress(phases: .down) { press in
            if let digit = Int(press.characters), digit >= 1, digit <= (request.kind == .status ? 6 : 5) {
                pick(digit - 1)
                return .handled
            }
            return .ignored
        }
    }

    private func row<Glyph: View>(index: Int, @ViewBuilder glyph: () -> Glyph, label: () -> String) -> some View {
        Button {
            pick(index)
        } label: {
            HStack(spacing: 8) {
                glyph()
                Text(label()).font(Theme.rowFont)
                Spacer()
                Text("\(index + 1)").font(Theme.metaFont).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowButtonStyle())
    }
}

struct HoverRowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.textPrimary)
            .background(hovering || configuration.isPressed ? Theme.bgHover : .clear, in: RoundedRectangle(cornerRadius: 5))
            .onHover { hovering = $0 }
    }
}

// MARK: - Small shared pieces

struct FlatChip: View {
    var title: String
    var systemImage: String?
    var isActive = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 11)) }
            Text(title).font(Theme.metaFont)
        }
        .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(isActive ? Theme.bgSelected : Theme.bgElevated, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var buttonTitle: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
            Text(message).font(Theme.rowFont).foregroundStyle(Theme.textSecondary)
            Button(buttonTitle, action: action)
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Theme.bgElevated.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
    }
}
