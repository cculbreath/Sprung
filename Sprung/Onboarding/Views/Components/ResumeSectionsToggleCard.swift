import SwiftUI

struct ResumeSectionsToggleCard: View {
    let request: OnboardingSectionToggleRequest
    let existingDraft: ExperienceDefaultsDraft
    let onConfirm: ([String]) -> Void
    let onCancel: () -> Void

    @State private var draft: ExperienceDefaultsDraft

    init(
        request: OnboardingSectionToggleRequest,
        existingDraft: ExperienceDefaultsDraft,
        onConfirm: @escaping ([String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.existingDraft = existingDraft
        self.onConfirm = onConfirm
        self.onCancel = onCancel

        var initial = existingDraft
        let proposedKeys = Set(request.proposedSections.compactMap { ExperienceSectionKey.fromOnboardingIdentifier($0) })
        if !proposedKeys.isEmpty {
            initial.setEnabledSections(proposedKeys)
        }
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Résumé Sections")
                .font(.headline)

            if let rationale = request.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Choose the sections that apply to your résumé. You can adjust these later if needed.")
                .font(.callout)

            ExperienceSectionBrowserView(draft: $draft)
                .frame(minHeight: 280)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Confirm Sections") {
                    let enabled = draft.enabledSectionKeys().map(\.rawValue)
                    onConfirm(enabled)
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
