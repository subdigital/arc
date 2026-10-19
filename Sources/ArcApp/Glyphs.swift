import ArcCore
import SwiftUI

/// Filled wedge starting at 12 o'clock, clockwise.
private struct Pie: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center,
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.midY + rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.26))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY + rect.height * 0.28))
        return path
    }
}

private struct Cross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.3, y: rect.maxY - rect.height * 0.3))
        path.move(to: CGPoint(x: rect.maxX - rect.width * 0.3, y: rect.minY + rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY - rect.height * 0.3))
        return path
    }
}

/// Linear-style circular status glyph, used everywhere a status appears.
struct StatusGlyph: View {
    let status: TicketStatus
    var size: CGFloat = 14

    private var ringWidth: CGFloat { size / 9 }
    private var ringInset: CGFloat { ringWidth / 2 }

    var body: some View {
        ZStack {
            switch status {
            case .backlog:
                Circle()
                    .inset(by: ringInset)
                    .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: ringWidth, dash: [size / 8, size / 8]))
            case .todo:
                Circle()
                    .inset(by: ringInset)
                    .stroke(Theme.textSecondary, lineWidth: ringWidth)
            case .inProgress:
                ring(Theme.yellow, fraction: 0.5)
            case .inReview:
                ring(Theme.green, fraction: 0.75)
            case .done:
                Circle().fill(Theme.accent)
                CheckMark()
                    .stroke(.white, style: StrokeStyle(lineWidth: size / 9, lineCap: .round, lineJoin: .round))
            case .canceled:
                Circle().fill(Theme.textSecondary)
                Cross()
                    .stroke(Theme.bgContent, style: StrokeStyle(lineWidth: size / 9, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(status.displayName)
    }

    private func ring(_ color: Color, fraction: Double) -> some View {
        ZStack {
            Circle().inset(by: ringInset).stroke(color, lineWidth: ringWidth)
            Pie(fraction: fraction).fill(color).padding(size * 0.25)
        }
    }
}

/// Priority glyph: three ascending bars (lit = priority), an urgent badge, or faint dashes for none.
struct PriorityGlyph: View {
    let priority: TicketPriority
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch priority {
            case .urgent:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22).fill(Theme.urgent)
                    VStack(spacing: size * 0.08) {
                        RoundedRectangle(cornerRadius: 0.5).fill(Theme.bgContent).frame(width: size * 0.14, height: size * 0.36)
                        Circle().fill(Theme.bgContent).frame(width: size * 0.16, height: size * 0.16)
                    }
                }
            case .high: bars(lit: 3)
            case .medium: bars(lit: 2)
            case .low: bars(lit: 1)
            case .none:
                VStack(spacing: size * 0.18) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(Theme.textTertiary.opacity(0.6))
                            .frame(width: size * 0.6, height: size * 0.1)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Priority: \(priority.displayName)")
    }

    private func bars(lit: Int) -> some View {
        HStack(alignment: .bottom, spacing: size * 0.1) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(index < lit ? Theme.textPrimary : Theme.textTertiary.opacity(0.55))
                    .frame(width: size * 0.2, height: size * (0.4 + 0.25 * CGFloat(index)))
            }
        }
    }
}

#Preview("Glyph gallery") {
    VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 18) {
            ForEach(TicketStatus.allCases, id: \.self) { status in
                VStack(spacing: 6) {
                    StatusGlyph(status: status, size: 28)
                    Text(status.displayName).font(Theme.metaFont)
                }
            }
        }
        HStack(spacing: 18) {
            ForEach(TicketPriority.allCases, id: \.self) { priority in
                VStack(spacing: 6) {
                    PriorityGlyph(priority: priority, size: 28)
                    Text(priority.displayName).font(Theme.metaFont)
                }
            }
        }
    }
    .foregroundStyle(Theme.textPrimary)
    .padding(24)
    .background(Theme.bgContent)
    .preferredColorScheme(.dark)
}
