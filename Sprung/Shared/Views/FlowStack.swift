//
//  FlowStack.swift
//  Sprung
//
//  A flow layout that wraps children horizontally, creating new rows as needed.
//

import SwiftUI

/// A layout that arranges views in a horizontal flow, wrapping to new lines as needed.
struct FlowStack<Content: View>: View {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let content: () -> Content

    init(
        spacing: CGFloat = 8,
        verticalSpacing: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.horizontalSpacing = spacing
        self.verticalSpacing = verticalSpacing ?? spacing
        self.content = content
    }

    var body: some View {
        _FlowLayout(horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
            content()
        }
    }
}

private struct _FlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(for: subviews, in: proposal.width ?? 0)
        return CGSize(width: proposal.width ?? result.width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(for: subviews, in: bounds.width)

        for (index, position) in result.positions.enumerated() {
            guard index < subviews.count else { break }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func layout(for subviews: Subviews, in availableWidth: CGFloat) -> LayoutResult {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap to next line
            if currentX + size.width > availableWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX - horizontalSpacing)
        }

        let totalHeight = currentY + lineHeight
        return LayoutResult(positions: positions, width: maxWidth, height: totalHeight)
    }

    private struct LayoutResult {
        let positions: [CGPoint]
        let width: CGFloat
        let height: CGFloat
    }
}
