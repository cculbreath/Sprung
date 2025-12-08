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
actor GitIngestionKernel: ArtifactIngestionKernel {
    let kernelType: IngestionSource = .gitRepository

    private let eventBus: EventCoordinator
    private var llmFacade: LLMFacade?
    private weak var ingestionCoordinator: ArtifactIngestionCoordinator?

    /// Active ingestion tasks by pending ID
    private var activeTasks: [String: Task<Void, Never>] = [:]

    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
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
            startTime: Date(),
            status: .pending,
            statusMessage: "Analyzing repository..."
        )

        // Start async processing
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.analyzeRepository(
                pendingId: pendingId,
                repoURL: source,
                planItemId: planItemId
            )
        }
        activeTasks[pendingId] = task

        return pending
    }

    func completeIngestion(pendingId: String) async throws -> IngestionResult {
        throw NSError(domain: "GitIngestionKernel", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Git ingestion completes asynchronously via callback"
        ])
    }

    // MARK: - Private Analysis

    private func analyzeRepository(
        pendingId: String,
        repoURL: URL,
        planItemId: String?
    ) async {
        let repoPath = repoURL.path
        let repoName = repoURL.lastPathComponent

        do {
            await eventBus.publish(.extractionStateChanged(true, statusMessage: "Gathering repository data..."))

            // Step 1: Gather raw git data
            let gitData = try gatherGitData(repoPath: repoPath)

            await eventBus.publish(.extractionStateChanged(true, statusMessage: "Analyzing code patterns with multi-turn agent..."))

            // Step 2: Run multi-turn agent to analyze actual code
            let analysis = try await runAnalysisAgent(gitData: gitData, repoName: repoName, repoURL: repoURL)

            await eventBus.publish(.extractionStateChanged(true, statusMessage: "Creating artifact record..."))

            // Step 3: Create artifact record
            var record = JSON()
            record["id"].string = UUID().uuidString
            record["type"].string = "git_analysis"
            record["source"].string = "git_repository"
            record["filename"].string = repoName
            record["file_path"].string = repoPath
            record["created_at"].string = ISO8601DateFormatter().string(from: Date())
            if let planItemId = planItemId {
                record["plan_item_id"].string = planItemId
            }
            record["analysis"] = analysis
            record["raw_data"] = gitData

            // Set extracted_text from analysis summary for artifact display
            if let summary = analysis["summary"].string, !summary.isEmpty {
                record["extracted_text"].string = summary
            } else {
                // Fallback: build a summary from highlights and skills
                var summaryParts: [String] = []
                if let highlights = analysis["highlights"].array {
                    summaryParts.append(contentsOf: highlights.prefix(5).compactMap { $0.string })
                }
                if let skills = analysis["skills"].array {
                    let skillNames = skills.prefix(10).compactMap { $0["skill"].string }
                    if !skillNames.isEmpty {
                        summaryParts.append("Skills: " + skillNames.joined(separator: ", "))
                    }
                }
                record["extracted_text"].string = summaryParts.joined(separator: "\n\n")
            }

            let result = IngestionResult(
                artifactId: record["id"].stringValue,
                artifactRecord: record,
                source: .gitRepository
            )

            await ingestionCoordinator?.handleIngestionCompleted(pendingId: pendingId, result: result)
            // Note: DocumentArtifactMessenger.sendGitArtifact turns off the spinner after sending the developer message

            Logger.info("✅ Git repository analysis completed: \(repoName)", category: .ai)

        } catch {
            await ingestionCoordinator?.handleIngestionFailed(pendingId: pendingId, error: error.localizedDescription)
            Logger.error("❌ Git repository analysis failed: \(error.localizedDescription)", category: .ai)
        }

        activeTasks[pendingId] = nil
    }

    // MARK: - Git Data Gathering

    private func gatherGitData(repoPath: String) throws -> JSON {
        var data = JSON()

        // Get contributors
        let contributors = try runGitCommand(["shortlog", "-sne", "HEAD"], in: repoPath)
        data["contributors"] = parseContributors(contributors)

        // Get file types breakdown
        let files = try runGitCommand(["ls-files"], in: repoPath)
        data["file_types"] = parseFileTypes(files)

        // Get recent commits (last 50)
        let commits = try runGitCommand([
            "log", "--oneline", "-50", "--format=%h|%an|%s"
        ], in: repoPath)
        data["recent_commits"] = parseCommits(commits)

        // Get branch info
        let branches = try runGitCommand(["branch", "-a"], in: repoPath)
        data["branches"] = JSON(branches.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) })

        // Get repo stats
        let totalCommits = try runGitCommand(["rev-list", "--count", "HEAD"], in: repoPath)
        data["total_commits"].int = Int(totalCommits.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // Get first and last commit dates
        let firstCommit = try runGitCommand(["log", "--reverse", "--format=%ci", "-1"], in: repoPath)
        let lastCommit = try runGitCommand(["log", "--format=%ci", "-1"], in: repoPath)
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

    private func runGitCommand(_ args: [String], in directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - LLM Analysis Agent

    private func runAnalysisAgent(gitData: JSON, repoName: String, repoURL: URL) async throws -> JSON {
        guard let facade = llmFacade else {
            throw GitIngestionError.noLLMFacade
        }

        // Get model from settings (OpenRouter-style ID)
        let modelId = UserDefaults.standard.string(forKey: "onboardingGitIngestModelId") ?? "anthropic/claude-haiku-4.5"

        // Get optional author filter from git data
        let authorFilter: String? = gitData["contributors"].array?.first?["name"].string

        Logger.info("🤖 Starting multi-turn git analysis agent with model: \(modelId)", category: .ai)

        // Run the multi-turn analysis agent
        let analysisResult = try await runGitAnalysisAgent(
            facade: facade,
            repoPath: repoURL,
            authorFilter: authorFilter,
            modelId: modelId,
            eventBus: eventBus
        )

        // Convert GitAnalysisResult to JSON using Codable (CodingKeys handle snake_case)
        var result: JSON
        do {
            let data = try JSONEncoder().encode(analysisResult)
            result = try JSON(data: data)
        } catch {
            Logger.error("Failed to encode GitAnalysisResult: \(error)", category: .ai)
            result = JSON()
        }

        // Merge in the original git metadata
        result["git_metadata"] = gitData

        Logger.info("✅ Multi-turn git analysis agent completed", category: .ai)
        return result
    }

    // MARK: - Multi-Turn Agent Execution

    @MainActor
    private func runGitAnalysisAgent(
        facade: LLMFacade,
        repoPath: URL,
        authorFilter: String?,
        modelId: String,
        eventBus: EventCoordinator
    ) async throws -> GitAnalysisResult {
        let agent = GitAnalysisAgent(
            repoPath: repoPath,
            authorFilter: authorFilter,
            modelId: modelId,
            facade: facade,
            eventBus: eventBus
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
