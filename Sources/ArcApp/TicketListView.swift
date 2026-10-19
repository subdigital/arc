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
                                        isSelected: app.selectedTicketID == row.id
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
    @State private var hovering = false

    private var summary: TicketSummary { item.summary }
    private var ticket: Ticket { summary.ticket }

    var body: some View {
        HStack(spacing: 8) {
            PriorityGlyph(priority: ticket.priority)
            Text(ticket.identifier)
                .font(Theme.metaFont.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 52, alignment: .leading)
            StatusGlyph(status: ticket.status)
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
        .padding(.leading, item.isNested ? 40 : 14)
        .padding(.trailing, 14)
        .frame(height: Theme.rowHeight)
        .background(isSelected ? Theme.bgSelected : (hovering ? Theme.bgHover : Color.clear))
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(Theme.accent).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            app.selectedTicketID = ticket.id
            app.open(ticket: ticket.id)
        }
        .ticketContextMenu(summary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ticket.identifier), \(ticket.title), \(ticket.status.displayName), \(ticket.priority.displayName) priority")
        .accessibilityAddTraits(.isButton)
    }
}
