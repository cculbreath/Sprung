import AppKit
import SwiftUI
struct ExperienceEditorView: View {
    @Environment(ExperienceDefaultsStore.self) private var defaultsStore: ExperienceDefaultsStore
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment
    @Environment(ExperienceEntryRefinementService.self) private var refinementService: ExperienceEntryRefinementService
    // Stores the SeedGenerationContextBuilder needs (all injected above this view).
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore: KnowledgeCardStore
    @Environment(SkillStore.self) private var skillStore: SkillStore
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore: ApplicantProfileStore
    @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore
    @Environment(CandidateDossierStore.self) private var candidateDossierStore: CandidateDossierStore
    @Environment(TitleSetStore.self) private var titleSetStore: TitleSetStore
    @State private var draft = ExperienceDefaultsDraft()
    @State private var originalDraft = ExperienceDefaultsDraft()
    @State private var isLoading = true
    @State private var showSectionBrowser = false
    @State private var hasChanges = false
    @State private var saveState: SaveState = .idle
    @State private var editingEntries: Set<UUID> = []
    @State private var showImportSheet = false
    @State private var refineRequest: ExperienceRefineRequest?
    /// Seed Generation (one-shot Experience Defaults generator) presented as a
    /// sheet from this module. The orchestrator is built by `presentSeedGeneration()`
    /// only after all prerequisite guards pass; `showSeedSheet` drives presentation
    /// (SeedGenerationOrchestrator is not Identifiable, so `.sheet(isPresented:)`).
    @State private var seedOrchestrator: SeedGenerationOrchestrator?
    @State private var showSeedSheet = false
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
        .sheet(isPresented: $showSeedSheet) {
            if let seedOrchestrator {
                SeedGenerationView(orchestrator: seedOrchestrator)
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
                Task { await presentSeedGeneration() }
            } label: {
                Label("Generate", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.blue.opacity(0.08))
    }

    // MARK: - Seed Generation

    /// Run the seed-generation prerequisite guards and, if all pass, build the
    /// orchestrator and present `SeedGenerationView` as a sheet. Mirrors the
    /// gating the detached window used to perform, in order: approved knowledge
    /// cards → context build → configured backend+model. HARD RULE: never
    /// proceed without a configured backend AND model — surface Model Settings.
    @MainActor
    private func presentSeedGeneration() async {
        // Prerequisite: at least one APPROVED knowledge card to generate from.
        // Pending (unapproved) cards never feed generation — surface the paths
        // to create/approve some instead of failing silently.
        guard !knowledgeCardStore.approvedCards.isEmpty else {
            Logger.error("Cannot show seed generation: no approved knowledge cards exist.", category: .ui)
            presentNoKnowledgeCardsAlert()
            return
        }

        // Build SeedGenerationContext from onboarding artifacts
        guard let context = await SeedGenerationContextBuilder.build(
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore,
            experienceDefaultsStore: defaultsStore,
            applicantProfileStore: applicantProfileStore,
            coverRefStore: coverRefStore,
            candidateDossierStore: candidateDossierStore,
            titleSetStore: titleSetStore
        ) else {
            Logger.error("Failed to build SeedGenerationContext", category: .ui)
            presentContextBuildFailureAlert()
            return
        }

        // Get model and backend from settings (per-backend model persistence).
        // No silent backend default — an unconfigured backend surfaces the picker.
        guard let backendString = UserDefaults.standard.string(forKey: "seedGenerationBackend"),
              !backendString.isEmpty else {
            Logger.error("Cannot show seed generation: no backend configured.", category: .ui)
            presentSeedModelAlert(
                message: "Choose a backend and model for Experience Defaults generation before continuing.",
                highlightKey: "seedGenerationBackend"
            )
            return
        }
        let backend: LLMFacade.Backend = backendString == "anthropic" ? .anthropic : .openRouter
        let modelKey = backendString == "anthropic" ? "seedGenerationAnthropicModelId" : "seedGenerationOpenRouterModelId"
        guard let modelId = UserDefaults.standard.string(forKey: modelKey),
              !modelId.isEmpty else {
            Logger.error("Cannot show seed generation: no model configured.", category: .ui)
            presentSeedModelAlert(
                message: "Select \(backend == .anthropic ? "an Anthropic" : "an OpenRouter") model for Experience Defaults generation before continuing.",
                highlightKey: modelKey
            )
            return
        }

        seedOrchestrator = SeedGenerationOrchestrator(
            context: context,
            llmFacade: appEnvironment.llmFacade,
            modelId: modelId,
            backend: backend,
            experienceDefaultsStore: defaultsStore
        )
        showSeedSheet = true
    }

    /// Missing backend/model for Experience Defaults: explain, then route to the
    /// Models settings tab with the unconfigured picker boxed in red.
    @MainActor
    private func presentSeedModelAlert(message: String, highlightKey: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Model Required for Experience Defaults"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Model Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NotificationCenter.default.post(
                name: .showModelSettings, object: nil,
                userInfo: ["settingKey": highlightKey]
            )
        }
    }

    /// No knowledge cards to generate from: offer the two ways to create some
    /// (onboarding interview, or the Knowledge Card browser) or cancel.
    @MainActor
    private func presentNoKnowledgeCardsAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "No Knowledge Cards Yet"
        alert.informativeText = "Experience Defaults are generated from your knowledge cards, but none exist yet. Run the onboarding interview to build them from your documents, or add cards manually in the Knowledge Card browser."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start Onboarding Interview")
        alert.addButton(withTitle: "Open Knowledge Card Browser")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NotificationCenter.default.post(name: .startOnboardingInterview, object: nil)
        case .alertSecondButtonReturn:
            NotificationCenter.default.post(
                name: .navigateToModule, object: nil,
                userInfo: ["module": AppModule.references.rawValue]
            )
            NotificationCenter.default.post(
                name: .navigateToReferencesTab, object: nil,
                userInfo: ["tab": ReferencesModuleView.Tab.knowledge.rawValue]
            )
        default:
            break
        }
    }

    /// SeedGenerationContextBuilder returned nil — onboarding likely incomplete.
    @MainActor
    private func presentContextBuildFailureAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't Assemble Generation Context"
        alert.informativeText = "Couldn't assemble generation context. Ensure the onboarding interview has been completed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
