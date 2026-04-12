import SwiftUI

// whether a word wants a space after it, chinese and japanese pieces sit flush against the next one
nonisolated struct FlowSpaceAfter: LayoutValueKey {
    static let defaultValue = true
}

extension View {
    func flowSpaceAfter(_ space: Bool) -> some View {
        layoutValue(key: FlowSpaceAfter.self, value: space)
    }
}

// lays words out like text: left to right, wrapping to a new line when the next one won't fit
nonisolated struct WordFlow: Layout {
    enum Alignment: Sendable { case leading, center, trailing }

    var alignment: Alignment = .leading
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { $0.isFinite ? $0 : widest } ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat = switch alignment {
            case .leading: bounds.minX
            case .center: bounds.minX + (bounds.width - row.width) / 2
            case .trailing: bounds.maxX - row.width
            }
            for (position, index) in row.indices.enumerated() {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + row.height - size.height), anchor: .topLeading, proposal: .unspecified)
                x += size.width
                if position < row.indices.count - 1, subviews[index][FlowSpaceAfter.self] { x += spacing }
            }
            y += row.height + lineSpacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var pendingSpace: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, current.width + pendingSpace + size.width > width {
                rows.append(current)
                current = Row()
                pendingSpace = 0
            }
            current.width += (current.indices.isEmpty ? 0 : pendingSpace) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
            pendingSpace = subviews[index][FlowSpaceAfter.self] ? spacing : 0
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
