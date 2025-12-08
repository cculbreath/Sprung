import SwiftUI

/// Floating overlay panel for browsing, editing, and managing knowledge cards.
/// Features a fanned card deck with filter chips and CRUD controls.
struct KnowledgeCardBrowserOverlay: View {
    @Binding var isPresented: Bool
    @Binding var cards: [ResRef]
    let resRefStore: ResRefStore
    let onCardUpdated: (ResRef) -> Void
    let onCardDeleted: (ResRef) -> Void
    let onCardAdded: (ResRef) -> Void

    @State private var currentIndex: Int = 0
    @State private var selectedFilter: CardTypeFilter = .all
    @State private var searchText: String = ""
    @State private var editingCard: ResRef?
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: ResRef?
    @State private var showAddSheet = false
    @State private var dealAnimation = false

    enum CardTypeFilter: String, CaseIterable {
        case all = "All"
        case job = "Jobs"
        case skill = "Skills"
        case education = "Education"
        case project = "Projects"
        case other = "Other"

        var cardType: String? {
            switch self {
            case .all: return nil
            case .job: return "job"
            case .skill: return "skill"
            case .education: return "education"
            case .project: return "project"
            case .other: return nil
            }
        }
    }

    private var filteredCards: [ResRef] {
        var result = cards

        // Apply type filter
        if selectedFilter != .all {
            if selectedFilter == .other {
                result = result.filter {
                    $0.cardType == nil ||
                    !["job", "skill", "education", "project"].contains($0.cardType?.lowercased() ?? "")
                }
            } else if let filterType = selectedFilter.cardType {
                result = result.filter { $0.cardType?.lowercased() == filterType }
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(search) ||
                $0.content.lowercased().contains(search) ||
                $0.organization?.lowercased().contains(search) == true
            }
        }

        return result
    }

    var body: some View {
        // Main panel (as sheet content)
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Filter bar
            filterBar

            // Card deck with navigation
            if filteredCards.isEmpty {
                emptyFilterState
            } else {
                cardNavigationSection
            }
        }
        .frame(width: 540, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                dealAnimation = true
            }
        }
        .onKeyPress(.escape) {
            dismissOverlay()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            navigatePrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateNext()
            return .handled
        }
        .sheet(item: $editingCard) { card in
            KnowledgeCardEditSheet(
                card: card,
                onSave: { updatedCard in
                    onCardUpdated(updatedCard)
                    editingCard = nil
                },
                onCancel: {
                    editingCard = nil
                }
            )
        }
        .sheet(isPresented: $showAddSheet) {
            KnowledgeCardEditSheet(
                card: nil,
                onSave: { newCard in
                    onCardAdded(newCard)
                    showAddSheet = false
                    // Navigate to the new card
                    if let index = filteredCards.firstIndex(where: { $0.id == newCard.id }) {
                        currentIndex = index
                    }
                },
                onCancel: {
                    showAddSheet = false
                }
            )
        }
        .alert("Delete Card?", isPresented: $showDeleteConfirmation, presenting: cardToDelete) { card in
            Button("Delete", role: .destructive) {
                deleteCard(card)
            }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text("Are you sure you want to delete \"\(card.name)\"? This action cannot be undone.")
        }
        .onChange(of: selectedFilter) { _, _ in
            // Reset to first card when filter changes
            currentIndex = 0
        }
        .onChange(of: searchText) { _, _ in
            // Reset to first card when search changes
            currentIndex = 0
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Knowledge Cards")
                    .font(.title2.weight(.semibold))
                Text("\(cards.count) card\(cards.count == 1 ? "" : "s") total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Add button
            Button(action: { showAddSheet = true }) {
                Label("Add Card", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            // Close button
            Button(action: dismissOverlay) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(20)
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search cards...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CardTypeFilter.allCases, id: \.self) { filter in
                        filterChip(filter)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func filterChip(_ filter: CardTypeFilter) -> some View {
        let isSelected = selectedFilter == filter
        let count = countForFilter(filter)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFilter = filter
            }
        }) {
            HStack(spacing: 4) {
                Text(filter.rawValue)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func countForFilter(_ filter: CardTypeFilter) -> Int {
        switch filter {
        case .all:
            return cards.count
        case .other:
            return cards.filter {
                $0.cardType == nil ||
                !["job", "skill", "education", "project"].contains($0.cardType?.lowercased() ?? "")
            }.count
        default:
            guard let filterType = filter.cardType else { return 0 }
            return cards.filter { $0.cardType?.lowercased() == filterType }.count
        }
    }

    private var cardNavigationSection: some View {
        VStack(spacing: 12) {
            // Navigation with arrows flanking the card
            HStack(spacing: 16) {
                // Previous button
                Button(action: navigatePrevious) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(currentIndex > 0 ? Color.accentColor : Color.secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(currentIndex == 0)

                // Single card display
                KnowledgeCardView(
                    resRef: filteredCards[currentIndex],
                    isTopCard: true,
                    onEdit: { editingCard = filteredCards[currentIndex] },
                    onDelete: {
                        cardToDelete = filteredCards[currentIndex]
                        showDeleteConfirmation = true
                    }
                )
                .frame(width: 400, height: 420)

                // Next button
                Button(action: navigateNext) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(currentIndex < filteredCards.count - 1 ? Color.accentColor : Color.secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(currentIndex >= filteredCards.count - 1)
            }
            .padding(.horizontal, 8)

            // Page indicator
            HStack(spacing: 8) {
                Text("\(currentIndex + 1) of \(filteredCards.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                // Dot indicators (up to 7)
                HStack(spacing: 4) {
                    ForEach(0..<min(7, filteredCards.count), id: \.self) { index in
                        let actualIndex = dotIndexFor(displayIndex: index)
                        Circle()
                            .fill(actualIndex == currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: actualIndex == currentIndex ? 8 : 6, height: actualIndex == currentIndex ? 8 : 6)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    currentIndex = actualIndex
                                }
                            }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 12)
    }

    private func dotIndexFor(displayIndex: Int) -> Int {
        let maxDots = 7
        guard filteredCards.count > maxDots else { return displayIndex }

        let half = maxDots / 2
        let start = max(0, min(currentIndex - half, filteredCards.count - maxDots))
        return start + displayIndex
    }

    private func navigateNext() {
        guard currentIndex < filteredCards.count - 1 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentIndex += 1
        }
    }

    private func navigatePrevious() {
        guard currentIndex > 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentIndex -= 1
        }
    }

    private var emptyFilterState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No Matching Cards")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Try adjusting your filters or search terms")
                .font(.callout)
                .foregroundStyle(.tertiary)

            Button("Clear Filters") {
                withAnimation {
                    selectedFilter = .all
                    searchText = ""
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dismissOverlay() {
        isPresented = false
    }

    private func deleteCard(_ card: ResRef) {
        // Adjust index if needed
        if currentIndex >= filteredCards.count - 1 && currentIndex > 0 {
            currentIndex -= 1
        }
        onCardDeleted(card)
    }
}
