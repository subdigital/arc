import AppKit
import ArcCore
import SwiftUI
import UniformTypeIdentifiers

/// What travels during a drag: the ticket's id.
struct TicketDragItem: Codable, Transferable {
    var id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct BoardView: View {
    @Environment(AppModel.self) private var app
    let model: TicketListModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(model.boardColumns) { column in
                        BoardColumnView(column: column, model: model)
                    }
                }
                .padding(14)
            }
            .ticketKeyboardNavigation(model: model) { id in proxy.scrollTo(id) }
        }
    }
}

private struct BoardColumnView: View {
    @Environment(AppModel.self) private var app
    let column: BoardColumn
    let model: TicketListModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatusGlyph(status: column.status)
                Text(column.status.displayName).font(Theme.headerFont).foregroundStyle(Theme.textPrimary)
                Text("\(column.cards.count)").font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 26)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(column.cards) { card in
                        BoardCardView(summary: card, column: column, showProject: model.scope == .allTasks)
                            .id(card.id)
                    }
                    Color.clear.frame(height: 40)
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .dropDestination(for: TicketDragItem.self) { items, _ in
                guard let item = items.first else { return false }
                move(item.id, to: .bottom)
                return true
            } isTargeted: { isTargeted = $0 }
        }
        .padding(8)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(isTargeted ? Theme.bgHover : Theme.bgSidebar, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.status.displayName), \(column.cards.count) tickets")
    }

    private func move(_ id: String, to position: TicketPosition) {
        Task {
            await app.perform {
                try await app.store.moveTicket(id: id, status: column.status, position: position)
            }
        }
    }
}

struct BoardCardView: View {
    @Environment(AppModel.self) private var app
    let summary: TicketSummary
    let column: BoardColumn
    let showProject: Bool
    @State private var hovering = false
    @State private var height: CGFloat = 60
    @State private var dropEdge: VerticalEdge?

    private var ticket: Ticket { summary.ticket }
    private var isSelected: Bool { app.selectedTicketID == ticket.id }
    private var isChecked: Bool { app.checkedTicketIDs.contains(ticket.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(ticket.identifier)
                    .font(Theme.metaFont.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                PriorityGlyph(priority: ticket.priority)
            }
            Text(ticket.title)
                .font(Theme.rowFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if summary.parent != nil || summary.childCount > 0 || showProject {
                HStack(spacing: 6) {
                    if let parent = summary.parent {
                        Text(parent.title)
                            .font(Theme.metaFont)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Theme.bgSelected, in: RoundedRectangle(cornerRadius: 4))
                    }
                    if summary.childCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "checklist").font(.system(size: 10))
                            Text("\(summary.childrenDone)/\(summary.childCount)").font(Theme.metaFont.monospacedDigit())
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if showProject {
                        Text(summary.projectName)
                            .font(Theme.metaFont)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(isChecked ? Theme.accent.opacity(0.18) : (hovering ? Theme.bgHover : Theme.bgElevated), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected || isChecked ? Theme.accent : Theme.border, lineWidth: isSelected || isChecked ? 1.5 : 1)
        )
        .overlay(alignment: dropEdge == .top ? .top : .bottom) {
            if dropEdge != nil {
                Capsule().fill(Theme.accent).frame(height: 2).padding(.horizontal, 2).offset(y: dropEdge == .top ? -4 : 4)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .onTapGesture {
            app.selectedTicketID = ticket.id
            if NSEvent.modifierFlags.contains(.command) {
                app.toggleChecked(ticket.id)
            } else {
                app.open(ticket: ticket.id)
            }
        }
        .draggable(TicketDragItem(id: ticket.id))
        .dropDestination(for: TicketDragItem.self) { items, location in
            guard let item = items.first, item.id != ticket.id else { return false }
            let before = location.y < height / 2
            Task {
                await app.perform {
                    try await app.store.moveTicket(
                        id: item.id,
                        status: column.status,
                        position: before ? .before(ticket.id) : .after(ticket.id)
                    )
                }
            }
            return true
        } isTargeted: { targeted in
            dropEdge = targeted ? .top : nil
        }
        .ticketContextMenu(summary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ticket.identifier), \(ticket.title), \(ticket.priority.displayName) priority")
        .accessibilityAddTraits(.isButton)
    }
}
