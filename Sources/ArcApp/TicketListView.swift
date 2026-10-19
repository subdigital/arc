import AppKit
import ArcCore
import SwiftUI

struct TicketListView: View {
    @Environment(AppModel.self) private var app
    let model: TicketListModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.listGroups) { group in
                        Section {
                            if !model.isCollapsed(group.status) {
                                ForEach(group.rows) { row in
                                    TicketRowView(
                                        item: row,
                                        showProject: model.scope == .allTasks,
                                        isSelected: app.selectedTicketID == row.id,
                                        isChecked: app.checkedTicketIDs.contains(row.id),
                                        order: model.navigationOrder
                                    )
                                    .id(row.id)
                                }
                            }
                        } header: {
                            GroupHeader(group: group, isCollapsed: model.isCollapsed(group.status)) {
                                model.toggleCollapsed(group.status)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ticketKeyboardNavigation(model: model) { id in proxy.scrollTo(id) }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

struct GroupHeader: View {
    let group: StatusGroup
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 10)
                StatusGlyph(status: group.status)
                Text(group.status.displayName).font(Theme.headerFont).foregroundStyle(Theme.textPrimary)
                Text("\(group.count)").font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(Theme.bgSidebar)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.status.displayName), \(group.count) tickets, \(isCollapsed ? "collapsed" : "expanded")")
    }
}

struct TicketRowView: View {
    @Environment(AppModel.self) private var app
    let item: TicketRowItem
    let showProject: Bool
    let isSelected: Bool
    let isChecked: Bool
    let order: [String]
    @State private var hovering = false
    @State private var picker: PickerRequest.Kind?

    private var summary: TicketSummary { item.summary }
    private var ticket: Ticket { summary.ticket }

    var body: some View {
        HStack(spacing: 8) {
            checkbox
            glyphButton(.priority) { PriorityGlyph(priority: ticket.priority) }
            Text(ticket.identifier)
                .font(Theme.metaFont.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 52, alignment: .leading)
            glyphButton(.status) { StatusGlyph(status: ticket.status) }
            Text(ticket.title)
                .font(Theme.rowFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Group {
                if let epic = summary.epic, ticket.kind != .epic {
                    Text(epic.title)
                        .font(Theme.metaFont)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(width: 150, alignment: .leading)
            Group {
                if summary.subtaskCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "checklist").font(.system(size: 10))
                        Text("\(summary.subtasksDone)/\(summary.subtaskCount)").font(Theme.metaFont.monospacedDigit())
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 44, alignment: .leading)
            if showProject {
                Text(summary.projectName)
                    .font(Theme.metaFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
            }
            Text(ticket.updatedAt.shortDate)
                .font(Theme.metaFont)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.leading, item.isNested ? 40 : 10)
        .padding(.trailing, 14)
        .frame(height: Theme.rowHeight)
        .background(isChecked ? Theme.accent.opacity(0.18) : (isSelected ? Theme.bgSelected : (hovering ? Theme.bgHover : Color.clear)))
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(Theme.accent).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { click() }
        .ticketContextMenu(summary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ticket.identifier), \(ticket.title), \(ticket.status.displayName), \(ticket.priority.displayName) priority")
        .accessibilityAddTraits(.isButton)
    }

    private var checkbox: some View {
        Button {
            app.selectedTicketID = ticket.id
            app.toggleChecked(ticket.id)
        } label: {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .font(.system(size: 13))
                .foregroundStyle(isChecked ? Theme.accent : Theme.textTertiary)
                .frame(width: 16, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isChecked || hovering || !app.checkedTicketIDs.isEmpty ? 1 : 0)
        .help("Select (X)")
        .accessibilityLabel(isChecked ? "Deselect \(ticket.identifier)" : "Select \(ticket.identifier)")
    }

    /// A glyph that opens the status/priority picker when clicked.
    private func glyphButton<Glyph: View>(_ kind: PickerRequest.Kind, @ViewBuilder _ glyph: () -> Glyph) -> some View {
        Button {
            picker = kind
        } label: {
            glyph().padding(3).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(kind == .status ? "Change status" : "Change priority")
        .popover(isPresented: Binding(get: { picker == kind }, set: { if !$0 { picker = nil } }), arrowEdge: .bottom) {
            let request = PickerRequest(ticketIDs: [ticket.id], kind: kind)
            PickerPopover(request: request) { index in
                picker = nil
                Task { await app.applyPick(index, for: request) }
            }
        }
    }

    private func click() {
        app.selectedTicketID = ticket.id
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            app.checkRange(to: ticket.id, order: order)
        } else if modifiers.contains(.command) {
            app.toggleChecked(ticket.id)
        } else {
            app.open(ticket: ticket.id)
        }
    }
}
