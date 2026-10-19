import SwiftUI

/// Colors and sizes for rendered Markdown. The defaults match the app's dark palette; the app
/// builds its own from `Theme` so there is one source of truth for the hex values.
public struct MarkdownStyle: Sendable {
    public var text = Color(red: 0.902, green: 0.902, blue: 0.918)
    public var secondaryText = Color(red: 0.541, green: 0.561, blue: 0.596)
    public var accent = Color(red: 0.369, green: 0.416, blue: 0.824)
    public var border = Color(red: 0.149, green: 0.149, blue: 0.169)
    public var codeBackground = Color(red: 0.102, green: 0.102, blue: 0.118)
    public var inlineCodeBackground = Color(white: 1, opacity: 0.08)
    public var tableHeaderBackground = Color(white: 1, opacity: 0.04)
    public var bodySize: CGFloat = 13.5
    public var codeSize: CGFloat = 12.5
    /// Sizes for heading levels 1 through 6.
    public var headingSizes: [CGFloat] = [22, 19, 17, 15, 14, 13.5]
    public var blockSpacing: CGFloat = 10

    public init() {}

    func headingSize(_ level: Int) -> CGFloat {
        headingSizes[min(max(level, 1), headingSizes.count) - 1]
    }
}
