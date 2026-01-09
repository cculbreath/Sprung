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
final class ArtifactRecordStore {
    /// Weak reference to ModelContext to prevent crashes during container teardown.
    /// Operations gracefully fail if context is deallocated.
    private(set) weak var modelContext: ModelContext?

    init(context: ModelContext) {
        modelContext = context
        Logger.info("ArtifactRecordStore initialized", category: .ai)
    }

    // MARK: - Context Management

    /// Attempts to save the context, handling deallocated context gracefully.
    @discardableResult
    private func saveContext() -> Bool {
        guard let context = modelContext else {
            Logger.warning("ModelContext deallocated, skipping save", category: .storage)
            return false
        }
        do {
            try context.save()
            return true
        } catch {
            Logger.error("SwiftData save failed: \(error.localizedDescription)", category: .storage)
            return false
        }
    }

    // MARK: - Read Operations

    /// All artifact records (computed, always fresh from SwiftData)
    var allArtifacts: [ArtifactRecord] {
        guard let modelContext else { return [] }
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
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<ArtifactRecord>(
            predicate: #Predicate { $0.session == nil },
            sortBy: [SortDescriptor(\.ingestedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Find artifact by UUID
    func artifact(byId id: UUID) -> ArtifactRecord? {
        guard let modelContext else { return nil }
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
        guard let modelContext else { return nil }
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
        guard let modelContext else {
            Logger.warning("ModelContext deallocated, cannot insert artifact", category: .ai)
            return record
        }
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
        guard let modelContext else {
            Logger.warning("ModelContext deallocated, cannot insert standalone artifact", category: .ai)
            return record
        }
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

        guard let modelContext else {
            Logger.warning("ModelContext deallocated, cannot delete artifact", category: .ai)
            return
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
            guard let modelContext else { return [] }
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
            guard let modelContext else { return [] }
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
            guard let modelContext else { return [] }
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
            guard let modelContext else { return [] }
            let descriptor = FetchDescriptor<ArtifactRecord>(
                sortBy: [SortDescriptor(\.ingestedAt, order: .reverse)]
            )
            let all = (try? modelContext.fetch(descriptor)) ?? []
            return all.filter { $0.hasNarrativeCards }
        }
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
