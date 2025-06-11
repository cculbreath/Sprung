//
//  MultiModelProgressSheet.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/10/25.
//

import SwiftUI
import SwiftData

struct MultiModelProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) var appState: AppState
    @Environment(JobAppStore.self) var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) var coverLetterStore: CoverLetterStore
    @Environment(EnabledLLMStore.self) var enabledLLMStore: EnabledLLMStore
    
    @Binding var coverLetter: CoverLetter
    let selectedModels: Set<String>
    let selectedVotingScheme: VotingScheme
    let onCompletion: () -> Void
    
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
    @State private var failedModels: [String: String] = [:]
    @State private var isCompleted = false
    @State private var pendingModels: Set<String> = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                
                if isProcessing {
                    progressSection
                }
                
                if !voteTally.isEmpty || !scoreTally.isEmpty || isProcessing {
                    resultsSection
                }
                
                if !failedModels.isEmpty {
                    failedModelsSection
                }
                
                if !modelReasonings.isEmpty || reasoningSummary != nil || isGeneratingSummary {
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
        .frame(width: 700, height: 600)
        .onAppear {
            Logger.info("🎯 MultiModelProgressSheet appeared, starting selection with \(selectedModels.count) models")
            Task {
                await performMultiModelSelection()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Multi-Model Cover Letter Analysis")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Running \(selectedVotingScheme.rawValue) with \(selectedModels.count) models")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
            
            Text("Processing \(completedOperations) of \(totalOperations) models...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Show pending models when down to last few
            if pendingModels.count <= 3 && pendingModels.count > 0 && !isCompleted {
                let modelNames = Array(pendingModels).sorted()
                let formattedNames = formatModelNames(modelNames)
                Text("Awaiting response from \(formattedNames)")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .italic()
            }
            
            if isGeneratingSummary {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating analysis summary...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var resultsSection: some View {
        GroupBox(selectedVotingScheme == .firstPastThePost ? "Live Vote Tally" : "Live Score Tally") {
            if let jobApp = jobAppStore.selectedApp {
                VStack(alignment: .leading, spacing: 8) {
                    if isProcessing && voteTally.isEmpty && scoreTally.isEmpty {
                        Text("Waiting for first results...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    ForEach(jobApp.coverLetters.sorted(by: { $0.sequencedName < $1.sequencedName }), id: \.id) { letter in
                        HStack {
                            Text(letter.sequencedName)
                                .fontWeight(getWinningLetter()?.id == letter.id ? .bold : .regular)
                            Spacer()
                            if selectedVotingScheme == .firstPastThePost {
                                let votes = voteTally[letter.id] ?? 0
                                Text("\(votes) vote\(votes == 1 ? "" : "s")")
                                    .foregroundColor(getWinningLetter()?.id == letter.id ? .green : .primary)
                                    .animation(.easeInOut(duration: 0.3), value: votes)
                            } else {
                                let points = scoreTally[letter.id] ?? 0
                                Text("\(points) point\(points == 1 ? "" : "s")")
                                    .foregroundColor(getWinningLetter()?.id == letter.id ? .green : .primary)
                                    .animation(.easeInOut(duration: 0.3), value: points)
                            }
                        }
                    }
                    
                    // Delete 0-vote letters button
                    if isCompleted && hasZeroVoteLetters() {
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
    
    private var failedModelsSection: some View {
        GroupBox("Failed Models") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(failedModels.sorted(by: { $0.key < $1.key }), id: \.key) { modelId, errorReason in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(modelId)
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        Text(errorReason)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                    
                    if modelId != failedModels.keys.sorted().last {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                                    if let bestUuid = reasoning.response.bestLetterUuid {
                                        Text("Selected: \(getLetterName(for: bestUuid) ?? "Unknown")")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
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
                                                if let reasoning = allocation.reasoning {
                                                    Text("- \(reasoning)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(2)
                                                }
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
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            if isProcessing {
                Button("Cancel") {
                    // TODO: Implement cancellation logic if needed
                    dismiss()
                    onCompletion()
                }
                .disabled(false)
            } else {
                Button("Close") {
                    // Select the winning letter before dismissing
                    if let winningLetter = getWinningLetter() {
                        jobAppStore.selectedApp?.selectedCover = winningLetter
                    }
                    dismiss()
                    onCompletion()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatModelNames(_ modelIds: [String]) -> String {
        let displayNames = modelIds.map { modelId in
            // Clean up model names for better display
            return modelId
                .replacingOccurrences(of: "openai/", with: "")
                .replacingOccurrences(of: "anthropic/", with: "")
                .replacingOccurrences(of: "meta-llama/", with: "")
                .replacingOccurrences(of: "google/", with: "")
                .replacingOccurrences(of: "x-ai/", with: "")
                .replacingOccurrences(of: "deepseek/", with: "")
        }
        
        if displayNames.count == 1 {
            return displayNames[0]
        } else if displayNames.count == 2 {
            return "\(displayNames[0]) and \(displayNames[1])"
        } else {
            let allButLast = displayNames.dropLast().joined(separator: ", ")
            return "\(allButLast), and \(displayNames.last!)"
        }
    }
    
    private func getLetterName(for uuid: String) -> String? {
        guard let jobApp = jobAppStore.selectedApp,
              let uuid = UUID(uuidString: uuid) else { return nil }
        return jobApp.coverLetters.first(where: { $0.id == uuid })?.sequencedName
    }
    
    private func replaceUUIDsWithLetterNames(in text: String) -> String {
        guard let jobApp = jobAppStore.selectedApp else { return text }
        
        var result = text
        
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
            voteTally.removeValue(forKey: letter.id)
            scoreTally.removeValue(forKey: letter.id)
        }
        
        if lettersToDelete.contains(where: { $0.id == jobApp.selectedCover?.id }) {
            jobApp.selectedCover = getWinningLetter()
        }
    }
    
    // MARK: - Multi-Model Selection Logic
    
    private func performMultiModelSelection() async {
        Logger.info("🚀 Starting multi-model selection with \(selectedModels.count) models using \(selectedVotingScheme.rawValue)")
        isProcessing = true
        errorMessage = nil
        voteTally = [:]
        scoreTally = [:]
        modelReasonings = []
        failedModels = [:]
        totalOperations = selectedModels.count
        completedOperations = 0
        progress = 0
        pendingModels = selectedModels
        
        guard let jobApp = jobAppStore.selectedApp else {
            errorMessage = "No job application selected"
            isProcessing = false
            return
        }
        
        _ = coverLetter.writingSamplesString
        
        let query = CoverLetterQuery(
            coverLetter: coverLetter,
            resume: jobApp.selectedRes!,
            jobApp: jobApp
        )
        
        // Capture model capabilities and cover letters data before entering async context
        let modelCapabilities = Dictionary(uniqueKeysWithValues: selectedModels.map { modelId in
            let model = enabledLLMStore.enabledModels.first(where: { $0.modelId == modelId })
            let supportsSchema = model?.supportsJSONSchema ?? false
            let shouldAvoidSchema = model?.shouldAvoidJSONSchema ?? false
            return (modelId, (supportsSchema: supportsSchema, shouldAvoidSchema: shouldAvoidSchema))
        })
        
        // Capture cover letters to avoid SwiftData concurrency issues
        let coverLetters = jobApp.coverLetters
        
        // Execute models in parallel with real-time result processing
        do {
            try await withThrowingTaskGroup(of: (String, Result<BestCoverLetterResponse, Error>).self) { group in
                // Start all model tasks
                Logger.info("🚀 Starting all \(selectedModels.count) model tasks in parallel")
                for modelId in selectedModels {
                    group.addTask {
                        do {
                            // Get model capabilities from pre-captured data
                            let capabilities = modelCapabilities[modelId]!
                            let includeJSONInstructions = !capabilities.supportsSchema || capabilities.shouldAvoidSchema
                            
                            // Generate model-specific prompt with JSON instructions if needed
                            let prompt = query.bestCoverLetterPrompt(
                                coverLetters: coverLetters,
                                votingScheme: selectedVotingScheme,
                                includeJSONInstructions: includeJSONInstructions
                            )
                            
                            let response = try await LLMService.shared.executeFlexibleJSON(
                                prompt: prompt,
                                modelId: modelId,
                                responseType: BestCoverLetterResponse.self,
                                temperature: nil,
                                jsonSchema: CoverLetterQuery.getJSONSchema(for: selectedVotingScheme)
                            )
                            return (modelId, .success(response))
                        } catch {
                            return (modelId, .failure(error))
                        }
                    }
                }
                
                // Process results as they come in
                for try await (modelId, result) in group {
                    await MainActor.run {
                        completedOperations += 1
                        progress = Double(completedOperations) / Double(totalOperations)
                        pendingModels.remove(modelId)
                        Logger.debug("📊 Progress update: \(completedOperations)/\(totalOperations) (\(Int(progress * 100))%)")
                        
                        switch result {
                        case .success(let response):
                            modelReasonings.append((model: modelId, response: response))
                            
                            if selectedVotingScheme == .firstPastThePost {
                                if let bestUuid = response.bestLetterUuid,
                                   let uuid = UUID(uuidString: bestUuid) {
                                    voteTally[uuid, default: 0] += 1
                                    Logger.debug("🗳️ \(modelId) voted for \(getLetterName(for: bestUuid) ?? bestUuid)")
                                }
                            } else {
                                if let scoreAllocations = response.scoreAllocations {
                                    let totalAllocated = scoreAllocations.reduce(0) { $0 + $1.score }
                                    if totalAllocated != 20 {
                                        Logger.debug("⚠️ Model \(modelId) allocated \(totalAllocated) points instead of 20!")
                                    }
                                    
                                    for allocation in scoreAllocations {
                                        if let uuid = UUID(uuidString: allocation.letterUuid) {
                                            scoreTally[uuid, default: 0] += allocation.score
                                            Logger.debug("📊 Model \(modelId) allocated \(allocation.score) points to \(getLetterName(for: allocation.letterUuid) ?? allocation.letterUuid)")
                                        }
                                    }
                                }
                            }
                            
                        case .failure(let error):
                            failedModels[modelId] = error.localizedDescription
                            Logger.debug("❌ Model \(modelId) failed: \(error.localizedDescription)")
                        }
                        
                        // Update error message based on current results
                        let successCount = modelReasonings.count
                        let failureCount = failedModels.count
                        let totalCompleted = successCount + failureCount
                        
                        // Log major progress milestones
                        if successCount == 1 && failureCount == 0 {
                            Logger.info("🎉 First model completed successfully")
                        }
                        
                        if failureCount > 0 && successCount > 0 {
                            errorMessage = "\(failureCount) of \(totalCompleted) models failed"
                        } else if successCount == 0 && totalCompleted == selectedModels.count {
                            Logger.info("❌ All selected models failed to respond")
                            errorMessage = "All selected models failed to respond"
                            isProcessing = false
                            return
                        } else if failureCount == 0 && totalCompleted > 0 {
                            errorMessage = nil
                        }
                    }
                }
            }
        } catch {
            Logger.error("💥 Multi-model task group failed: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "Multi-model selection failed: \(error.localizedDescription)"
                isProcessing = false
            }
            return
        }
        
        await MainActor.run {
            isProcessing = false
            Logger.info("✅ Multi-model selection completed. Processing results...")
            
            for letter in coverLetters {
                if selectedVotingScheme == .firstPastThePost {
                    letter.voteCount = voteTally[letter.id] ?? 0
                    letter.scoreCount = 0
                } else {
                    letter.scoreCount = scoreTally[letter.id] ?? 0
                    letter.voteCount = 0
                }
                letter.hasBeenAssessed = true
            }
            
            if selectedVotingScheme == .scoreVoting {
                Logger.info("📊 Final Score Tally:")
                for (letterId, score) in scoreTally {
                    if let letter = coverLetters.first(where: { $0.id == letterId }) {
                        Logger.debug("  - \(letter.sequencedName): \(score) points")
                    }
                }
                let totalPoints = scoreTally.values.reduce(0, +)
                Logger.info("  Total points allocated: \(totalPoints) (should be \(selectedModels.count * 20))")
            }
            
            if !modelReasonings.isEmpty {
                isGeneratingSummary = true
                Logger.info("📝 Starting analysis summary generation with \(modelReasonings.count) model responses")
                Logger.debug("🔍 Current reasoningSummary state: \(reasoningSummary == nil ? "nil" : "has value")")
                Logger.debug("🔍 Current isGeneratingSummary state: \(isGeneratingSummary)")
            }
        }
        
        if !modelReasonings.isEmpty {
            await generateReasoningSummary(coverLetters: coverLetters)
        } else {
            Logger.info("⚠️ No model reasonings to summarize")
        }
        
        await MainActor.run {
            isCompleted = true
            Logger.info("🏁 MultiModel process completed. Summary state: \(reasoningSummary == nil ? "nil" : "has value")")
            Logger.debug("🏁 Final UI state - isCompleted: \(isCompleted), isGeneratingSummary: \(isGeneratingSummary)")
            if getWinningLetter() == nil {
                errorMessage = "No clear winner could be determined"
            }
        }
    }
    
    private func generateReasoningSummary(coverLetters: [CoverLetter]) async {
        Logger.info("🧠 Generating reasoning summary...")
        guard let jobApp = jobAppStore.selectedApp else { 
            Logger.debug("❌ No job app selected for summary generation")
            return 
        }
        
        var letterAnalyses: [LetterAnalysis] = []
        
        for letter in coverLetters {
            let letterAnalysis: LetterAnalysis
            
            if selectedVotingScheme == .firstPastThePost {
                let votes = voteTally[letter.id] ?? 0
                let modelComments = modelReasonings.compactMap { reasoning -> String? in
                    if let bestUuid = reasoning.response.bestLetterUuid,
                       bestUuid == letter.id.uuidString {
                        return "\(reasoning.model): \(reasoning.response.verdict)"
                    }
                    return nil
                }
                
                letterAnalysis = LetterAnalysis(
                    letterId: letter.id.uuidString,
                    summaryOfModelAnalysis: modelComments.isEmpty ? "No specific comments from voting models." : modelComments.joined(separator: " | "),
                    pointsAwarded: [ModelPointsAwarded(model: "Committee Vote", points: votes)]
                )
            } else {
                var pointsFromModels: [ModelPointsAwarded] = []
                var modelComments: [String] = []
                
                for reasoning in modelReasonings {
                    if let scoreAllocations = reasoning.response.scoreAllocations,
                       let allocation = scoreAllocations.first(where: { $0.letterUuid == letter.id.uuidString }) {
                        pointsFromModels.append(ModelPointsAwarded(model: reasoning.model, points: allocation.score))
                        var comment = "\(reasoning.model): \(reasoning.response.verdict)"
                        if let allocationReasoning = allocation.reasoning {
                            comment += " (Score reasoning: \(allocationReasoning))"
                        }
                        modelComments.append(comment)
                    }
                }
                
                letterAnalysis = LetterAnalysis(
                    letterId: letter.id.uuidString,
                    summaryOfModelAnalysis: modelComments.isEmpty ? "No specific analysis provided." : modelComments.joined(separator: " | "),
                    pointsAwarded: pointsFromModels
                )
            }
            
            letterAnalyses.append(letterAnalysis)
        }
        
        let _ = CommitteeSummaryResponse(letterAnalyses: letterAnalyses)
        
        var summaryPrompt = "You are analyzing the reasoning from multiple AI models that evaluated cover letters for a \(jobApp.jobPosition) position at \(jobApp.companyName). "
        
        if selectedVotingScheme == .firstPastThePost {
            summaryPrompt += "Each model voted for their single preferred cover letter using a first-past-the-post voting system. "
        } else {
            summaryPrompt += "Each model allocated 20 points among all cover letters using a score voting system. "
        }
        
        summaryPrompt += "Based on the voting results and model reasoning provided, create a structured analysis for each cover letter that includes:\n"
        summaryPrompt += "1. A comprehensive summary of what the models said about this specific letter\n"
        summaryPrompt += "2. The points/votes awarded by each model\n"
        summaryPrompt += "3. Key themes in the model feedback\n\n"
        summaryPrompt += "Here are the model reasonings and vote allocations:\n\n"
        
        for reasoning in modelReasonings {
            if selectedVotingScheme == .firstPastThePost {
                let letterUuid = reasoning.response.bestLetterUuid ?? "Unknown"
                summaryPrompt += "**\(reasoning.model)** voted for '\(letterUuid)':\n"
            } else {
                summaryPrompt += "**\(reasoning.model)** score allocations:\n"
                if let scoreAllocations = reasoning.response.scoreAllocations {
                    for allocation in scoreAllocations {
                        summaryPrompt += "- \(allocation.letterUuid): \(allocation.score) points"
                        if let allocationReasoning = allocation.reasoning {
                            summaryPrompt += " (\(allocationReasoning))"
                        }
                        summaryPrompt += "\n"
                    }
                }
            }
            summaryPrompt += "Analysis: \(reasoning.response.strengthAndVoiceAnalysis)\n"
            summaryPrompt += "Verdict: \(reasoning.response.verdict)\n\n"
        }
        
        if selectedVotingScheme == .firstPastThePost {
            summaryPrompt += "Final vote tally:\n"
            for (letterId, votes) in voteTally {
                summaryPrompt += "- \(letterId.uuidString): \(votes) vote(s)\n"
            }
        } else {
            summaryPrompt += "Final score tally:\n"
            for (letterId, score) in scoreTally {
                summaryPrompt += "- \(letterId.uuidString): \(score) points\n"
            }
        }
        
        summaryPrompt += "\n\nProvide your analysis as a JSON response following this structure:\n"
        summaryPrompt += "```json\n"
        summaryPrompt += "{\n"
        summaryPrompt += "  \"letterAnalyses\": [\n"
        summaryPrompt += "    {\n"
        summaryPrompt += "      \"letterId\": \"UUID of the letter\",\n"
        summaryPrompt += "      \"summaryOfModelAnalysis\": \"Comprehensive summary of what models said about this letter\",\n"
        summaryPrompt += "      \"pointsAwarded\": [\n"
        summaryPrompt += "        {\"model\": \"Model name\", \"points\": 0}\n"
        summaryPrompt += "      ]\n"
        summaryPrompt += "    }\n"
        summaryPrompt += "  ]\n"
        summaryPrompt += "}\n"
        summaryPrompt += "```"
        
        do {
            let llmService = LLMService.shared
            
            let jsonSchema = JSONSchema(
                type: .object,
                properties: [
                    "letterAnalyses": JSONSchema(
                        type: .array,
                        items: JSONSchema(
                            type: .object,
                            properties: [
                                "letterId": JSONSchema(
                                    type: .string,
                                    description: "UUID of the cover letter"
                                ),
                                "summaryOfModelAnalysis": JSONSchema(
                                    type: .string,
                                    description: "Comprehensive summary of model feedback for this letter"
                                ),
                                "pointsAwarded": JSONSchema(
                                    type: .array,
                                    items: JSONSchema(
                                        type: .object,
                                        properties: [
                                            "model": JSONSchema(
                                                type: .string,
                                                description: "Name of the model"
                                            ),
                                            "points": JSONSchema(
                                                type: .integer,
                                                description: "Points awarded by this model"
                                            )
                                        ],
                                        required: ["model", "points"],
                                        additionalProperties: false
                                    )
                                )
                            ],
                            required: ["letterId", "summaryOfModelAnalysis", "pointsAwarded"],
                            additionalProperties: false
                        )
                    )
                ],
                required: ["letterAnalyses"],
                additionalProperties: false
            )
            
            let summaryResponse = try await llmService.executeStructured(
                prompt: summaryPrompt,
                modelId: "openai/o4-mini",
                responseType: CommitteeSummaryResponse.self,
                temperature: 0.7,
                jsonSchema: jsonSchema
            )
            
            await MainActor.run {
                Logger.debug("🔍 Processing \(summaryResponse.letterAnalyses.count) letter analyses")
                for analysis in summaryResponse.letterAnalyses {
                    Logger.debug("🔍 Processing analysis for letterId: \(analysis.letterId)")
                    if let letter = coverLetters.first(where: { $0.id.uuidString == analysis.letterId }) {
                        Logger.debug("🔍 Found letter: \(letter.sequencedName)")
                        let committeeFeedback = CommitteeFeedbackSummary(
                            letterId: analysis.letterId,
                            summaryOfModelAnalysis: analysis.summaryOfModelAnalysis,
                            pointsAwarded: analysis.pointsAwarded
                        )
                        letter.committeeFeedback = committeeFeedback
                    } else {
                        Logger.debug("❌ Could not find letter for ID: \(analysis.letterId)")
                    }
                }
                
                var displaySummary = "Committee Analysis Summary:\n\n"
                Logger.debug("🔍 Building display summary from \(summaryResponse.letterAnalyses.count) analyses")
                for analysis in summaryResponse.letterAnalyses {
                    if let letter = coverLetters.first(where: { $0.id.uuidString == analysis.letterId }) {
                        Logger.debug("🔍 Adding analysis for \(letter.sequencedName): \(analysis.summaryOfModelAnalysis.prefix(100))...")
                        displaySummary += "**\(letter.sequencedName)**\n"
                        displaySummary += "\(analysis.summaryOfModelAnalysis)\n\n"
                    } else {
                        Logger.debug("❌ Display summary: Could not find letter for ID: \(analysis.letterId)")
                        // Add available letter IDs for debugging
                        let availableIds = coverLetters.map { $0.id.uuidString }
                        Logger.debug("🔍 Available letter IDs: \(availableIds)")
                    }
                }
                
                self.reasoningSummary = displaySummary
                self.isGeneratingSummary = false
                Logger.info("✅ Analysis summary generation completed")
                Logger.debug("🔍 Summary length: \(displaySummary.count) characters")
                Logger.debug("🔍 Summary preview: \(String(displaySummary.prefix(100)))...")
            }
            
        } catch {
            Logger.error("❌ Analysis summary generation failed: \(error.localizedDescription)")
            await MainActor.run {
                // Update error message to include analysis failure
                let analysisError = "Analysis generation failed: \(error.localizedDescription)"
                if let existingError = errorMessage {
                    errorMessage = "\(existingError); \(analysisError)"
                } else {
                    errorMessage = analysisError
                }
                
                // Provide a fallback summary based on the voting results
                var fallbackSummary = "Committee Analysis Summary:\n\n"
                fallbackSummary += "**Voting Results:**\n"
                
                if selectedVotingScheme == .firstPastThePost {
                    for (letterId, votes) in voteTally.sorted(by: { $0.value > $1.value }) {
                        if let letter = coverLetters.first(where: { $0.id == letterId }) {
                            fallbackSummary += "• \(letter.sequencedName): \(votes) vote(s)\n"
                        }
                    }
                } else {
                    for (letterId, score) in scoreTally.sorted(by: { $0.value > $1.value }) {
                        if let letter = coverLetters.first(where: { $0.id == letterId }) {
                            fallbackSummary += "• \(letter.sequencedName): \(score) points\n"
                        }
                    }
                }
                
                fallbackSummary += "\n**Model Verdicts:**\n"
                for reasoning in modelReasonings {
                    fallbackSummary += "• **\(reasoning.model)**: \(replaceUUIDsWithLetterNames(in: reasoning.response.verdict))\n"
                }
                
                fallbackSummary += "\n*Note: Detailed analysis generation failed, showing basic voting summary.*"
                
                self.reasoningSummary = fallbackSummary
                self.isGeneratingSummary = false
            }
        }
    }
}