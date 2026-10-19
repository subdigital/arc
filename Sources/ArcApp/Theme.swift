import ArcCore
import ArcMarkdown
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Parses `#RRGGBB`; falls back to the accent color for anything else.
    init(hexString: String) {
        let digits = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(digits, radix: 16) ?? 0x5E6AD2)
    }
}

/// Color and font tokens (design.md §7). Everything visual goes through here.
enum Theme {
    static let bgSidebar = Color(hex: 0x0E0E10)
    static let bgContent = Color(hex: 0x121214)
    static let bgElevated = Color(hex: 0x1A1A1E)
    static let bgHover = Color(hex: 0x1F1F24)
    static let bgSelected = Color(hex: 0x26262C)
    static let border = Color(hex: 0x26262B)
    static let textPrimary = Color(hex: 0xE6E6EA)
    static let textSecondary = Color(hex: 0x8A8F98)
    static let textTertiary = Color(hex: 0x5C6068)
    static let accent = Color(hex: 0x5E6AD2)
    static let yellow = Color(hex: 0xF2C94C)
    static let green = Color(hex: 0x4CB782)
    static let urgent = Color(hex: 0xF2994A)

    static let rowFont = Font.system(size: 13)
    static let metaFont = Font.system(size: 12)
    static let headerFont = Font.system(size: 12, weight: .medium)
    static let titleFont = Font.system(size: 22, weight: .semibold)

    static let rowHeight: CGFloat = 32

    static var markdownStyle: MarkdownStyle {
        var style = MarkdownStyle()
        style.text = textPrimary
        style.secondaryText = textSecondary
        style.accent = accent
        style.border = border
        style.codeBackground = bgElevated
        return style
    }

    /// Palette for highlighted code on `bgElevated`.
    static var syntaxPalette: SyntaxPalette { SyntaxPalette() }
}

extension TicketStatus {
    /// List order (Linear-style): active work first.
    static let listOrder: [TicketStatus] = [.inProgress, .inReview, .todo, .backlog, .done, .canceled]

    /// Board columns, in workflow order.
    static let boardOrder: [TicketStatus] = [.backlog, .todo, .inProgress, .inReview, .done, .canceled]
}
