import SwiftUI
import SwiftyJSON
struct TimelineCardEditorView: View {
    enum Mode {
        case editor      // Save/Discard buttons, auto-sync with coordinator
        case validation  // Confirm/Reject buttons, final approval
    }
    let timeline: JSON
    let coordinator: OnboardingInterviewCoordinator
    var mode: Mode = .editor
    var onValidationSubmit: ((String) -> Void)?  // Callback for validation mode: "confirmed" or "confirmed_with_changes"
    var onSubmitChangesOnly: (() -> Void)?  // Callback for "Submit Changes Only" - saves and lets LLM reassess
    @State private var drafts: [TimelineEntryDraft] = []
    @State private var baselineCards: [TimelineCard] = []
    @State private var previousDraftIds: Set<String> = []  // Track IDs to detect deletions
    @State private var meta: JSON?
    @State private var hasChanges = false
    @State private var isSaving = false
    @State private var isLoadingFromCoordinator = false  // Track when loading from coordinator to prevent drafts onChange interference
    @State private var errorMessage: String?
    @State private var lastLoadedToken: Int = -1  // Track last loaded version to prevent redundant loads
    var body: some View {
        // IMPORTANT: Access timelineUIChangeToken in body to establish @Observable tracking
        // Without this, onChange(of: timelineUIChangeToken) may not fire for LLM updates
        let _ = coordinator.ui.timelineUIChangeToken

        VStack(alignment: .leading, spacing: 12) {
            header

            // Scrollable cards section - uses remaining space but leaves room for footer
            ScrollView {
                TimelineEntrySectionView(
                    entries: $drafts,
                    onChange: {
                        guard !isLoadingFromCoordinator else { return }
                        hasChanges = TimelineCardAdapter.cards(from: drafts) != baselineCards
                    }
                )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            // Sticky footer - always visible
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
        .onAppear {
            // Load from coordinator's sync cache, not the initial empty timeline
            if let syncTimeline = coordinator.ui.skeletonTimeline {
                Logger.info("🔄 TimelineCardEditorView: onAppear loading from sync cache with \(syncTimeline["experiences"].array?.count ?? 0) cards", category: .ai)
                load(from: syncTimeline)
            } else {
                Logger.info("🔄 TimelineCardEditorView: onAppear - no sync cache yet, loading from timeline param", category: .ai)
                load(from: timeline)
            }
        }
        .onChange(of: timeline) { _, newValue in
            // Only load if coordinator sync is not available
            if coordinator.ui.skeletonTimeline == nil {
                load(from: newValue)
            }
        }
        .onChange(of: coordinator.ui.timelineUIChangeToken) { _, newToken in
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
            let newTimeline = coordinator.ui.skeletonTimeline
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
                drafts = TimelineCardAdapter.entryDrafts(from: state.cards)
                previousDraftIds = Set(drafts.map { $0.id })  // Update tracking set
                meta = state.meta
                // If LLM created/modified cards, they need user confirmation
                hasChanges = needsConfirmation
                errorMessage = nil
                lastLoadedToken = newToken
                // Clear loading flag
                isLoadingFromCoordinator = false
                Logger.info("🔄 TimelineCardEditorView: Loaded \(newCards.count) cards, hasChanges=\(needsConfirmation)", category: .ai)
            }
        }
        .onChange(of: drafts) { _, newDrafts in
            // Skip recalculation if we're actively loading from coordinator
            // to prevent overwriting hasChanges that was just set in token onChange
            guard !isLoadingFromCoordinator else { return }
            // Detect deletions and immediately sync them to coordinator
            // This prevents deleted cards from reappearing when LLM updates other cards
            let currentIds = Set(newDrafts.map { $0.id })
            let deletedIds = previousDraftIds.subtracting(currentIds)
            if !deletedIds.isEmpty {
                Task {
                    for deletedId in deletedIds {
                        Logger.info("🗑️ UI deletion detected: immediately syncing card \(deletedId) deletion to coordinator", category: .ai)
                        await coordinator.deleteTimelineCardFromUI(id: deletedId)
                    }
                }
            }
            // Update tracking set
            previousDraftIds = currentIds
            hasChanges = TimelineCardAdapter.cards(from: newDrafts) != baselineCards
        }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timeline Entries")
                    .font(.title3.weight(.semibold))
                Text("Use the entries below to tidy types, titles, organizations, and dates.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation {
                    drafts.append(TimelineEntryDraft())
                }
            } label: {
                Label("Add Entry", systemImage: "plus")
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
                    // Validation mode: Always show reject option, plus confirm buttons
                    Button("Reject", role: .destructive) {
                        onValidationSubmit?("rejected")
                    }
                    if hasChanges {
                        // User made changes - offer to submit changes for reassessment or confirm with changes
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
                        // No changes - simple confirm
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
        drafts = TimelineCardAdapter.entryDrafts(from: state.cards)
        meta = state.meta
        hasChanges = false
        errorMessage = nil
        // Clear loading flag
        isLoadingFromCoordinator = false
    }
    private func discardChanges() {
        withAnimation {
            // Set loading flag to prevent drafts onChange from interfering
            isLoadingFromCoordinator = true
            drafts = TimelineCardAdapter.entryDrafts(from: baselineCards)
            hasChanges = false
            // Clear loading flag
            isLoadingFromCoordinator = false
        }
        errorMessage = nil
    }
    private func saveChanges() {
        Logger.info("💾 saveChanges called: hasChanges=\(hasChanges), isSaving=\(isSaving)", category: .ai)
        guard hasChanges, !isSaving else {
            Logger.info("💾 saveChanges guard failed: hasChanges=\(hasChanges), isSaving=\(isSaving)", category: .ai)
            return
        }
        let updatedCards = TimelineCardAdapter.cards(from: drafts)
        let diff = TimelineDiffBuilder.diff(original: baselineCards, updated: updatedCards)
        Logger.info("💾 Diff calculated: isEmpty=\(diff.isEmpty), added=\(diff.added.count), removed=\(diff.removed.count), updated=\(diff.updated.count), reordered=\(diff.reordered)", category: .ai)
        guard diff.isEmpty == false else {
            Logger.info("💾 saveChanges: diff is empty, skipping", category: .ai)
            hasChanges = false
            errorMessage = nil
            return
        }
        isSaving = true
        errorMessage = nil
        Logger.info("💾 saveChanges: calling coordinator.applyUserTimelineUpdate with \(updatedCards.count) cards", category: .ai)
        Task { @MainActor in
            await coordinator.applyUserTimelineUpdate(cards: updatedCards, meta: meta, diff: diff)
            Logger.info("💾 saveChanges: applyUserTimelineUpdate completed", category: .ai)
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
        Task { @MainActor in
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
}
