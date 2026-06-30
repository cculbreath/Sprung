import AppKit
import SwiftUI
struct ExperienceEditorView: View {
    @Environment(ExperienceDefaultsStore.self) private var defaultsStore: ExperienceDefaultsStore
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment
    @Environment(ExperienceEntryRefinementService.self) private var refinementService: ExperienceEntryRefinementService
    @State private var draft = ExperienceDefaultsDraft()
    @State private var originalDraft = ExperienceDefaultsDraft()
    @State private var isLoading = true
    @State private var showSectionBrowser = false
    @State private var hasChanges = false
    @State private var saveState: SaveState = .idle
    @State private var editingEntries: Set<UUID> = []
    @State private var showImportSheet = false
    @State private var refineRequest: ExperienceRefineRequest?
    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }
    private var sectionCallbacks: ExperienceSectionViewCallbacks {
        ExperienceSectionViewCallbacks(
            isEditing: isEditingEntry,
            beginEditing: beginEditingEntry,
            toggleEditing: toggleEditingEntry,
            endEditing: endEditingEntry,
            onChange: markDirty,
            requestRefine: requestRefine
        )
    }
    private var activeSectionRenderers: [AnyExperienceSectionRenderer] {
        ExperienceSectionRenderers.all.filter { $0.isEnabled(in: draft) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if !defaultsStore.isSeedCreated {
                seedGenerationBanner
            }
            header
            Divider()
            content
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await loadDraft()
        }
        .onChange(of: draft) { _, newValue in
            hasChanges = newValue != originalDraft
            if saveState == .saved {
                saveState = .idle
            }
        }
        .onChange(of: defaultsStore.changeVersion) { oldVersion, newVersion in
            // Reload draft when store changes externally (e.g., from SGM apply)
            // Only reload if we don't have unsaved changes
            if !hasChanges && oldVersion != newVersion {
                Task {
                    await loadDraft()
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ExperienceDefaultsImportSheet(
                currentDraft: draft,
                onImport: { imported in
                    draft = imported
                    markDirty()
                }
            )
        }
        .sheet(item: $refineRequest) { request in
            if let current = currentRefineContent(for: request) {
                ExperienceRefineSheet(
                    draft: draft,
                    request: request,
                    current: current,
                    onApply: { accepted in applyRefinement(accepted, for: request) }
                )
                .environment(refinementService)
            }
        }
    }
    // MARK: - Seed Generation Banner

    private var seedGenerationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Generate Experience Defaults")
                    .font(.headline)
                Text("Use AI to generate professional descriptions for your work history, education, and projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NotificationCenter.default.post(name: .showSeedGeneration, object: nil)
            } label: {
                Label("Generate", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.blue.opacity(0.08))
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Experience")
                    .font(.headline)
                Text("Manage your work history, education, and skills defaults")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if case .saved = saveState {
                Text("Changes saved")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if case .error(let message) = saveState {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        showSectionBrowser.toggle()
                    }
                } label: {
                    Label(showSectionBrowser ? "Hide Sections" : "Enable Sections", systemImage: "slider.horizontal.3")
                }

                Button {
                    showImportSheet = true
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .disabled(isLoading || appEnvironment.launchState.isReadOnly)
                .help("Import values from an existing resume into Experience Defaults")

                Button("Revert") {
                    revertChanges()
                }
                .disabled(isLoading || hasChanges == false)

                Button("Save") {
                    Task {
                        await saveDraft()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || hasChanges == false || saveState == .saving)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.windowBackgroundColor))
    }
    // MARK: - Content
    private var content: some View {
        HStack(spacing: 0) {
            if showSectionBrowser {
                ExperienceSectionBrowserView(draft: $draft)
                    .frame(width: 280)
                    .background(Color(NSColor.controlBackgroundColor))
                    .transition(.move(edge: .leading))
                    .padding(.trailing, 1)
            }
            Divider()
            if isLoading {
                ProgressView("Loading experience defaults…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Dynamic sections from section renderers
                        ForEach(activeSectionRenderers) { renderer in
                            renderer.render(in: $draft, callbacks: sectionCallbacks)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showSectionBrowser)
    }

    // MARK: - Actions
    private func markDirty() {
        hasChanges = true
        if saveState == .saved {
            saveState = .idle
        }
    }
    @MainActor
    private func loadDraft() async {
        let loadedDraft = defaultsStore.loadDraft()
        draft = loadedDraft
        originalDraft = loadedDraft
        hasChanges = false
        isLoading = false
        clearEditingEntries()
    }
    @MainActor
    private func saveDraft() async {
        guard hasChanges else { return }
        saveState = .saving
        defaultsStore.save(draft: draft)
        // Mark seed as created when user manually saves content
        defaultsStore.markSeedCreated()
        originalDraft = draft
        hasChanges = false
        saveState = .saved
        clearEditingEntries()
    }
    private func revertChanges() {
        draft = originalDraft
        hasChanges = false
        saveState = .idle
        clearEditingEntries()
    }
    private func isEditingEntry(_ id: UUID) -> Bool {
        editingEntries.contains(id)
    }
    private func toggleEditingEntry(_ id: UUID) {
        if editingEntries.contains(id) {
            editingEntries.remove(id)
        } else {
            editingEntries.insert(id)
        }
    }
    private func beginEditingEntry(_ id: UUID) {
        editingEntries.insert(id)
    }
    private func endEditingEntry(_ id: UUID) {
        editingEntries.remove(id)
    }
    private func clearEditingEntries() {
        editingEntries.removeAll()
    }

    // MARK: - Refinement

    private func requestRefine(_ entryID: UUID, kind: ExperienceRefineKind) {
        guard let title = refineTitle(for: entryID, kind: kind) else { return }
        refineRequest = ExperienceRefineRequest(entryID: entryID, kind: kind, title: title)
    }

    private func refineTitle(for entryID: UUID, kind: ExperienceRefineKind) -> String? {
        switch kind {
        case .work:
            guard let entry = draft.work.first(where: { $0.id == entryID }) else { return nil }
            let position = entry.position.trimmed()
            let company = entry.name.trimmed()
            return [position, company].filter { !$0.isEmpty }.joined(separator: " · ").nonEmptyOr("Work Role")
        case .projects:
            guard let entry = draft.projects.first(where: { $0.id == entryID }) else { return nil }
            return entry.name.trimmed().nonEmptyOr("Project")
        }
    }

    /// Snapshot the entry's current AI-revisable content to seed the prompt and
    /// drive the review sheet's current-vs-proposed comparison.
    private func currentRefineContent(for request: ExperienceRefineRequest) -> ExperienceRefineContent? {
        switch request.kind {
        case .work:
            guard let entry = draft.work.first(where: { $0.id == request.entryID }) else { return nil }
            return ExperienceRefineContent(
                description: nil,
                highlights: entry.highlights.map(\.text),
                keywords: nil
            )
        case .projects:
            guard let entry = draft.projects.first(where: { $0.id == request.entryID }) else { return nil }
            return ExperienceRefineContent(
                description: entry.description,
                highlights: entry.highlights.map(\.text),
                keywords: entry.keywords.map(\.keyword)
            )
        }
    }

    /// Write the user-accepted content back onto the live draft. Fields the user
    /// rejected (empty/nil here) are left untouched.
    private func applyRefinement(_ accepted: ExperienceRefineContent, for request: ExperienceRefineRequest) {
        switch request.kind {
        case .work:
            guard let index = draft.work.firstIndex(where: { $0.id == request.entryID }) else { return }
            guard !accepted.highlights.isEmpty else { return }
            draft.work[index].highlights = accepted.highlights.map { HighlightDraft(text: $0) }
        case .projects:
            guard let index = draft.projects.firstIndex(where: { $0.id == request.entryID }) else { return }
            if let description = accepted.description {
                draft.projects[index].description = description
            }
            if !accepted.highlights.isEmpty {
                draft.projects[index].highlights = accepted.highlights.map { ProjectHighlightDraft(text: $0) }
            }
            if let keywords = accepted.keywords {
                draft.projects[index].keywords = keywords.map { KeywordDraft(keyword: $0) }
            }
        }
        markDirty()
    }
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
