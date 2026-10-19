import ArcCore
import SwiftUI

/// Keyboard handling shared by the list and the board: arrows / J / K move the selection,
/// Return opens, S and P open pickers, ⌘⌫ asks to delete.
struct TicketKeyboardNavigation: ViewModifier {
    @Environment(AppModel.self) private var app
    let model: TicketListModel
    let scrollTo: (String) -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(phases: .down) { press in handle(press) }
            .popover(item: pickerBinding, attachmentAnchor: .point(.center), arrowEdge: .bottom) { request in
                PickerPopover(request: request) { index in choose(index, for: request) }
            }
    }

    private var pickerBinding: Binding<PickerRequest?> {
        Binding(get: { app.picker }, set: { app.picker = $0 })
    }

    private func select(_ target: String?) -> KeyPress.Result {
        guard let target else { return .handled }
        app.selectedTicketID = target
        scrollTo(target)
        return .handled
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard !isEditingText else { return .ignored }
        let id = app.selectedTicketID

        if press.modifiers.contains(.command) {
            if press.key == .delete, !app.actionTargets.isEmpty {
                app.pendingDeletionIDs = app.actionTargets
                return .handled
            }
            return .ignored
        }
        if press.key == .escape, !app.checkedTicketIDs.isEmpty {
            app.checkedTicketIDs = []
            return .handled
        }
        guard press.modifiers.isEmpty else { return .ignored }

        switch press.key {
        case .downArrow: return select(model.neighbor(of: id, offset: 1))
        case .upArrow: return select(model.neighbor(of: id, offset: -1))
        case .leftArrow where model.settings.layout == .board: return select(model.boardNeighbor(of: id, columnOffset: -1))
        case .rightArrow where model.settings.layout == .board: return select(model.boardNeighbor(of: id, columnOffset: 1))
        case .return:
            if let id { app.open(ticket: id) }
            return .handled
        default: break
        }
        switch press.characters {
        case "j": return select(model.neighbor(of: id, offset: 1))
        case "k": return select(model.neighbor(of: id, offset: -1))
        case "x":
            if let id { app.toggleChecked(id) }
            return .handled
        case "s":
            let targets = app.actionTargets
            if !targets.isEmpty { app.picker = PickerRequest(ticketIDs: targets, kind: .status) }
            return .handled
        case "p":
            let targets = app.actionTargets
            if !targets.isEmpty { app.picker = PickerRequest(ticketIDs: targets, kind: .priority) }
            return .handled
        default: return .ignored
        }
    }

    private func choose(_ index: Int, for request: PickerRequest) {
        app.picker = nil
        Task { await app.applyPick(index, for: request) }
    }
}

extension View {
    func ticketKeyboardNavigation(model: TicketListModel, scrollTo: @escaping (String) -> Void) -> some View {
        modifier(TicketKeyboardNavigation(model: model, scrollTo: scrollTo))
    }
}
