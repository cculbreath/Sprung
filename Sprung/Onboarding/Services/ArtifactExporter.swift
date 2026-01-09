//
//  ArtifactExporter.swift
//  Sprung
//
//  Handles exporting artifacts to filesystem and other formats.
//  Extracted from ArtifactRecordStore to focus the store on CRUD operations.
//

import Foundation

/// Handles exporting artifacts to filesystem and other formats.
enum ArtifactExporter {

    // MARK: - Session Export

    /// Export session artifacts to a temporary filesystem directory for analysis.
    /// Creates a folder per artifact with extracted_text.txt, summary.txt, and JSON files.
    /// - Parameter session: The session whose artifacts to export
    /// - Returns: URL to the temporary directory containing exported artifacts
    static func exportArtifactsToFilesystem(_ session: OnboardingSession) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprung-artifacts-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for artifact in session.artifacts {
            try exportArtifact(artifact, to: tempDir)
        }

        Logger.info("Exported \(session.artifacts.count) artifacts to \(tempDir.path)", category: .ai)
        return tempDir
    }

    /// Export specific artifacts to a temporary filesystem directory.
    /// - Parameters:
    ///   - artifacts: The artifacts to export
    /// - Returns: URL to the temporary directory containing exported artifacts
    static func exportArtifacts(_ artifacts: [ArtifactRecord]) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprung-artifacts-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for artifact in artifacts {
            try exportArtifact(artifact, to: tempDir)
        }

        Logger.info("Exported \(artifacts.count) artifacts to \(tempDir.path)", category: .ai)
        return tempDir
    }

    // MARK: - Single Artifact Export

    /// Export a single artifact to an existing directory root (for incremental updates).
    /// - Parameters:
    ///   - artifact: The artifact to export
    ///   - directory: The root directory to export into
    static func exportSingleArtifact(_ artifact: ArtifactRecord, to directory: URL) throws {
        try exportArtifact(artifact, to: directory)
    }

    /// Export a single artifact to a directory
    private static func exportArtifact(_ artifact: ArtifactRecord, to directory: URL) throws {
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
            try writePrettyJSON(skillsJSON, to: skillsPath)
        }

        // Write narrative cards
        if let narrativeCardsJSON = artifact.narrativeCardsJSON, !narrativeCardsJSON.isEmpty {
            let cardsPath = artifactDir.appendingPathComponent("narrative_cards.json")
            try writePrettyJSON(narrativeCardsJSON, to: cardsPath)
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

    // MARK: - Git Analysis Export

    /// Export git repository analysis data
    private static func exportGitAnalysis(_ rawData: [String: Any], to directory: URL) throws {
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

    // MARK: - Knowledge Cards Export

    /// Export all knowledge cards to a knowledge_cards/ subdirectory.
    /// Each card is exported as a markdown file with metadata and content.
    /// - Parameters:
    ///   - knowledgeCards: The cards to export
    ///   - directory: The root directory to export into
    static func exportKnowledgeCards(_ knowledgeCards: [KnowledgeCard], to directory: URL) throws {
        let kcDir = directory.appendingPathComponent("knowledge_cards")
        try FileManager.default.createDirectory(at: kcDir, withIntermediateDirectories: true)

        for card in knowledgeCards {
            try exportKnowledgeCard(card, to: kcDir)
        }

        Logger.info("📚 Exported \(knowledgeCards.count) knowledge cards to filesystem", category: .ai)
    }

    /// Export a single knowledge card to the knowledge_cards directory.
    /// - Parameters:
    ///   - knowledgeCard: The card to export
    ///   - rootDirectory: The root directory (knowledge_cards/ will be created inside)
    static func exportSingleKnowledgeCard(_ knowledgeCard: KnowledgeCard, to rootDirectory: URL) throws {
        let kcDir = rootDirectory.appendingPathComponent("knowledge_cards")
        try FileManager.default.createDirectory(at: kcDir, withIntermediateDirectories: true)
        try exportKnowledgeCard(knowledgeCard, to: kcDir)
    }

    /// Export a KnowledgeCard to a directory as a markdown file
    private static func exportKnowledgeCard(_ card: KnowledgeCard, to directory: URL) throws {
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

    // MARK: - Cleanup

    /// Clean up an exported artifact directory
    /// - Parameter url: The directory to remove
    static func cleanupExportedArtifacts(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            Logger.info("Cleaned up exported artifacts", category: .ai)
        } catch {
            Logger.warning("Failed to cleanup exported artifacts: \(error)", category: .ai)
        }
    }

    // MARK: - Helpers

    /// Write JSON string to file, pretty-printing if possible
    private static func writePrettyJSON(_ jsonString: String, to path: URL) throws {
        if let data = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            try prettyString.write(to: path, atomically: true, encoding: .utf8)
        } else {
            try jsonString.write(to: path, atomically: true, encoding: .utf8)
        }
    }
}
