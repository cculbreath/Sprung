import SwiftUI

/// View that displays the knowledge card collection plan and generation workflow.
/// Multi-agent workflow: plan → assignments → Generate Cards button → parallel generation
struct KnowledgeCardCollectionView: View {
    let coordinator: OnboardingInterviewCoordinator
    let onGenerateCards: () -> Void
    let onAdvanceToNextPhase: () -> Void

    @State private var selectedCardId: String?
    @State private var showGapsPopover = false

    private var planItems: [KnowledgeCardPlanItem] {
        coordinator.ui.knowledgeCardPlan
    }

    private var message: String? {
        coordinator.ui.knowledgeCardPlanMessage
    }

    private var hasCompletedCards: Bool {
        planItems.contains { $0.status == .completed }
    }

    private var isReadyForGeneration: Bool {
        coordinator.ui.cardAssignmentsReadyForApproval
    }

    private var isGenerating: Bool {
        coordinator.ui.isGeneratingCards
    }

    private var includedCardCount: Int {
        planItems.count - coordinator.ui.excludedCardIds.count
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

            if planItems.isEmpty {
                emptyState
            } else {
                planListSection
            }

            // Show Generate Cards button when assignments are ready
            if isReadyForGeneration && !isGenerating {
                generateCardsButton
            }

            // Show generation progress when generating
            if isGenerating {
                generatingProgressView
            }

            // Show advance button when at least one card is complete
            if hasCompletedCards && !isGenerating {
                advanceToNextPhaseButton
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
                progressSummary
            }

            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var progressSummary: some View {
        let completed = planItems.filter { $0.status == .completed }.count
        let total = planItems.count

        return Group {
            if total > 0 {
                Text("\(completed)/\(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Building Plan",
            systemImage: "list.bullet.clipboard",
            description: Text("The interviewer is analyzing your timeline to plan knowledge card collection...")
        )
        .frame(height: 150)
    }

    private var planListSection: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(planItems) { item in
                    let isExcluded = coordinator.ui.excludedCardIds.contains(item.id)
                    let mergedCard = mergedInventory?.mergedCards.first { $0.cardId == item.id }

                    KnowledgeCardPlanRow(
                        item: item,
                        isGenerating: isGenerating,
                        showAssignments: isReadyForGeneration,
                        isExcluded: isExcluded,
                        isSelected: selectedCardId == item.id,
                        mergedCard: mergedCard,
                        onToggleExclude: {
                            if isExcluded {
                                coordinator.ui.excludedCardIds.remove(item.id)
                            } else {
                                coordinator.ui.excludedCardIds.insert(item.id)
                            }
                            // Persist exclusion changes
                            Task {
                                await coordinator.eventBus.publish(.excludedCardIdsChanged(excludedIds: coordinator.ui.excludedCardIds))
                            }
                        },
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCardId = selectedCardId == item.id ? nil : item.id
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
                    Image(systemName: "sparkles")
                    Text("Generate \(includedCardCount) Knowledge Card\(includedCardCount == 1 ? "" : "s")")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
            .disabled(includedCardCount == 0)

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

            Text("Review the assignments in chat before generating")
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

    private var advanceToNextPhaseButton: some View {
        Button(action: onAdvanceToNextPhase) {
            HStack {
                Image(systemName: "arrow.right.circle.fill")
                Text("Advance to Writing Samples")
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(.blue)
        .padding(.top, 4)
    }
}

private struct KnowledgeCardPlanRow: View {
    let item: KnowledgeCardPlanItem
    let isGenerating: Bool
    let showAssignments: Bool
    let isExcluded: Bool
    let isSelected: Bool
    let mergedCard: MergedCardInventory.MergedCard?
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
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isExcluded ? .secondary : (item.status == .completed ? .secondary : .primary))
                                .strikethrough(isExcluded)
                                .italic(isExcluded)
                                .lineLimit(1)

                            Spacer()

                            typeTag
                        }

                        if let description = item.description {
                            Text(description)
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
                if mergedCard != nil {
                    Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

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
            if isSelected, let card = mergedCard {
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
        switch item.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .inProgress:
            if isGenerating {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "circle.dotted")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        case .pending:
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var typeTag: some View {
        let typeName: String
        let typeColor: Color
        switch item.type {
        case .job: typeName = "Job"; typeColor = .blue
        case .skill: typeName = "Skill"; typeColor = .purple
        case .project: typeName = "Project"; typeColor = .orange
        case .achievement: typeName = "Achievement"; typeColor = .green
        case .education: typeName = "Education"; typeColor = .cyan
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
        } else if item.status == .inProgress && isGenerating {
            return Color.accentColor.opacity(0.05)
        } else if item.status == .completed {
            return Color.green.opacity(0.03)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.4)
        } else if item.status == .inProgress && isGenerating {
            return Color.accentColor.opacity(0.5)
        } else if item.status == .completed {
            return Color.green.opacity(0.3)
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
            if !card.combinedKeyFacts.isEmpty {
                DetailList(title: "Key Facts", items: card.combinedKeyFacts, icon: "lightbulb.fill", color: .yellow)
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
