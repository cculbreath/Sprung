import SwiftyJSON
import SwiftUI

struct KnowledgeCardValidationHost: View {
    let prompt: OnboardingValidationPrompt
    let coordinator: OnboardingInterviewCoordinator
    @State private var draft: KnowledgeCardDraft
    private let artifactDisplayInfos: [ArtifactDisplayInfo]
    init(
        prompt: OnboardingValidationPrompt,
        artifacts: [ArtifactRecord],
        coordinator: OnboardingInterviewCoordinator
    ) {
        self.prompt = prompt
        self.coordinator = coordinator
        _draft = State(initialValue: KnowledgeCardDraft(json: prompt.payload))
        artifactDisplayInfos = artifacts.map { ArtifactDisplayInfo(from: $0) }
    }
    var body: some View {
        KnowledgeCardReviewCard(
            card: $draft,
            artifacts: artifactDisplayInfos,
            onApprove: { approved in
                Task {
                    await coordinator.submitValidationAndResume(
                        status: "approved",
                        updatedData: approved.toJSON(),
                        changes: nil,
                        notes: nil
                    )
                }
            },
            onReject: { reason in
                Task {
                    await coordinator.submitValidationAndResume(
                        status: "rejected",
                        updatedData: nil,
                        changes: nil,
                        notes: reason.isEmpty ? nil : reason
                    )
                }
            }
        )
        .onChange(of: prompt.id) { _, _ in
            draft = KnowledgeCardDraft(json: prompt.payload)
        }
    }
}
