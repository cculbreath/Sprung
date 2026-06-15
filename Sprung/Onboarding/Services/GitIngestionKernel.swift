//
//  GitIngestionKernel.swift
//  Sprung
//
//  Kernel for git repository ingestion. A multi-turn `GitAnalysisAgent` explores
//  the codebase and produces a `RepositoryDigest` (the artifact's intermediate
//  representation). Skills and narrative cards are then derived by running the
//  SHARED text-extraction path (`AnthropicDocumentAnalysisService.analyzeText`)
//  over `digest.renderedForExtraction()` — exactly like a transcribed document.
//  Git and PDF share ONE extraction path.
//  Runs on the Anthropic Messages API via LLMFacade.
//
import Foundation
import SwiftyJSON

/// Git repository ingestion kernel using an async LLM agent on the Anthropic Messages API
actor GitIngestionKernel {

    private let eventBus: EventCoordinator
    private var llmFacade: LLMFacade?
    /// Shared document-analysis service: derives skills/cards from the rendered
    /// digest via the SAME path PDFs take. Injected at container wiring.
    private var documentAnalysisService: AnthropicDocumentAnalysisService?
    private weak var ingestionCoordinator: ArtifactIngestionCoordinator?

    /// Agent activity tracker for UI visibility
    private weak var agentActivityTracker: AgentActivityTracker?

    /// Active ingestion tasks by pending ID
    private var activeTasks: [String: Task<Void, Never>] = [:]

    /// Mapping from pending ID to agent tracker ID
    private var agentIds: [String: String] = [:]

    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
    }

    /// Set the agent activity tracker for monitoring
    func setAgentActivityTracker(_ tracker: AgentActivityTracker) {
        self.agentActivityTracker = tracker
    }

    /// Update the LLM facade (called when dependencies change)
    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    /// Inject the shared document-analysis service used to derive skills/cards
    /// from the rendered digest (the same path PDF extraction takes).
    func updateDocumentAnalysisService(_ service: AnthropicDocumentAnalysisService?) {
        self.documentAnalysisService = service
    }

    func setIngestionCoordinator(_ coordinator: ArtifactIngestionCoordinator) {
        self.ingestionCoordinator = coordinator
    }

    func startIngestion(
        source: URL,
        planItemId: String?,
        metadata: JSON
    ) async throws -> PendingArtifact {
        let pendingId = UUID().uuidString
        let repoName = source.lastPathComponent

        // Any readable directory ingests as a codebase. Git history is the
        // preferred evidence but optional — GitEvidenceCollector falls back to
        // a filesystem scan when history is missing or corrupt.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitIngestionError.notADirectory(source.path)
        }

        let pending = PendingArtifact(
            id: pendingId,
            source: .gitRepository,
            filename: repoName,
            planItemId: planItemId,
            status: .pending
        )

        // Register with agent activity tracker for UI visibility
        let agentId = UUID().uuidString
        agentIds[pendingId] = agentId

        // Start async processing
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.analyzeRepository(
                pendingId: pendingId,
                agentId: agentId,
                repoURL: source,
                repoName: repoName,
                planItemId: planItemId
            )
        }
        activeTasks[pendingId] = task

        // Register agent after creating task (so we can associate the task with it)
        if let tracker = agentActivityTracker {
            _ = await MainActor.run {
                tracker.trackAgent(
                    id: agentId,
                    type: .gitIngestion,
                    name: "Git: \(repoName)",
                    task: task
                )
            }
        }

        return pending
    }

    // MARK: - Private Analysis

    private func analyzeRepository(
        pendingId: String,
        agentId: String,
        repoURL: URL,
        repoName: String,
        planItemId: String?
    ) async {
        Logger.info("🔬 [GitIngest] analyzeRepository Task started for: \(repoName)", category: .ai)
        let repoPath = repoURL.path

        // Capture tracker locally for sendable closure access
        let tracker = agentActivityTracker

        // Helper to append transcript entries
        @Sendable func appendTranscript(_ type: AgentTranscriptEntry.EntryType, _ content: String, details: String? = nil) async {
            if let tracker = tracker {
                await MainActor.run {
                    tracker.appendTranscript(agentId: agentId, entryType: type, content: content, details: details)
                }
            }
        }

        do {
            // Note: We don't emit extractionStateChanged here - the agent tracker handles status display
            // to avoid duplicate status messages in BackgroundAgentStatusBar
            await appendTranscript(.system, "Starting repository analysis", details: repoPath)

            // Step 1: Gather raw git data
            Logger.info("🔬 [GitIngest] About to gather git evidence for: \(repoPath)", category: .ai)
            let gitData = try await GitEvidenceCollector.gather(repoPath: repoPath)
            let contributorCount = gitData["contributors"].arrayValue.count
            Logger.info("🔬 [GitIngest] Git evidence gathering completed, contributors: \(contributorCount)", category: .ai)
            await appendTranscript(.system, "Gathered repository metadata", details: "\(contributorCount) contributor(s) found")

            // Note: extractionStateChanged not emitted - agent tracker handles status
            await appendTranscript(.system, "Starting multi-turn code analysis agent")
            Logger.info("🔬 [GitIngest] About to call runAnalysisAgent (requires @MainActor hop)", category: .ai)

            // Step 2: Run the multi-turn agent to produce the repository digest (IR)
            let digest = try await runAnalysisAgent(gitData: gitData, repoName: repoName, repoURL: repoURL, agentId: agentId, tracker: tracker)

            // Step 3: Derive skills + narrative cards via the SHARED text-extraction
            // path over the rendered digest — the same passes a transcribed PDF runs.
            await appendTranscript(.system, "Extracting skills and cards from digest")
            let artifactId = UUID().uuidString
            let analysis = try await deriveKnowledge(digest: digest, documentId: artifactId, repoName: repoName)
            let skills = analysis.skills ?? []
            let narrativeCards = analysis.narrativeCards ?? []
            if !analysis.passFailures.isEmpty {
                Logger.warning(
                    "⚠️ Git digest extraction had \(analysis.passFailures.count) pass failure(s): \(analysis.passFailures.joined(separator: " | "))",
                    category: .ai
                )
            }

            // Step 4: Create artifact record
            // Note: Skill/KnowledgeCard models have explicit CodingKeys for snake_case - no conversion needed
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let skillsData = try encoder.encode(skills)
            let skillsString = String(data: skillsData, encoding: .utf8) ?? "[]"

            let narrativeCardsData = try encoder.encode(narrativeCards)
            let narrativeCardsString = String(data: narrativeCardsData, encoding: .utf8) ?? "[]"

            // Encode the digest as the artifact's intermediate representation so
            // extraction can be re-run later without re-running the live agent.
            // Routed through the IR codec (single source of truth for date strategy).
            let ir = IntermediateRepresentation.git(digest)
            let irString = try ir.encodedJSONString()

            var record = JSON()
            record["id"].string = artifactId
            record["type"].string = "git_analysis"
            record["sourceType"].string = "git_repository"
            record["filename"].string = repoName
            record["filePath"].string = repoPath
            record["createdAt"].string = ISO8601DateFormatter().string(from: Date())
            if let planItemId = planItemId {
                record["planItemId"].string = planItemId
            }

            // Store skills, narrative cards, and the intermediate representation
            record["skills"].string = skillsString
            record["narrativeCards"].string = narrativeCardsString
            record["intermediateRepresentation"].string = irString
            record["rawData"] = gitData

            // Surface the shared-path summary (the summary pass runs first to warm
            // the cache; reuse its output rather than discarding it).
            if let summary = analysis.summary {
                record["summary"].string = summary.summary
                record["briefDescription"].string = summary.briefDescription
            }

            // Store git metadata for SwiftData persistence
            var metadata = JSON()
            metadata["gitMetadata"] = gitData
            record["metadata"] = metadata

            // Build extractedText for display from the digest + derived skills.
            var extractedParts: [String] = []
            extractedParts.append(ir.fullText)
            if !skills.isEmpty {
                let skillNames = skills.prefix(15).map { $0.canonical }
                extractedParts.append("\n## Key Technologies\n" + skillNames.joined(separator: ", "))
            }
            record["extractedText"].string = extractedParts
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            Logger.info("✅ Git knowledge extraction: \(skills.count) skills, \(narrativeCards.count) narrative cards", category: .ai)

            let result = IngestionResult(artifactRecord: record)

            await ingestionCoordinator?.handleIngestionCompleted(pendingId: pendingId, result: result)
            // Note: DocumentArtifactMessenger.sendGitArtifact turns off the spinner after sending the developer message

            // Mark agent as completed in tracker
            await appendTranscript(.assistant, "Analysis complete", details: "Artifact created: \(record["id"].stringValue)")
            if let tracker = tracker {
                await MainActor.run {
                    tracker.markCompleted(agentId: agentId)
                }
            }

            Logger.info("✅ Git repository analysis completed: \(repoName)", category: .ai)

        } catch {
            await ingestionCoordinator?.handleIngestionFailed(pendingId: pendingId, error: error.localizedDescription)

            // Mark agent as failed in tracker
            if let tracker = tracker {
                await MainActor.run {
                    tracker.markFailed(agentId: agentId, error: error.localizedDescription)
                }
            }
            Logger.error("❌ Git repository analysis failed: \(error.localizedDescription)", category: .ai)
        }

        activeTasks[pendingId] = nil
        agentIds[pendingId] = nil
    }

    // MARK: - LLM Analysis Agent

    private func runAnalysisAgent(gitData: JSON, repoName _: String, repoURL: URL, agentId: String, tracker: AgentActivityTracker?) async throws -> RepositoryDigest {
        Logger.info("🔬 [GitIngest] runAnalysisAgent entered, checking llmFacade...", category: .ai)
        guard let facade = llmFacade else {
            Logger.error("🔬 [GitIngest] llmFacade is nil!", category: .ai)
            throw GitIngestionError.noLLMFacade
        }
        Logger.info("🔬 [GitIngest] llmFacade exists, getting model ID...", category: .ai)

        // Get model from settings (Anthropic model ID)
        let modelId = try ModelConfigResolver.resolve(key: "onboardingGitIngestModelId", operation: "Git Repository Analysis")
        Logger.info("🔬 [GitIngest] Using model: \(modelId)", category: .ai)

        // Note: Author filtering removed - this app analyzes the user's own repositories,
        // so there's no need to filter by a specific contributor. The agent will analyze
        // the entire codebase to extract the user's skills and contributions.
        let authorFilter: String? = nil

        Logger.info("🤖 Starting multi-turn git digest agent with model: \(modelId)", category: .ai)

        // Render the deterministic git evidence for the agent's initial context
        let gitEvidence = GitEvidenceCollector.render(gitData)

        // Run the multi-turn agent — returns a RepositoryDigest (the IR). The
        // model authors the analysis layers; the agent grafts on the mechanical
        // layers (file tree, language stats, git history, authorship) from gitData.
        let digest = try await runGitAnalysisAgent(
            facade: facade,
            repoPath: repoURL,
            authorFilter: authorFilter,
            modelId: modelId,
            gitEvidence: gitEvidence,
            gitData: gitData,
            eventBus: eventBus,
            agentId: agentId,
            tracker: tracker
        )

        Logger.info("✅ Multi-turn git digest agent completed", category: .ai)
        return digest
    }

    /// Derive skills + narrative cards from the rendered digest using the SHARED
    /// document-analysis path (the same passes a transcribed PDF runs). The
    /// digest is a pre-rendered, path/line/commit-anchored transcript.
    private func deriveKnowledge(
        digest: RepositoryDigest,
        documentId: String,
        repoName: String
    ) async throws -> AnthropicDocumentAnalysisService.AnalysisResult {
        guard let analysisService = documentAnalysisService else {
            Logger.error("🔬 [GitIngest] documentAnalysisService is nil — cannot derive knowledge", category: .ai)
            throw GitIngestionError.noLLMFacade
        }
        return try await analysisService.analyzeText(
            documentId: documentId,
            filename: repoName,
            text: digest.renderedForExtraction()
        )
    }

    // MARK: - Multi-Turn Agent Execution

    @MainActor
    private func runGitAnalysisAgent(
        facade: LLMFacade,
        repoPath: URL,
        authorFilter: String?,
        modelId: String,
        gitEvidence: String,
        gitData: JSON,
        eventBus: EventCoordinator,
        agentId: String,
        tracker: AgentActivityTracker?
    ) async throws -> RepositoryDigest {
        let agent = GitAnalysisAgent(
            repoPath: repoPath,
            authorFilter: authorFilter,
            modelId: modelId,
            gitEvidence: gitEvidence,
            gitData: gitData,
            facade: facade,
            eventBus: eventBus,
            agentId: agentId,
            tracker: tracker
        )
        return try await agent.run()
    }

    /// Cancel all active git analysis tasks
    func cancelAllTasks() async {
        Logger.info("🛑 GitIngestionKernel: Cancelling \(activeTasks.count) active task(s)", category: .ai)
        for (pendingId, task) in activeTasks {
            task.cancel()
            Logger.debug("Cancelled git analysis task: \(pendingId)", category: .ai)
        }
        activeTasks.removeAll()
    }
}

// MARK: - Errors

enum GitIngestionError: LocalizedError {
    case notADirectory(String)
    case noReadableFiles(String)
    case noLLMFacade
    case analysisEmpty
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .notADirectory(let path):
            return "The selected path is not a directory: \(path)"
        case .noReadableFiles(let path):
            return "The directory contains no readable source files — it may be an incomplete copy "
                + "(empty folder structure only). Check the directory contents, or point the scan at "
                + "an intact copy of the codebase: \(path)"
        case .noLLMFacade:
            return "LLM service is not configured. Please check your API settings."
        case .analysisEmpty:
            return "Git analysis returned no content"
        case .invalidOutput:
            return "Git analysis output was not valid"
        }
    }
}
