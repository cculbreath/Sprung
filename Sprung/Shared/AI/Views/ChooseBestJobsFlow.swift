//
//  ChooseBestJobsFlow.swift
//  Sprung
//
//  Shared "Choose Best Jobs" flow: model-picker sheet → OpenRouter streaming
//  selection over the Identified column → report/error sheet. Attached by both
//  entry points (the main-window BestJobButton toolbar item and the pipeline
//  kanban header) so the report always appears in the window that asked for it.
//

import SwiftUI

/// View modifier owning the Choose Best Jobs run: presents the model picker,
/// streams the selection via OpenRouter, and presents the resulting report
/// locally on whatever view it is attached to.
struct ChooseBestJobsFlow: ViewModifier {
    /// Everything the run and its sheets need. Passed explicitly (rather than
    /// read from `@Environment`) because the flow can be hosted in windows
    /// whose environments differ — the Discovery window, for example, does not
    /// carry `JobAppStore`/`EnabledLLMStore`/`OpenRouterService`.
    struct Dependencies {
        let jobAppStore: JobAppStore
        let knowledgeCardStore: KnowledgeCardStore
        let candidateDossierStore: CandidateDossierStore
        let coverRefStore: CoverRefStore
        let llmFacade: LLMFacade
        let openRouterService: OpenRouterService
        let enabledLLMStore: EnabledLLMStore
        /// Reasoning overlay state; optional because only the main window
        /// hosts the overlay and injects this into its environment.
        let reasoningStream: ReasoningStreamState?
    }

    /// Shows the model-picker sheet when set true.
    @Binding var isActive: Bool
    /// Mirrors the run state so the attaching view can style/disable its trigger.
    @Binding var isProcessing: Bool
    let dependencies: Dependencies

    @State private var selectionResult: JobSelectionsResult?
    @State private var selectionError: String?
    @State private var showSelectionReport = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isActive) {
                // DropdownModelPicker inside the sheet reads these from the
                // environment; inject explicitly so the flow also works in
                // windows that don't carry them (see Dependencies doc).
                ChooseBestJobsSheet(
                    isPresented: $isActive,
                    onModelSelected: { modelId in
                        isActive = false
                        isProcessing = true
                        Task { await chooseBestJobs(modelId: modelId) }
                    }
                )
                .environment(dependencies.openRouterService)
                .environment(dependencies.enabledLLMStore)
            }
            .sheet(isPresented: $showSelectionReport) {
                if let result = selectionResult {
                    SelectionReportSheet(result: result)
                        .environment(dependencies.jobAppStore)
                } else if let error = selectionError {
                    SelectionErrorSheet(error: error)
                }
            }
    }

    @MainActor
    private func chooseBestJobs(modelId: String) async {
        selectionError = nil

        // Build knowledge context from KnowledgeCards
        let knowledgeContext = dependencies.knowledgeCardStore.knowledgeCards
            .map { card in
                let typeLabel = "[\(card.cardType?.rawValue ?? "general")]"
                return "\(typeLabel) \(card.title):\n\(card.narrative)"
            }
            .joined(separator: "\n\n")

        // Build dossier context from CandidateDossier + writing samples
        var dossierParts: [String] = []
        if let dossier = dependencies.candidateDossierStore.dossier {
            dossierParts.append(dossier.exportForJobMatching())
        }
        let writingSamples = dependencies.coverRefStore.storedCoverRefs
            .filter { $0.type == .writingSample }
            .prefix(5)
            .map { "<writing_sample name=\"\($0.name)\">\n\($0.content.prefix(500))...\n</writing_sample>" }
            .joined(separator: "\n\n")
        if !writingSamples.isEmpty {
            dossierParts.append(writingSamples)
        }
        let dossierContext = dossierParts.joined(separator: "\n\n")

        // Build prompt (same as DiscoveryAgentService.chooseBestJobs)
        let identifiedJobs = dependencies.jobAppStore.jobApps(forStatus: .new)
        guard !identifiedJobs.isEmpty else {
            selectionError = "No jobs in Identified status to choose from"
            showSelectionReport = true
            isProcessing = false
            return
        }

        guard let systemPrompt = loadPromptTemplate(named: "discovery_choose_best_jobs") else {
            selectionError = "Couldn't load the job-matching prompt template. The app may need to be reinstalled."
            showSelectionReport = true
            isProcessing = false
            return
        }
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
            // Start reasoning stream overlay (hosted by the main window)
            dependencies.reasoningStream?.startReasoning(modelName: modelId)

            // Stream via OpenRouter with reasoning
            let handle = try await dependencies.llmFacade.startConversationStreaming(
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
                    dependencies.reasoningStream?.appendReasoning(reasoningContent)
                }
                if let content = chunk.content {
                    fullResponse += content
                }
                if chunk.isFinished {
                    dependencies.reasoningStream?.isStreaming = false
                    dependencies.reasoningStream?.isVisible = false
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
            dependencies.reasoningStream?.showError(error.localizedDescription)
            selectionError = error.localizedDescription
            showSelectionReport = true
        }

        isProcessing = false
    }

    private func loadPromptTemplate(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(name)", category: .ai)
            return nil
        }
        return content
    }
}

extension View {
    /// Attaches the Choose Best Jobs flow (model picker → run → local report).
    func chooseBestJobsFlow(
        isActive: Binding<Bool>,
        isProcessing: Binding<Bool>,
        dependencies: ChooseBestJobsFlow.Dependencies
    ) -> some View {
        modifier(ChooseBestJobsFlow(
            isActive: isActive,
            isProcessing: isProcessing,
            dependencies: dependencies
        ))
    }
}

// MARK: - Selection Report Sheet

struct SelectionReportSheet: View {
    let result: JobSelectionsResult
    @Environment(\.dismiss) private var dismiss
    @Environment(JobAppStore.self) private var jobAppStore

    @State private var checkedJobIds: Set<UUID> = []

    private var checkedCount: Int { checkedJobIds.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top \(result.selections.count) Job Matches")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Check jobs to advance to Queued stage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)

                    Button("Advance Selected (\(checkedCount))") {
                        advanceCheckedJobs()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(checkedJobIds.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Selections with checkboxes
                    ForEach(Array(result.selections.enumerated()), id: \.element.jobId) { index, selection in
                        HStack(alignment: .top, spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { checkedJobIds.contains(selection.jobId) },
                                set: { isOn in
                                    if isOn {
                                        checkedJobIds.insert(selection.jobId)
                                    } else {
                                        checkedJobIds.remove(selection.jobId)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .padding(.top, 16)

                            SelectionCard(selection: selection, rank: index + 1)
                        }
                    }

                    // Overall Analysis
                    if !result.overallAnalysis.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Analysis Summary")
                                .font(.headline)
                            Text(result.overallAnalysis)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Considerations
                    if !result.considerations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Things to Consider")
                                .font(.headline)
                            ForEach(result.considerations, id: \.self) { consideration in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "lightbulb")
                                        .foregroundStyle(.yellow)
                                    Text(consideration)
                                        .font(.body)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .frame(width: 620, height: 700)
        .onAppear {
            // All selections checked by default
            checkedJobIds = Set(result.selections.map(\.jobId))
        }
    }

    private func advanceCheckedJobs() {
        for selection in result.selections where checkedJobIds.contains(selection.jobId) {
            if let job = jobAppStore.jobApps(forStatus: .new).first(where: { $0.id == selection.jobId }) {
                jobAppStore.setStatus(job, to: .queued)
                Logger.info("📋 Advanced '\(job.jobPosition)' at \(job.companyName) to Queued", category: .ai)
            }
        }
    }
}

struct SelectionCard: View {
    let selection: JobSelection
    let rank: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Rank badge
            Text("#\(rank)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(rankColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 8) {
                // Company and role
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selection.company)
                            .font(.headline)
                        Text(selection.role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Match score
                    Text("\(Int(selection.matchScore * 100))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(scoreColor)
                }

                // Reasoning
                Text(selection.reasoning)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue
        }
    }

    private var scoreColor: Color {
        if selection.matchScore >= 0.9 { return .green }
        if selection.matchScore >= 0.7 { return .blue }
        return .orange
    }
}

struct SelectionErrorSheet: View {
    let error: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Selection Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Dismiss") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(width: 400)
    }
}
