import SwiftUI
import SwiftyJSON

struct TimelineCardEditorView: View {
    let timeline: JSON
    @Bindable var coordinator: OnboardingInterviewCoordinator

    @State private var drafts: [WorkExperienceDraft] = []
    @State private var baselineCards: [TimelineCard] = []
    @State private var meta: JSON?
    @State private var hasChanges = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var editingEntries: Set<UUID> = []
    @State private var lastLoadedToken: Int = -1  // Track last loaded version to prevent redundant loads

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // Scrollable cards section
            ScrollView {
                WorkExperienceSectionView(items: $drafts, callbacks: callbacks())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            footerButtons
        }
        .frame(maxHeight: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onAppear {
            // Load from coordinator's sync cache, not the initial empty timeline
            if let syncTimeline = coordinator.skeletonTimelineSync {
                Logger.info("🔄 TimelineCardEditorView: onAppear loading from sync cache with \(syncTimeline["experiences"].array?.count ?? 0) cards", category: .ai)
                load(from: syncTimeline)
            } else {
                Logger.info("🔄 TimelineCardEditorView: onAppear - no sync cache yet, loading from timeline param", category: .ai)
                load(from: timeline)
            }
        }
        .onChange(of: timeline) { _, newValue in
            // Only load if coordinator sync is not available
            if coordinator.skeletonTimelineSync == nil {
                load(from: newValue)
            }
        }
        .onChange(of: coordinator.timelineUIChangeToken) { _, newToken in
            // React to timeline changes via UI change token
            // Skip if we're currently saving to prevent infinite loops
            guard !isSaving else {
                Logger.info("🔄 TimelineCardEditorView: onChange skipped (currently saving)", category: .ai)
                return
            }

            // Skip if we've already loaded this version
            guard newToken != lastLoadedToken else {
                Logger.info("🔄 TimelineCardEditorView: onChange skipped (already loaded token \(newToken))", category: .ai)
                return
            }

            let newTimeline = coordinator.skeletonTimelineSync
            Logger.info("🔄 TimelineCardEditorView: onChange fired (UI token \(newToken)). New timeline has \(newTimeline?["experiences"].array?.count ?? 0) cards", category: .ai)
            if let newTimeline {
                load(from: newTimeline)
                lastLoadedToken = newToken
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
