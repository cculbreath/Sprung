import SwiftUI
import SwiftyJSON

struct TimelineCardEditorView: View {
    let timeline: JSON
    let coordinator: OnboardingInterviewCoordinator

    @State private var drafts: [WorkExperienceDraft] = []
    @State private var baselineCards: [TimelineCard] = []
    @State private var meta: JSON?
    @State private var hasChanges = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var editingEntries: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            WorkExperienceSectionView(items: $drafts, callbacks: callbacks())
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            footerButtons
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onAppear { load(from: timeline) }
        .onChange(of: timeline) { _, newValue in
            load(from: newValue)
        }
        .onChange(of: coordinator.skeletonTimelineSync) { _, newTimeline in
            // Reload when timeline cards are created/updated in real-time
            if let newTimeline {
                load(from: newTimeline)
            }
        }
        .onChange(of: drafts) { _, _ in
            hasChanges = TimelineCardAdapter.cards(from: drafts) != baselineCards
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timeline Cards")
                    .font(.title3.weight(.semibold))
                Text("Use the cards below to tidy titles, companies, and dates. Drag handles to reorder entries before we dive deeper.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                let draft = WorkExperienceDraft()
                let identifier = draft.id
                withAnimation {
                    drafts.append(draft)
                    editingEntries.insert(identifier)
                }
            } label: {
                Label("Add Card", systemImage: "plus")
            }
        }
    }

    private var footerButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Discard Changes", role: .cancel, action: discardChanges)
                    .disabled(!hasChanges || isSaving)

                Button {
                    saveChanges()
                } label: {
                    Label(isSaving ? "Saving…" : "Save Timeline", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || isSaving)
            }
        }
    }

    private func load(from timeline: JSON) {
        let state = TimelineCardAdapter.cards(from: timeline)
        baselineCards = state.cards
        drafts = TimelineCardAdapter.workDrafts(from: state.cards)
        meta = state.meta
        hasChanges = false
        errorMessage = nil
        editingEntries.removeAll()
    }

    private func discardChanges() {
        withAnimation {
            drafts = TimelineCardAdapter.workDrafts(from: baselineCards)
            hasChanges = false
            editingEntries.removeAll()
        }
        errorMessage = nil
    }

    private func saveChanges() {
        guard hasChanges, !isSaving else { return }
        let updatedCards = TimelineCardAdapter.cards(from: drafts)
        let diff = TimelineDiffBuilder.diff(original: baselineCards, updated: updatedCards)
        guard diff.isEmpty == false else {
            hasChanges = false
            errorMessage = nil
            return
        }

        isSaving = true
        errorMessage = nil

        Task {
            await coordinator.applyUserTimelineUpdate(cards: updatedCards, meta: meta, diff: diff)
            await MainActor.run {
                baselineCards = updatedCards
                hasChanges = false
                isSaving = false
            }
        }
    }

    private func callbacks() -> ExperienceSectionViewCallbacks {
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
            onChange: { hasChanges = TimelineCardAdapter.cards(from: drafts) != baselineCards }
        )
    }
}
