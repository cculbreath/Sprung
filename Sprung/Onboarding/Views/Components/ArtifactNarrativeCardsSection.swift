import SwiftUI

/// Displays a list of KnowledgeCard objects extracted from an artifact,
/// each as a self-contained card row with title, type badge, org/date line,
/// narrative excerpt, and domain badges. Includes optional regen button.
struct ArtifactNarrativeCardsSection: View {
    let cards: [KnowledgeCard]
    let onRegenNarrativeCards: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.teal)
                Text("Narrative Cards (\(cards.count))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let regenAction = onRegenNarrativeCards {
                    Button {
                        regenAction()
                    } label: {
                        Image(systemName: "arrow.trianglehead.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Regenerate knowledge cards for this artifact")
                }
            }

            // Cards list
            VStack(alignment: .leading, spacing: 6) {
                ForEach(cards, id: \.id) { card in
                    NarrativeCardRow(card: card)
                }
            }
        }
        .padding(8)
        .background(Color.teal.opacity(0.05))
        .cornerRadius(6)
    }
}

// MARK: - Narrative Card Row

private struct NarrativeCardRow: View {
    let card: KnowledgeCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row with type
            HStack(spacing: 6) {
                Image(systemName: cardTypeIcon(card.cardType))
                    .foregroundStyle(cardTypeColor(card.cardType))
                    .font(.caption)

                Text(card.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)

                Spacer()

                Text(card.cardType?.rawValue ?? "general")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(cardTypeColor(card.cardType).opacity(0.15))
                    .foregroundStyle(cardTypeColor(card.cardType))
                    .cornerRadius(3)
            }

            // Organization and date range
            if let org = card.organization {
                HStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(org)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let dateRange = card.dateRange {
                        Text("\u{2022}")
                            .foregroundStyle(.tertiary)
                        Text(dateRange)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Narrative preview
            if !card.narrative.isEmpty {
                Text(card.narrative.prefix(150) + (card.narrative.count > 150 ? "..." : ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Domains as badges
            if !card.extractable.domains.isEmpty {
                FlowStack(spacing: 4) {
                    ForEach(card.extractable.domains.prefix(6), id: \.self) { domain in
                        artifactBadgePill(domain, color: .indigo)
                    }
                    if card.extractable.domains.count > 6 {
                        Text("+\(card.extractable.domains.count - 6)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
    }
}

// MARK: - Card Type Helpers

private func cardTypeIcon(_ type: CardType?) -> String {
    switch type {
    case .employment: return "briefcase.fill"
    case .project: return "hammer.fill"
    case .achievement: return "star.fill"
    case .education: return "graduationcap.fill"
    case nil: return "doc.fill"
    }
}

private func cardTypeColor(_ type: CardType?) -> Color {
    switch type {
    case .employment: return .blue
    case .project: return .orange
    case .achievement: return .yellow
    case .education: return .green
    case nil: return .gray
    }
}
