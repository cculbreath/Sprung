//
//  StandaloneKCCoordinator.swift
//  Sprung
//
//  Orchestrates standalone knowledge card generation from documents/git repos.
//  This is an alternative to the onboarding interview workflow - users can
//  directly ingest documents and generate knowledge cards without going
//  through the full onboarding process.
//
//  Pipeline: Upload Sources → Extract → Metadata → KC Agent → Persist
//

import Foundation
import SwiftyJSON
import Observation

/// Coordinates standalone document ingestion and knowledge card generation.
/// This is an @Observable class for SwiftUI binding in the ingestion sheet.
@Observable
@MainActor
class StandaloneKCCoordinator {
    // MARK: - Status

    enum Status: Equatable {
        case idle
        case extracting(current: Int, total: Int, filename: String)
        case analyzingMetadata
        case generatingCard
        case completed
        case failed(String)

        var isProcessing: Bool {
            switch self {
            case .idle, .completed, .failed:
                return false
            case .extracting, .analyzingMetadata, .generatingCard:
                return true
            }
        }

        var displayText: String {
            switch self {
            case .idle:
                return "Ready"
            case .extracting(let current, let total, let filename):
                return "Extracting (\(current)/\(total)): \(filename)"
            case .analyzingMetadata:
                return "Analyzing document metadata..."
            case .generatingCard:
                return "Generating knowledge card..."
            case .completed:
                return "Knowledge card created!"
            case .failed(let error):
                return "Failed: \(error)"
            }
        }
    }

    // MARK: - Published State

    var status: Status = .idle
    var generatedCard: ResRef?
    var errorMessage: String?

    // MARK: - Dependencies

    private let repository = InMemoryArtifactRepository()
    private var extractionService: DocumentExtractionService?
    private var metadataService: MetadataExtractionService?
    private weak var llmFacade: LLMFacade?
    private weak var resRefStore: ResRefStore?
    /// Session store for persisting artifacts (optional - allows standalone use without persistence)
    private weak var sessionStore: OnboardingSessionStore?

    // MARK: - Configuration

    private let kcAgentModelId: String

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, resRefStore: ResRefStore?, sessionStore: OnboardingSessionStore? = nil) {
        self.llmFacade = llmFacade
        self.resRefStore = resRefStore
        self.sessionStore = sessionStore
        self.kcAgentModelId = UserDefaults.standard.string(forKey: "onboardingKCAgentModelId") ?? "anthropic/claude-haiku-4.5"

        // Initialize services
        self.extractionService = DocumentExtractionService(llmFacade: llmFacade, eventBus: nil)
        self.metadataService = MetadataExtractionService(llmFacade: llmFacade)
    }

    // MARK: - Public API

    /// Generate a knowledge card from the given source URLs.
    /// Sources can be document files (PDF, DOCX, TXT) or git repository folders.
    func generateCard(from sources: [URL]) async throws {
        guard !sources.isEmpty else {
            throw StandaloneKCError.noSources
        }

        guard llmFacade != nil else {
            throw StandaloneKCError.llmNotConfigured
        }

        status = .idle
        errorMessage = nil
        generatedCard = nil

        do {
            // Phase 1: Extract all sources
            let artifacts = try await extractAllSources(sources)

            guard !artifacts.isEmpty else {
                throw StandaloneKCError.noArtifactsExtracted
            }

            // Phase 2: Extract metadata
            status = .analyzingMetadata
            let metadata = try await extractMetadata(from: artifacts)

            // Phase 3: Generate KC via agent
            status = .generatingCard
            let generated = try await runKCAgent(artifacts: artifacts, metadata: metadata)

            // Phase 4: Persist to ResRef
            let resRef = createResRef(from: generated, metadata: metadata, artifacts: artifacts)
            resRefStore?.addResRef(resRef)

            self.generatedCard = resRef
            status = .completed

            Logger.info("✅ StandaloneKCCoordinator: Knowledge card created - \(resRef.name)", category: .ai)

        } catch {
            let message = error.localizedDescription
            status = .failed(message)
            errorMessage = message
            Logger.error("❌ StandaloneKCCoordinator: Failed - \(message)", category: .ai)
            throw error
        }
    }

    /// Reset the coordinator state for a new ingestion
    func reset() {
        status = .idle
        generatedCard = nil
        errorMessage = nil
        Task {
            await repository.reset()
        }
    }

    /// Load archived artifacts into the repository for KC generation.
    /// These artifacts have already been extracted and stored in SwiftData.
    /// Returns the JSON representations of the loaded artifacts.
    func loadArchivedArtifacts(_ artifactIds: Set<String>) async -> [JSON] {
        guard let store = sessionStore else { return [] }

        var loadedArtifacts: [JSON] = []

        for id in artifactIds {
            guard let record = store.findArtifactById(id) else {
                Logger.warning("⚠️ StandaloneKCCoordinator: Archived artifact not found: \(id)", category: .ai)
                continue
            }

            // Convert SwiftData record to JSON
            var artifactJSON = JSON()
            artifactJSON["id"].string = record.id.uuidString
            artifactJSON["filename"].string = record.sourceFilename
            artifactJSON["source_type"].string = record.sourceType
            artifactJSON["extracted_text"].string = record.extractedContent
            artifactJSON["sha256"].string = record.sourceHash

            // Parse metadata JSON
            if let metadataJSONString = record.metadataJSON,
               let data = metadataJSONString.data(using: .utf8),
               let metadata = try? JSON(data: data) {
                if let summary = metadata["summary"].string {
                    artifactJSON["summary"].string = summary
                }
                if let brief = metadata["brief_description"].string {
                    artifactJSON["brief_description"].string = brief
                }
                if let title = metadata["title"].string {
                    artifactJSON["metadata"]["title"].string = title
                }
            }

            // Add to in-memory repository for KC agent access
            await repository.addArtifactRecord(artifactJSON)
            loadedArtifacts.append(artifactJSON)

            Logger.debug("📦 StandaloneKCCoordinator: Loaded archived artifact: \(record.sourceFilename)", category: .ai)
        }

        return loadedArtifacts
    }

    /// Generate a knowledge card from URLs and/or pre-loaded archived artifacts.
    /// Call loadArchivedArtifacts first if you have archived artifact IDs to include.
    func generateCardWithExisting(from sources: [URL], existingArtifacts: [JSON]) async throws {
        guard !sources.isEmpty || !existingArtifacts.isEmpty else {
            throw StandaloneKCError.noSources
        }

        guard llmFacade != nil else {
            throw StandaloneKCError.llmNotConfigured
        }

        status = .idle
        errorMessage = nil
        generatedCard = nil

        do {
            // Phase 1: Extract new sources (if any)
            var allArtifacts = existingArtifacts

            if !sources.isEmpty {
                let newArtifacts = try await extractAllSources(sources)
                allArtifacts.append(contentsOf: newArtifacts)
            }

            guard !allArtifacts.isEmpty else {
                throw StandaloneKCError.noArtifactsExtracted
            }

            // Phase 2: Extract metadata
            status = .analyzingMetadata
            let metadata = try await extractMetadata(from: allArtifacts)

            // Phase 3: Generate KC via agent
            status = .generatingCard
            let generated = try await runKCAgent(artifacts: allArtifacts, metadata: metadata)

            // Phase 4: Persist to ResRef
            let resRef = createResRef(from: generated, metadata: metadata, artifacts: allArtifacts)
            resRefStore?.addResRef(resRef)

            self.generatedCard = resRef
            status = .completed

            Logger.info("✅ StandaloneKCCoordinator: Knowledge card created - \(resRef.name)", category: .ai)

        } catch {
            let message = error.localizedDescription
            status = .failed(message)
            errorMessage = message
            Logger.error("❌ StandaloneKCCoordinator: Failed - \(message)", category: .ai)
            throw error
        }
    }

    // MARK: - Private: Extraction Phase

    private func extractAllSources(_ sources: [URL]) async throws -> [JSON] {
        var artifacts: [JSON] = []
        let total = sources.count

        for (index, url) in sources.enumerated() {
            let filename = url.lastPathComponent
            status = .extracting(current: index + 1, total: total, filename: filename)

            do {
                if isGitRepository(url) {
                    let artifact = try await extractGitRepository(url)
                    artifacts.append(artifact)
                } else {
                    let artifact = try await extractDocument(url)
                    artifacts.append(artifact)
                }
            } catch {
                Logger.warning("⚠️ StandaloneKCCoordinator: Failed to extract \(filename): \(error.localizedDescription)", category: .ai)
                // Continue with other sources even if one fails
            }
        }

        return artifacts
    }

    private func isGitRepository(_ url: URL) -> Bool {
        let gitDir = url.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func extractDocument(_ url: URL) async throws -> JSON {
        guard let service = extractionService else {
            throw StandaloneKCError.extractionServiceNotAvailable
        }

        let request = DocumentExtractionService.ExtractionRequest(
            fileURL: url,
            purpose: "knowledge_card",
            returnTypes: ["text"],
            autoPersist: false,
            displayFilename: url.lastPathComponent
        )

        let result = try await service.extract(using: request)

        guard result.status == .ok || result.status == .partial,
              let artifact = result.artifact else {
            throw StandaloneKCError.extractionFailed("No content extracted from \(url.lastPathComponent)")
        }

        // Build artifact JSON for repository
        var artifactJSON = JSON()
        artifactJSON["id"].string = artifact.id
        artifactJSON["filename"].string = artifact.filename
        artifactJSON["content_type"].string = artifact.contentType
        artifactJSON["size_bytes"].int = artifact.sizeInBytes
        artifactJSON["sha256"].string = artifact.sha256
        artifactJSON["extracted_text"].string = artifact.extractedContent

        if let title = artifact.title {
            artifactJSON["metadata"]["title"].string = title
        }

        // Generate a summary for metadata extraction
        let summary = generateLocalSummary(from: artifact.extractedContent, filename: artifact.filename)
        artifactJSON["summary"].string = summary
        artifactJSON["brief_description"].string = String(artifact.extractedContent.prefix(200))

        // Store in repository for KC agent access
        await repository.addArtifactRecord(artifactJSON)

        // Also persist to SwiftData as standalone artifact (session = nil, immediately archived)
        persistArtifactToSwiftData(artifactJSON)

        return artifactJSON
    }

    private func extractGitRepository(_ url: URL) async throws -> JSON {
        // For git repos, we do a simpler analysis without the full GitIngestionKernel
        // to avoid heavy dependencies. We extract basic repo info and file structure.
        let repoName = url.lastPathComponent

        // Get basic git info
        let gitInfo = try await gatherGitInfo(url)

        var artifactJSON = JSON()
        artifactJSON["id"].string = UUID().uuidString
        artifactJSON["filename"].string = repoName
        artifactJSON["content_type"].string = "application/x-git"
        artifactJSON["source_type"].string = "git_repository"
        artifactJSON["extracted_text"].string = gitInfo.fullText
        artifactJSON["summary"].string = gitInfo.summary
        artifactJSON["brief_description"].string = "Git repository: \(repoName)"

        // Add summary metadata
        artifactJSON["summary_metadata"]["document_type"].string = "git_repository"
        artifactJSON["summary_metadata"]["technologies"].arrayObject = gitInfo.technologies

        // Store in repository for KC agent access
        await repository.addArtifactRecord(artifactJSON)

        // Also persist to SwiftData as standalone artifact (session = nil, immediately archived)
        persistArtifactToSwiftData(artifactJSON)

        return artifactJSON
    }

    private struct GitInfo {
        let summary: String
        let fullText: String
        let technologies: [String]
    }

    private func gatherGitInfo(_ repoURL: URL) async throws -> GitInfo {
        let repoPath = repoURL.path
        let repoName = repoURL.lastPathComponent

        // Run git commands to gather info
        let commitCount = try? await runGitCommand("git -C \"\(repoPath)\" rev-list --count HEAD")
        let firstCommitDate = try? await runGitCommand("git -C \"\(repoPath)\" log --reverse --format=%cd --date=short | head -1")
        let lastCommitDate = try? await runGitCommand("git -C \"\(repoPath)\" log -1 --format=%cd --date=short")

        // Get file types (extensions)
        let fileTypes = try? await runGitCommand("git -C \"\(repoPath)\" ls-files | sed 's/.*\\.//' | sort | uniq -c | sort -rn | head -10")

        // Get recent commits
        let recentCommits = try? await runGitCommand("git -C \"\(repoPath)\" log --oneline -20")

        // Detect technologies from file extensions
        var technologies: [String] = []
        if let types = fileTypes {
            if types.contains("swift") { technologies.append("Swift") }
            if types.contains("py") { technologies.append("Python") }
            if types.contains("js") || types.contains("ts") { technologies.append("JavaScript/TypeScript") }
            if types.contains("go") { technologies.append("Go") }
            if types.contains("rs") { technologies.append("Rust") }
            if types.contains("java") { technologies.append("Java") }
            if types.contains("kt") { technologies.append("Kotlin") }
        }

        let summary = """
        Repository: \(repoName)
        Commits: \(commitCount?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown")
        Period: \(firstCommitDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?") to \(lastCommitDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?")
        Technologies: \(technologies.joined(separator: ", "))
        """

        let fullText = """
        # Git Repository: \(repoName)

        ## Overview
        - Total commits: \(commitCount?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown")
        - First commit: \(firstCommitDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown")
        - Last commit: \(lastCommitDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown")
        - Primary technologies: \(technologies.joined(separator: ", "))

        ## File Type Distribution
        \(fileTypes ?? "Unable to determine")

        ## Recent Commits
        \(recentCommits ?? "Unable to retrieve")
        """

        return GitInfo(
            summary: summary,
            fullText: fullText,
            technologies: technologies
        )
    }

    private func runGitCommand(_ command: String) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func generateLocalSummary(from text: String, filename: String) -> String {
        // Generate a simple local summary without LLM
        // This is used for quick context; full extraction prompts are used for KC generation
        let wordCount = text.split(separator: " ").count
        let lineCount = text.split(separator: "\n").count

        let preview = String(text.prefix(500))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        Document: \(filename)
        Length: approximately \(wordCount) words, \(lineCount) lines

        Preview:
        \(preview)...
        """
    }

    // MARK: - Private: Metadata Extraction

    private func extractMetadata(from artifacts: [JSON]) async throws -> CardMetadata {
        guard let service = metadataService else {
            let filename = artifacts.first?["filename"].stringValue ?? "Document"
            return CardMetadata.defaults(fromFilename: filename)
        }

        return try await service.extract(from: artifacts)
    }

    // MARK: - Private: KC Agent Generation

    private func runKCAgent(artifacts: [JSON], metadata: CardMetadata) async throws -> GeneratedCard {
        guard let facade = llmFacade else {
            throw StandaloneKCError.llmNotConfigured
        }

        // Build CardProposal
        let artifactIds = artifacts.compactMap { $0["id"].string }
        let proposal = CardProposal(
            cardId: UUID().uuidString,
            cardType: metadata.cardType,
            title: metadata.title,
            timelineEntryId: nil,
            assignedArtifactIds: artifactIds,
            chatExcerpts: [],
            notes: nil
        )

        // Build prompts using reused KCAgentPrompts
        let systemPrompt = KCAgentPrompts.systemPrompt(
            cardType: metadata.cardType,
            title: metadata.title,
            candidateName: nil
        )

        // Build artifact summaries for the initial prompt
        let summaries = await repository.getArtifactSummaries()

        let initialPrompt = KCAgentPrompts.initialPrompt(
            proposal: proposal,
            allSummaries: summaries
        )

        // Create tool executor with our in-memory repository
        let toolExecutor = SubAgentToolExecutor(artifactRepository: repository)

        // Run agent
        let runner = AgentRunner.forKnowledgeCard(
            agentId: UUID().uuidString,
            cardTitle: metadata.title,
            systemPrompt: systemPrompt,
            initialPrompt: initialPrompt,
            modelId: kcAgentModelId,
            toolExecutor: toolExecutor,
            llmFacade: facade,
            eventBus: nil,
            tracker: nil
        )

        let output = try await runner.run()

        // Parse result
        guard let result = output.result?["result"] else {
            throw StandaloneKCError.agentNoResult
        }

        let generated = GeneratedCard.fromAgentOutput(result, cardId: proposal.cardId)

        // Validate
        if let error = generated.validationError(minProseChars: 500) {
            throw StandaloneKCError.agentInvalidOutput(error)
        }

        return generated
    }

    // MARK: - Private: Persistence

    private func createResRef(from card: GeneratedCard, metadata: CardMetadata, artifacts: [JSON]) -> ResRef {
        // Encode sources as JSON
        var sourcesJSON: String?
        if !card.sources.isEmpty {
            let sourcesArray = card.sources.map { artifactId -> [String: String] in
                ["type": "artifact", "artifact_id": artifactId]
            }
            if let data = try? JSONSerialization.data(withJSONObject: sourcesArray),
               let jsonString = String(data: data, encoding: .utf8) {
                sourcesJSON = jsonString
            }
        }

        return ResRef(
            name: card.title.isEmpty ? metadata.title : card.title,
            content: card.prose,
            enabledByDefault: true,
            cardType: metadata.cardType,
            timePeriod: card.timePeriod ?? metadata.timePeriod,
            organization: card.organization ?? metadata.organization,
            location: card.location ?? metadata.location,
            sourcesJSON: sourcesJSON,
            isFromOnboarding: false  // Standalone, not from onboarding
        )
    }

    // MARK: - Private: SwiftData Persistence

    /// Persist artifact to SwiftData as a standalone artifact (no session, immediately archived).
    /// This allows KC Browser extractions to be reused in future onboarding interviews.
    private func persistArtifactToSwiftData(_ artifactJSON: JSON) {
        guard let store = sessionStore else {
            Logger.debug("📦 StandaloneKCCoordinator: No session store, skipping persistence", category: .ai)
            return
        }

        // Check for existing artifact by hash to avoid duplicates
        if let hash = artifactJSON["sha256"].string,
           store.findExistingArtifactByHash(hash) != nil {
            Logger.debug("📦 StandaloneKCCoordinator: Artifact already exists, skipping", category: .ai)
            return
        }

        let sourceType = artifactJSON["source_type"].string ?? "document"
        let filename = artifactJSON["filename"].stringValue
        let extractedContent = artifactJSON["extracted_text"].stringValue
        let sourceHash = artifactJSON["sha256"].string

        // Build metadata JSON including summary
        var metadataDict: [String: Any] = [:]
        if let summary = artifactJSON["summary"].string {
            metadataDict["summary"] = summary
        }
        if let brief = artifactJSON["brief_description"].string {
            metadataDict["brief_description"] = brief
        }
        if let title = artifactJSON["metadata"]["title"].string {
            metadataDict["title"] = title
        }
        if !artifactJSON["summary_metadata"].dictionaryValue.isEmpty {
            metadataDict["summary_metadata"] = artifactJSON["summary_metadata"].dictionaryObject ?? [:]
        }

        let metadataJSONString: String?
        if !metadataDict.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: metadataDict),
           let string = String(data: data, encoding: .utf8) {
            metadataJSONString = string
        } else {
            metadataJSONString = nil
        }

        // Persist as standalone artifact (session = nil)
        _ = store.addStandaloneArtifact(
            sourceType: sourceType,
            sourceFilename: filename,
            extractedContent: extractedContent,
            sourceHash: sourceHash,
            metadataJSON: metadataJSONString
        )

        Logger.info("📦 StandaloneKCCoordinator: Persisted artifact to SwiftData: \(filename)", category: .ai)
    }
}

// MARK: - Errors

enum StandaloneKCError: LocalizedError {
    case noSources
    case llmNotConfigured
    case extractionServiceNotAvailable
    case noArtifactsExtracted
    case extractionFailed(String)
    case agentNoResult
    case agentInvalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .noSources:
            return "No source documents provided"
        case .llmNotConfigured:
            return "LLM service is not configured. Check your API keys in Settings."
        case .extractionServiceNotAvailable:
            return "Document extraction service is not available"
        case .noArtifactsExtracted:
            return "No content could be extracted from the provided documents"
        case .extractionFailed(let message):
            return message
        case .agentNoResult:
            return "Knowledge card agent completed without producing a result"
        case .agentInvalidOutput(let message):
            return "Invalid knowledge card output: \(message)"
        }
    }
}
