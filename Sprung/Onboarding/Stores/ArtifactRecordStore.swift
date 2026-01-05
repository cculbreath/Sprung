//
//  ArtifactRecordStore.swift
//  Sprung
//
//  SwiftData CRUD store for ArtifactRecord.
//  Follows the same pattern as ResRefStore, JobAppStore, etc.
//
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ArtifactRecordStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
        Logger.info("ArtifactRecordStore initialized", category: .ai)
    }

    // MARK: - Read Operations

    /// All artifact records (computed, always fresh from SwiftData)
    var allArtifacts: [ArtifactRecord] {
        let descriptor = FetchDescriptor<ArtifactRecord>(
            sortBy: [SortDescriptor(\.ingestedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Artifacts for the current session
    func artifacts(for session: OnboardingSession) -> [ArtifactRecord] {
        session.artifacts.sorted { $0.ingestedAt < $1.ingestedAt }
    }

    /// Archived artifacts (no session, available for reuse)
    var archivedArtifacts: [ArtifactRecord] {
        let descriptor = FetchDescriptor<ArtifactRecord>(
            predicate: #Predicate { $0.session == nil },
            sortBy: [SortDescriptor(\.ingestedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Find artifact by UUID
    func artifact(byId id: UUID) -> ArtifactRecord? {
        var descriptor = FetchDescriptor<ArtifactRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Find artifact by ID string
    func artifact(byIdString idString: String) -> ArtifactRecord? {
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return artifact(byId: uuid)
    }

    /// Find artifact by SHA256 hash
    func artifact(bySha256 hash: String) -> ArtifactRecord? {
        var descriptor = FetchDescriptor<ArtifactRecord>(
            predicate: #Predicate { $0.sha256 == hash }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Check if artifact exists for session by filename and optional hash
    func existingArtifact(
        in session: OnboardingSession,
        filename: String,
        sha256: String?
    ) -> ArtifactRecord? {
        session.artifacts.first { artifact in
            artifact.filename == filename &&
            (sha256 == nil || artifact.sha256 == sha256)
        }
    }

    // MARK: - Create Operations

    /// Add an artifact to a session
    @discardableResult
    func addArtifact(
        to session: OnboardingSession,
        sourceType: String,
        filename: String,
        extractedContent: String,
        sha256: String? = nil,
        contentType: String? = nil,
        sizeInBytes: Int = 0,
        summary: String? = nil,
        briefDescription: String? = nil,
        title: String? = nil,
        skillsJSON: String? = nil,
        narrativeCardsJSON: String? = nil,
        metadataJSON: String? = nil,
        rawFileRelativePath: String? = nil,
        planItemId: String? = nil
    ) -> ArtifactRecord {
        let record = ArtifactRecord(
            sourceType: sourceType,
            filename: filename,
            sha256: sha256,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            extractedContent: extractedContent,
            summary: summary,
            briefDescription: briefDescription,
            title: title,
            skillsJSON: skillsJSON,
            narrativeCardsJSON: narrativeCardsJSON,
            metadataJSON: metadataJSON,
            rawFileRelativePath: rawFileRelativePath,
            planItemId: planItemId
        )
        record.session = session
        session.artifacts.append(record)
        modelContext.insert(record)
        saveContext()
        Logger.info("Added artifact: \(filename) (\(sourceType))", category: .ai)
        return record
    }

    /// Add a standalone artifact (no session, immediately archived)
    @discardableResult
    func addStandaloneArtifact(
        sourceType: String,
        filename: String,
        extractedContent: String,
        sha256: String? = nil,
        contentType: String? = nil,
        sizeInBytes: Int = 0,
        summary: String? = nil,
        briefDescription: String? = nil,
        title: String? = nil,
        skillsJSON: String? = nil,
        narrativeCardsJSON: String? = nil,
        metadataJSON: String? = nil,
        rawFileRelativePath: String? = nil,
        planItemId: String? = nil
    ) -> ArtifactRecord {
        let record = ArtifactRecord(
            sourceType: sourceType,
            filename: filename,
            sha256: sha256,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            extractedContent: extractedContent,
            summary: summary,
            briefDescription: briefDescription,
            title: title,
            skillsJSON: skillsJSON,
            narrativeCardsJSON: narrativeCardsJSON,
            metadataJSON: metadataJSON,
            rawFileRelativePath: rawFileRelativePath,
            planItemId: planItemId
        )
        // Note: session is nil, so artifact is immediately archived
        modelContext.insert(record)
        saveContext()
        Logger.info("Added standalone artifact (archived): \(filename) (\(sourceType))", category: .ai)
        return record
    }

    // MARK: - Update Operations

    /// Update an artifact (saves context after mutation)
    func updateArtifact(_ artifact: ArtifactRecord) {
        saveContext()
    }

    /// Update artifact metadata JSON
    func updateMetadata(_ artifact: ArtifactRecord, metadataJSON: String?) {
        artifact.metadataJSON = metadataJSON
        saveContext()
    }

    /// Update artifact's skills
    func updateSkills(_ artifact: ArtifactRecord, skillsJSON: String?) {
        artifact.skillsJSON = skillsJSON
        saveContext()
    }

    /// Update artifact's narrative cards
    func updateNarrativeCards(_ artifact: ArtifactRecord, narrativeCardsJSON: String?) {
        artifact.narrativeCardsJSON = narrativeCardsJSON
        saveContext()
    }

    /// Update artifact summary
    func updateSummary(_ artifact: ArtifactRecord, summary: String?, briefDescription: String? = nil) {
        artifact.summary = summary
        if let brief = briefDescription {
            artifact.briefDescription = brief
        }
        saveContext()
    }

    /// Update artifact extracted content
    func updateExtractedContent(_ artifact: ArtifactRecord, content: String) {
        artifact.extractedContent = content
        saveContext()
    }

    /// Promote an archived artifact to a session
    func promoteArtifact(_ artifact: ArtifactRecord, to session: OnboardingSession) {
        artifact.session = session
        session.artifacts.append(artifact)
        saveContext()
        Logger.info("Promoted archived artifact to session: \(artifact.filename)", category: .ai)
    }

    /// Demote an artifact from session (makes it archived)
    func demoteArtifact(_ artifact: ArtifactRecord) {
        if let session = artifact.session,
           let index = session.artifacts.firstIndex(of: artifact) {
            session.artifacts.remove(at: index)
        }
        artifact.session = nil
        saveContext()
        Logger.info("Demoted artifact to archive: \(artifact.filename)", category: .ai)
    }

    // MARK: - Delete Operations

    /// Delete an artifact permanently
    func deleteArtifact(_ artifact: ArtifactRecord) {
        let filename = artifact.filename

        // Remove from session if attached
        if let session = artifact.session,
           let index = session.artifacts.firstIndex(of: artifact) {
            session.artifacts.remove(at: index)
        }

        modelContext.delete(artifact)
        saveContext()
        Logger.info("Permanently deleted artifact: \(filename)", category: .ai)
    }

    /// Delete an artifact by ID
    @discardableResult
    func deleteArtifact(byId id: UUID) -> Bool {
        guard let artifact = artifact(byId: id) else { return false }
        deleteArtifact(artifact)
        return true
    }

    /// Delete an artifact by ID string
    @discardableResult
    func deleteArtifact(byIdString idString: String) -> Bool {
        guard let uuid = UUID(uuidString: idString) else { return false }
        return deleteArtifact(byId: uuid)
    }

    // MARK: - Query Operations

    /// Get artifact summaries (lightweight list for display)
    func artifactSummaries(for session: OnboardingSession) -> [ArtifactSummary] {
        artifacts(for: session).map { ArtifactSummary(artifact: $0) }
    }

    /// Find artifacts by source type
    func artifacts(bySourceType sourceType: String, in session: OnboardingSession? = nil) -> [ArtifactRecord] {
        if let session {
            return session.artifacts.filter { $0.sourceType == sourceType }
        } else {
            let descriptor = FetchDescriptor<ArtifactRecord>(
                predicate: #Predicate { $0.sourceType == sourceType },
                sortBy: [SortDescriptor(\.ingestedAt, order: .reverse)]
            )
            return (try? modelContext.fetch(descriptor)) ?? []
        }
    }

    /// Get artifacts with knowledge extraction (skills or narrative cards)
    func artifactsWithKnowledgeExtraction(in session: OnboardingSession? = nil) -> [ArtifactRecord] {
        if let session {
            return session.artifacts.filter { $0.hasKnowledgeExtraction }
        } else {
            // Note: Can't use hasKnowledgeExtraction computed property in predicate,
            // so we filter after fetch
            let descriptor = FetchDescriptor<ArtifactRecord>(
                sortBy: [SortDescriptor(\.ingestedAt, order: .reverse)]
            )
            let all = (try? modelContext.fetch(descriptor)) ?? []
            return all.filter { $0.hasKnowledgeExtraction }
        }
    }

    /// Get artifacts with skills
    func artifactsWithSkills(in session: OnboardingSession? = nil) -> [ArtifactRecord] {
        if let session {
            return session.artifacts.filter { $0.hasSkills }
        } else {
            let descriptor = FetchDescriptor<ArtifactRecord>(
                sortBy: [SortDescriptor(\.ingestedAt, order: .reverse)]
            )
            let all = (try? modelContext.fetch(descriptor)) ?? []
            return all.filter { $0.hasSkills }
        }
    }

    /// Get artifacts with narrative cards
    func artifactsWithNarrativeCards(in session: OnboardingSession? = nil) -> [ArtifactRecord] {
        if let session {
            return session.artifacts.filter { $0.hasNarrativeCards }
        } else {
            let descriptor = FetchDescriptor<ArtifactRecord>(
                sortBy: [SortDescriptor(\.ingestedAt, order: .reverse)]
            )
            let all = (try? modelContext.fetch(descriptor)) ?? []
            return all.filter { $0.hasNarrativeCards }
        }
    }

    // MARK: - Filesystem Export

    /// Export session artifacts to a temporary filesystem directory for analysis.
    /// Creates a folder per artifact with extracted_text.txt, summary.txt, and card_inventory.json.
    func exportArtifactsToFilesystem(_ session: OnboardingSession) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprung-artifacts-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for artifact in session.artifacts {
            try exportArtifact(artifact, to: tempDir)
        }

        Logger.info("Exported \(session.artifacts.count) artifacts to \(tempDir.path)", category: .ai)
        return tempDir
    }

    /// Export specific artifacts by ID to a temporary filesystem directory.
    func exportArtifacts(byIds ids: Set<String>) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprung-artifacts-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var exportedCount = 0
        for idString in ids {
            guard let artifact = artifact(byIdString: idString) else {
                Logger.warning("Artifact not found for export: \(idString)", category: .ai)
                continue
            }
            try exportArtifact(artifact, to: tempDir)
            exportedCount += 1
        }

        Logger.info("Exported \(exportedCount) artifacts to \(tempDir.path)", category: .ai)
        return tempDir
    }

    /// Export a single artifact to an existing directory root (for incremental updates).
    /// Public wrapper for updating the filesystem mirror when artifacts change.
    func exportSingleArtifact(_ artifact: ArtifactRecord, to directory: URL) throws {
        try exportArtifact(artifact, to: directory)
    }

    /// Export a single artifact to a directory
    private func exportArtifact(_ artifact: ArtifactRecord, to directory: URL) throws {
        let artifactDir = directory.appendingPathComponent(artifact.artifactFolderName)
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

        // Write extracted text
        if !artifact.extractedContent.isEmpty {
            let textPath = artifactDir.appendingPathComponent("extracted_text.txt")
            try artifact.extractedContent.write(to: textPath, atomically: true, encoding: .utf8)
        }

        // Write summary
        if let summary = artifact.summary, !summary.isEmpty {
            let summaryPath = artifactDir.appendingPathComponent("summary.txt")
            try summary.write(to: summaryPath, atomically: true, encoding: .utf8)
        }

        // Write skills
        if let skillsJSON = artifact.skillsJSON, !skillsJSON.isEmpty {
            let skillsPath = artifactDir.appendingPathComponent("skills.json")
            // Try to pretty-print
            if let data = skillsJSON.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                try prettyString.write(to: skillsPath, atomically: true, encoding: .utf8)
            } else {
                try skillsJSON.write(to: skillsPath, atomically: true, encoding: .utf8)
            }
        }

        // Write narrative cards
        if let narrativeCardsJSON = artifact.narrativeCardsJSON, !narrativeCardsJSON.isEmpty {
            let cardsPath = artifactDir.appendingPathComponent("narrative_cards.json")
            // Try to pretty-print
            if let data = narrativeCardsJSON.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                try prettyString.write(to: cardsPath, atomically: true, encoding: .utf8)
            } else {
                try narrativeCardsJSON.write(to: cardsPath, atomically: true, encoding: .utf8)
            }
        }

        // Export git analysis for git repositories
        if artifact.sourceType == "git" || artifact.sourceType == "git_repository",
           let metadataJSON = artifact.metadataJSON,
           let metadataData = metadataJSON.data(using: .utf8),
           let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
           let rawData = metadata["raw_data"] as? [String: Any] {
            try exportGitAnalysis(rawData, to: artifactDir)
        }
    }

    /// Export git repository analysis data
    private func exportGitAnalysis(_ rawData: [String: Any], to directory: URL) throws {
        var report = "# Git Repository Analysis\n\n"

        // Contributors
        if let contributors = rawData["contributors"] as? [[String: Any]], !contributors.isEmpty {
            report += "## Contributors\n"
            for contributor in contributors {
                let name = contributor["name"] as? String ?? "Unknown"
                let commits = contributor["commits"] as? Int ?? 0
                let email = contributor["email"] as? String ?? ""
                report += "- \(name) (\(email)): \(commits) commits\n"
            }
            report += "\n"
        }

        // Commit stats
        let totalCommits = rawData["total_commits"] as? Int ?? 0
        let firstCommit = rawData["first_commit"] as? String ?? ""
        let lastCommit = rawData["last_commit"] as? String ?? ""
        if totalCommits > 0 {
            report += "## Commit Statistics\n"
            report += "- Total commits: \(totalCommits)\n"
            if !firstCommit.isEmpty { report += "- First commit: \(firstCommit)\n" }
            if !lastCommit.isEmpty { report += "- Last commit: \(lastCommit)\n" }
            report += "\n"
        }

        // Recent commits
        if let recentCommits = rawData["recent_commits"] as? [[String: Any]], !recentCommits.isEmpty {
            report += "## Recent Commits\n"
            for commit in recentCommits.prefix(20) {
                let hash = commit["hash"] as? String ?? ""
                let author = commit["author"] as? String ?? ""
                let message = commit["message"] as? String ?? ""
                report += "- [\(hash)] \(message) (\(author))\n"
            }
            report += "\n"
        }

        // File types
        if let fileTypes = rawData["file_types"] as? [String: Int], !fileTypes.isEmpty {
            report += "## File Types & Technologies\n"
            let sorted = fileTypes.sorted { $0.value > $1.value }
            for (ext, count) in sorted.prefix(15) {
                report += "- .\(ext): \(count) files\n"
            }
            report += "\n"
        }

        let analysisPath = directory.appendingPathComponent("git_analysis.txt")
        try report.write(to: analysisPath, atomically: true, encoding: .utf8)
    }

    /// Clean up an exported artifact directory
    func cleanupExportedArtifacts(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            Logger.info("Cleaned up exported artifacts", category: .ai)
        } catch {
            Logger.warning("Failed to cleanup exported artifacts: \(error)", category: .ai)
        }
    }

    // MARK: - Knowledge Cards Export

    /// Export all knowledge cards to a knowledge_cards/ subdirectory.
    /// Each card is exported as a markdown file with metadata and content.
    func exportKnowledgeCards(_ knowledgeCards: [KnowledgeCard], to directory: URL) throws {
        let kcDir = directory.appendingPathComponent("knowledge_cards")
        try FileManager.default.createDirectory(at: kcDir, withIntermediateDirectories: true)

        for card in knowledgeCards {
            try exportKnowledgeCard(card, to: kcDir)
        }

        Logger.info("📚 Exported \(knowledgeCards.count) knowledge cards to filesystem", category: .ai)
    }

    /// Export a single knowledge card to the knowledge_cards directory.
    func exportSingleKnowledgeCard(_ knowledgeCard: KnowledgeCard, to rootDirectory: URL) throws {
        let kcDir = rootDirectory.appendingPathComponent("knowledge_cards")
        try FileManager.default.createDirectory(at: kcDir, withIntermediateDirectories: true)
        try exportKnowledgeCard(knowledgeCard, to: kcDir)
    }

    /// Export a KnowledgeCard to a directory as a markdown file
    private func exportKnowledgeCard(_ card: KnowledgeCard, to directory: URL) throws {
        // Create a safe filename from the card title
        let safeFilename = card.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .prefix(50)
        let filename = "\(safeFilename)_\(card.id.uuidString.prefix(8)).md"
        let filePath = directory.appendingPathComponent(String(filename))

        var content = "# \(card.title)\n\n"

        // Metadata section
        content += "## Metadata\n"
        content += "- **Type**: \(card.cardType?.rawValue ?? "other")\n"
        if let org = card.organization, !org.isEmpty { content += "- **Organization**: \(org)\n" }
        if let dateRange = card.dateRange, !dateRange.isEmpty { content += "- **Date Range**: \(dateRange)\n" }
        content += "\n"

        // Narrative/Summary
        if !card.narrative.isEmpty {
            content += "## Summary\n"
            content += card.narrative
            content += "\n\n"
        }

        // Facts
        let facts = card.facts
        if !facts.isEmpty {
            content += "## Key Facts\n"
            // Group by category
            let factsByCategory = Dictionary(grouping: facts, by: { $0.category })
            for (category, categoryFacts) in factsByCategory.sorted(by: { $0.key < $1.key }) {
                content += "### \(category.capitalized)\n"
                for fact in categoryFacts {
                    content += "- \(fact.statement)\n"
                }
            }
            content += "\n"
        }

        // Evidence anchors (source documents)
        let anchors = card.evidenceAnchors
        if !anchors.isEmpty {
            content += "## Source Documents\n"
            for anchor in anchors {
                content += "- \(anchor.documentId)"
                if let excerpt = anchor.verbatimExcerpt, !excerpt.isEmpty {
                    content += ": \"\(excerpt.prefix(100))...\""
                }
                content += "\n"
            }
            content += "\n"
        }

        try content.write(to: filePath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Artifact Summary (Lightweight DTO)

/// Lightweight summary for artifact display without full content
struct ArtifactSummary: Identifiable {
    let id: UUID
    let filename: String
    let displayName: String
    let sourceType: String
    let contentType: String?
    let sizeInBytes: Int
    let briefDescription: String?
    let hasSkills: Bool
    let hasNarrativeCards: Bool
    let hasKnowledgeExtraction: Bool
    let ingestedAt: Date
    let isArchived: Bool

    init(artifact: ArtifactRecord) {
        self.id = artifact.id
        self.filename = artifact.filename
        self.displayName = artifact.displayName
        self.sourceType = artifact.sourceType
        self.contentType = artifact.contentType
        self.sizeInBytes = artifact.sizeInBytes
        self.briefDescription = artifact.briefDescription
        self.hasSkills = artifact.hasSkills
        self.hasNarrativeCards = artifact.hasNarrativeCards
        self.hasKnowledgeExtraction = artifact.hasKnowledgeExtraction
        self.ingestedAt = artifact.ingestedAt
        self.isArchived = artifact.isArchived
    }
}
