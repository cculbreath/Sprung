import SwiftUI

/// Generic coverflow browser that works with any Identifiable item.
/// Provides navigation, filtering scaffold, and 3D card carousel.
struct CoverflowBrowser<Item: Identifiable, CardContent: View, FilterContent: View>: View {
    @Binding var items: [Item]
    @State private var currentIndex: Int = 0

    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let accentColor: Color

    @ViewBuilder let cardContent: (Item, Bool) -> CardContent  // (item, isTopCard) -> View
    @ViewBuilder let filterContent: (Binding<Int>) -> FilterContent  // (currentIndex binding) -> View

    let onNavigate: ((Int) -> Void)?

    init(
        items: Binding<[Item]>,
        cardWidth: CGFloat = 360,
        cardHeight: CGFloat = 420,
        accentColor: Color = .accentColor,
        @ViewBuilder cardContent: @escaping (Item, Bool) -> CardContent,
        @ViewBuilder filterContent: @escaping (Binding<Int>) -> FilterContent,
        onNavigate: ((Int) -> Void)? = nil
    ) {
        self._items = items
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.accentColor = accentColor
        self.cardContent = cardContent
        self.filterContent = filterContent
        self.onNavigate = onNavigate
    }

    private let visibleCardOffset: CGFloat = 240

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar (provided by caller)
            filterContent($currentIndex)

            if items.isEmpty {
                emptyState
            } else {
                // Coverflow carousel
                carousel

                // Navigation controls
                navigationControls
            }
        }
        .onKeyPress(.leftArrow) { navigatePrevious(); return .handled }
        .onKeyPress(.rightArrow) { navigateNext(); return .handled }
        .onChange(of: items.count) { oldCount, newCount in
            // Adjust index if items removed
            if currentIndex >= newCount && newCount > 0 {
                currentIndex = newCount - 1
            }
        }
    }

    // MARK: - Carousel

    private var carousel: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let offset = index - currentIndex
                if abs(offset) <= 3 {
                    cardView(item: item, index: index, offset: offset)
                }
            }
        }
        .frame(height: cardHeight + 40)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -50 { navigateNext() }
                    else if value.translation.width > 50 { navigatePrevious() }
                }
        )
    }

    private func cardView(item: Item, index: Int, offset: Int) -> some View {
        let isSelected = offset == 0
        let clampedOffset = max(-3, min(3, offset))
        let xOffset = CGFloat(clampedOffset) * visibleCardOffset
        let rotation = Double(clampedOffset) * -35
        let scale = isSelected ? 1.0 : 0.75
        let opacity = isSelected ? 1.0 : max(0.3, 1.0 - Double(abs(clampedOffset)) * 0.25)
        let zIndex = isSelected ? 100.0 : 50.0 - Double(abs(offset)) * 10.0

        return cardContent(item, isSelected)
            .frame(width: cardWidth, height: cardHeight)
            .scaleEffect(scale)
            .rotation3DEffect(
                .degrees(rotation),
                axis: (x: 0, y: 1, z: 0),
                anchor: offset < 0 ? .trailing : (offset > 0 ? .leading : .center),
                perspective: 0.5
            )
            .offset(x: xOffset)
            .opacity(opacity)
            .zIndex(zIndex)
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentIndex = index
                    onNavigate?(index)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentIndex)
    }

    // MARK: - Navigation

    private var navigationControls: some View {
        HStack(spacing: 20) {
            Button(action: navigatePrevious) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(currentIndex > 0 ? accentColor : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(currentIndex == 0)

            VStack(spacing: 4) {
                Text("\(currentIndex + 1) of \(items.count)")
                    .font(.subheadline.weight(.medium).monospacedDigit())

                // Dot indicators
                HStack(spacing: 6) {
                    ForEach(0..<min(7, items.count), id: \.self) { i in
                        let actualIndex = dotIndex(for: i)
                        Circle()
                            .fill(actualIndex == currentIndex ? accentColor : Color.secondary.opacity(0.3))
                            .frame(width: actualIndex == currentIndex ? 10 : 6, height: actualIndex == currentIndex ? 10 : 6)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    currentIndex = actualIndex
                                }
                            }
                    }
                }
            }

            Button(action: navigateNext) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(currentIndex < items.count - 1 ? accentColor : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= items.count - 1)
        }
        .padding(.vertical, 12)
    }

    private func dotIndex(for displayIndex: Int) -> Int {
        let maxDots = 7
        guard items.count > maxDots else { return displayIndex }
        let half = maxDots / 2
        let start = max(0, min(currentIndex - half, items.count - maxDots))
        return start + displayIndex
    }

    private func navigateNext() {
        guard currentIndex < items.count - 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentIndex += 1
            onNavigate?(currentIndex)
        }
    }

    private func navigatePrevious() {
        guard currentIndex > 0 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentIndex -= 1
            onNavigate?(currentIndex)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Items")
                .font(.title3.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
