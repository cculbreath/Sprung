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
    private weak var sessionStore: OnboardingSessionStore?

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, sessionStore: OnboardingSessionStore?) {
        self.sessionStore = sessionStore
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
                Logger.warning("⚠️ StandaloneKCExtractor: Failed to extract \(filename): \(error.localizedDescription)", category: .ai)
                // Continue with other sources even if one fails
            }
        }

        return artifacts
    }

    /// Load archived artifacts from SwiftData.
    /// - Parameter artifactIds: Set of artifact IDs to load
    /// - Returns: Array of artifact JSON objects
    func loadArchivedArtifacts(_ artifactIds: Set<String>) -> [JSON] {
        guard let store = sessionStore else { return [] }

        var loadedArtifacts: [JSON] = []

        for id in artifactIds {
            guard let record = store.findArtifactById(id) else {
                Logger.warning("⚠️ StandaloneKCExtractor: Archived artifact not found: \(id)", category: .ai)
                continue
            }

            let artifactJSON = artifactRecordToJSON(record)
            loadedArtifacts.append(artifactJSON)

            Logger.debug("📦 StandaloneKCExtractor: Loaded archived artifact: \(record.sourceFilename)", category: .ai)
        }

        return loadedArtifacts
    }

    /// Convert OnboardingArtifactRecord to JSON format
    func artifactRecordToJSON(_ record: OnboardingArtifactRecord) -> JSON {
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
            // Include summary_metadata if present
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

        // Persist to SwiftData as standalone artifact (session = nil, immediately archived)
        let artifactId = persistArtifactToSwiftData(artifactJSON)
        artifactJSON["id"].string = artifactId  // Use the SwiftData ID

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
        guard let store = sessionStore else {
            Logger.debug("📦 StandaloneKCExtractor: No session store, skipping persistence", category: .ai)
            return artifactJSON["id"].stringValue
        }

        // Check for existing artifact by hash to avoid duplicates
        if let hash = artifactJSON["sha256"].string,
           let existing = store.findExistingArtifactByHash(hash) {
            Logger.debug("📦 StandaloneKCExtractor: Artifact already exists, returning existing ID", category: .ai)
            return existing.id.uuidString
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
        let record = store.addStandaloneArtifact(
            sourceType: sourceType,
            sourceFilename: filename,
            extractedContent: extractedContent,
            sourceHash: sourceHash,
            metadataJSON: metadataJSONString
        )

        Logger.info("📦 StandaloneKCExtractor: Persisted artifact to SwiftData: \(filename)", category: .ai)
        return record.id.uuidString
    }
}
