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
    private var suggestedSections: [ExperienceSectionKey] {
        let identifiers = request.availableSections
        return identifiers.compactMap { ExperienceSectionKey.fromOnboardingIdentifier($0) }
    }
    private var recommendedSections: Set<ExperienceSectionKey> {
        Set(request.proposedSections.compactMap { ExperienceSectionKey.fromOnboardingIdentifier($0) })
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
            if !suggestedSections.isEmpty {
                Text("Suggested sections: \(suggestedSections.map { $0.metadata.title }.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.vertical, showsIndicators: true) {
                ResumeSectionToggleGrid(draft: $draft, recommended: recommendedSections)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            .frame(maxHeight: 240)
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
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
private struct ResumeSectionToggleGrid: View {
    @Binding var draft: ExperienceDefaultsDraft
    let recommended: Set<ExperienceSectionKey>
    private let columns = [
        GridItem(.flexible(minimum: 140), spacing: 12),
        GridItem(.flexible(minimum: 140), spacing: 12)
    ]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(ExperienceSectionKey.allCases) { key in
                Toggle(isOn: key.metadata.toggleBinding(in: $draft)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.metadata.title)
                            .font(.subheadline)
                            .fontWeight(recommended.contains(key) ? .semibold : .regular)
                        if let subtitle = key.metadata.subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}
