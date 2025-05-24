//
//  MultiModelChooseBestCoverLetterSheet.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/23/25.
//

import SwiftUI
import SwiftData

struct MultiModelChooseBestCoverLetterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) var appState: AppState
    @Environment(JobAppStore.self) var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) var coverLetterStore: CoverLetterStore
    
    @State private var selectedModels: Set<String> = []
    @State private var isProcessing = false
    @State private var voteTally: [UUID: Int] = [:]
    @State private var modelReasonings: [(model: String, response: BestCoverLetterResponse)] = []
    @State private var errorMessage: String?
    @State private var progress: Double = 0
    @State private var totalOperations: Int = 0
    @State private var completedOperations: Int = 0
    
    @EnvironmentObject private var modelService: ModelService
    
    @Binding var coverLetter: CoverLetter
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            modelSelectionSection
            if isProcessing {
                progressSection
            }
            if !voteTally.isEmpty {
                resultsSection
            }
            if !modelReasonings.isEmpty {
                reasoningsSection
            }
            actionSection
        }
        .padding()
        .frame(width: 600, height: 700)
        .onAppear {
            // Check if we need to auto-fetch models on appear
            let needsFetching = modelService.fetchStatus.values.allSatisfy { status in
                if case .notStarted = status { return true }
                return false
            }
            
            if needsFetching {
                fetchModels()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Multi-Model Cover Letter Selection")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select multiple models to vote on the best cover letter")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var modelSelectionSection: some View {
        GroupBox("Select Models") {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let allModels = modelService.getAllModels()
                    let providers = [
                        AIModels.Provider.openai,
                        AIModels.Provider.claude,
                        AIModels.Provider.grok,
                        AIModels.Provider.gemini
                    ]
                    
                    ForEach(providers, id: \.self) { provider in
                        if let models = allModels[provider], !models.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(provider)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                
                                ForEach(models, id: \.self) { model in
                                    let sanitizedModel = OpenAIModelFetcher.sanitizeModelName(model)
                                    HStack {
                                        Toggle(isOn: Binding(
                                            get: { selectedModels.contains(sanitizedModel) },
                                            set: { isSelected in
                                                if isSelected {
                                                    selectedModels.insert(sanitizedModel)
                                                } else {
                                                    selectedModels.remove(sanitizedModel)
                                                }
                                            }
                                        )) {
                                            Text(formatModelName(sanitizedModel))
                                                .font(.system(.body))
                                        }
                                        .toggleStyle(CheckboxToggleStyle())
                                    }
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
    }
    
    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
            
            Text("Processing \(completedOperations) of \(totalOperations) models...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var resultsSection: some View {
        GroupBox("Vote Tally") {
            if let jobApp = jobAppStore.selectedApp {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(jobApp.coverLetters.sorted(by: { $0.sequencedName < $1.sequencedName }), id: \.id) { letter in
                        HStack {
                            Text(letter.sequencedName)
                                .fontWeight(getWinningLetter()?.id == letter.id ? .bold : .regular)
                            Spacer()
                            Text("\(voteTally[letter.id] ?? 0) votes")
                                .foregroundColor(getWinningLetter()?.id == letter.id ? .green : .primary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var reasoningsSection: some View {
        GroupBox("Model Reasonings") {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(modelReasonings, id: \.model) { reasoning in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatModelName(reasoning.model))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            Text("Selected: \(getLetterName(for: reasoning.response.bestLetterUuid) ?? "Unknown")")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Text(reasoning.response.verdict)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
    }
    
    private var actionSection: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .disabled(isProcessing)
            
            Spacer()
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Button("Choose Best Cover Letter") {
                Task {
                    await performMultiModelSelection()
                }
            }
            .disabled(selectedModels.isEmpty || isProcessing)
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func fetchModels() {
        Logger.debug("🔄 Auto-fetching models on sheet appear")
        
        // Fetch models for each provider that has an API key
        let keysToCheck = [
            ("openAiApiKey", AIModels.Provider.openai),
            ("claudeApiKey", AIModels.Provider.claude),
            ("grokApiKey", AIModels.Provider.grok),
            ("geminiApiKey", AIModels.Provider.gemini)
        ]
        
        for (keyName, provider) in keysToCheck {
            if let apiKey = UserDefaults.standard.string(forKey: keyName), 
               apiKey != "none" && !apiKey.isEmpty {
                modelService.fetchModelsForProvider(provider: provider, apiKey: apiKey)
            }
        }
    }
    
    private func formatModelName(_ model: String) -> String {
        return AIModels.friendlyModelName(for: model) ?? model
    }
    
    private func getLetterName(for uuid: String) -> String? {
        guard let jobApp = jobAppStore.selectedApp,
              let uuid = UUID(uuidString: uuid) else { return nil }
        return jobApp.coverLetters.first(where: { $0.id == uuid })?.sequencedName
    }
    
    private func getWinningLetter() -> CoverLetter? {
        guard let jobApp = jobAppStore.selectedApp else { return nil }
        
        let maxVotes = voteTally.values.max() ?? 0
        guard maxVotes > 0 else { return nil }
        
        let winningIds = voteTally.filter { $0.value == maxVotes }.map { $0.key }
        return jobApp.coverLetters.first { winningIds.contains($0.id) }
    }
    
    private func performMultiModelSelection() async {
        isProcessing = true
        errorMessage = nil
        voteTally = [:]
        modelReasonings = []
        totalOperations = selectedModels.count
        completedOperations = 0
        progress = 0
        
        guard let jobApp = jobAppStore.selectedApp else {
            errorMessage = "No job application selected"
            isProcessing = false
            return
        }
        
        let writingSamples = coverLetter.writingSamplesString
        
        await withTaskGroup(of: (String, Result<BestCoverLetterResponse, Error>).self) { group in
            for model in selectedModels {
                group.addTask {
                    do {
                        // Determine the provider for this model
                        let modelProvider = AIModels.providerFor(modelName: model)
                        
                        // Create a new app state instance for this specific request
                        let tempAppState = AppState()
                        tempAppState.settings.preferredLLMProvider = modelProvider
                        
                        // Create provider with the specific model
                        let provider = CoverLetterRecommendationProvider(
                            appState: tempAppState,
                            jobApp: jobApp,
                            writingSamples: writingSamples
                        )
                        
                        // Override the model in the provider's query
                        provider.overrideModel = model
                        
                        let response = try await provider.fetchBestCoverLetter()
                        return (model, .success(response))
                    } catch {
                        return (model, .failure(error))
                    }
                }
            }
            
            for await (model, result) in group {
                await MainActor.run {
                    completedOperations += 1
                    progress = Double(completedOperations) / Double(totalOperations)
                    
                    switch result {
                    case .success(let response):
                        // Add to reasonings
                        modelReasonings.append((model: model, response: response))
                        
                        // Update vote tally
                        if let uuid = UUID(uuidString: response.bestLetterUuid) {
                            voteTally[uuid, default: 0] += 1
                        }
                        
                    case .failure(let error):
                        Logger.debug("Error from model \(model): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        await MainActor.run {
            isProcessing = false
            
            // Select the winning letter
            if let winningLetter = getWinningLetter() {
                jobAppStore.selectedApp?.selectedCover = winningLetter
                
                // Give a brief delay before dismissing to show the result
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    dismiss()
                }
            } else {
                errorMessage = "No clear winner could be determined"
            }
        }
    }
}

// Helper to format model names from picker (matching BatchCoverLetterView)
private func formatModelNameFromPicker(_ model: String) -> String {
    return AIModels.friendlyModelName(for: model) ?? model
}