import SwiftUI
import SwiftyJSON

struct ResumeSectionEntriesCard: View {
    let request: OnboardingSectionEntryRequest
    let existingDraft: ExperienceDefaultsDraft
    let onConfirm: ([JSON]) -> Void
    let onCancel: () -> Void

    @State private var draft: ExperienceDefaultsDraft
    @State private var editingEntries: Set<UUID> = []

    private let sectionKey: ExperienceSectionKey?
    private let renderer: AnyExperienceSectionRenderer?
    private let codec: AnyExperienceSectionCodec?
    private let initialDraft: ExperienceDefaultsDraft

    init(
        request: OnboardingSectionEntryRequest,
        existingDraft: ExperienceDefaultsDraft,
        onConfirm: @escaping ([JSON]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.existingDraft = existingDraft
        self.onConfirm = onConfirm
        self.onCancel = onCancel

        let key = ExperienceSectionKey.fromOnboardingIdentifier(request.section)
        self.sectionKey = key
        self.renderer = key.flatMap { sectionKey in
            ExperienceSectionRenderers.all.first { $0.key == sectionKey }
        }
        self.codec = key.flatMap { sectionKey in
            ExperienceSectionCodecs.all.first { $0.key == sectionKey }
        }

        var combinedDraft = existingDraft
        if let sectionKey, let codec {
            var proposedDraft = ExperienceDefaultsDraft()
            let jsonArray = JSON(request.entries)
            codec.decodeSection(from: jsonArray, into: &proposedDraft)
            combinedDraft.replaceSection(sectionKey, with: proposedDraft)
        }

        self.initialDraft = combinedDraft
        _draft = State(initialValue: combinedDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sectionTitle)
                .font(.headline)

            if let context = request.context, !context.isEmpty {
                Text(context)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Review and edit the entries below. Approving replaces the entire section with what you confirm here.")
                .font(.callout)

            if let renderer, sectionKey != nil {
                ScrollView {
                    renderer.render(in: $draft, callbacks: makeCallbacks())
                        .padding(.vertical, 12)
                }
            } else {
                Text("This section is not supported yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Reset to Proposed") {
                    draft = initialDraft
                    editingEntries.removeAll()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel", action: onCancel)
                Button("Approve & Continue") {
                    guard let codec = codec else {
                        onCancel()
                        return
                    }
                    let encoded = codec.encodeSection(from: draft) ?? []
                    let jsonEntries = encoded.map { JSON($0) }
                    onConfirm(jsonEntries)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sectionKey == nil)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }

    private var sectionTitle: String {
        if let key = sectionKey {
            return ExperienceSchema.sectionsByKey[key]?.metadata.title ?? key.rawValue.capitalized
        }
        return "Validate Section"
    }

    private func makeCallbacks() -> ExperienceSectionViewCallbacks {
        ExperienceSectionViewCallbacks(
            isEditing: { editingEntries.contains($0) },
            beginEditing: { editingEntries.insert($0) },
            toggleEditing: { id in
                if editingEntries.contains(id) {
                    editingEntries.remove(id)
                } else {
                    editingEntries.insert(id)
                }
            },
            endEditing: { editingEntries.remove($0) },
            onChange: {}
        )
    }
}
