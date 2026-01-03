//
//  GitIngestionKernel.swift
//  Sprung
//
//  Kernel for git repository analysis using a multi-turn LLM agent.
//  Uses the GitAnalysisAgent to explore codebases and extract skills with evidence.
//  Leverages LLMFacade (OpenRouter) for model flexibility.
//
import Foundation
import SwiftyJSON

/// Git repository ingestion kernel using async LLM agent via OpenRouter
actor GitIngestionKernel {

    private let eventBus: EventCoordinator
    private var llmFacade: LLMFacade?
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

        // Verify it's a git repo
        let gitDir = source.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            throw GitIngestionError.notAGitRepository(source.path)
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
            Logger.info("🔬 [GitIngest] About to call gatherGitData for: \(repoPath)", category: .ai)
            let gitData = try await gatherGitData(repoPath: repoPath)
            let contributorCount = gitData["contributors"].arrayValue.count
            Logger.info("🔬 [GitIngest] gatherGitData completed, contributors: \(contributorCount)", category: .ai)
            await appendTranscript(.system, "Gathered repository metadata", details: "\(contributorCount) contributor(s) found")

            // Note: extractionStateChanged not emitted - agent tracker handles status
            await appendTranscript(.system, "Starting multi-turn code analysis agent")
            Logger.info("🔬 [GitIngest] About to call runAnalysisAgent (requires @MainActor hop)", category: .ai)

            // Step 2: Run multi-turn agent to analyze actual code
            let analysis = try await runAnalysisAgent(gitData: gitData, repoName: repoName, repoURL: repoURL, agentId: agentId, tracker: tracker)

            // Note: extractionStateChanged not emitted - agent tracker handles status

            // Step 3: Create artifact record
            // Encode skills and narrative cards separately
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601

            let skillsData = try encoder.encode(analysis.skills)
            let skillsString = String(data: skillsData, encoding: .utf8) ?? "[]"

            let narrativeCardsData = try encoder.encode(analysis.narrativeCards)
            let narrativeCardsString = String(data: narrativeCardsData, encoding: .utf8) ?? "[]"

            var record = JSON()
            record["id"].string = UUID().uuidString
            record["type"].string = "git_analysis"
            record["source_type"].string = "git_repository"
            record["filename"].string = repoName
            record["file_path"].string = repoPath
            record["created_at"].string = ISO8601DateFormatter().string(from: Date())
            if let planItemId = planItemId {
                record["plan_item_id"].string = planItemId
            }

            // Store skills and narrative cards as JSON strings
            record["skills"].string = skillsString
            record["narrative_cards"].string = narrativeCardsString
            record["raw_data"] = gitData

            // Store git metadata for SwiftData persistence
            var metadata = JSON()
            metadata["git_metadata"] = gitData
            record["metadata"] = metadata

            // Build extracted_text for display
            var extractedParts: [String] = []
            extractedParts.append("## Repository: \(repoName)")

            // Find project cards for description
            let projectCards = analysis.narrativeCards.filter { $0.cardType == .project }
            if let mainProject = projectCards.first {
                if !mainProject.narrative.isEmpty {
                    extractedParts.append(mainProject.narrative)
                }
            }

            // Add key technologies from skills
            if !analysis.skills.isEmpty {
                let skillNames = analysis.skills.prefix(15).map { $0.canonical }
                extractedParts.append("\n## Key Technologies\n" + skillNames.joined(separator: ", "))
            }

            // Add achievements
            let achievementCards = analysis.narrativeCards.filter { $0.cardType == .achievement }
            if !achievementCards.isEmpty {
                let bullets = achievementCards.prefix(5).map { "• \($0.title)" }
                extractedParts.append("\n## Notable Achievements\n" + bullets.joined(separator: "\n"))
            }

            record["extracted_text"].string = extractedParts.joined(separator: "\n")
            Logger.info("✅ Git knowledge extraction: \(analysis.skills.count) skills, \(analysis.narrativeCards.count) narrative cards", category: .ai)

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

    // MARK: - Git Data Gathering

    private func gatherGitData(repoPath: String) async throws -> JSON {
        var data = JSON()

        // Get contributors
        let contributors = try await runGitCommand(["shortlog", "-sne", "HEAD"], in: repoPath)
        data["contributors"] = parseContributors(contributors)

        // Get file types breakdown
        let files = try await runGitCommand(["ls-files"], in: repoPath)
        data["file_types"] = parseFileTypes(files)

        // Get recent commits (last 50)
        let commits = try await runGitCommand([
            "log", "--oneline", "-50", "--format=%h|%an|%s"
        ], in: repoPath)
        data["recent_commits"] = parseCommits(commits)

        // Get branch info
        let branches = try await runGitCommand(["branch", "-a"], in: repoPath)
        data["branches"] = JSON(branches.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) })

        // Get repo stats
        let totalCommits = try await runGitCommand(["rev-list", "--count", "HEAD"], in: repoPath)
        data["total_commits"].int = Int(totalCommits.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // Get first and last commit dates
        let firstCommit = try await runGitCommand(["log", "--reverse", "--format=%ci", "-1"], in: repoPath)
        let lastCommit = try await runGitCommand(["log", "--format=%ci", "-1"], in: repoPath)
        data["first_commit"].string = firstCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        data["last_commit"].string = lastCommit.trimmingCharacters(in: .whitespacesAndNewlines)

        return data
    }

    private func parseContributors(_ output: String) -> JSON {
        var contributors: [[String: Any]] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 {
                let commits = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
                let authorPart = String(parts[1])
                var name = authorPart
                var email = ""
                if let emailStart = authorPart.firstIndex(of: "<"),
                   let emailEnd = authorPart.firstIndex(of: ">") {
                    name = String(authorPart[..<emailStart]).trimmingCharacters(in: .whitespaces)
                    email = String(authorPart[authorPart.index(after: emailStart)..<emailEnd])
                }
                contributors.append([
                    "name": name,
                    "email": email,
                    "commits": commits
                ])
            }
        }
        return JSON(contributors)
    }

    private func parseFileTypes(_ output: String) -> JSON {
        var extensionCounts: [String: Int] = [:]
        for line in output.split(separator: "\n") {
            let ext = (String(line) as NSString).pathExtension.lowercased()
            if !ext.isEmpty {
                extensionCounts[ext, default: 0] += 1
            }
        }
        let sorted = extensionCounts.sorted { $0.value > $1.value }.prefix(20)
        return JSON(sorted.map { ["extension": $0.key, "count": $0.value] })
    }

    private func parseCommits(_ output: String) -> JSON {
        var commits: [[String: String]] = []
        for line in output.split(separator: "\n") {
            let parts = String(line).split(separator: "|", maxSplits: 2)
            if parts.count == 3 {
                commits.append([
                    "hash": String(parts[0]),
                    "author": String(parts[1]),
                    "message": String(parts[2])
                ])
            }
        }
        return JSON(commits)
    }

    private func runGitCommand(_ args: [String], in directory: String) async throws -> String {
        // Run process in detached task to avoid blocking the actor
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + args
            process.currentDirectoryURL = URL(fileURLWithPath: directory)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            // IMPORTANT: Read output BEFORE waitUntilExit to avoid deadlock
            // If we wait first, the pipe buffer can fill up and block the process
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }

    // MARK: - LLM Analysis Agent

    private func runAnalysisAgent(gitData _: JSON, repoName _: String, repoURL: URL, agentId: String, tracker: AgentActivityTracker?) async throws -> GitAnalysisResult {
        Logger.info("🔬 [GitIngest] runAnalysisAgent entered, checking llmFacade...", category: .ai)
        guard let facade = llmFacade else {
            Logger.error("🔬 [GitIngest] llmFacade is nil!", category: .ai)
            throw GitIngestionError.noLLMFacade
        }
        Logger.info("🔬 [GitIngest] llmFacade exists, getting model ID...", category: .ai)

        // Get model from settings (OpenRouter-style ID)
        let modelId = UserDefaults.standard.string(forKey: "onboardingGitIngestModelId") ?? DefaultModels.openRouter
        Logger.info("🔬 [GitIngest] Using model: \(modelId)", category: .ai)

        // Note: Author filtering removed - this app analyzes the user's own repositories,
        // so there's no need to filter by a specific contributor. The agent will analyze
        // the entire codebase to extract the user's skills and contributions.
        let authorFilter: String? = nil

        Logger.info("🤖 Starting multi-turn git analysis agent with model: \(modelId)", category: .ai)

        // Run the multi-turn analysis agent - returns DocumentInventory directly
        let analysisResult = try await runGitAnalysisAgent(
            facade: facade,
            repoPath: repoURL,
            authorFilter: authorFilter,
            modelId: modelId,
            eventBus: eventBus,
            agentId: agentId,
            tracker: tracker
        )

        Logger.info("✅ Multi-turn git analysis agent completed", category: .ai)
        return analysisResult
    }

    // MARK: - Multi-Turn Agent Execution

    @MainActor
    private func runGitAnalysisAgent(
        facade: LLMFacade,
        repoPath: URL,
        authorFilter: String?,
        modelId: String,
        eventBus: EventCoordinator,
        agentId: String,
        tracker: AgentActivityTracker?
    ) async throws -> GitAnalysisResult {
        let agent = GitAnalysisAgent(
            repoPath: repoPath,
            authorFilter: authorFilter,
            modelId: modelId,
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
    case notAGitRepository(String)
    case noLLMFacade
    case analysisEmpty
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .notAGitRepository(let path):
            return "The selected directory is not a git repository: \(path)"
        case .noLLMFacade:
            return "LLM service is not configured. Please check your API settings."
        case .analysisEmpty:
            return "Git analysis returned no content"
        case .invalidOutput:
            return "Git analysis output was not valid"
        }
    }
}
