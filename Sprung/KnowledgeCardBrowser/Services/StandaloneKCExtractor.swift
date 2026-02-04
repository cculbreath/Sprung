//
//  StandaloneKCExtractor.swift
//  Sprung
//
//  Handles document and git repository extraction for standalone KC generation.
//  Extracts content into JSON artifacts suitable for KC agent processing.
//

import Foundation
import SwiftyJSON

/// Handles extraction of documents and git repositories into artifacts.
@MainActor
class StandaloneKCExtractor {
    // MARK: - Dependencies

    private var extractionService: DocumentExtractionService?
    private weak var llmFacade: LLMFacade?
    private weak var artifactRecordStore: ArtifactRecordStore?

    // MARK: - Pre-analyzed Results (from GitAnalysisAgent)

    /// Knowledge cards produced directly by GitAnalysisAgent, bypassing the analyzer step.
    private(set) var gitAnalyzedCards: [KnowledgeCard] = []
    /// Skills produced directly by GitAnalysisAgent.
    private(set) var gitAnalyzedSkills: [Skill] = []

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, artifactRecordStore: ArtifactRecordStore?) {
        self.llmFacade = llmFacade
        self.artifactRecordStore = artifactRecordStore
        self.extractionService = DocumentExtractionService(llmFacade: llmFacade, eventBus: nil)
    }

    // MARK: - Public API

    /// Extract all sources into artifacts. Artifacts are persisted to SwiftData as standalone (archived).
    /// - Parameters:
    ///   - sources: URLs to documents or git repositories
    ///   - onProgress: Progress callback (current, total, filename)
    /// - Returns: Array of artifact JSON objects with their IDs
    func extractAllSources(
        _ sources: [URL],
        onProgress: @escaping (Int, Int, String) -> Void
    ) async throws -> [JSON] {
        var artifacts: [JSON] = []
        let total = sources.count

        // Reset pre-analyzed results from previous runs
        gitAnalyzedCards = []
        gitAnalyzedSkills = []

        for (index, url) in sources.enumerated() {
            let filename = url.lastPathComponent
            onProgress(index + 1, total, filename)

            do {
                if isGitRepository(url) {
                    let artifact = try await extractGitRepository(url)
                    artifacts.append(artifact)
                } else {
                    let artifact = try await extractDocument(url)
                    artifacts.append(artifact)
                }
            } catch {
                Logger.warning("StandaloneKCExtractor: Failed to extract \(filename): \(error.localizedDescription)", category: .ai)
                // Continue with other sources even if one fails
            }
        }

        return artifacts
    }

    /// Load archived artifacts from SwiftData.
    /// - Parameter artifactIds: Set of artifact IDs to load
    /// - Returns: Array of artifact JSON objects
    func loadArchivedArtifacts(_ artifactIds: Set<String>) -> [JSON] {
        guard let store = artifactRecordStore else { return [] }

        var loadedArtifacts: [JSON] = []

        for id in artifactIds {
            guard let record = store.artifact(byIdString: id) else {
                Logger.warning("StandaloneKCExtractor: Archived artifact not found: \(id)", category: .ai)
                continue
            }

            let artifactJSON = artifactRecordToJSON(record)
            loadedArtifacts.append(artifactJSON)

            Logger.debug("StandaloneKCExtractor: Loaded archived artifact: \(record.filename)", category: .ai)
        }

        return loadedArtifacts
    }

    /// Convert ArtifactRecord to JSON format
    func artifactRecordToJSON(_ record: ArtifactRecord) -> JSON {
        var artifactJSON = JSON()
        artifactJSON["id"].string = record.id.uuidString
        artifactJSON["filename"].string = record.filename
        artifactJSON["source_type"].string = record.sourceType
        artifactJSON["extracted_text"].string = record.extractedContent
        artifactJSON["sha256"].string = record.sha256
        artifactJSON["content_type"].string = record.contentType
        artifactJSON["size_bytes"].int = record.sizeInBytes
        artifactJSON["summary"].string = record.summary
        artifactJSON["brief_description"].string = record.briefDescription
        artifactJSON["title"].string = record.title
        artifactJSON["has_skills"].bool = record.hasSkills
        artifactJSON["has_narrative_cards"].bool = record.hasNarrativeCards
        artifactJSON["skills"].string = record.skillsJSON
        artifactJSON["narrative_cards"].string = record.narrativeCardsJSON

        // Parse metadata JSON
        if let metadataJSONString = record.metadataJSON,
           let data = metadataJSONString.data(using: .utf8),
           let metadata = try? JSON(data: data) {
            artifactJSON["metadata"] = metadata
            // Also extract summary_metadata to top level for easier access
            if !metadata["summary_metadata"].dictionaryValue.isEmpty {
                artifactJSON["summary_metadata"] = metadata["summary_metadata"]
            }
        }

        return artifactJSON
    }

    // MARK: - Private: Document Extraction

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

        // Build artifact JSON
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

        // Persist to SwiftData as standalone artifact (session = nil, immediately archived)
        let artifactId = persistArtifactToSwiftData(artifactJSON)
        artifactJSON["id"].string = artifactId  // Use the SwiftData ID

        return artifactJSON
    }

    // MARK: - Private: Git Repository Extraction

    private func isGitRepository(_ url: URL) -> Bool {
        let gitDir = url.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func extractGitRepository(_ url: URL) async throws -> JSON {
        guard let facade = llmFacade else {
            throw StandaloneKCError.llmNotConfigured
        }

        let repoName = url.lastPathComponent

        // Validate model is configured
        guard let modelId = UserDefaults.standard.string(forKey: "onboardingGitIngestModelId"),
              !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "onboardingGitIngestModelId",
                operationName: "Git Repository Analysis"
            )
        }

        Logger.info("StandaloneKCExtractor: Running GitAnalysisAgent on \(repoName) with model \(modelId)", category: .ai)

        // Run the full GitAnalysisAgent
        let agent = GitAnalysisAgent(
            repoPath: url,
            modelId: modelId,
            facade: facade
        )
        let result = try await agent.run()

        // Accumulate pre-analyzed cards and skills (these bypass the analyzer)
        gitAnalyzedCards.append(contentsOf: result.narrativeCards)
        gitAnalyzedSkills.append(contentsOf: result.skills)

        Logger.info("StandaloneKCExtractor: GitAnalysisAgent produced \(result.narrativeCards.count) cards, \(result.skills.count) skills from \(repoName)", category: .ai)

        // Build a summary artifact JSON for persistence/archiving
        let cardSummaries = result.narrativeCards.map { $0.title }.joined(separator: ", ")
        let skillNames = result.skills.map { $0.canonical }.joined(separator: ", ")

        let fullText = """
        # Git Repository Analysis: \(repoName)

        ## Knowledge Cards (\(result.narrativeCards.count))
        \(cardSummaries)

        ## Skills (\(result.skills.count))
        \(skillNames)

        Analyzed at: \(result.analyzedAt.formatted())
        """

        var artifactJSON = JSON()
        artifactJSON["id"].string = UUID().uuidString
        artifactJSON["filename"].string = repoName
        artifactJSON["content_type"].string = "application/x-git"
        artifactJSON["source_type"].string = "git_repository"
        artifactJSON["extracted_text"].string = fullText
        artifactJSON["summary"].string = "Git repository \(repoName): \(result.narrativeCards.count) knowledge cards, \(result.skills.count) skills"
        artifactJSON["brief_description"].string = "Git repository: \(repoName)"
        artifactJSON["summary_metadata"]["document_type"].string = "git_repository"

        // Persist to SwiftData as standalone artifact
        let artifactId = persistArtifactToSwiftData(artifactJSON)
        artifactJSON["id"].string = artifactId

        return artifactJSON
    }

    // MARK: - Private: Helpers

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

    /// Persist artifact to SwiftData as a standalone artifact (no session, immediately archived).
    /// This allows KC Browser extractions to be reused in future onboarding interviews.
    /// - Returns: The artifact ID (UUID string) of the persisted record
    @discardableResult
    private func persistArtifactToSwiftData(_ artifactJSON: JSON) -> String {
        guard let store = artifactRecordStore else {
            Logger.debug("StandaloneKCExtractor: No artifact store, skipping persistence", category: .ai)
            return artifactJSON["id"].stringValue
        }

        // Check for existing artifact by hash to avoid duplicates
        if let hash = artifactJSON["sha256"].string,
           let existing = store.artifact(bySha256: hash) {
            Logger.debug("StandaloneKCExtractor: Artifact already exists, returning existing ID", category: .ai)
            return existing.id.uuidString
        }

        let sourceType = artifactJSON["source_type"].string ?? "document"
        let filename = artifactJSON["filename"].stringValue
        let extractedContent = artifactJSON["extracted_text"].stringValue
        let sha256 = artifactJSON["sha256"].string
        let contentType = artifactJSON["content_type"].string
        let sizeInBytes = artifactJSON["size_bytes"].intValue
        let summary = artifactJSON["summary"].string
        let briefDescription = artifactJSON["brief_description"].string
        let title = artifactJSON["metadata"]["title"].string

        // Build metadata JSON including summary
        var metadataDict: [String: Any] = [:]
        if let summary = summary {
            metadataDict["summary"] = summary
        }
        if let brief = briefDescription {
            metadataDict["brief_description"] = brief
        }
        if let title = title {
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

        // Persist as standalone artifact (session = nil, archived)
        let record = store.addStandaloneArtifact(
            sourceType: sourceType,
            filename: filename,
            extractedContent: extractedContent,
            sha256: sha256,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            summary: summary,
            briefDescription: briefDescription,
            title: title,
            metadataJSON: metadataJSONString
        )

        Logger.info("StandaloneKCExtractor: Persisted artifact to SwiftData: \(filename)", category: .ai)
        return record.id.uuidString
    }
}
