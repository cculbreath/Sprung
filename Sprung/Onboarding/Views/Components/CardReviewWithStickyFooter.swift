import SwiftUI

struct CardReviewWithStickyFooter: View {
    let coordinator: OnboardingInterviewCoordinator
    let onGenerateCards: () -> Void
    let onAdvanceToNextPhase: () -> Void

    private var pendingCardCount: Int {
        coordinator.knowledgeCardStore.pendingCards.count
    }

    private var pendingSkillCount: Int {
        coordinator.skillStore.pendingSkills.count
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

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: 12) {
                    KnowledgeCardCollectionView(
                        coordinator: coordinator,
                        onGenerateCards: onGenerateCards,
                        onAdvanceToNextPhase: onAdvanceToNextPhase,
                        showApproveButton: false
                    )

                    PendingSkillsCollectionView(coordinator: coordinator)
                }
                .padding(.bottom, 8)
            }

            // Sticky footer with approve button
            if isReadyForGeneration || isGenerating {
                Divider()
                stickyFooter
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    @ViewBuilder
    private var stickyFooter: some View {
        if isGenerating {
            // Progress indicator during generation
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
        } else {
            // Approve button
            VStack(spacing: 6) {
                Button(action: onGenerateCards) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text(approveButtonText)
                    }
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.green)
                .disabled(pendingCardCount == 0 || isMerging)

                Text("Click cards above to review details, use trash to remove")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var approveButtonText: String {
        let cardText = "\(pendingCardCount) Card\(pendingCardCount == 1 ? "" : "s")"
        if pendingSkillCount > 0 {
            let skillText = "\(pendingSkillCount) Skill\(pendingSkillCount == 1 ? "" : "s")"
            return "Approve & Add \(cardText) and \(skillText)"
        } else {
            return "Approve & Add \(cardText)"
        }
    }
}
