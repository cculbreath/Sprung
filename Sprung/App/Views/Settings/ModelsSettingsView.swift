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
    // MARK: - Onboarding Models
    @AppStorage("onboardingAnthropicModelId") private var onboardingAnthropicModelId: String = ""

    // MARK: - Seed Generation (per-backend persistence)
    @AppStorage("seedGenerationBackend") private var seedGenerationBackend: String = "anthropic"
    @AppStorage("seedGenerationAnthropicModelId") private var seedGenerationAnthropicModelId: String = ""
    @AppStorage("seedGenerationOpenRouterModelId") private var seedGenerationOpenRouterModelId: String = ""

    // MARK: - Resume Revision
    @AppStorage("resumeRevisionModelId") private var resumeRevisionModelId: String = ""

    // MARK: - Document Processing
    @AppStorage("onboardingPDFExtractionModelId") private var pdfExtractionModelId: String = ""
    @AppStorage("onboardingDocSummaryModelId") private var docSummaryModelId: String = ""
    @AppStorage("onboardingCardMergeModelId") private var cardMergeModelId: String = ""

    // MARK: - Skill Processing
    @AppStorage("skillBankModelId") private var skillBankModelId: String = ""
    @AppStorage("kcExtractionModelId") private var kcExtractionModelId: String = ""
    @AppStorage("guidanceExtractionModelId") private var guidanceExtractionModelId: String = ""
    @AppStorage("skillsProcessingModelId") private var skillsProcessingModelId: String = ""
    @AppStorage("skillCurationModelId") private var skillCurationModelId: String = ""
    @AppStorage("skillsProcessingParallelAgents") private var skillsProcessingParallelAgents: Int = 12

    // MARK: - Additional Models
    @AppStorage("voicePrimerExtractionModelId") private var voicePrimerModelId: String = ""
    @AppStorage("onboardingKCAgentModelId") private var kcAgentModelId: String = ""
    @AppStorage("onboardingGitIngestModelId") private var gitIngestModelId: String = ""
    @AppStorage("backgroundProcessingModelId") private var backgroundProcessingModelId: String = ""

    // MARK: - Discovery Models
    @AppStorage("discoveryCoachingModelId") private var coachingModelId: String = ""

    // MARK: - Environment
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(LLMFacade.self) private var llmFacade
    @Environment(DiscoveryCoordinator.self) private var discoveryCoordinator

    // MARK: - Model List State
    @State private var anthropicModels: [AnthropicModel] = []
    @State private var isLoadingAnthropicModels = false
    @State private var anthropicModelError: String?

    @State private var geminiModels: [GoogleAIService.GeminiModel] = []
    @State private var isLoadingGeminiModels = false
    @State private var geminiModelError: String?

    @State private var openAIModels: [ModelObject] = []
    @State private var isLoadingOpenAIModels = false
    @State private var openAIModelError: String?

    // Discovery state synced with coordinator
    @State private var discoveryLLMModelId: String = ""
    @State private var discoveryReasoningEffort: String = "low"

    private let googleAIService = GoogleAIService()

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
            let s = discoveryCoordinator.settingsStore.current()
            discoveryLLMModelId = s.llmModelId
            discoveryReasoningEffort = s.reasoningEffort
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
        modelRow(operation: "Interview", backend: .anthropic) {
            anthropicPicker(selection: $onboardingAnthropicModelId)
        }

        // Experience Defaults - special case with backend switcher
        experienceDefaultsRow

        // Resume Revision
        modelRow(operation: "Resume Revision", backend: .anthropic) {
            anthropicPicker(selection: $resumeRevisionModelId)
        }

        Divider().padding(.vertical, 4)

        // Document Processing
        modelRow(operation: "PDF Extraction", backend: .gemini) {
            geminiPicker(selection: $pdfExtractionModelId, minTokens: 64000)
        }
        modelRow(operation: "Doc Summary", backend: .gemini) {
            geminiPicker(selection: $docSummaryModelId, minTokens: 64000)
        }
        modelRow(operation: "Card Merge", backend: .openRouter) {
            openRouterPicker(selection: $cardMergeModelId)
        }

        Divider().padding(.vertical, 4)

        // Skill Processing
        modelRow(operation: "Skill Bank", backend: .gemini) {
            geminiPicker(selection: $skillBankModelId, minTokens: 16000)
        }
        modelRow(operation: "Narrative Cards", backend: .gemini) {
            geminiPicker(selection: $kcExtractionModelId, minTokens: 32000)
        }
        modelRow(operation: "Inference Guidance", backend: .gemini) {
            geminiPicker(selection: $guidanceExtractionModelId, minTokens: 4000)
        }
        modelRow(operation: "Skills Processing", backend: .gemini) {
            geminiPicker(selection: $skillsProcessingModelId, minTokens: 64000)
        }
        modelRow(operation: "Skill Curation", backend: .openRouter) {
            openRouterPicker(selection: $skillCurationModelId)
        }

        Divider().padding(.vertical, 4)

        // Additional Models
        modelRow(operation: "Voice Primer", backend: .openRouter) {
            openRouterPicker(selection: $voicePrimerModelId)
        }
        modelRow(operation: "KC Agent", backend: .openRouter) {
            openRouterPicker(selection: $kcAgentModelId)
        }
        modelRow(operation: "Git Ingest", backend: .openRouter) {
            openRouterPicker(selection: $gitIngestModelId)
        }
        modelRow(operation: "Background Processing", backend: .openRouter) {
            openRouterPicker(selection: $backgroundProcessingModelId)
        }

        Divider().padding(.vertical, 4)

        // Discovery
        discoveryAIRow
        discoveryReasoningRow
        modelRow(operation: "Discovery Coaching", backend: .openRouter) {
            openRouterPicker(selection: $coachingModelId)
        }
    }

    // MARK: - Row Builder

    private func modelRow<P: View>(
        operation: String,
        backend: Backend,
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
    }

    // MARK: - Special Rows

    private var experienceDefaultsRow: some View {
        HStack(spacing: 0) {
            Text("Experience Defaults")
                .frame(width: operationWidth, alignment: .leading)

            // Backend switcher
            Menu {
                Button("Anthropic") { seedGenerationBackend = "anthropic" }
                Button("OpenRouter") { seedGenerationBackend = "openrouter" }
            } label: {
                HStack(spacing: 4) {
                    Text(seedGenerationBackend == "anthropic" ? "Anthropic" : "OpenRouter")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: backendWidth, alignment: .leading)

            // Model picker based on backend
            if seedGenerationBackend == "anthropic" {
                anthropicPicker(selection: $seedGenerationAnthropicModelId)
            } else {
                openRouterPicker(selection: $seedGenerationOpenRouterModelId)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var discoveryAIRow: some View {
        HStack(spacing: 0) {
            Text("Discovery AI")
                .frame(width: operationWidth, alignment: .leading)
            backendBadge(.openAI)
                .frame(width: backendWidth, alignment: .leading)
            openAIPicker(selection: $discoveryLLMModelId)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var discoveryReasoningRow: some View {
        HStack(spacing: 0) {
            Text("Discovery Reasoning")
                .frame(width: operationWidth, alignment: .leading)
            Text("")
                .frame(width: backendWidth, alignment: .leading)
            Menu {
                Button("Low") {
                    discoveryReasoningEffort = "low"
                    updateReasoningEffort("low")
                }
                Button("Medium") {
                    discoveryReasoningEffort = "medium"
                    updateReasoningEffort("medium")
                }
                Button("High") {
                    discoveryReasoningEffort = "high"
                    updateReasoningEffort("high")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(discoveryReasoningEffort.capitalized)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            Spacer()
        }
        .padding(.vertical, 6)
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
        case anthropic, gemini, openRouter, openAI

        var name: String {
            switch self {
            case .anthropic: return "Anthropic"
            case .gemini: return "Gemini"
            case .openRouter: return "OpenRouter"
            case .openAI: return "OpenAI"
            }
        }

        var color: Color {
            switch self {
            case .anthropic: return .orange
            case .gemini: return .blue
            case .openRouter: return .purple
            case .openAI: return .green
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
    private func geminiPicker(selection: Binding<String>, minTokens: Int) -> some View {
        if !hasGeminiKey {
            Text("No API key")
                .foregroundStyle(.secondary)
        } else if isLoadingGeminiModels {
            ProgressView().controlSize(.small)
        } else if let error = geminiModelError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        } else if geminiModels.isEmpty {
            Text("No models")
                .foregroundStyle(.secondary)
        } else {
            let filtered = geminiModels.filter { $0.outputTokenLimit >= minTokens }
            let selectedModel = filtered.first { $0.id == selection.wrappedValue }
            Menu {
                ForEach(filtered) { model in
                    Button(model.displayName) {
                        selection.wrappedValue = model.id
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
            Text("No models enabled")
                .foregroundStyle(.secondary)
        } else {
            let selectedModel = allOpenRouterModels.first { $0.modelId == selection.wrappedValue }
            let displayName = selectedModel.map { $0.displayName.isEmpty ? $0.modelId : $0.displayName } ?? "Select..."
            Menu {
                ForEach(allOpenRouterModels, id: \.modelId) { model in
                    Button(model.displayName.isEmpty ? model.modelId : model.displayName) {
                        selection.wrappedValue = model.modelId
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

    @ViewBuilder
    private func openAIPicker(selection: Binding<String>) -> some View {
        if !hasOpenAIKey {
            Text("No API key")
                .foregroundStyle(.secondary)
        } else if isLoadingOpenAIModels {
            ProgressView().controlSize(.small)
        } else if let error = openAIModelError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        } else if filteredOpenAIModels.isEmpty {
            Text("No models")
                .foregroundStyle(.secondary)
        } else {
            let selectedModel = filteredOpenAIModels.first { $0.id == selection.wrappedValue }
            Menu {
                ForEach(filteredOpenAIModels, id: \.id) { model in
                    Button(model.id) {
                        selection.wrappedValue = model.id
                        var s = discoveryCoordinator.settingsStore.current()
                        guard s.llmModelId != model.id else { return }
                        s.llmModelId = model.id
                        discoveryCoordinator.settingsStore.update(s)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedModel?.id ?? "Select...")
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
        APIKeyManager.get(.anthropic) != nil
    }

    private var hasGeminiKey: Bool {
        APIKeyManager.get(.gemini) != nil
    }

    private var hasOpenAIKey: Bool {
        guard let key = APIKeyManager.get(.openAI) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredAnthropicModels: [AnthropicModel] {
        anthropicModels
            .filter { model in
                let id = model.id.lowercased()
                return id.hasPrefix("claude-") && !id.contains("instant")
            }
            .sorted { $0.displayName < $1.displayName }
    }

    private var filteredOpenAIModels: [ModelObject] {
        openAIModels
            .filter { model in
                let id = model.id.lowercased()
                return id.hasPrefix("gpt-4o") || id.hasPrefix("gpt-5") || id.hasPrefix("gpt-6") || id.hasPrefix("gpt-7")
            }
            .sorted { $0.id < $1.id }
    }

    private var allOpenRouterModels: [EnabledLLM] {
        enabledLLMStore.enabledModels
            .sorted { lhs, rhs in
                (lhs.displayName.isEmpty ? lhs.modelId : lhs.displayName)
                    < (rhs.displayName.isEmpty ? rhs.modelId : rhs.displayName)
            }
    }
}

// MARK: - Helpers
private extension ModelsSettingsView {
    func updateReasoningEffort(_ newValue: String) {
        var s = discoveryCoordinator.settingsStore.current()
        guard s.reasoningEffort != newValue else { return }
        s.reasoningEffort = newValue
        discoveryCoordinator.settingsStore.update(s)
    }
}

// MARK: - Model Loading
private extension ModelsSettingsView {
    func refreshAllModelLists() async {
        async let anthropic: () = loadAnthropicModels()
        async let gemini: () = loadGeminiModels()
        async let openai: () = loadOpenAIModels()
        _ = await (anthropic, gemini, openai)
    }

    @MainActor
    func loadAnthropicModels() async {
        guard hasAnthropicKey else { return }
        isLoadingAnthropicModels = true
        anthropicModelError = nil
        do {
            let response = try await llmFacade.anthropicListModels()
            anthropicModels = response.data
            if !filteredAnthropicModels.contains(where: { $0.id == onboardingAnthropicModelId }) {
                if let first = filteredAnthropicModels.first {
                    onboardingAnthropicModelId = first.id
                }
            }
            if !filteredAnthropicModels.contains(where: { $0.id == seedGenerationAnthropicModelId }) {
                if let first = filteredAnthropicModels.first {
                    seedGenerationAnthropicModelId = first.id
                }
            }
        } catch {
            anthropicModelError = error.localizedDescription
        }
        isLoadingAnthropicModels = false
    }

    @MainActor
    func loadGeminiModels() async {
        guard hasGeminiKey else { return }
        isLoadingGeminiModels = true
        geminiModelError = nil
        do {
            geminiModels = try await googleAIService.fetchAvailableModels()
        } catch {
            geminiModelError = error.localizedDescription
        }
        isLoadingGeminiModels = false
    }

    @MainActor
    func loadOpenAIModels() async {
        guard hasOpenAIKey else { return }
        guard let apiKey = APIKeyManager.get(.openAI) else { return }

        isLoadingOpenAIModels = true
        openAIModelError = nil
        do {
            let service = OpenAIServiceFactory.service(apiKey: apiKey)
            let response = try await service.listModels()
            openAIModels = response.data
            if !filteredOpenAIModels.contains(where: { $0.id == discoveryLLMModelId }) {
                if let first = filteredOpenAIModels.first {
                    discoveryLLMModelId = first.id
                    var s = discoveryCoordinator.settingsStore.current()
                    s.llmModelId = first.id
                    discoveryCoordinator.settingsStore.update(s)
                }
            }
        } catch {
            openAIModelError = error.localizedDescription
        }
        isLoadingOpenAIModels = false
    }
}
