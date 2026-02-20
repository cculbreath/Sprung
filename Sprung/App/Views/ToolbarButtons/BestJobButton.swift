// Sprung/App/Views/ToolbarButtons/BestJobButton.swift
import SwiftUI

struct BestJobButton: View {
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(DiscoveryCoordinator.self) private var coordinator
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore
    @Environment(CandidateDossierStore.self) private var candidateDossierStore
    @Environment(CoverRefStore.self) private var coverRefStore
    @Environment(LLMFacade.self) private var llmFacade
    @Environment(ReasoningStreamManager.self) private var reasoningStreamManager

    @State private var showModelSheet = false
    @State private var isProcessing = false
    @State private var selectionResult: JobSelectionsResult?
    @State private var selectionError: String?
    @State private var showSelectionReport = false

    var body: some View {
        Button(action: {
            showModelSheet = true
        }, label: {
            if isProcessing {
                Label("Best Job", systemImage: "sparkle").fontWeight(.bold).foregroundColor(.blue)
                    .symbolEffect(.rotate.byLayer)
                    .font(.system(size: 14, weight: .light))
            } else {
                Label("Best Job", systemImage: "medal")
                    .font(.system(size: 14, weight: .light))
            }
        })
        .buttonStyle(.automatic)
        .help("Find the best job matches based on your qualifications")
        .disabled(isProcessing)
        .sheet(isPresented: $showModelSheet) {
            ChooseBestJobsSheet(
                isPresented: $showModelSheet,
                onModelSelected: { modelId in
                    showModelSheet = false
                    isProcessing = true
                    Task {
                        await chooseBestJobs(modelId: modelId)
                    }
                }
            )
        }
        .sheet(isPresented: $showSelectionReport) {
            if let result = selectionResult {
                SelectionReportSheet(result: result)
            } else if let error = selectionError {
                SelectionErrorSheet(error: error)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerBestJobButton)) { _ in
            showModelSheet = true
        }
    }

    @MainActor
    private func chooseBestJobs(modelId: String) async {
        selectionError = nil

        // Build knowledge context from KnowledgeCards
        let knowledgeContext = knowledgeCardStore.knowledgeCards
            .map { card in
                let typeLabel = "[\(card.cardType?.rawValue ?? "general")]"
                return "\(typeLabel) \(card.title):\n\(card.narrative)"
            }
            .joined(separator: "\n\n")

        // Build dossier context from CandidateDossier + writing samples
        var dossierParts: [String] = []
        if let dossier = candidateDossierStore.dossier {
            dossierParts.append(dossier.exportForJobMatching())
        }
        let writingSamples = coverRefStore.storedCoverRefs
            .filter { $0.type == .writingSample }
            .prefix(5)
            .map { "<writing_sample name=\"\($0.name)\">\n\($0.content.prefix(500))...\n</writing_sample>" }
            .joined(separator: "\n\n")
        if !writingSamples.isEmpty {
            dossierParts.append(writingSamples)
        }
        let dossierContext = dossierParts.joined(separator: "\n\n")

        // Build prompt (same as DiscoveryAgentService.chooseBestJobs)
        let identifiedJobs = coordinator.jobAppStore.jobApps(forStatus: .new)
        guard !identifiedJobs.isEmpty else {
            selectionError = "No jobs in Identified status to choose from"
            showSelectionReport = true
            isProcessing = false
            return
        }

        let systemPrompt = loadPromptTemplate(named: "discovery_choose_best_jobs")
        var userMessage = "Please select the top 5 jobs from the following opportunities.\n\n"
        userMessage += "## CANDIDATE KNOWLEDGE CARDS\n\(knowledgeContext)\n\n"
        userMessage += "## CANDIDATE DOSSIER\n\(dossierContext)\n\n"
        userMessage += "## JOB OPPORTUNITIES\n"
        for job in identifiedJobs {
            userMessage += """
            ---
            ID: \(job.id.uuidString)
            Company: \(job.companyName)
            Role: \(job.jobPosition)
            Description: \(job.jobDescription)

            """
        }

        do {
            // Start reasoning stream overlay
            reasoningStreamManager.startReasoning(modelName: modelId)

            // Stream via OpenRouter with reasoning
            let handle = try await llmFacade.startConversationStreaming(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                reasoning: .init(effort: "high"),
                backend: .openRouter
            )

            // Process stream: forward reasoning, collect response
            var fullResponse = ""
            for try await chunk in handle.stream {
                if let reasoningContent = chunk.allReasoningText {
                    reasoningStreamManager.appendReasoning(reasoningContent)
                }
                if let content = chunk.content {
                    fullResponse += content
                }
                if chunk.isFinished {
                    reasoningStreamManager.isStreaming = false
                    reasoningStreamManager.isVisible = false
                }
            }

            // Parse the JSON response
            let parser = DiscoveryResponseParser()
            let result = try parser.parseJobSelections(fullResponse)

            selectionResult = result
            showSelectionReport = true
            Logger.info("✅ Choose Best Jobs: selected \(result.selections.count) jobs", category: .ai)
        } catch {
            Logger.error("Choose Best Jobs Error: \(error)")
            reasoningStreamManager.showError(error.localizedDescription)
            selectionError = error.localizedDescription
            showSelectionReport = true
        }

        isProcessing = false
    }

    private func loadPromptTemplate(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(name)", category: .ai)
            return "Error loading prompt template"
        }
        return content
    }
}
