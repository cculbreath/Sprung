import SwiftUI

/// View that displays pending knowledge cards for review before approval.
struct KnowledgeCardCollectionView: View {
    let coordinator: OnboardingInterviewCoordinator
    let onGenerateCards: () -> Void
    let onAdvanceToNextPhase: () -> Void

    @State private var selectedCardId: UUID?

    /// Pending cards from SwiftData store (not yet approved)
    private var pendingCards: [KnowledgeCard] {
        coordinator.knowledgeCardStore.pendingCards
    }

    private var isReadyForGeneration: Bool {
        coordinator.ui.cardAssignmentsReadyForApproval
    }

    private var isMerging: Bool {
        coordinator.ui.isMergingCards
    }

    private var isGenerating: Bool {
        coordinator.ui.isGeneratingCards
    }

    private var pendingCardCount: Int {
        pendingCards.count
    }

    private var pendingSkillCount: Int {
        coordinator.skillStore.pendingSkills.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection

            if pendingCards.isEmpty {
                emptyState
            } else {
                cardListSection
            }

            // Show Generate Cards button when assignments are ready
            if isReadyForGeneration && !isGenerating {
                generateCardsButton
            }

            // Show generation progress when generating
            if isGenerating {
                generatingProgressView
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Knowledge Cards")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if !pendingCards.isEmpty {
                    Text("\(pendingCards.count) card\(pendingCards.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isReadyForGeneration {
                Text("Review card assignments below")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var emptyState: some View {
        Group {
            if isMerging {
                // Show progress when merge is in progress
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Merging knowledge cards...")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Aggregating and deduplicating cards from your documents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Building Plan",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Upload documents and click 'Done with Uploads' to generate card assignments...")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var cardListSection: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(pendingCards) { card in
                    NarrativeCardRow(
                        card: card,
                        isGenerating: isGenerating,
                        showAssignments: isReadyForGeneration,
                        isSelected: selectedCardId == card.id,
                        onDelete: {
                            coordinator.knowledgeCardStore.delete(card)
                        },
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCardId = selectedCardId == card.id ? nil : card.id
                            }
                        }
                    )
                }
            }
            .padding(.bottom, 4)
        }
    }

    private var generateCardsButton: some View {
        VStack(spacing: 6) {
            Button(action: onGenerateCards) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text(approveButtonText)
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
            .disabled(pendingCardCount == 0 || isMerging)

            Text("Click cards above to review details, use trash to remove")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var approveButtonText: String {
        let cardText = "\(pendingCardCount) Card\(pendingCardCount == 1 ? "" : "s")"
        if pendingSkillCount > 0 {
            let skillText = "\(pendingSkillCount) Skill\(pendingSkillCount == 1 ? "" : "s")"
            return "Approve & Create \(cardText) and \(skillText)"
        } else {
            return "Approve & Create \(cardText)"
        }
    }

    private var generatingProgressView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 16, height: 16)

            Text("Generating knowledge cards...")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct NarrativeCardRow: View {
    let card: KnowledgeCard
    let isGenerating: Bool
    let showAssignments: Bool
    let isSelected: Bool
    let onDelete: () -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main row - clickable for details
            HStack(alignment: .center, spacing: 8) {
                // Status icon
                statusIcon
                    .frame(width: 20)

                // Content - clickable for details
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(card.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            typeTag
                        }

                        if let dateRange = card.dateRange, !dateRange.isEmpty {
                            Text(dateRange)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Expand indicator
                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Delete button (only when ready for generation)
                if showAssignments && !isGenerating {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Remove this card")
                }
            }

            // Expanded detail section
            if isSelected {
                NarrativeCardDetailSection(card: card)
                    .padding(.leading, 28)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isGenerating {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var typeTag: some View {
        let typeName: String
        let typeColor: Color
        switch card.cardType {
        case .employment: typeName = "Employment"; typeColor = .blue
        case .project: typeName = "Project"; typeColor = .green
        case .achievement: typeName = "Achievement"; typeColor = .yellow
        case .education: typeName = "Education"; typeColor = .cyan
        case nil: typeName = "General"; typeColor = .gray
        }
        return Text(typeName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(typeColor.opacity(0.1))
            .foregroundStyle(typeColor)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.08)
        } else if isGenerating {
            return Color.accentColor.opacity(0.05)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.4)
        } else if isGenerating {
            return Color.accentColor.opacity(0.5)
        }
        return Color(nsColor: .separatorColor)
    }
}

// MARK: - Card Detail Section

private struct NarrativeCardDetailSection: View {
    let card: KnowledgeCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Organization
            if let org = card.organization, !org.isEmpty {
                HStack(spacing: 4) {
                    Text("Organization:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(org)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }

            // Evidence anchors count
            if !card.evidenceAnchors.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(card.evidenceAnchors.count) evidence anchor\(card.evidenceAnchors.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Domains
            if !card.extractable.domains.isEmpty {
                DetailList(title: "Domains", items: card.extractable.domains, icon: "cpu.fill", color: .blue)
            }

            // Scale/outcomes
            if !card.extractable.scale.isEmpty {
                DetailList(title: "Scale", items: card.extractable.scale, icon: "chart.line.uptrend.xyaxis", color: .green)
            }

            // Keywords
            if !card.extractable.keywords.isEmpty {
                DetailList(title: "Keywords", items: card.extractable.keywords, icon: "tag.fill", color: .purple)
            }

            // Narrative preview
            if !card.narrative.isEmpty {
                Text(String(card.narrative.prefix(200)) + (card.narrative.count > 200 ? "..." : ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DetailList: View {
    let title: String
    let items: [String]
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ForEach(items.prefix(3), id: \.self) { item in
                Text("• \(item)")
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if items.count > 3 {
                Text("...and \(items.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
