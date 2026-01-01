import SwiftUI

/// View that displays the knowledge card collection from merged inventory.
/// Multi-agent workflow: merge → assignments → Generate Cards button → parallel generation
struct KnowledgeCardCollectionView: View {
    let coordinator: OnboardingInterviewCoordinator
    let onGenerateCards: () -> Void
    let onAdvanceToNextPhase: () -> Void

    @State private var selectedCardId: String?
    @State private var showGapsPopover = false

    private var mergedCards: [MergedCardInventory.MergedCard] {
        coordinator.ui.mergedInventory?.mergedCards ?? []
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

    private var includedCardCount: Int {
        mergedCards.count - coordinator.ui.excludedCardIds.count
    }

    private var gapCount: Int {
        coordinator.ui.identifiedGapCount
    }

    private var mergedInventory: MergedCardInventory? {
        coordinator.ui.mergedInventory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection

            if mergedCards.isEmpty {
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
                if !mergedCards.isEmpty {
                    Text("\(mergedCards.count) card\(mergedCards.count == 1 ? "" : "s")")
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
        ContentUnavailableView(
            "Building Plan",
            systemImage: "list.bullet.clipboard",
            description: Text("Upload documents and click 'Done with Uploads' to generate card assignments...")
        )
        .frame(maxWidth: .infinity, minHeight: 150)
        .frame(maxHeight: .infinity)
    }

    private var cardListSection: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(mergedCards, id: \.cardId) { card in
                    let isExcluded = coordinator.ui.excludedCardIds.contains(card.cardId)

                    MergedCardRow(
                        card: card,
                        isGenerating: isGenerating,
                        showAssignments: isReadyForGeneration,
                        isExcluded: isExcluded,
                        isSelected: selectedCardId == card.cardId,
                        onToggleExclude: {
                            if isExcluded {
                                coordinator.ui.excludedCardIds.remove(card.cardId)
                            } else {
                                coordinator.ui.excludedCardIds.insert(card.cardId)
                            }
                            // Persist exclusion changes
                            Task {
                                await coordinator.eventBus.publish(.excludedCardIdsChanged(excludedIds: coordinator.ui.excludedCardIds))
                            }
                        },
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCardId = selectedCardId == card.cardId ? nil : card.cardId
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
                    Text("Approve & Create \(includedCardCount) Card\(includedCardCount == 1 ? "" : "s")")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
            .disabled(includedCardCount == 0 || isMerging)

            if gapCount > 0 {
                Button {
                    showGapsPopover = true
                } label: {
                    Text("\(gapCount) documentation gap\(gapCount == 1 ? "" : "s") identified — upload more docs or proceed")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showGapsPopover) {
                    GapsPopoverContent(gaps: mergedInventory?.gaps ?? [])
                }
            }

            Text("Click cards above to review details, use trash to exclude")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
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

private struct MergedCardRow: View {
    let card: MergedCardInventory.MergedCard
    let isGenerating: Bool
    let showAssignments: Bool
    let isExcluded: Bool
    let isSelected: Bool
    let onToggleExclude: () -> Void
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
                                .foregroundStyle(isExcluded ? .secondary : .primary)
                                .strikethrough(isExcluded)
                                .italic(isExcluded)
                                .lineLimit(1)

                            Spacer()

                            typeTag
                        }

                        if let dateRange = card.dateRange, !dateRange.isEmpty {
                            Text(dateRange)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .strikethrough(isExcluded)
                                .italic(isExcluded)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Expand indicator
                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Exclude/Restore button (only when ready for generation)
                if showAssignments && !isGenerating {
                    Button(action: onToggleExclude) {
                        Image(systemName: isExcluded ? "arrow.uturn.backward" : "trash")
                            .font(.caption)
                            .foregroundColor(isExcluded ? .blue : .red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help(isExcluded ? "Restore this card" : "Exclude this card")
                }
            }

            // Expanded detail section
            if isSelected {
                CardDetailSection(card: card)
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
        .opacity(isExcluded ? 0.6 : 1.0)
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
        switch card.cardType.lowercased() {
        case "job", "employment": typeName = "Job"; typeColor = .blue
        case "skill": typeName = "Skill"; typeColor = .purple
        case "project": typeName = "Project"; typeColor = .orange
        case "achievement": typeName = "Achievement"; typeColor = .green
        case "education": typeName = "Education"; typeColor = .cyan
        default: typeName = card.cardType.capitalized; typeColor = .gray
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

private struct CardDetailSection: View {
    let card: MergedCardInventory.MergedCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Evidence quality
            HStack(spacing: 4) {
                Text("Evidence:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(card.evidenceQuality.rawValue.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(evidenceColor)
            }

            // Key facts
            if !card.keyFactStatements.isEmpty {
                DetailList(title: "Key Facts", items: card.keyFactStatements, icon: "lightbulb.fill", color: .yellow)
            }

            // Technologies
            if !card.combinedTechnologies.isEmpty {
                DetailList(title: "Technologies", items: card.combinedTechnologies, icon: "cpu.fill", color: .blue)
            }

            // Outcomes
            if !card.combinedOutcomes.isEmpty {
                DetailList(title: "Outcomes", items: card.combinedOutcomes, icon: "chart.line.uptrend.xyaxis", color: .green)
            }

            // Sources
            let sourceCount = 1 + card.supportingSources.count
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(sourceCount) source\(sourceCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var evidenceColor: Color {
        switch card.evidenceQuality {
        case .strong: return .green
        case .moderate: return .orange
        case .weak: return .red
        }
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

// MARK: - Gaps Popover

private struct GapsPopoverContent: View {
    let gaps: [MergedCardInventory.DocumentationGap]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documentation Gaps")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(gaps, id: \.cardTitle) { gap in
                        GapRow(gap: gap)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding()
        .frame(width: 350)
    }
}

private struct GapRow: View {
    let gap: MergedCardInventory.DocumentationGap

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(gap.cardTitle)
                .font(.caption.weight(.medium))

            HStack(spacing: 4) {
                Image(systemName: gapIcon)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(gapDescription)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if !gap.recommendedDocs.isEmpty {
                Text("Recommended: \(gap.recommendedDocs.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(6)
    }

    private var gapIcon: String {
        switch gap.gapType {
        case .missingPrimarySource: return "doc.questionmark"
        case .insufficientDetail: return "text.magnifyingglass"
        case .noQuantifiedOutcomes: return "number"
        }
    }

    private var gapDescription: String {
        switch gap.gapType {
        case .missingPrimarySource: return "Needs primary documentation"
        case .insufficientDetail: return "Needs more detail"
        case .noQuantifiedOutcomes: return "Needs quantified outcomes"
        }
    }
}
