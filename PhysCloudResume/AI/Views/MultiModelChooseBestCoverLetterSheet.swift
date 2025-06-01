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
    @State private var scoreTally: [UUID: Int] = [:]
    @State private var modelReasonings: [(model: String, response: BestCoverLetterResponse)] = []
    @State private var errorMessage: String?
    @State private var progress: Double = 0
    @State private var totalOperations: Int = 0
    @State private var completedOperations: Int = 0
    @State private var reasoningSummary: String?
    @State private var isGeneratingSummary = false
    @State private var selectedVotingScheme: VotingScheme = .firstPastThePost
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
    @Binding var coverLetter: CoverLetter
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                votingSchemeSection
                modelSelectionSection
                if isProcessing {
                    progressSection
                }
                if !voteTally.isEmpty || !scoreTally.isEmpty {
                    resultsSection
                }
                if !modelReasonings.isEmpty || reasoningSummary != nil {
                    reasoningsSection
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            actionSection
                .padding()
                .background(.regularMaterial)
        }
        .frame(width: 600, height: 700)
        .onAppear {
            // Fetch OpenRouter models if we don't have any and have a valid API key
            if appState.hasValidOpenRouterKey && openRouterService.availableModels.isEmpty {
                Task {
                    await openRouterService.fetchModels()
                }
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
    
    private var votingSchemeSection: some View {
        GroupBox("Voting Method") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Voting Scheme", selection: $selectedVotingScheme) {
                    ForEach(VotingScheme.allCases, id: \.self) { scheme in
                        Text(scheme.rawValue)
                            .tag(scheme)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Text(selectedVotingScheme.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var modelSelectionSection: some View {
        GroupBox("Select Models") {
            ModelCheckboxListView(
                selectedModels: $selectedModels,
                sanitizeModelNames: false  // Keep raw model names for better distinction
            )
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
        GroupBox(selectedVotingScheme == .firstPastThePost ? "Vote Tally" : "Score Tally") {
            if let jobApp = jobAppStore.selectedApp {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(jobApp.coverLetters.sorted(by: { $0.sequencedName < $1.sequencedName }), id: \.id) { letter in
                        HStack {
                            Text(letter.sequencedName)
                                .fontWeight(getWinningLetter()?.id == letter.id ? .bold : .regular)
                            Spacer()
                            if selectedVotingScheme == .firstPastThePost {
                                Text("\(voteTally[letter.id] ?? 0) votes")
                                    .foregroundColor(getWinningLetter()?.id == letter.id ? .green : .primary)
                            } else {
                                Text("\(scoreTally[letter.id] ?? 0) points")
                                    .foregroundColor(getWinningLetter()?.id == letter.id ? .green : .primary)
                            }
                        }
                    }
                    
                    // Delete 0-vote letters button
                    if hasZeroVoteLetters() {
                        Divider()
                            .padding(.vertical, 4)
                        
                        Button(action: deleteZeroVoteLetters) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete letters with 0 \(selectedVotingScheme == .firstPastThePost ? "votes" : "points")")
                            }
                            .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var reasoningsSection: some View {
        GroupBox("Analysis Summary") {
            if isGeneratingSummary {
                VStack {
                    ProgressView("Generating summary...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                }
                .frame(maxHeight: 200)
            } else if let summary = reasoningSummary {
                ScrollView {
                    Text(replaceUUIDsWithLetterNames(in: summary))
                        .font(.system(.body))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(modelReasonings, id: \.model) { reasoning in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reasoning.model)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                if selectedVotingScheme == .firstPastThePost {
                                    Text("Selected: \(getLetterName(for: reasoning.response.bestLetterUuid) ?? "Unknown")")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                } else if let scoreAllocations = reasoning.response.scoreAllocations {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Score Allocations:")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        ForEach(scoreAllocations, id: \.letterUuid) { allocation in
                                            HStack {
                                                Text("\(getLetterName(for: allocation.letterUuid) ?? "Unknown"):")
                                                Text("\(allocation.score) pts")
                                                    .fontWeight(.semibold)
                                            }
                                            .font(.caption2)
                                        }
                                    }
                                }
                                
                                // Replace UUIDs with letter names in the verdict text
                                Text(replaceUUIDsWithLetterNames(in: reasoning.response.verdict))
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
    }
    
    private var actionSection: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .disabled(isProcessing || isGeneratingSummary)
            
            Spacer()
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // Show different buttons based on state
            if !voteTally.isEmpty {
                // After voting is complete, show OK button
                Button("OK") {
                    // Select the winning letter before dismissing
                    if let winningLetter = getWinningLetter() {
                        jobAppStore.selectedApp?.selectedCover = winningLetter
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingSummary)
            } else {
                // Before voting, show the choose button
                Button("Choose Best Cover Letter") {
                    Task {
                        await performMultiModelSelection()
                    }
                }
                .disabled(selectedModels.isEmpty || isProcessing)
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private func fetchModels() {
        Logger.debug("🔄 Auto-fetching OpenRouter models on sheet appear")
        
        // Fetch OpenRouter models if we have a valid API key
        if appState.hasValidOpenRouterKey {
            Task {
                await openRouterService.fetchModels()
            }
        }
    }
    
    private func getLetterName(for uuid: String) -> String? {
        guard let jobApp = jobAppStore.selectedApp,
              let uuid = UUID(uuidString: uuid) else { return nil }
        return jobApp.coverLetters.first(where: { $0.id == uuid })?.sequencedName
    }
    
    /// Replaces all UUID references in text with their corresponding letter names
    private func replaceUUIDsWithLetterNames(in text: String) -> String {
        guard let jobApp = jobAppStore.selectedApp else { return text }
        
        var result = text
        
        // Replace each cover letter's UUID with its name
        for letter in jobApp.coverLetters {
            let uuidString = letter.id.uuidString
            if result.contains(uuidString) {
                result = result.replacingOccurrences(of: uuidString, with: letter.sequencedName)
            }
        }
        
        return result
    }
    
    private func getWinningLetter() -> CoverLetter? {
        guard let jobApp = jobAppStore.selectedApp else { return nil }
        
        if selectedVotingScheme == .firstPastThePost {
            let maxVotes = voteTally.values.max() ?? 0
            guard maxVotes > 0 else { return nil }
            
            let winningIds = voteTally.filter { $0.value == maxVotes }.map { $0.key }
            return jobApp.coverLetters.first { winningIds.contains($0.id) }
        } else {
            let maxScore = scoreTally.values.max() ?? 0
            guard maxScore > 0 else { return nil }
            
            let winningIds = scoreTally.filter { $0.value == maxScore }.map { $0.key }
            return jobApp.coverLetters.first { winningIds.contains($0.id) }
        }
    }
    
    private func hasZeroVoteLetters() -> Bool {
        guard let jobApp = jobAppStore.selectedApp else { return false }
        
        return jobApp.coverLetters.contains { letter in
            if selectedVotingScheme == .firstPastThePost {
                return (voteTally[letter.id] ?? 0) == 0
            } else {
                return (scoreTally[letter.id] ?? 0) == 0
            }
        }
    }
    
    private func deleteZeroVoteLetters() {
        guard let jobApp = jobAppStore.selectedApp else { return }
        
        let lettersToDelete = jobApp.coverLetters.filter { letter in
            if selectedVotingScheme == .firstPastThePost {
                return (voteTally[letter.id] ?? 0) == 0
            } else {
                return (scoreTally[letter.id] ?? 0) == 0
            }
        }
        
        for letter in lettersToDelete {
            coverLetterStore.deleteLetter(letter)
            // Remove from tallies
            voteTally.removeValue(forKey: letter.id)
            scoreTally.removeValue(forKey: letter.id)
        }
        
        // If the selected cover letter was deleted, select the winning letter
        if lettersToDelete.contains(where: { $0.id == jobApp.selectedCover?.id }) {
            jobApp.selectedCover = getWinningLetter()
        }
    }
    
    private func performMultiModelSelection() async {
        isProcessing = true
        errorMessage = nil
        voteTally = [:]
        scoreTally = [:]
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
        
        let currentVotingScheme = selectedVotingScheme
        await withTaskGroup(of: (String, Result<BestCoverLetterResponse, Error>).self) { group in
            for model in selectedModels {
                group.addTask {
                    do {
                        // Sanitize the model name for API usage
                        let sanitizedModel = OpenAIModelFetcher.sanitizeModelName(model)
                        
                        // Determine the provider for this model
                        let modelProvider = AIModels.providerFor(modelName: sanitizedModel)
                        
                        // Create a new app state instance for this specific request
                        let tempAppState = AppState()
                        await MainActor.run {
                            tempAppState.settings.preferredLLMProvider = modelProvider
                        }
                        
                        // Create provider with the specific model
                        let provider = CoverLetterRecommendationProvider(
                            appState: tempAppState,
                            jobApp: jobApp,
                            writingSamples: writingSamples,
                            modelId: model
                        )
                        
                        // Set the override model to ensure this provider uses the correct model
                        provider.overrideModel = sanitizedModel
                        
                        // Set the voting scheme
                        provider.votingScheme = currentVotingScheme
                        
                        let response = try await provider.fetchBestCoverLetter()
                        
                        return (model, .success(response))  // Return original model name for display
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
                        
                        if selectedVotingScheme == .firstPastThePost {
                            // Update vote tally for FPTP
                            if let uuid = UUID(uuidString: response.bestLetterUuid) {
                                voteTally[uuid, default: 0] += 1
                            }
                        } else {
                            // Update score tally for score voting
                            if let scoreAllocations = response.scoreAllocations {
                                // Validate that total allocation is exactly 20
                                let totalAllocated = scoreAllocations.reduce(0) { $0 + $1.score }
                                if totalAllocated != 20 {
                                    Logger.debug("⚠️ Model \(model) allocated \(totalAllocated) points instead of 20!")
                                }
                                
                                for allocation in scoreAllocations {
                                    if let uuid = UUID(uuidString: allocation.letterUuid) {
                                        scoreTally[uuid, default: 0] += allocation.score
                                        Logger.debug("📊 Model \(model) allocated \(allocation.score) points to \(getLetterName(for: allocation.letterUuid) ?? allocation.letterUuid)")
                                    }
                                }
                            }
                        }
                        
                    case .failure(let error):
                        Logger.debug("Error from model \(model): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        await MainActor.run {
            isProcessing = false
            
            // Persist vote/score data to cover letters and mark as assessed
            for letter in jobApp.coverLetters {
                if selectedVotingScheme == .firstPastThePost {
                    letter.voteCount = voteTally[letter.id] ?? 0
                    letter.scoreCount = 0 // Reset score count when doing FPTP
                } else {
                    letter.scoreCount = scoreTally[letter.id] ?? 0
                    letter.voteCount = 0 // Reset vote count when doing score voting
                }
                letter.hasBeenAssessed = true
            }
            
            // Log final tallies for debugging
            if selectedVotingScheme == .scoreVoting {
                Logger.debug("📊 Final Score Tally:")
                for (letterId, score) in scoreTally {
                    if let letter = jobApp.coverLetters.first(where: { $0.id == letterId }) {
                        Logger.debug("  - \(letter.sequencedName): \(score) points")
                    }
                }
                let totalPoints = scoreTally.values.reduce(0, +)
                Logger.debug("  Total points allocated: \(totalPoints) (should be \(selectedModels.count * 20))")
            }
            
            // Generate summary of reasonings if we have any
            if !modelReasonings.isEmpty {
                isGeneratingSummary = true
            }
        }
        
        // Generate summary using o3-mini
        if !modelReasonings.isEmpty {
            await generateReasoningSummary()
        }
        
        await MainActor.run {
            // Determine the winning letter but don't select it yet
            if getWinningLetter() == nil {
                errorMessage = "No clear winner could be determined"
            }
        }
    }
    
    /// Generates a summary of all model reasonings using o3-mini
    private func generateReasoningSummary() async {
        guard let jobApp = jobAppStore.selectedApp else { return }
        
        // Build the prompt for summary generation
        var summaryPrompt = "You are analyzing the reasoning from multiple AI models that evaluated cover letters for a \(jobApp.jobPosition) position at \(jobApp.companyName). "
        
        if selectedVotingScheme == .firstPastThePost {
            summaryPrompt += "Each model voted for their single preferred cover letter using a first-past-the-post voting system. "
        } else {
            summaryPrompt += "Each model allocated 20 points among all cover letters using a score voting system. "
        }
        
        summaryPrompt += "Please provide a comprehensive summary that:\n"
        summaryPrompt += "1. Identifies key themes and criteria the models used\n"
        summaryPrompt += "2. Highlights areas of agreement and disagreement\n"
        summaryPrompt += "3. Synthesizes the overall reasoning behind the winning choice\n"
        summaryPrompt += "4. Notes any interesting insights about what makes an effective cover letter based on the models' analyses\n\n"
        summaryPrompt += "Here are the model reasonings:\n\n"
        
        // Add all model reasonings with their votes
        for reasoning in modelReasonings {
            let letterName = getLetterName(for: reasoning.response.bestLetterUuid) ?? "Unknown Letter"
            
            if selectedVotingScheme == .firstPastThePost {
                summaryPrompt += "**\(reasoning.model)** voted for '\(letterName)':\n"
            } else {
                summaryPrompt += "**\(reasoning.model)** score allocations:\n"
                if let scoreAllocations = reasoning.response.scoreAllocations {
                    for allocation in scoreAllocations {
                        if let letter = jobApp.coverLetters.first(where: { $0.id.uuidString == allocation.letterUuid }) {
                            summaryPrompt += "- \(letter.sequencedName): \(allocation.score) points\n"
                        }
                    }
                }
            }
            // Replace UUIDs in verdict before adding to summary prompt
            summaryPrompt += "\(replaceUUIDsWithLetterNames(in: reasoning.response.verdict))\n\n"
        }
        
        // Add final tally
        if selectedVotingScheme == .firstPastThePost {
            summaryPrompt += "Final vote tally:\n"
            for (letterId, votes) in voteTally {
                if let letter = jobApp.coverLetters.first(where: { $0.id == letterId }) {
                    summaryPrompt += "- \(letter.sequencedName): \(votes) vote(s)\n"
                }
            }
        } else {
            summaryPrompt += "Final score tally:\n"
            for (letterId, score) in scoreTally {
                if let letter = jobApp.coverLetters.first(where: { $0.id == letterId }) {
                    summaryPrompt += "- \(letter.sequencedName): \(score) points\n"
                }
            }
        }
        
        do {
            // Create a provider using OpenRouter with o4-mini
            let provider = BaseLLMProvider(appState: appState)
            
            // Initialize conversation
            _ = provider.initializeConversation(
                systemPrompt: "You are an expert at analyzing and summarizing AI model reasoning. Provide clear, insightful summaries that help users understand the decision-making process.",
                userPrompt: summaryPrompt
            )
            
            // Execute query
            let query = AppLLMQuery(
                messages: provider.conversationHistory,
                modelIdentifier: AIModels.o4_mini,
                temperature: 0.7
            )
            
            let response = try await provider.executeQuery(query)
            
            // Extract text from response
            let summaryText: String
            switch response {
            case .text(let text):
                summaryText = text
            case .structured(let data):
                summaryText = String(data: data, encoding: .utf8) ?? "Failed to decode summary"
            }
            
            await MainActor.run {
                self.reasoningSummary = summaryText
                self.isGeneratingSummary = false
            }
            
        } catch {
            await MainActor.run {
                self.reasoningSummary = "Failed to generate summary: \(error.localizedDescription)"
                self.isGeneratingSummary = false
            }
        }
    }
}
