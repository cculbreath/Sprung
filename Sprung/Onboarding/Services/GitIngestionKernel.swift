//
//  GitIngestionKernel.swift
//  Sprung
//
//  Kernel for git repository analysis using an async LLM agent.
//  Analyzes commit history, code patterns, and contributions to extract skills.
//  Uses LLMFacade (OpenRouter) for model flexibility.
//
import Foundation
import SwiftyJSON

/// Response structure for git analysis LLM call
struct GitAnalysisResponse: Codable, Sendable {
    struct LanguageInfo: Codable, Sendable {
        let name: String
        let proficiencyIndicator: String?
        let fileCount: Int?

        enum CodingKeys: String, CodingKey {
            case name
            case proficiencyIndicator = "proficiency_indicator"
            case fileCount = "file_count"
        }
    }

    struct DevelopmentPatterns: Codable, Sendable {
        let commitFrequency: String?
        let collaborationStyle: String?
        let branchStrategy: String?

        enum CodingKeys: String, CodingKey {
            case commitFrequency = "commit_frequency"
            case collaborationStyle = "collaboration_style"
            case branchStrategy = "branch_strategy"
        }
    }

    let languages: [LanguageInfo]?
    let technologies: [String]?
    let skills: [String]?
    let developmentPatterns: DevelopmentPatterns?
    let highlights: [String]?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case languages, technologies, skills, highlights, summary
        case developmentPatterns = "development_patterns"
    }
}

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
            await eventBus.publish(.processingStateChanged(true, statusMessage: "Gathering repository data..."))

            // Step 1: Gather raw git data
            let gitData = try gatherGitData(repoPath: repoPath)

            await eventBus.publish(.processingStateChanged(true, statusMessage: "Analyzing code patterns..."))

            // Step 2: Send to LLM agent for analysis
            let analysis = try await runAnalysisAgent(gitData: gitData, repoName: repoName)

            await eventBus.publish(.processingStateChanged(true, statusMessage: "Creating artifact record..."))

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

            let result = IngestionResult(
                artifactId: record["id"].stringValue,
                artifactRecord: record,
                source: .gitRepository
            )

            await ingestionCoordinator?.handleIngestionCompleted(pendingId: pendingId, result: result)
            await eventBus.publish(.processingStateChanged(false))

            Logger.info("✅ Git repository analysis completed: \(repoName)", category: .ai)

        } catch {
            await ingestionCoordinator?.handleIngestionFailed(pendingId: pendingId, error: error.localizedDescription)
            await eventBus.publish(.processingStateChanged(false))
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

    private func runAnalysisAgent(gitData: JSON, repoName: String) async throws -> JSON {
        guard let facade = llmFacade else {
            throw GitIngestionError.noLLMFacade
        }

        // Get model from settings (OpenRouter-style ID, e.g., "openai/gpt-4o-mini")
        let modelId = UserDefaults.standard.string(forKey: "onboardingGitIngestModelId") ?? "openai/gpt-4o-mini"

        let prompt = """
        You are a technical skills analyst. Analyze the following git repository data to identify:
        1. Programming languages and technologies used (based on file extensions)
        2. Development patterns (commit frequency, collaboration style)
        3. Areas of expertise demonstrated by the code
        4. Notable contributions and their impact

        Repository: \(repoName)

        Repository Data:
        \(gitData.rawString(.utf8, options: [.prettyPrinted]) ?? gitData.description)

        Output a JSON object with these keys:
        - languages: array of {name, proficiency_indicator, file_count}
        - technologies: array of inferred technologies/frameworks
        - skills: array of technical skills demonstrated
        - development_patterns: object with commit_frequency, collaboration_style, branch_strategy
        - highlights: array of notable findings for resume/portfolio
        - summary: 2-3 sentence overview of the developer's work

        Be specific and evidence-based. Only include skills clearly demonstrated by the data.
        Return ONLY valid JSON, no markdown formatting or code blocks.
        """

        Logger.info("🔬 Starting git analysis with model: \(modelId)", category: .ai)

        do {
            // Use LLMFacade for the OpenRouter call (MainActor-isolated)
            let response: GitAnalysisResponse = try await callFacadeFlexibleJSON(
                facade: facade,
                prompt: prompt,
                modelId: modelId
            )

            // Convert response to JSON
            var result = JSON()
            if let languages = response.languages {
                result["languages"] = JSON(languages.map { lang in
                    var obj: [String: Any] = ["name": lang.name]
                    if let prof = lang.proficiencyIndicator { obj["proficiency_indicator"] = prof }
                    if let count = lang.fileCount { obj["file_count"] = count }
                    return obj
                })
            }
            if let techs = response.technologies {
                result["technologies"] = JSON(techs)
            }
            if let skills = response.skills {
                result["skills"] = JSON(skills)
            }
            if let patterns = response.developmentPatterns {
                var patternsObj: [String: String] = [:]
                if let freq = patterns.commitFrequency { patternsObj["commit_frequency"] = freq }
                if let collab = patterns.collaborationStyle { patternsObj["collaboration_style"] = collab }
                if let branch = patterns.branchStrategy { patternsObj["branch_strategy"] = branch }
                result["development_patterns"] = JSON(patternsObj)
            }
            if let highlights = response.highlights {
                result["highlights"] = JSON(highlights)
            }
            if let summary = response.summary {
                result["summary"].string = summary
            }

            Logger.info("✅ Git analysis LLM call completed", category: .ai)
            return result

        } catch {
            Logger.error("❌ Git analysis LLM call failed: \(error.localizedDescription)", category: .ai)

            // Try a simpler text-based fallback
            do {
                let textResponse = try await callFacadeText(
                    facade: facade,
                    prompt: prompt,
                    modelId: modelId
                )

                // Attempt to parse as JSON
                if let data = textResponse.data(using: .utf8) {
                    return try JSON(data: data)
                }
            } catch {
                Logger.error("❌ Git analysis text fallback also failed: \(error.localizedDescription)", category: .ai)
            }

            throw GitIngestionError.analysisEmpty
        }
    }

    // MARK: - MainActor Bridge Methods

    @MainActor
    private func callFacadeFlexibleJSON(
        facade: LLMFacade,
        prompt: String,
        modelId: String
    ) async throws -> GitAnalysisResponse {
        try await facade.executeFlexibleJSON(
            prompt: prompt,
            modelId: modelId,
            as: GitAnalysisResponse.self,
            temperature: 0.3
        )
    }

    @MainActor
    private func callFacadeText(
        facade: LLMFacade,
        prompt: String,
        modelId: String
    ) async throws -> String {
        try await facade.executeText(
            prompt: prompt,
            modelId: modelId,
            temperature: 0.3
        )
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
