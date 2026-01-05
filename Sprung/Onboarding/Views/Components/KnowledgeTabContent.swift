import SwiftUI

/// Tab content showing knowledge cards in an inline expandable list.
struct KnowledgeTabContent: View {
    let coordinator: OnboardingInterviewCoordinator
    @State private var expandedCardIds: Set<UUID> = []
    @State private var editingCard: KnowledgeCard?

    private var allCards: [KnowledgeCard] {
        coordinator.allKnowledgeCards
    }

    private var knowledgeCardStore: KnowledgeCardStore {
        coordinator.getKnowledgeCardStore()
    }

    /// Group cards by type for organized display
    private var cardsByType: [(type: String, cards: [KnowledgeCard])] {
        let grouped = Dictionary(grouping: allCards) { $0.cardType?.rawValue.lowercased() ?? "other" }
        let order = ["employment", "job", "project", "education", "skill", "other"]
        return order.compactMap { type in
            if let cards = grouped[type], !cards.isEmpty {
                return (type: type, cards: cards)
            }
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Summary header
            summaryHeader

            // Cards list
            if allCards.isEmpty {
                emptyState
            } else {
                cardsList
            }
        }
        .sheet(item: $editingCard) { card in
            KnowledgeCardEditSheet(
                card: card,
                onSave: { updated in
                    knowledgeCardStore.update(updated)
                    Task { await coordinator.syncKnowledgeCardToFilesystem(updated) }
                    editingCard = nil
                },
                onCancel: { editingCard = nil }
            )
        }
    }

    private var summaryHeader: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundStyle(.purple)
            Text("Knowledge Cards")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(allCards.count)")
                .font(.caption.weight(.medium).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.15))
                .foregroundStyle(.purple)
                .clipShape(Capsule())
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cardsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(cardsByType, id: \.type) { group in
                cardGroupSection(type: group.type, cards: group.cards)
            }
        }
    }

    private func cardGroupSection(type: String, cards: [KnowledgeCard]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Group header
            HStack {
                Image(systemName: iconFor(type))
                    .font(.caption)
                    .foregroundStyle(colorFor(type))
                Text(labelFor(type))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("(\(cards.count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            // Cards in group
            ForEach(cards) { card in
                expandableCardRow(card)
            }
        }
    }

    private func expandableCardRow(_ card: KnowledgeCard) -> some View {
        let isExpanded = expandedCardIds.contains(card.id)

        return VStack(alignment: .leading, spacing: 0) {
            // Card header (always visible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedCardIds.remove(card.id)
                    } else {
                        expandedCardIds.insert(card.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        if let org = card.organization, !org.isEmpty {
                            Text(org)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if card.isFromOnboarding {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                expandedCardContent(card)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorFor(card.cardType?.rawValue.lowercased() ?? "other").opacity(isExpanded ? 0.4 : 0.2), lineWidth: 1)
        )
    }

    private func expandedCardContent(_ card: KnowledgeCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.horizontal, 10)

            // Metadata row
            if card.dateRange != nil || card.location != nil {
                HStack(spacing: 12) {
                    if let period = card.dateRange {
                        Label(period, systemImage: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let location = card.location {
                        Label(location, systemImage: "location")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
            }

            // Technologies
            if !card.technologies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skills & Technologies")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)

                    FlowLayout(spacing: 4) {
                        ForEach(card.technologies.prefix(8), id: \.self) { tech in
                            Text(tech)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        if card.technologies.count > 8 {
                            Text("+\(card.technologies.count - 8) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            // Content preview
            if !card.narrative.isEmpty {
                Text(card.narrative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.horizontal, 10)
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    editingCard = card
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                let wordCount = card.narrative.split(separator: " ").count
                Text("\(wordCount) words")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No Knowledge Cards")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Cards will appear here as they're created")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private func iconFor(_ type: String) -> String {
        switch type {
        case "employment", "job": return "briefcase.fill"
        case "project": return "folder.fill"
        case "education": return "graduationcap.fill"
        case "skill": return "star.fill"
        default: return "doc.fill"
        }
    }

    private func colorFor(_ type: String) -> Color {
        switch type {
        case "employment", "job": return .blue
        case "project": return .green
        case "education": return .orange
        case "skill": return .purple
        default: return .gray
        }
    }

    private func labelFor(_ type: String) -> String {
        switch type {
        case "employment": return "Employment"
        case "job": return "Jobs"
        case "project": return "Projects"
        case "education": return "Education"
        case "skill": return "Skills"
        default: return "Other"
        }
    }
}

// MARK: - Flow Layout for Tags

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, containerWidth: bounds.width).offsets

        for (subview, offset) in zip(subviews, offsets) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX)
        }

        return (offsets, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}
