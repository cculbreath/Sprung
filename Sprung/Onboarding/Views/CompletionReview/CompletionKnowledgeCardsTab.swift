import SwiftUI

/// Tab view for browsing knowledge cards in the completion review sheet
struct CompletionKnowledgeCardsTab: View {
    let coordinator: OnboardingInterviewCoordinator

    @State private var expandedCardIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var selectedType: String?

    private var allCards: [KnowledgeCard] {
        coordinator.allKnowledgeCards
    }

    private var filteredCards: [KnowledgeCard] {
        var cards = allCards

        if !searchText.isEmpty {
            let search = searchText.lowercased()
            cards = cards.filter {
                $0.title.lowercased().contains(search) ||
                $0.organization?.lowercased().contains(search) == true ||
                $0.narrative.lowercased().contains(search)
            }
        }

        if let type = selectedType {
            cards = cards.filter { $0.cardType?.rawValue.lowercased() == type }
        }

        return cards
    }

    private var cardTypes: [String] {
        let types = Set(allCards.compactMap { $0.cardType?.rawValue.lowercased() })
        let orderedTypes = CardType.allCases.map { $0.rawValue.lowercased() }
        return orderedTypes.filter { types.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            if allCards.isEmpty {
                emptyState
            } else if filteredCards.isEmpty {
                noMatchesState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCards) { card in
                            cardRow(card)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    typeChip(nil, label: "All")
                    ForEach(cardTypes, id: \.self) { type in
                        typeChip(type, label: type.capitalized)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func typeChip(_ type: String?, label: String) -> some View {
        let isSelected = selectedType == type
        let count: Int
        if let type = type {
            count = allCards.filter { $0.cardType?.rawValue.lowercased() == type }.count
        } else {
            count = allCards.count
        }

        return Button(action: { selectedType = type }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.purple : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func cardRow(_ card: KnowledgeCard) -> some View {
        let isExpanded = expandedCardIds.contains(card.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedCardIds.remove(card.id)
                    } else {
                        expandedCardIds.insert(card.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: iconFor(card.cardType?.rawValue.lowercased() ?? "other"))
                        .font(.caption)
                        .foregroundStyle(colorFor(card.cardType?.rawValue.lowercased() ?? "other"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let org = card.organization, !org.isEmpty {
                            Text(org)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if !card.technologies.isEmpty {
                        Text("\(card.technologies.count) skills")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent(card)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func expandedContent(_ card: KnowledgeCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.horizontal, 12)

            if let dateRange = card.dateRange {
                Label(dateRange, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            if !card.technologies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(card.technologies.prefix(10), id: \.self) { tech in
                            Text(tech)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        if card.technologies.count > 10 {
                            Text("+\(card.technologies.count - 10)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            if !card.narrative.isEmpty {
                Text(card.narrative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .padding(.horizontal, 12)
            }

            Spacer().frame(height: 8)
        }
    }

    private func iconFor(_ type: String) -> String {
        switch type {
        case "employment": return "briefcase.fill"
        case "project": return "folder.fill"
        case "education": return "graduationcap.fill"
        case "achievement": return "star.fill"
        default: return "doc.fill"
        }
    }

    private func colorFor(_ type: String) -> Color {
        switch type {
        case "employment": return .blue
        case "project": return .green
        case "education": return .orange
        case "achievement": return .purple
        default: return .gray
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Knowledge Cards")
                .font(.title3.weight(.medium))
            Text("Knowledge cards are created from your uploaded documents")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Matching Cards")
                .font(.headline)
            Button("Clear Filters") {
                searchText = ""
                selectedType = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
