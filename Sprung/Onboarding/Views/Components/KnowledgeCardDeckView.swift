import SwiftUI

/// A fanned card deck view showing 3 cards at once with swipe/drag navigation.
/// Supports keyboard navigation (arrow keys) and click-to-focus on back cards.
struct KnowledgeCardDeckView: View {
    @Binding var cards: [ResRef]
    @Binding var currentIndex: Int
    let onEdit: (ResRef) -> Void
    let onDelete: (ResRef) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    // Configuration
    private let cardWidth: CGFloat = 400
    private let cardHeight: CGFloat = 480
    private let stackOffset: CGFloat = 20
    private let scaleDecrement: CGFloat = 0.05
    private let dragThreshold: CGFloat = 80

    private var visibleRange: ClosedRange<Int> {
        let start = max(0, currentIndex - 1)
        let end = min(cards.count - 1, currentIndex + 1)
        return start...end
    }

    var body: some View {
        ZStack {
            if cards.isEmpty {
                emptyState
            } else {
                cardStack
            }
        }
        .frame(width: cardWidth + 60, height: cardHeight + 80)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onKeyPress(.leftArrow) {
            navigatePrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateNext()
            return .handled
        }
        .focusable()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Knowledge Cards")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Create your first card to get started")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .foregroundStyle(.tertiary)
        )
    }

    private var cardStack: some View {
        ZStack {
            // Render cards from back to front
            ForEach(Array(visibleRange.reversed()), id: \.self) { index in
                if index < cards.count {
                    cardAtIndex(index)
                        .zIndex(Double(index == currentIndex ? 100 : index))
                }
            }
        }
    }

    @ViewBuilder
    private func cardAtIndex(_ index: Int) -> some View {
        let offset = index - currentIndex
        let isTopCard = index == currentIndex

        KnowledgeCardView(
            resRef: cards[index],
            isTopCard: isTopCard,
            onEdit: { onEdit(cards[index]) },
            onDelete: { onDelete(cards[index]) }
        )
        .frame(width: cardWidth, height: cardHeight)
        .offset(x: xOffset(for: offset), y: yOffset(for: offset))
        .scaleEffect(scale(for: offset))
        .opacity(opacity(for: offset))
        .rotation3DEffect(
            .degrees(rotation(for: offset)),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
        )
        .allowsHitTesting(isTopCard)
        .onTapGesture {
            if !isTopCard {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentIndex = index
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: currentIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
    }

    // MARK: - Card Transforms

    private func xOffset(for offset: Int) -> CGFloat {
        let baseOffset = CGFloat(offset) * stackOffset * 1.5

        // Apply drag offset only to current card
        if offset == 0 {
            return baseOffset + dragOffset
        }

        // Slightly shift adjacent cards based on drag
        let dragInfluence = dragOffset * 0.2
        if offset == -1 && dragOffset > 0 {
            return baseOffset + dragInfluence
        } else if offset == 1 && dragOffset < 0 {
            return baseOffset + dragInfluence
        }

        return baseOffset
    }

    private func yOffset(for offset: Int) -> CGFloat {
        CGFloat(abs(offset)) * -stackOffset * 0.5
    }

    private func scale(for offset: Int) -> CGFloat {
        let baseScale = 1.0 - (CGFloat(abs(offset)) * scaleDecrement)

        // Slightly scale based on drag
        if offset == 0 && isDragging {
            return baseScale * 0.98
        }

        return baseScale
    }

    private func opacity(for offset: Int) -> CGFloat {
        switch abs(offset) {
        case 0: return 1.0
        case 1: return 0.85
        default: return 0.6
        }
    }

    private func rotation(for offset: Int) -> Double {
        let baseRotation = Double(offset) * 3

        // Add rotation during drag
        if offset == 0 {
            return baseRotation + Double(dragOffset / 30)
        }

        return baseRotation
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation.width

                // Add resistance at edges
                if (currentIndex == 0 && dragOffset > 0) ||
                   (currentIndex == cards.count - 1 && dragOffset < 0) {
                    dragOffset *= 0.3
                }
            }
            .onEnded { value in
                isDragging = false

                let velocity = value.predictedEndTranslation.width - value.translation.width

                if abs(dragOffset) > dragThreshold || abs(velocity) > 200 {
                    if dragOffset < 0 || velocity < -200 {
                        navigateNext()
                    } else if dragOffset > 0 || velocity > 200 {
                        navigatePrevious()
                    }
                }

                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    dragOffset = 0
                }
            }
    }

    // MARK: - Navigation

    private func navigateNext() {
        guard currentIndex < cards.count - 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentIndex += 1
            dragOffset = 0
        }
    }

    private func navigatePrevious() {
        guard currentIndex > 0 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentIndex -= 1
            dragOffset = 0
        }
    }
}

// MARK: - Page Indicator

struct DeckPageIndicator: View {
    let totalCount: Int
    let currentIndex: Int
    let onSelect: (Int) -> Void

    private let maxVisibleDots = 7

    var body: some View {
        HStack(spacing: 6) {
            // Previous button
            Button(action: { if currentIndex > 0 { onSelect(currentIndex - 1) } }) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(currentIndex > 0 ? .primary : .tertiary)
            .disabled(currentIndex == 0)

            // Page dots
            HStack(spacing: 4) {
                ForEach(visibleDotIndices, id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: dotSize(for: index), height: dotSize(for: index))
                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                        .onTapGesture {
                            onSelect(index)
                        }
                }
            }

            // Next button
            Button(action: { if currentIndex < totalCount - 1 { onSelect(currentIndex + 1) } }) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(currentIndex < totalCount - 1 ? .primary : .tertiary)
            .disabled(currentIndex >= totalCount - 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .clipShape(Capsule())
    }

    private var visibleDotIndices: [Int] {
        guard totalCount > maxVisibleDots else {
            return Array(0..<totalCount)
        }

        let half = maxVisibleDots / 2
        let start = max(0, min(currentIndex - half, totalCount - maxVisibleDots))
        let end = min(totalCount, start + maxVisibleDots)

        return Array(start..<end)
    }

    private func dotSize(for index: Int) -> CGFloat {
        if index == currentIndex {
            return 8
        }
        let distance = abs(index - currentIndex)
        return max(4, 8 - CGFloat(distance))
    }
}
