//
//  ModelsSettingsView.swift
//  Sprung
//
//  Consolidated view for all LLM model selections.
//  Force-refreshes model lists on every open.
//

import SwiftUI
import SwiftOpenAI

struct ModelsSettingsView: View {
    /// When set to a model-setting key, that row is boxed in red with a tooltip.
    /// Cleared once the user picks a model. Bound to the owning SettingsView.
    @Binding var highlightedKey: String?

    // MARK: - Onboarding Models
    @AppStorage("onboardingAnthropicModelId") private var onboardingAnthropicModelId: String = ""

    // MARK: - Seed Generation (per-backend persistence)
    @AppStorage("seedGenerationBackend") private var seedGenerationBackend: String = ""
    @AppStorage("seedGenerationAnthropicModelId") private var seedGenerationAnthropicModelId: String = ""
    @AppStorage("seedGenerationOpenRouterModelId") private var seedGenerationOpenRouterModelId: String = ""

    // MARK: - Resume Revision
    @AppStorage("resumeRevisionModelId") private var resumeRevisionModelId: String = ""

    // MARK: - Document Processing
    @AppStorage("onboardingDocAnalysisModelId") private var docAnalysisModelId: String = ""
    @AppStorage("onboardingCardMergeModelId") private var cardMergeModelId: String = ""

    // MARK: - Skill Processing
    @AppStorage("guidanceExtractionModelId") private var guidanceExtractionModelId: String = ""
    @AppStorage("skillsProcessingModelId") private var skillsProcessingModelId: String = ""
    @AppStorage("skillCurationModelId") private var skillCurationModelId: String = ""
    @AppStorage("skillsProcessingParallelAgents") private var skillsProcessingParallelAgents: Int = 12

    // MARK: - Additional Models
    @AppStorage("voiceProfileModelId") private var voiceProfileModelId: String = ""
    @AppStorage("onboardingKCAgentModelId") private var kcAgentModelId: String = ""
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = ""
    @AppStorage("backgroundProcessingModelId") private var backgroundProcessingModelId: String = ""
    @AppStorage("jobImportModelId") private var jobImportModelId: String = ""

    // MARK: - Discovery Models
    @AppStorage("discoveryAnthropicModelId") private var discoveryAnthropicModelId: String = ""

    // MARK: - Environment
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(LLMFacade.self) private var llmFacade

    // MARK: - Model List State
    @State private var anthropicModels: [AnthropicModel] = []
    @State private var isLoadingAnthropicModels = false
    @State private var anthropicModelError: String?

    // Column widths
    private let operationWidth: CGFloat = 180
    private let backendWidth: CGFloat = 100

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                headerRow
                Divider()

                // Model rows
                modelRows

                Divider()
                    .padding(.top, 8)

                // Additional settings
                additionalSettings
            }
            .padding()
        }
        .onAppear {
            Task {
                await refreshAllModelLists()
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Operation")
                .font(.headline)
                .frame(width: operationWidth, alignment: .leading)
            Text("Backend")
                .font(.headline)
                .frame(width: backendWidth, alignment: .leading)
            Text("Model")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Model Rows

    @ViewBuilder
    private var modelRows: some View {
        // Interview
        modelRow(operation: "Interview", backend: .anthropic, highlightKeys: ["onboardingAnthropicModelId"]) {
            anthropicPicker(selection: $onboardingAnthropicModelId)
        }

        // Experience Defaults - special case with backend switcher
        experienceDefaultsRow

        // Resume Revision
        modelRow(operation: "Resume Revision", backend: .anthropic, highlightKeys: ["resumeRevisionModelId"]) {
            anthropicPicker(selection: $resumeRevisionModelId)
        }

        Divider().padding(.vertical, 4)

        // Document Processing
        modelRow(operation: "Document Analysis", backend: .anthropic, highlightKeys: ["onboardingDocAnalysisModelId"]) {
            anthropicPicker(selection: $docAnalysisModelId)
        }
        Text("Powers all document ingestion passes: summary, narrative cards, skill bank, and enrichment. Sonnet balances extraction quality and cost; Haiku is the budget option. Extraction fidelity feeds all downstream cards.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.leading, operationWidth + backendWidth)
        modelRow(operation: "Card Merge", backend: .anthropic, highlightKeys: ["onboardingCardMergeModelId"]) {
            anthropicPicker(selection: $cardMergeModelId)
        }
        Text("Deduplicates and curates cards/skills after ingestion. Structured judgment over already-extracted content — Sonnet handles this well at a fraction of Opus cost.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.leading, operationWidth + backendWidth)

        Divider().padding(.vertical, 4)

        // Skill Processing
        modelRow(operation: "Inference Guidance", backend: .openRouter, highlightKeys: ["guidanceExtractionModelId"]) {
            openRouterPicker(selection: $guidanceExtractionModelId)
        }
        modelRow(operation: "Skills Processing", backend: .openRouter, highlightKeys: ["skillsProcessingModelId"]) {
            openRouterPicker(selection: $skillsProcessingModelId)
        }
        modelRow(operation: "Skill Curation", backend: .openRouter, highlightKeys: ["skillCurationModelId"]) {
            openRouterPicker(selection: $skillCurationModelId)
        }

        Divider().padding(.vertical, 4)

        // Additional Models
        modelRow(operation: "Voice Profile", backend: .openRouter, highlightKeys: ["voiceProfileModelId"]) {
            openRouterPicker(selection: $voiceProfileModelId)
        }
        modelRow(operation: "KC Agent", backend: .openRouter, highlightKeys: ["onboardingKCAgentModelId"]) {
            openRouterPicker(selection: $kcAgentModelId)
        }
        modelRow(operation: "Git Ingest", backend: .anthropic, highlightKeys: ["onboardingGitIngestModelId"]) {
            anthropicPicker(selection: $gitIngestModelId)
        }
        Text("Multi-turn repository analysis agent. High request volume across many repos/commits — Haiku keeps this affordable; step up to Sonnet only if analysis quality disappoints.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.leading, operationWidth + backendWidth)
        modelRow(operation: "Background Processing", backend: .openRouter, highlightKeys: ["backgroundProcessingModelId"]) {
            openRouterPicker(selection: $backgroundProcessingModelId)
        }
        jobImportRow

        Divider().padding(.vertical, 4)

        // Discovery
        modelRow(operation: "Discovery Agent", backend: .anthropic, highlightKeys: ["discoveryAnthropicModelId"]) {
            anthropicPicker(selection: $discoveryAnthropicModelId)
        }
        Text("Powers daily coaching sessions, daily-task generation, event prep, weekly reflections, and job-lead triage in Discovery.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.leading, operationWidth + backendWidth)
    }

    // MARK: - Row Builder

    private func modelRow<P: View>(
        operation: String,
        backend: Backend,
        highlightKeys: [String] = [],
        @ViewBuilder picker: () -> P
    ) -> some View {
        HStack(spacing: 0) {
            Text(operation)
                .frame(width: operationWidth, alignment: .leading)
            backendBadge(backend)
                .frame(width: backendWidth, alignment: .leading)
            picker()
            Spacer()
        }
        .padding(.vertical, 6)
        .modelRowHighlight(active: isHighlighted(highlightKeys))
    }

    // MARK: - Highlight (no-model-selected affordance)

    /// True when `highlightedKey` matches one of this row's setting keys.
    private func isHighlighted(_ keys: [String]) -> Bool {
        guard let highlightedKey else { return false }
        return keys.contains(highlightedKey)
    }

    /// Drop the red highlight once the user makes a selection.
    private func clearHighlight() {
        highlightedKey = nil
    }

    // MARK: - Special Rows

    private var experienceDefaultsRow: some View {
        HStack(spacing: 0) {
            Text("Experience Defaults")
                .frame(width: operationWidth, alignment: .leading)

            // Backend switcher
            Menu {
                Button("Anthropic") { seedGenerationBackend = "anthropic"; clearHighlight() }
                Button("OpenRouter") { seedGenerationBackend = "openrouter"; clearHighlight() }
            } label: {
                HStack(spacing: 4) {
                    Text(backendLabel(seedGenerationBackend))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: backendWidth, alignment: .leading)

            // Model picker based on backend (no silent default — a backend must be chosen)
            if seedGenerationBackend == "anthropic" {
                anthropicPicker(selection: $seedGenerationAnthropicModelId)
            } else if seedGenerationBackend == "openrouter" {
                openRouterPicker(selection: $seedGenerationOpenRouterModelId)
            } else {
                Text("Select a backend")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .modelRowHighlight(active: isHighlighted([
            "seedGenerationBackend", "seedGenerationAnthropicModelId", "seedGenerationOpenRouterModelId",
        ]))
    }

    private func backendLabel(_ backend: String) -> String {
        switch backend {
        case "anthropic": return "Anthropic"
        case "openrouter": return "OpenRouter"
        default: return "Select…"
        }
    }

    private var jobImportRow: some View {
        HStack(spacing: 0) {
            Text("Job Import")
                .frame(width: operationWidth, alignment: .leading)
            backendBadge(.anthropic)
                .frame(width: backendWidth, alignment: .leading)
            anthropicPicker(selection: $jobImportModelId)
            Spacer()
        }
        .padding(.vertical, 6)
        .modelRowHighlight(active: isHighlighted(["jobImportModelId"]))
    }

    // MARK: - Additional Settings

    private var additionalSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Additional Settings")
                .font(.headline)
                .padding(.top, 8)

            HStack {
                Text("Parallel ATS Agents")
                Stepper(value: $skillsProcessingParallelAgents, in: 1...24) {
                    Text("\(skillsProcessingParallelAgents)")
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }
            Text("Number of parallel agents for ATS synonym expansion.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Backend Badge

    private enum Backend {
        case anthropic, openRouter

        var name: String {
            switch self {
            case .anthropic: return "Anthropic"
            case .openRouter: return "OpenRouter"
            }
        }

        var color: Color {
            switch self {
            case .anthropic: return .orange
            case .openRouter: return .purple
            }
        }
    }

    private func backendBadge(_ backend: Backend) -> some View {
        Text(backend.name)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backend.color.opacity(0.15), in: Capsule())
            .foregroundStyle(backend.color)
    }

    // MARK: - Pickers

    @ViewBuilder
    private func anthropicPicker(selection: Binding<String>) -> some View {
        if !hasAnthropicKey {
            Text("No API key")
                .foregroundStyle(.secondary)
        } else if isLoadingAnthropicModels {
            ProgressView().controlSize(.small)
        } else if let error = anthropicModelError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        } else if filteredAnthropicModels.isEmpty {
            Text("No models")
                .foregroundStyle(.secondary)
        } else {
            let selectedModel = filteredAnthropicModels.first { $0.id == selection.wrappedValue }
            Menu {
                ForEach(filteredAnthropicModels) { model in
                    Button(model.displayName) {
                        selection.wrappedValue = model.id
                        clearHighlight()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedModel?.displayName ?? "Select...")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
        }
    }

    @ViewBuilder
    private func openRouterPicker(selection: Binding<String>) -> some View {
        if allOpenRouterModels.isEmpty {
            if let fetchError = enabledLLMStore.fetchError {
                Text("Couldn't load models — \(fetchError)")
                    .foregroundStyle(.red)
            } else {
                Text("No models enabled")
                    .foregroundStyle(.secondary)
            }
        } else {
            let selectedModel = allOpenRouterModels.first { $0.modelId == selection.wrappedValue }
            let displayName = selectedModel.map { $0.displayName.isEmpty ? $0.modelId : $0.displayName } ?? "Select..."
            Menu {
                ForEach(allOpenRouterModels, id: \.modelId) { model in
                    Button(model.displayName.isEmpty ? model.modelId : model.displayName) {
                        selection.wrappedValue = model.modelId
                        clearHighlight()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(displayName)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
        }
    }

    // MARK: - Computed Properties

    private var hasAnthropicKey: Bool {
        APIKeyStore.get(.anthropic) != nil
    }

    private var filteredAnthropicModels: [AnthropicModel] {
        anthropicModels
            .filter(\.isSelectable)
            .sorted { $0.displayName < $1.displayName }
    }

    private var allOpenRouterModels: [EnabledLLM] {
        enabledLLMStore.enabledModels
            .sorted { lhs, rhs in
                (lhs.displayName.isEmpty ? lhs.modelId : lhs.displayName)
                    < (rhs.displayName.isEmpty ? rhs.modelId : rhs.displayName)
            }
    }
}

// MARK: - Row Highlight Modifier
private extension View {
    /// Box a model row in red with a "select a model" tooltip when `active`.
    func modelRowHighlight(active: Bool) -> some View {
        padding(.horizontal, active ? 8 : 0)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red.opacity(active ? 0.08 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.red, lineWidth: active ? 1.5 : 0)
            )
            .help(active ? "Select a model for this operation" : "")
    }
}

// MARK: - Model Loading
private extension ModelsSettingsView {
    func refreshAllModelLists() async {
        await loadAnthropicModels()
    }

    @MainActor
    func loadAnthropicModels() async {
        guard hasAnthropicKey else { return }
        isLoadingAnthropicModels = true
        anthropicModelError = nil
        do {
            let response = try await llmFacade.anthropicListModels()
            anthropicModels = response.data
            // Never silently substitute a model. If a previously-selected model has
            // disappeared from the fetched list, leave the picker unselected and box
            // the row in red so the user explicitly re-picks.
            flagIfSelectedModelMissing(selectedId: onboardingAnthropicModelId, key: "onboardingAnthropicModelId")
            flagIfSelectedModelMissing(selectedId: seedGenerationAnthropicModelId, key: "seedGenerationAnthropicModelId")
            // Job Import migrated to Anthropic: a stale OpenAI id won't be in the
            // fetched list, so this boxes the row red until the user re-picks.
            flagIfSelectedModelMissing(selectedId: jobImportModelId, key: "jobImportModelId")
        } catch {
            anthropicModelError = error.localizedDescription
        }
        isLoadingAnthropicModels = false
    }

    @MainActor
    func flagIfSelectedModelMissing(selectedId: String, key: String) {
        guard !selectedId.isEmpty else { return }
        guard !filteredAnthropicModels.contains(where: { $0.id == selectedId }) else { return }
        if highlightedKey == nil {
            highlightedKey = key
        }
    }

}
