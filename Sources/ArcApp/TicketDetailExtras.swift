import AppKit
import ArcCore
import SwiftUI

// MARK: - Labels

/// The ticket's labels as removable chips, plus a button that opens the label picker.
struct LabelsRow: View {
    @Environment(AppModel.self) private var app
    let ticketID: String
    let labels: [TicketLabel]
    @State private var showingPicker = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(labels) { label in
                LabelChip(label: label) {
                    Task { await app.perform { try await app.store.removeLabel(ticketId: ticketID, labelId: label.id) } }
                }
            }
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tag").font(.system(size: 10))
                    if labels.isEmpty { Text("Add label").font(Theme.metaFont) }
                }
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .overlay(Capsule().strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            .buttonStyle(.plain)
            .help("Add or remove labels")
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                LabelPicker(ticketID: ticketID, selected: Set(labels.map(\.id))).environment(app)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Search the existing labels, toggle them on the ticket, or create a new one by typing its name.
struct LabelPicker: View {
    @Environment(AppModel.self) private var app
    let ticketID: String
    @State var selected: Set<String>
    @State private var all: [TicketLabel] = []
    @State private var text = ""
    @FocusState private var focused: Bool

    private var matches: [TicketLabel] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? all : all.filter { $0.nameKey.contains(query) }
    }

    private var canCreate: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !all.contains { $0.nameKey == trimmed.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Find or create a label…", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.rowFont)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .focused($focused)
                .onSubmit { submit() }
            Divider().overlay(Theme.border)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches) { label in
                        Button {
                            toggle(label)
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(Color(hexString: label.color)).frame(width: 9, height: 9)
                                Text(label.name).font(Theme.rowFont).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if selected.contains(label.id) { Image(systemName: "checkmark").font(.system(size: 11)) }
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if canCreate {
                        Button { create() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus").font(.system(size: 11))
                                Text("Create “\(text.trimmingCharacters(in: .whitespaces))”").font(Theme.rowFont)
                                Spacer()
                            }
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 260, height: 260)
        .background(Theme.bgContent)
        .task { all = (try? await app.store.labels()) ?? [] }
        .onAppear { focused = true }
    }

    private func toggle(_ label: TicketLabel) {
        if selected.contains(label.id) {
            selected.remove(label.id)
            Task { await app.perform { try await app.store.removeLabel(ticketId: ticketID, labelId: label.id) } }
        } else {
            selected.insert(label.id)
            Task { await app.perform { try await app.store.addLabel(ticketId: ticketID, name: label.name) } }
        }
    }

    private func create() {
        let name = text.trimmingCharacters(in: .whitespaces)
        text = ""
        Task {
            if let labels = await app.perform({ try await app.store.addLabel(ticketId: ticketID, name: name) }) {
                selected = Set(labels.map(\.id))
                all = (try? await app.store.labels()) ?? all
            }
        }
    }

    private func submit() {
        if canCreate { create() } else if let first = matches.first { toggle(first) }
    }
}

// MARK: - Relations

enum RelationChoice: String, Identifiable, CaseIterable {
    case blocks, blockedBy, related, duplicateOf
    var id: String { rawValue }

    var title: String {
        switch self {
        case .blocks: "Blocks…"
        case .blockedBy: "Blocked by…"
        case .related: "Related to…"
        case .duplicateOf: "Duplicate of…"
        }
    }

    var symbol: String {
        switch self {
        case .blocks: "hand.raised"
        case .blockedBy: "hand.raised.fill"
        case .related: "link"
        case .duplicateOf: "doc.on.doc"
        }
    }
}

/// Blocks / blocked by / related / duplicates, as seen from this ticket, with add and remove.
struct RelationsSection: View {
    @Environment(AppModel.self) private var app
    let ticket: Ticket
    let relations: TicketRelations
    @State private var adding: RelationChoice?

    private var groups: [(title: String, choice: RelationChoice?, kind: RelationKind, refs: [TicketRef])] {
        [
            ("Blocked by", .blockedBy, .blockedBy, relations.blockedBy),
            ("Blocks", .blocks, .blocks, relations.blocks),
            ("Related", .related, .related, relations.related),
            ("Duplicate of", .duplicateOf, .duplicateOf, relations.duplicateOf),
            ("Duplicated by", nil, .duplicatedBy, relations.duplicatedBy),
        ].filter { !$0.3.isEmpty }
    }

    enum RelationKind { case blocks, blockedBy, related, duplicateOf, duplicatedBy }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Relations").font(Theme.headerFont).foregroundStyle(Theme.textPrimary)
                Spacer()
                Menu {
                    ForEach(RelationChoice.allCases) { choice in
                        Button { adding = choice } label: { Label(choice.title, systemImage: choice.symbol) }
                    }
                } label: {
                    Label("Add relation", systemImage: "plus").font(Theme.metaFont)
                }
                .menuStyle(.button)
                .buttonStyle(SubtleButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()
                .popover(item: $adding, arrowEdge: .bottom) { choice in
                    TicketSearchList(excluding: [ticket.id], allowsClear: false) { otherID in
                        adding = nil
                        if let otherID { Task { await add(choice, otherID) } }
                    }
                    .environment(app)
                }
            }
            if groups.isEmpty {
                Text("No relations").font(Theme.rowFont).foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(groups, id: \.title) { group in
                        Text(group.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(group.refs, id: \.id) { ref in
                            RelationRow(ref: ref, isBlocker: group.kind == .blockedBy) {
                                Task { await remove(group.kind, ref.id) }
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
                .background(Theme.bgSidebar, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
            }
        }
    }

    private func add(_ choice: RelationChoice, _ other: String) async {
        let (from, to, type): (String, String, RelationType) = switch choice {
        case .blocks: (ticket.id, other, .blocks)
        case .blockedBy: (other, ticket.id, .blocks)
        case .related: (ticket.id, other, .related)
        case .duplicateOf: (ticket.id, other, .duplicate)
        }
        await app.perform { try await app.store.addRelation(from: from, to: to, type: type) }
    }

    private func remove(_ kind: RelationKind, _ other: String) async {
        let (from, to, type): (String, String, RelationType) = switch kind {
        case .blocks: (ticket.id, other, .blocks)
        case .blockedBy: (other, ticket.id, .blocks)
        case .related: (ticket.id, other, .related)
        case .duplicateOf: (ticket.id, other, .duplicate)
        case .duplicatedBy: (other, ticket.id, .duplicate)
        }
        await app.perform { try await app.store.removeRelation(from: from, to: to, type: type) }
    }
}

private struct RelationRow: View {
    @Environment(AppModel.self) private var app
    let ref: TicketRef
    let isBlocker: Bool
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            StatusGlyph(status: ref.status)
            Text(ref.identifier).font(Theme.metaFont.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            Text(ref.title).font(Theme.rowFont).foregroundStyle(Theme.textPrimary).lineLimit(1)
            if isBlocker && ref.status.isOpen { BlockedBadge() }
            Spacer()
            if hovering {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .help("Remove this relation")
                    .accessibilityLabel("Remove relation with \(ref.identifier)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .background(hovering ? Theme.bgHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { app.open(ticket: ref.id) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ref.identifier), \(ref.title), \(ref.status.displayName)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Attachments

struct AttachmentsSection: View {
    @Environment(AppModel.self) private var app
    let ticketID: String
    let attachments: [Attachment]
    @State private var addingLink = false
    @State private var linkURL = ""
    @State private var linkTitle = ""

    private var images: [Attachment] { attachments.filter { $0.kind == .file && $0.isImage } }
    private var others: [Attachment] { attachments.filter { !($0.kind == .file && $0.isImage) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Attachments").font(Theme.headerFont).foregroundStyle(Theme.textPrimary)
                if !attachments.isEmpty {
                    Text("\(attachments.count)").font(Theme.metaFont).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Menu {
                    Button { addingLink = true } label: { Label("Add link…", systemImage: "link") }
                    Button { chooseFiles() } label: { Label("Add file…", systemImage: "paperclip") }
                } label: {
                    Label("Attach", systemImage: "plus").font(Theme.metaFont)
                }
                .menuStyle(.button)
                .buttonStyle(SubtleButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()
                .popover(isPresented: $addingLink, arrowEdge: .bottom) { linkForm }
            }
            if !images.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(images) { ImageThumb(attachment: $0) }
                    }
                }
            }
            if !others.isEmpty {
                VStack(spacing: 0) {
                    ForEach(others) { AttachmentRow(attachment: $0) }
                }
                .background(Theme.bgSidebar, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
            }
            if attachments.isEmpty {
                Text("No attachments").font(Theme.rowFont).foregroundStyle(Theme.textTertiary)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            addFiles(urls.filter(\.isFileURL))
            return !urls.isEmpty
        }
    }

    private var linkForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add link").font(Theme.headerFont)
            TextField("https://…", text: $linkURL).textFieldStyle(.roundedBorder).onSubmit(saveLink)
            TextField("Title (optional)", text: $linkTitle).textFieldStyle(.roundedBorder).onSubmit(saveLink)
            HStack {
                Spacer()
                Button("Cancel") { addingLink = false }.buttonStyle(SubtleButtonStyle())
                Button("Add", action: saveLink)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(linkURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(Theme.bgElevated)
    }

    private func saveLink() {
        let url = linkURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        let title = linkTitle
        Task {
            if await app.perform({ try await app.store.addLink(ticketId: ticketID, title: title, url: url) }) != nil {
                linkURL = ""
                linkTitle = ""
                addingLink = false
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    private func addFiles(_ urls: [URL]) {
        Task {
            for url in urls {
                await app.perform { try await app.store.addFile(ticketId: ticketID, file: url) }
            }
        }
    }
}

private struct ImageThumb: View {
    @Environment(AppModel.self) private var app
    let attachment: Attachment

    var body: some View {
        let url = app.store.fileURL(for: attachment)
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 140, height: 100)
        .background(Theme.bgSidebar)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if let url { NSWorkspace.shared.open(url) } }
        .contextMenu { AttachmentMenu(attachment: attachment) }
        .help(attachment.title)
        .accessibilityLabel("Image attachment \(attachment.title)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct AttachmentRow: View {
    @Environment(AppModel.self) private var app
    let attachment: Attachment
    @State private var hovering = false

    private var symbol: String {
        if attachment.kind == .link { return "link" }
        if (attachment.mimeType ?? "").hasPrefix("video/") { return "film" }
        return "doc"
    }

    private var subtitle: String {
        if attachment.kind == .link { return URL(string: attachment.url ?? "")?.host ?? attachment.url ?? "" }
        return attachment.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).frame(width: 16)
            Text(attachment.title).font(Theme.rowFont).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Text(subtitle).font(Theme.metaFont).foregroundStyle(Theme.textTertiary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .background(hovering ? Theme.bgHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { open() }
        .contextMenu { AttachmentMenu(attachment: attachment) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(attachment.kind == .link ? "Link" : "File") \(attachment.title)")
        .accessibilityAddTraits(.isButton)
    }

    private func open() {
        if let file = app.store.fileURL(for: attachment) {
            NSWorkspace.shared.open(file)
        } else if let string = attachment.url, let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct AttachmentMenu: View {
    @Environment(AppModel.self) private var app
    let attachment: Attachment

    var body: some View {
        if let file = app.store.fileURL(for: attachment) {
            Button("Open") { NSWorkspace.shared.open(file) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        } else if let string = attachment.url, let url = URL(string: string) {
            Button("Open Link") { NSWorkspace.shared.open(url) }
            Button("Copy Link") { app.copyToPasteboard(string) }
        }
        if attachment.externalId == nil || !(attachment.externalId ?? "").hasPrefix("linear:link:") {
            Divider()
            Button("Remove", role: .destructive) {
                Task { await app.perform { try await app.store.removeAttachment(id: attachment.id) } }
            }
        }
    }
}
