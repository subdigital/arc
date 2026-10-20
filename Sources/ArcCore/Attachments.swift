import Foundation
import GRDB
import UniformTypeIdentifiers

extension ArcStore {
    /// Attached files live in a folder next to the database, one subfolder per ticket.
    public var attachmentsDirectory: URL {
        URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("attachments", isDirectory: true)
    }

    public func fileURL(for attachment: Attachment) -> URL? {
        guard let path = attachment.path else { return nil }
        return attachmentsDirectory.appendingPathComponent(path)
    }

    public func attachments(ticketId: String) async throws -> [Attachment] {
        try await read { db in
            try Attachment.fetchAll(db, sql: "SELECT * FROM attachment WHERE ticket_id = ? ORDER BY created_at, rowid", arguments: [ticketId])
        }
    }

    @discardableResult
    public func addLink(ticketId: String, title: String?, url: String) async throws -> Attachment {
        let timestamp = now()
        return try await write { db in
            _ = try Self.requireTicket(db, id: ticketId)
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = URL(string: trimmed), parsed.scheme != nil else {
                throw ArcError.invalidArgument("'\(url)' is not a valid URL.")
            }
            let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let attachment = Attachment(
                id: UUID().uuidString, ticketId: ticketId, kind: .link,
                title: (name?.isEmpty == false ? name : nil) ?? parsed.host ?? trimmed, url: trimmed,
                path: nil, mimeType: nil, size: nil, externalId: nil, createdAt: timestamp
            )
            try attachment.insert(db)
            return attachment
        }
    }

    /// Copies `file` into the attachments folder and records it on the ticket.
    @discardableResult
    public func addFile(ticketId: String, file: URL, title: String? = nil, sourceURL: String? = nil) async throws -> Attachment {
        let ticket = try await self.ticket(id: ticketId)
        let data = try Data(contentsOf: file)
        return try await addFile(ticketId: ticket.id, data: data, filename: file.lastPathComponent, title: title, sourceURL: sourceURL)
    }

    @discardableResult
    public func addFile(ticketId: String, data: Data, filename: String, title: String? = nil, sourceURL: String? = nil) async throws -> Attachment {
        _ = try await ticket(id: ticketId)
        let safeName = Self.safeFilename(filename)
        let id = UUID().uuidString
        let relative = "\(ticketId)/\(id.prefix(8))-\(safeName)"
        let destination = attachmentsDirectory.appendingPathComponent(relative)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        } catch {
            throw ArcError.invalidArgument("Could not store the file: \(error.localizedDescription)")
        }
        let mime = UTType(filenameExtension: (safeName as NSString).pathExtension)?.preferredMIMEType
        let timestamp = now()
        let attachment = Attachment(
            id: id, ticketId: ticketId, kind: .file, title: title ?? filename, url: sourceURL,
            path: relative, mimeType: mime, size: data.count, externalId: nil, createdAt: timestamp
        )
        try await write { db in try attachment.insert(db) }
        return attachment
    }

    public func removeAttachment(id: String) async throws {
        let removed: Attachment? = try await write { db in
            let found = try Attachment.fetchOne(db, sql: "SELECT * FROM attachment WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM attachment WHERE id = ?", arguments: [id])
            return found
        }
        if let removed, let url = fileURL(for: removed) { try? FileManager.default.removeItem(at: url) }
    }

    func removeAttachmentFiles(ticketId: String) {
        try? FileManager.default.removeItem(at: attachmentsDirectory.appendingPathComponent(ticketId, isDirectory: true))
    }

    static func safeFilename(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent
        let cleaned = base.map { $0.isLetter || $0.isNumber || ".-_ ()".contains($0) ? $0 : "_" }
        let result = String(cleaned).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "file" : result
    }
}
