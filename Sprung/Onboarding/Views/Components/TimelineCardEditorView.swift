import SwiftUI
import SwiftyJSON

struct TimelineCardEditorView: View {
    enum Mode {
        case editor      // Save/Discard buttons, auto-sync with coordinator
        case validation  // Confirm/Reject buttons, final approval
    }

    let timeline: JSON
    @Bindable var coordinator: OnboardingInterviewCoordinator
    var mode: Mode = .editor
    var onValidationSubmit: ((String) -> Void)? = nil  // Callback for validation mode: "confirmed" or "confirmed_with_changes"
    var onSubmitChangesOnly: (() -> Void)? = nil  // Callback for "Submit Changes Only" - saves and lets LLM reassess

    @State private var drafts: [WorkExperienceDraft] = []
    @State private var baselineCards: [TimelineCard] = []
    @State private var meta: JSON?
    @State private var hasChanges = false
    @State private var isSaving = false
    @State private var isLoadingFromCoordinator = false  // Track when loading from coordinator to prevent drafts onChange interference
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
            // Only watch coordinator changes in editor mode
            // In validation mode, we're showing a snapshot for final approval
            guard mode == .editor else { return }

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
                let state = TimelineCardAdapter.cards(from: newTimeline)

                // Check if this represents new LLM-created content that needs user confirmation
                let newCards = state.cards
                let needsConfirmation = !newCards.isEmpty && (baselineCards.isEmpty || newCards != baselineCards)

                // Set loading flag to prevent drafts onChange from overwriting hasChanges
                isLoadingFromCoordinator = true

                // Load the new timeline
                baselineCards = state.cards
                drafts = TimelineCardAdapter.workDrafts(from: state.cards)
                meta = state.meta

                // If LLM created/modified cards, they need user confirmation
                hasChanges = needsConfirmation

                errorMessage = nil
                editingEntries.removeAll()
                lastLoadedToken = newToken

                // Clear loading flag
                isLoadingFromCoordinator = false

                Logger.info("🔄 TimelineCardEditorView: Loaded \(newCards.count) cards, hasChanges=\(needsConfirmation)", category: .ai)
            }
        }
        .onChange(of: drafts) { _, _ in
            // Skip recalculation if we're actively loading from coordinator
            // to prevent overwriting hasChanges that was just set in token onChange
            guard !isLoadingFromCoordinator else { return }
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
                if mode == .editor {
                    // Editor mode: Save/Discard
                    Button("Discard Changes", role: .cancel, action: discardChanges)
                        .disabled(!hasChanges || isSaving)

                    Button {
                        saveChanges()
                    } label: {
                        Label(isSaving ? "Saving…" : "Save Timeline", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges || isSaving)
                } else {
                    // Validation mode: Buttons change based on whether user made edits
                    if hasChanges {
                        // User made changes - different options
                        Button("Submit Changes Only") {
                            submitChangesOnly()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Confirm with Changes") {
                            onValidationSubmit?("confirmed_with_changes")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        // No changes - simple confirm/reject
                        Button("Reject", role: .destructive) {
                            onValidationSubmit?("rejected")
                        }

                        Spacer()

                        Button("Confirm") {
                            onValidationSubmit?("confirmed")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func load(from timeline: JSON) {
        let state = TimelineCardAdapter.cards(from: timeline)

        // Set loading flag to prevent drafts onChange from interfering
        isLoadingFromCoordinator = true

        baselineCards = state.cards
        drafts = TimelineCardAdapter.workDrafts(from: state.cards)
        meta = state.meta
        hasChanges = false
        errorMessage = nil
        editingEntries.removeAll()

        // Clear loading flag
        isLoadingFromCoordinator = false
    }

    private func discardChanges() {
        withAnimation {
            // Set loading flag to prevent drafts onChange from interfering
            isLoadingFromCoordinator = true

            drafts = TimelineCardAdapter.workDrafts(from: baselineCards)
            hasChanges = false
            editingEntries.removeAll()

            // Clear loading flag
            isLoadingFromCoordinator = false
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

    private func submitChangesOnly() {
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
            // Save the changes to coordinator
            await coordinator.applyUserTimelineUpdate(cards: updatedCards, meta: meta, diff: diff)
            await MainActor.run {
                baselineCards = updatedCards
                hasChanges = false
                isSaving = false
                // Notify callback that changes were submitted
                onSubmitChangesOnly?()
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
