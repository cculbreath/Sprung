//
//  OnboardingSessionStore.swift
//  Sprung
//
//  Manages SwiftData persistence for onboarding sessions.
//  Enables resume functionality by persisting session state, artifacts, and messages.
//
import Foundation
import Observation
import SwiftData
import SwiftyJSON

@Observable
@MainActor
final class OnboardingSessionStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
        Logger.info("📦 OnboardingSessionStore initialized", category: .ai)
    }

    // MARK: - Session Management

    /// Get the most recent incomplete session (for resume)
    func getActiveSession() -> OnboardingSession? {
        var descriptor = FetchDescriptor<OnboardingSession>(
            predicate: #Predicate { !$0.isComplete },
            sortBy: [SortDescriptor(\.lastActiveAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Get all sessions (for history/debugging)
    func getAllSessions() -> [OnboardingSession] {
        let descriptor = FetchDescriptor<OnboardingSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Create a new session
    func createSession(phase: String = "phase1_core_facts") -> OnboardingSession {
        let session = OnboardingSession(phase: phase)
        modelContext.insert(session)
        saveContext()
        Logger.info("📦 Created new onboarding session: \(session.id)", category: .ai)
        return session
    }

    /// Update session's last active timestamp
    func touchSession(_ session: OnboardingSession) {
        session.lastActiveAt = Date()
        saveContext()
    }

    /// Update session phase
    func updatePhase(_ session: OnboardingSession, phase: String) {
        session.phase = phase
        session.lastActiveAt = Date()
        saveContext()
        Logger.info("📦 Session phase updated to: \(phase)", category: .ai)
    }

    /// Update previousResponseId for OpenAI thread continuity
    func updatePreviousResponseId(_ session: OnboardingSession, responseId: String?) {
        session.previousResponseId = responseId
        session.lastActiveAt = Date()
        saveContext()
        if let id = responseId {
            Logger.debug("📦 Session previousResponseId updated: \(id.prefix(12))...", category: .ai)
        }
    }

    /// Mark session as complete
    func completeSession(_ session: OnboardingSession) {
        session.isComplete = true
        session.lastActiveAt = Date()
        saveContext()
        Logger.info("📦 Session marked complete: \(session.id)", category: .ai)
    }

    /// Delete a session and all related data
    func deleteSession(_ session: OnboardingSession) {
        modelContext.delete(session)
        saveContext()
        Logger.info("📦 Deleted session: \(session.id)", category: .ai)
    }

    // MARK: - Objective Management

    /// Update or create objective status
    func updateObjective(_ session: OnboardingSession, objectiveId: String, status: String) {
        if let existing = session.objectives.first(where: { $0.objectiveId == objectiveId }) {
            existing.status = status
            existing.updatedAt = Date()
        } else {
            let record = OnboardingObjectiveRecord(objectiveId: objectiveId, status: status)
            record.session = session
            session.objectives.append(record)
            modelContext.insert(record)
        }
        session.lastActiveAt = Date()
        saveContext()
    }

    /// Get all objectives for a session
    func getObjectives(_ session: OnboardingSession) -> [OnboardingObjectiveRecord] {
        session.objectives
    }

    // MARK: - Artifact Management

    /// Add an artifact record
    func addArtifact(
        _ session: OnboardingSession,
        sourceType: String,
        sourceFilename: String,
        extractedContent: String,
        sourceHash: String? = nil,
        metadataJSON: String? = nil,
        rawFileRelativePath: String? = nil,
        planItemId: String? = nil
    ) -> OnboardingArtifactRecord {
        let record = OnboardingArtifactRecord(
            sourceType: sourceType,
            sourceFilename: sourceFilename,
            sourceHash: sourceHash,
            extractedContent: extractedContent,
            metadataJSON: metadataJSON,
            rawFileRelativePath: rawFileRelativePath,
            planItemId: planItemId
        )
        record.session = session
        session.artifacts.append(record)
        modelContext.insert(record)
        session.lastActiveAt = Date()
        saveContext()
        Logger.info("📦 Added artifact: \(sourceFilename) (\(sourceType))", category: .ai)
        return record
    }

    /// Check if an artifact already exists (by filename + hash)
    func findExistingArtifact(_ session: OnboardingSession, filename: String, hash: String?) -> OnboardingArtifactRecord? {
        session.artifacts.first { artifact in
            artifact.sourceFilename == filename &&
            (hash == nil || artifact.sourceHash == hash)
        }
    }

    /// Get all artifacts for a session
    func getArtifacts(_ session: OnboardingSession) -> [OnboardingArtifactRecord] {
        session.artifacts
    }

    // MARK: - Archived Artifact Management

    /// Get all archived artifacts (session == nil, available for reuse)
    func getArchivedArtifacts() -> [OnboardingArtifactRecord] {
        let descriptor = FetchDescriptor<OnboardingArtifactRecord>(
            predicate: #Predicate { $0.session == nil },
            sortBy: [SortDescriptor(\.ingestedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Find artifact by ID globally (across all sessions and archived)
    func findArtifactById(_ id: UUID) -> OnboardingArtifactRecord? {
        var descriptor = FetchDescriptor<OnboardingArtifactRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Find artifact by ID string (convenience for JSON-based lookups)
    func findArtifactById(_ idString: String) -> OnboardingArtifactRecord? {
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return findArtifactById(uuid)
    }

    /// Promote an archived artifact to the current session
    func promoteArtifact(_ artifact: OnboardingArtifactRecord, to session: OnboardingSession) {
        artifact.session = session
        session.artifacts.append(artifact)
        session.lastActiveAt = Date()
        saveContext()
        Logger.info("📦 Promoted archived artifact to session: \(artifact.sourceFilename)", category: .ai)
    }

    /// Permanently delete an artifact
    func deleteArtifact(_ artifact: OnboardingArtifactRecord) {
        let filename = artifact.sourceFilename
        modelContext.delete(artifact)
        saveContext()
        Logger.info("📦 Permanently deleted artifact: \(filename)", category: .ai)
    }

    /// Add a standalone artifact (no session, immediately archived)
    /// Used by KC Browser for document ingestion outside of onboarding
    func addStandaloneArtifact(
        sourceType: String,
        sourceFilename: String,
        extractedContent: String,
        sourceHash: String? = nil,
        metadataJSON: String? = nil,
        rawFileRelativePath: String? = nil,
        planItemId: String? = nil
    ) -> OnboardingArtifactRecord {
        let record = OnboardingArtifactRecord(
            sourceType: sourceType,
            sourceFilename: sourceFilename,
            sourceHash: sourceHash,
            extractedContent: extractedContent,
            metadataJSON: metadataJSON,
            rawFileRelativePath: rawFileRelativePath,
            planItemId: planItemId
        )
        // Note: session is nil, so artifact is immediately archived
        modelContext.insert(record)
        saveContext()
        Logger.info("📦 Added standalone artifact (archived): \(sourceFilename) (\(sourceType))", category: .ai)
        return record
    }

    /// Check if an artifact with matching hash already exists (global deduplication)
    func findExistingArtifactByHash(_ hash: String) -> OnboardingArtifactRecord? {
        var descriptor = FetchDescriptor<OnboardingArtifactRecord>(
            predicate: #Predicate { $0.sourceHash == hash }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: - Message Management

    /// Add a message record
    func addMessage(
        _ session: OnboardingSession,
        id: UUID = UUID(),
        role: String,
        text: String,
        isSystemGenerated: Bool = false,
        toolCallsJSON: String? = nil
    ) -> OnboardingMessageRecord {
        let record = OnboardingMessageRecord(
            id: id,
            role: role,
            text: text,
            isSystemGenerated: isSystemGenerated,
            toolCallsJSON: toolCallsJSON
        )
        record.session = session
        session.messages.append(record)
        modelContext.insert(record)
        // Don't call saveContext on every message - batch saves handled by caller
        return record
    }

    /// Update a message (for streaming finalization)
    func updateMessage(_ record: OnboardingMessageRecord, text: String, toolCallsJSON: String? = nil) {
        record.text = text
        if let json = toolCallsJSON {
            record.toolCallsJSON = json
        }
        // Don't save on every update during streaming
    }

    /// Get messages for a session (sorted by timestamp)
    func getMessages(_ session: OnboardingSession) -> [OnboardingMessageRecord] {
        session.messages.sorted { $0.timestamp < $1.timestamp }
    }

    /// Batch save messages (call after streaming completes)
    func saveMessages() {
        saveContext()
    }

    // MARK: - Restore Helpers

    /// Convert stored messages to OnboardingMessage models
    func restoreMessages(_ session: OnboardingSession) -> [OnboardingMessage] {
        getMessages(session).map { record in
            let role: OnboardingMessageRole
            switch record.role {
            case "user": role = .user
            case "assistant": role = .assistant
            default: role = .system
            }

            var toolCalls: [OnboardingMessage.ToolCallInfo]?
            if let json = record.toolCallsJSON,
               let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([OnboardingMessage.ToolCallInfo].self, from: data) {
                toolCalls = decoded
            }

            return OnboardingMessage(
                id: record.id,
                role: role,
                text: record.text,
                timestamp: record.timestamp,
                isSystemGenerated: record.isSystemGenerated,
                toolCalls: toolCalls
            )
        }
    }

    /// Convert stored objectives to dictionary
    func restoreObjectiveStatuses(_ session: OnboardingSession) -> [String: String] {
        Dictionary(uniqueKeysWithValues: getObjectives(session).map { ($0.objectiveId, $0.status) })
    }

    // MARK: - Timeline and Profile Management

    /// Update skeleton timeline JSON
    func updateSkeletonTimeline(_ session: OnboardingSession, timelineJSON: String?) {
        session.skeletonTimelineJSON = timelineJSON
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("📦 Session skeleton timeline updated", category: .ai)
    }

    /// Get skeleton timeline JSON
    func getSkeletonTimeline(_ session: OnboardingSession) -> String? {
        session.skeletonTimelineJSON
    }

    /// Update applicant profile JSON
    func updateApplicantProfile(_ session: OnboardingSession, profileJSON: String?) {
        session.applicantProfileJSON = profileJSON
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("📦 Session applicant profile updated", category: .ai)
    }

    /// Get applicant profile JSON
    func getApplicantProfile(_ session: OnboardingSession) -> String? {
        session.applicantProfileJSON
    }

    /// Update enabled sections
    func updateEnabledSections(_ session: OnboardingSession, sections: Set<String>) {
        session.enabledSectionsCSV = sections.sorted().joined(separator: ",")
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("📦 Session enabled sections updated: \(sections.count) sections", category: .ai)
    }

    /// Get enabled sections
    func getEnabledSections(_ session: OnboardingSession) -> Set<String> {
        guard let csv = session.enabledSectionsCSV, !csv.isEmpty else {
            return []
        }
        return Set(csv.split(separator: ",").map { String($0) })
    }

    // MARK: - Merged Inventory Management

    /// Update merged card inventory JSON (expensive Gemini call result)
    func updateMergedInventory(_ session: OnboardingSession, inventoryJSON: String?) {
        session.mergedInventoryJSON = inventoryJSON
        session.lastActiveAt = Date()
        saveContext()
        Logger.info("💾 Persisted merged card inventory (\(inventoryJSON?.count ?? 0) chars)", category: .ai)
    }

    /// Get merged inventory JSON
    func getMergedInventory(_ session: OnboardingSession) -> String? {
        session.mergedInventoryJSON
    }

    /// Update excluded card IDs
    func updateExcludedCardIds(_ session: OnboardingSession, excludedIds: Set<String>) {
        session.excludedCardIdsCSV = excludedIds.sorted().joined(separator: ",")
        session.lastActiveAt = Date()
        saveContext()
        Logger.debug("📦 Session excluded card IDs updated: \(excludedIds.count) excluded", category: .ai)
    }

    /// Get excluded card IDs
    func getExcludedCardIds(_ session: OnboardingSession) -> Set<String> {
        guard let csv = session.excludedCardIdsCSV, !csv.isEmpty else {
            return []
        }
        return Set(csv.split(separator: ",").map { String($0) })
    }

    // MARK: - Artifact Export for Analysis

    /// Export session artifacts to a temporary filesystem directory for analysis.
    /// Creates a folder per artifact with extracted_text.txt, summary.txt, and card_inventory.json.
    /// - Returns: URL of the temporary directory containing exported artifacts
    func exportArtifactsToFilesystem(_ session: OnboardingSession) throws -> URL {
        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprung-artifacts-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Export each artifact to its own folder
        for artifact in session.artifacts {
            let artifactDir = tempDir.appendingPathComponent(artifact.artifactFolderName)
            try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

            // Write extracted text
            if !artifact.extractedContent.isEmpty {
                let textPath = artifactDir.appendingPathComponent("extracted_text.txt")
                try artifact.extractedContent.write(to: textPath, atomically: true, encoding: .utf8)
            }

            // Parse metadataJSON for summary and card_inventory
            if let metadataString = artifact.metadataJSON,
               let metadataData = metadataString.data(using: .utf8) {
                let metadata = try JSON(data: metadataData)

                // Write summary
                let summary = metadata["summary"].stringValue
                if !summary.isEmpty {
                    let summaryPath = artifactDir.appendingPathComponent("summary.txt")
                    try summary.write(to: summaryPath, atomically: true, encoding: .utf8)
                }

                // Write card inventory if present
                let cardInventoryString = metadata["card_inventory"].stringValue
                if !cardInventoryString.isEmpty {
                    let inventoryPath = artifactDir.appendingPathComponent("card_inventory.json")
                    // Pretty-print if possible
                    if let data = cardInventoryString.data(using: .utf8),
                       let parsed = try? JSON(data: data),
                       let prettyData = try? parsed.rawData(options: .prettyPrinted),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        try prettyString.write(to: inventoryPath, atomically: true, encoding: .utf8)
                    } else {
                        try cardInventoryString.write(to: inventoryPath, atomically: true, encoding: .utf8)
                    }
                }
            }
        }

        Logger.info("📁 Exported \(session.artifacts.count) artifacts to \(tempDir.path)", category: .ai)
        return tempDir
    }

    /// Export specific artifacts by ID to a temporary filesystem directory.
    /// Used by standalone KC generation (artifacts not in a session).
    /// - Parameter artifactIds: Set of artifact IDs to export
    /// - Returns: URL of the temporary directory containing exported artifacts
    func exportArtifactsByIds(_ artifactIds: Set<String>) throws -> URL {
        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprung-artifacts-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Find and export each artifact
        var exportedCount = 0
        for idString in artifactIds {
            guard let artifact = findArtifactById(idString) else {
                Logger.warning("⚠️ Artifact not found for export: \(idString)", category: .ai)
                continue
            }

            try exportArtifact(artifact, to: tempDir)
            exportedCount += 1
        }

        Logger.info("📁 Exported \(exportedCount) artifacts to \(tempDir.path)", category: .ai)
        return tempDir
    }

    /// Export a single artifact to a directory
    private func exportArtifact(_ artifact: OnboardingArtifactRecord, to directory: URL) throws {
        let artifactDir = directory.appendingPathComponent(artifact.artifactFolderName)
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

        // Write extracted text
        if !artifact.extractedContent.isEmpty {
            let textPath = artifactDir.appendingPathComponent("extracted_text.txt")
            try artifact.extractedContent.write(to: textPath, atomically: true, encoding: .utf8)
        }

        // Parse metadataJSON for summary and card_inventory
        if let metadataString = artifact.metadataJSON,
           let metadataData = metadataString.data(using: .utf8),
           let metadata = try? JSON(data: metadataData) {

            // Write summary
            let summary = metadata["summary"].stringValue
            if !summary.isEmpty {
                let summaryPath = artifactDir.appendingPathComponent("summary.txt")
                try summary.write(to: summaryPath, atomically: true, encoding: .utf8)
            }

            // Write card inventory if present
            let cardInventoryString = metadata["card_inventory"].stringValue
            if !cardInventoryString.isEmpty {
                let inventoryPath = artifactDir.appendingPathComponent("card_inventory.json")
                if let data = cardInventoryString.data(using: .utf8),
                   let parsed = try? JSON(data: data),
                   let prettyData = try? parsed.rawData(options: .prettyPrinted),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    try prettyString.write(to: inventoryPath, atomically: true, encoding: .utf8)
                } else {
                    try cardInventoryString.write(to: inventoryPath, atomically: true, encoding: .utf8)
                }
            }

            // Export git analysis data for git repositories (rich structured data for analysis)
            let rawData = metadata["raw_data"]
            if rawData.exists() && metadata["type"].stringValue == "git_analysis" {
                var report = "# Git Repository Analysis\n\n"

                // Contributors
                let contributors = rawData["contributors"].arrayValue
                if !contributors.isEmpty {
                    report += "## Contributors\n"
                    for contributor in contributors {
                        let name = contributor["name"].stringValue
                        let commits = contributor["commits"].intValue
                        let email = contributor["email"].stringValue
                        report += "- \(name) (\(email)): \(commits) commits\n"
                    }
                    report += "\n"
                }

                // Commit stats
                let totalCommits = rawData["total_commits"].intValue
                let firstCommit = rawData["first_commit"].stringValue
                let lastCommit = rawData["last_commit"].stringValue
                if totalCommits > 0 {
                    report += "## Commit Statistics\n"
                    report += "- Total commits: \(totalCommits)\n"
                    if !firstCommit.isEmpty { report += "- First commit: \(firstCommit)\n" }
                    if !lastCommit.isEmpty { report += "- Last commit: \(lastCommit)\n" }
                    report += "\n"
                }

                // Recent commits (valuable for understanding what was built)
                let recentCommits = rawData["recent_commits"].arrayValue
                if !recentCommits.isEmpty {
                    report += "## Recent Commits (showing development activity)\n"
                    for commit in recentCommits.prefix(20) {
                        let hash = commit["hash"].stringValue
                        let author = commit["author"].stringValue
                        let message = commit["message"].stringValue
                        report += "- [\(hash)] \(message) (\(author))\n"
                    }
                    report += "\n"
                }

                // File types (technologies used)
                let fileTypes = rawData["file_types"].dictionaryValue
                if !fileTypes.isEmpty {
                    report += "## File Types & Technologies\n"
                    let sorted = fileTypes.sorted { $0.value.intValue > $1.value.intValue }
                    for (ext, count) in sorted.prefix(15) {
                        report += "- .\(ext): \(count.intValue) files\n"
                    }
                    report += "\n"
                }

                // Branches
                let branches = rawData["branches"].arrayValue
                if !branches.isEmpty {
                    report += "## Branches\n"
                    for branch in branches.prefix(10) {
                        report += "- \(branch.stringValue)\n"
                    }
                    report += "\n"
                }

                let analysisPath = artifactDir.appendingPathComponent("git_analysis.txt")
                try report.write(to: analysisPath, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Clean up an exported artifact directory
    func cleanupExportedArtifacts(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            Logger.info("🧹 Cleaned up exported artifacts", category: .ai)
        } catch {
            Logger.warning("⚠️ Failed to cleanup exported artifacts: \(error)", category: .ai)
        }
    }
}
