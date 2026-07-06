//
//  ChooseBestJobsFlow.swift
//  Sprung
//
//  Shared "Choose Best Jobs" flow: runs the single job-triage implementation
//  (DiscoveryAgentService.chooseBestJobs, on the user-selected Discovery
//  Anthropic model) over the Identified column, then presents the report/error
//  sheet. Attached by both entry points (the main-window BestJobButton toolbar
//  item and the pipeline kanban header) so the report always appears in the
//  window that asked for it.
//

import SwiftUI

/// View modifier owning the Choose Best Jobs run: kicks off the selection when
/// `isActive` flips true and presents the resulting report locally on whatever
/// view it is attached to.
struct ChooseBestJobsFlow: ViewModifier {
    /// Everything the run and its sheets need. Passed explicitly (rather than
    /// read from `@Environment`) because the flow can be hosted in windows
    /// whose environments differ — the Discovery window, for example, does not
    /// carry `JobAppStore`.
    struct Dependencies {
        let jobAppStore: JobAppStore
        let knowledgeCardStore: KnowledgeCardStore
        let candidateDossierStore: CandidateDossierStore
        let coverRefStore: CoverRefStore
        /// Discovery coordinator hosting the agent service that runs the
        /// selection. The model comes from the Discovery Anthropic model
        /// setting — there is no per-run picker.
        let coordinator: DiscoveryCoordinator
    }

    /// Set true by the attaching view to start a run; reset immediately.
    @Binding var isActive: Bool
    /// Mirrors the run state so the attaching view can style/disable its trigger.
    @Binding var isProcessing: Bool
    let dependencies: Dependencies

    @State private var selectionResult: JobSelectionsResult?
    @State private var selectionError: String?
    @State private var errorNeedsModelSettings = false
    @State private var showSelectionReport = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive) { _, active in
                guard active else { return }
                isActive = false
                guard !isProcessing else { return }
                isProcessing = true
                Task { await chooseBestJobs() }
            }
            .sheet(isPresented: $showSelectionReport) {
                if let result = selectionResult {
                    SelectionReportSheet(result: result)
                        .environment(dependencies.jobAppStore)
                } else if let error = selectionError {
                    SelectionErrorSheet(
                        error: error,
                        needsModelSettings: errorNeedsModelSettings
                    )
                }
            }
    }

    @MainActor
    private func chooseBestJobs() async {
        selectionResult = nil
        selectionError = nil
        errorNeedsModelSettings = false
        defer { isProcessing = false }

        let identifiedJobs = dependencies.jobAppStore.jobApps(forStatus: .new)
        guard !identifiedJobs.isEmpty else {
            presentError("No jobs in Identified status to choose from")
            return
        }

        guard let agent = dependencies.coordinator.agentService else {
            presentError("The Discovery agent service isn't configured yet. Try again in a moment.")
            return
        }

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

        do {
            let result = try await agent.chooseBestJobs(
                jobs: identifiedJobs.map {
                    (id: $0.id, company: $0.companyName, role: $0.jobPosition, description: $0.jobDescription)
                },
                knowledgeContext: knowledgeContext,
                dossierContext: dossierContext
            )
            selectionResult = result
            showSelectionReport = true
            Logger.info("✅ Choose Best Jobs: selected \(result.selections.count) jobs", category: .ai)
        } catch let error as ModelConfigurationError {
            // Missing Discovery model configuration: route the user to the
            // model settings picker instead of failing with a bare message.
            Logger.error("Choose Best Jobs: \(error.localizedDescription)")
            var message = error.localizedDescription
            if let suggestion = error.recoverySuggestion {
                message += "\n\n\(suggestion)"
            }
            presentError(message, needsModelSettings: true)
        } catch {
            Logger.error("Choose Best Jobs Error: \(error)")
            presentError(error.localizedDescription)
        }
    }

    @MainActor
    private func presentError(_ message: String, needsModelSettings: Bool = false) {
        selectionError = message
        errorNeedsModelSettings = needsModelSettings
        showSelectionReport = true
    }
}

extension View {
    /// Attaches the Choose Best Jobs flow (run on activation → local report).
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
    /// True when the failure is a missing/unavailable model configuration —
    /// adds a direct route to the model settings picker.
    var needsModelSettings: Bool = false
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

            HStack(spacing: 12) {
                if needsModelSettings {
                    Button("Open Model Settings") {
                        NotificationCenter.default.post(name: .showSettings, object: nil)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Dismiss") { dismiss() }
                    .keyboardShortcut(needsModelSettings ? .cancelAction : .defaultAction)
            }
        }
        .padding(40)
        .frame(width: 400)
    }
}
