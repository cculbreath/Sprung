import SwiftUI

/// View that displays the knowledge card collection plan and generation workflow.
/// Multi-agent workflow: plan → assignments → Generate Cards button → parallel generation
struct KnowledgeCardCollectionView: View {
    let coordinator: OnboardingInterviewCoordinator
    let onGenerateCards: () -> Void
    let onAdvanceToNextPhase: () -> Void

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

    private var assignmentCount: Int {
        coordinator.ui.proposedAssignmentCount
    }

    private var gapCount: Int {
        coordinator.ui.identifiedGapCount
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
                    KnowledgeCardPlanRow(
                        item: item,
                        isGenerating: isGenerating,
                        showAssignments: isReadyForGeneration
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
                    Text("Generate \(assignmentCount) Knowledge Card\(assignmentCount == 1 ? "" : "s")")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)

            if gapCount > 0 {
                Text("\(gapCount) documentation gap\(gapCount == 1 ? "" : "s") identified — upload more docs or proceed")
                    .font(.caption2)
                    .foregroundStyle(.orange)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                statusIcon
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(item.status == .completed ? .secondary : .primary)
                            .lineLimit(1)

                        Spacer()

                        typeTag
                    }

                    if let description = item.description {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Show assigned artifacts when assignments are ready
            if showAssignments && !item.assignedArtifactSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(item.assignedArtifactSummaries, id: \.self) { summary in
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 28)
            } else if showAssignments && item.assignedArtifactIds.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("No documents assigned")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .padding(.leading, 28)
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
        Text(item.type == .job ? "Job" : "Skill")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(item.type == .job ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
            .foregroundStyle(item.type == .job ? .blue : .purple)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        if item.status == .inProgress && isGenerating {
            return Color.accentColor.opacity(0.05)
        } else if item.status == .completed {
            return Color.green.opacity(0.03)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if item.status == .inProgress && isGenerating {
            return Color.accentColor.opacity(0.5)
        } else if item.status == .completed {
            return Color.green.opacity(0.3)
        }
        return Color(nsColor: .separatorColor)
    }
}
