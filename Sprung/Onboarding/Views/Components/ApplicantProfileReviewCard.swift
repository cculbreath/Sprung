import SwiftUI

struct ApplicantProfileReviewCard: View {
    let request: OnboardingApplicantProfileRequest
    let onConfirm: (ApplicantProfileDraft) -> Void
    let onCancel: () -> Void
    @State private var draft: ApplicantProfileDraft

    init(
        request: OnboardingApplicantProfileRequest,
        fallbackDraft: ApplicantProfileDraft,
        onConfirm: @escaping (ApplicantProfileDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        let incomingDraft = ApplicantProfileDraft(json: request.proposedProfile)
        let merged = fallbackDraft.merging(incomingDraft)
        _draft = State(initialValue: merged)
    }

    var body: some View {
        ReviewCard(
            title: "Review Applicant Profile",
            subtitle: nil,
            contentMaxHeight: 320,
            acceptButtonTitle: "Approve & Continue",
            onAccept: { onConfirm(draft) },
            onCancel: onCancel
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !request.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Information source\(request.sources.count > 1 ? "s" : "")")
                            .font(.headline)
                        ForEach(request.sources, id: \.self) { source in
                            Label(source, systemImage: "doc.text.magnifyingglass")
                                .font(.caption)
                        }
                    }
                }

                Text("Review the suggested details below. Edit anything that needs correction or add missing information before continuing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ApplicantProfileEditor(
                    draft: $draft,
                    showPhotoSection: false,
                    showsSummary: false,
                    showsProfessionalLabel: false,
                    emailSuggestions: draft.suggestedEmails
                )
            }
        }
    }
}
