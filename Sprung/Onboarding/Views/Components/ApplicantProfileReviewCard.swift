import SwiftUI

struct ApplicantProfileReviewCard: View {
    let request: OnboardingApplicantProfileRequest
    let fallbackDraft: ApplicantProfileDraft
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
        self.fallbackDraft = fallbackDraft
        self.onConfirm = onConfirm
        self.onCancel = onCancel

        let incomingDraft = ApplicantProfileDraft(json: request.proposedProfile)
        let merged = fallbackDraft.merging(incomingDraft)
        _draft = State(initialValue: merged)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Applicant Profile")
                .font(.headline)

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

            ScrollView {
                ApplicantProfileEditor(draft: $draft, showPhotoSection: true, showsSummary: true)
            }
            .frame(minHeight: 320)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Approve & Continue") {
                    onConfirm(draft)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }
}
