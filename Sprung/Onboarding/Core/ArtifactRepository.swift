import Foundation
import SwiftyJSON
/// Domain service for artifact storage and management.
/// Owns all artifact state including timeline cards, knowledge cards, and uploaded documents.
actor ArtifactRepository: OnboardingEventEmitter {
    // MARK: - Event System
    let eventBus: EventCoordinator
    // MARK: - Artifact Storage
    private var artifacts = OnboardingArtifacts()

    // MARK: - Synchronous Caches (for SwiftUI)
    /// Sync cache for SwiftUI access. Safe because:
    /// 1. Only mutated from actor-isolated methods (this actor's methods)
    /// 2. Only read from @MainActor SwiftUI views
    /// 3. Writes complete before reads occur due to event sequencing
    nonisolated(unsafe) private(set) var artifactRecordsSync: [JSON] = []
    /// Sync cache for skeleton timeline. Safe for same reasons as artifactRecordsSync.
    nonisolated(unsafe) private(set) var skeletonTimelineSync: JSON?
    /// Archived artifacts (from previous sessions, available for reuse).
    /// Sync cache for SwiftUI access. Safe for same reasons as artifactRecordsSync.
    nonisolated(unsafe) private(set) var archivedArtifactsSync: [JSON] = []
    // MARK: - Initialization
    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
        Logger.info("📦 ArtifactRepository initialized", category: .ai)
    }
    /// Get all artifacts snapshot
    func getArtifacts() -> OnboardingArtifacts {
        artifacts
    }
    // MARK: - Core Artifacts
    /// Set applicant profile artifact
    func setApplicantProfile(_ profile: JSON?) async {
        artifacts.applicantProfile = profile
        Logger.info("👤 Applicant profile \(profile != nil ? "saved" : "cleared")", category: .ai)
        // Emit event for state coordinator to update objectives
        if profile != nil {
            await emit(.state(.applicantProfileStored(profile!)))
        }
    }
    /// Get applicant profile
    func getApplicantProfile() -> JSON? {
        artifacts.applicantProfile
    }
    /// Set skeleton timeline artifact
    func setSkeletonTimeline(_ timeline: JSON?) async {
        artifacts.skeletonTimeline = timeline
        skeletonTimelineSync = timeline
        Logger.info("📅 Skeleton timeline \(timeline != nil ? "saved" : "cleared")", category: .ai)
        // Emit event for state coordinator to update objectives
        if timeline != nil {
            await emit(.state(.skeletonTimelineStored(timeline!)))
        }
    }
    /// Get skeleton timeline
    func getSkeletonTimeline() -> JSON? {
        artifacts.skeletonTimeline
    }
    /// Set enabled sections
    func setEnabledSections(_ sections: Set<String>) async {
        artifacts.enabledSections = sections
        Logger.info("📑 Enabled sections updated: \(sections.count) sections", category: .ai)
        // Emit event for state coordinator to update objectives
        await emit(.state(.enabledSectionsUpdated(sections)))
    }
    /// Get enabled sections
    func getEnabledSections() -> Set<String> {
        artifacts.enabledSections
    }

    /// Set custom field definitions
    func setCustomFieldDefinitions(_ definitions: [CustomFieldDefinition]) async {
        artifacts.customFieldDefinitions = definitions
        Logger.info("📋 Custom field definitions updated: \(definitions.count) fields", category: .ai)
    }

    /// Get custom field definitions
    func getCustomFieldDefinitions() -> [CustomFieldDefinition] {
        artifacts.customFieldDefinitions
    }

    // MARK: - Artifact Records
    /// Set artifact records (bulk restore)
    func setArtifactRecords(_ records: [JSON]) {
        artifacts.artifactRecords = records
        artifactRecordsSync = records
        Logger.info("📦 Artifact records restored: \(records.count)", category: .ai)
    }
    /// Add a new artifact record
    func addArtifactRecord(_ artifact: JSON) {
        artifacts.artifactRecords.append(artifact)
        artifactRecordsSync = artifacts.artifactRecords
        Logger.info("📦 Artifact record added: \(artifact["id"].stringValue)", category: .ai)
    }
    /// Get artifact record by ID or SHA256
    func getArtifactRecord(id: String) -> JSON? {
        artifacts.artifactRecords.first { artifact in
            let artifactId = artifact["id"].stringValue
            let sha256 = artifact["sha256"].stringValue
            return artifactId == id || sha256 == id
        }
    }
    /// Query artifacts by target_phase_objective
    func getArtifactsForPhaseObjective(_ objectiveId: String) -> [JSON] {
        artifacts.artifactRecords.filter { artifact in
            let targetObjectives = artifact["metadata"]["targetPhaseObjectives"].arrayValue
            return targetObjectives.contains { $0.stringValue == objectiveId }
        }
    }
    /// Idempotent upsert of artifact record by id or sha256
    func upsertArtifactRecord(_ record: JSON) {
        let id = record["id"].string ?? record["sha256"].string ?? UUID().uuidString
        var replaced = false
        for i in artifacts.artifactRecords.indices {
            let existingId = artifacts.artifactRecords[i]["id"].string ?? artifacts.artifactRecords[i]["sha256"].string
            if existingId == id {
                artifacts.artifactRecords[i] = record
                replaced = true
                break
            }
        }
        if !replaced {
            artifacts.artifactRecords.append(record)
        }
        artifactRecordsSync = artifacts.artifactRecords
    }
    /// Update artifact metadata (field-level merge)
    func updateArtifactMetadata(artifactId: String, updates: JSON) async {
        // Find the artifact by ID
        guard let index = artifacts.artifactRecords.firstIndex(where: { record in
            record["id"].string == artifactId
        }) else {
            Logger.warning("⚠️ Artifact not found for metadata update: \(artifactId)", category: .ai)
            return
        }
        var artifact = artifacts.artifactRecords[index]
        var metadata = artifact["metadata"].dictionaryValue.isEmpty ? JSON() : artifact["metadata"]
        // Merge updates into metadata (field-level)
        for (key, value) in updates.dictionaryValue {
            metadata[key] = value
        }
        // Update artifact with new metadata
        artifact["metadata"] = metadata
        artifacts.artifactRecords[index] = artifact
        artifactRecordsSync = artifacts.artifactRecords
        Logger.info("✅ Artifact metadata updated: \(artifactId) (\(updates.dictionaryValue.keys.count) fields)", category: .ai)
        // Emit confirmation event for persistence
        await emit(.artifact(.metadataUpdated(artifact: artifact)))
    }
    /// List artifact summaries (id, filename, size, contentType, summary)
    /// Used by main coordinator to see all docs at a glance without full text
    func listArtifactSummaries() -> [JSON] {
        artifacts.artifactRecords.map { artifact in
            var summary = JSON()
            summary["id"].string = artifact["id"].string ?? artifact["sha256"].string
            summary["filename"].string = artifact["filename"].string
            summary["sizeBytes"].int = artifact["sizeBytes"].int
            summary["contentType"].string = artifact["contentType"].string
            // Include the brief description if available (short ~10 word description)
            if let briefDesc = artifact["briefDescription"].string, !briefDesc.isEmpty {
                summary["briefDescription"].string = briefDesc
            }
            // Include the summary if available (from summarization step)
            if let docSummary = artifact["summary"].string, !docSummary.isEmpty {
                summary["summary"].string = docSummary
            }
            // Include summaryMetadata (document_type, time_period, companies, roles, skills, etc.)
            if !artifact["summaryMetadata"].dictionaryValue.isEmpty {
                summary["summaryMetadata"] = artifact["summaryMetadata"]
            }
            // Include metadata for additional context
            if let title = artifact["metadata"]["title"].string, !title.isEmpty {
                summary["title"].string = title
            }
            if let purpose = artifact["metadata"]["purpose"].string, !purpose.isEmpty {
                summary["purpose"].string = purpose
            }
            return summary
        }
    }

    /// Delete an artifact record by ID
    /// Returns the deleted artifact (for notification purposes) or nil if not found
    func deleteArtifactRecord(id: String) -> JSON? {
        guard let index = artifacts.artifactRecords.firstIndex(where: { record in
            record["id"].string == id || record["sha256"].string == id
        }) else {
            Logger.warning("⚠️ Artifact not found for deletion: \(id)", category: .ai)
            return nil
        }
        let deleted = artifacts.artifactRecords.remove(at: index)
        artifactRecordsSync = artifacts.artifactRecords
        Logger.info("🗑️ Artifact record deleted: \(deleted["filename"].stringValue)", category: .ai)
        return deleted
    }

    // MARK: - Archived Artifacts Management

    /// Set archived artifacts (loaded from SwiftData)
    /// Called by coordinator to populate the cache on startup
    func setArchivedArtifacts(_ records: [JSON]) {
        archivedArtifactsSync = records
        Logger.info("📦 Archived artifacts loaded: \(records.count)", category: .ai)
    }

    /// Refresh archived artifacts cache
    /// Called after promotion or deletion to update UI
    func refreshArchivedArtifacts(_ records: [JSON]) {
        archivedArtifactsSync = records
        Logger.debug("📦 Archived artifacts refreshed: \(records.count)", category: .ai)
    }

    /// Remove an artifact from the archived cache
    /// Called after promotion (artifact moves to current session)
    func removeFromArchivedCache(id: String) {
        archivedArtifactsSync.removeAll { $0["id"].stringValue == id }
        Logger.debug("📦 Removed from archived cache: \(id)", category: .ai)
    }

    // MARK: - Timeline Card Management
    /// Helper to get current timeline cards using TimelineCardAdapter
    private func currentTimelineCards() -> (cards: [TimelineCard], meta: JSON?) {
        let timelineJSON = artifacts.skeletonTimeline ?? JSON()
        return TimelineCardAdapter.cards(from: TimelineCardAdapter.normalizedTimeline(timelineJSON))
    }
    /// Create a new timeline card
    func createTimelineCard(_ card: JSON) async {
        var (cards, meta) = currentTimelineCards()
        // Create new timeline card
        let newCard: TimelineCard
        if let id = card["id"].string {
            newCard = TimelineCard(id: id, fields: card)
        } else {
            newCard = TimelineCard(id: UUID().uuidString, fields: card)
        }
        cards.append(newCard)
        artifacts.skeletonTimeline = TimelineCardAdapter.makeTimelineJSON(cards: cards, meta: meta)
        skeletonTimelineSync = artifacts.skeletonTimeline
        Logger.info("📅 Timeline card created", category: .ai)
    }
    /// Update an existing timeline card
    func updateTimelineCard(id: String, fields: JSON) async {
        var (cards, meta) = currentTimelineCards()
        guard let idx = cards.firstIndex(where: { $0.id == id }) else {
            Logger.warning("Timeline card \(id) not found for update", category: .ai)
            return
        }
        cards[idx] = cards[idx].applying(fields: fields)
        artifacts.skeletonTimeline = TimelineCardAdapter.makeTimelineJSON(cards: cards, meta: meta)
        skeletonTimelineSync = artifacts.skeletonTimeline
        Logger.info("📅 Timeline card \(id) updated", category: .ai)
    }
    /// Delete a timeline card
    func deleteTimelineCard(id: String) async {
        var (cards, meta) = currentTimelineCards()
        cards.removeAll { $0.id == id }
        artifacts.skeletonTimeline = TimelineCardAdapter.makeTimelineJSON(cards: cards, meta: meta)
        skeletonTimelineSync = artifacts.skeletonTimeline
        Logger.info("📅 Timeline card \(id) deleted", category: .ai)
    }
    /// Reorder timeline cards
    func reorderTimelineCards(orderedIds: [String]) async {
        let (cards, meta) = currentTimelineCards()
        let cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let reordered = orderedIds.compactMap { cardMap[$0] }
        artifacts.skeletonTimeline = TimelineCardAdapter.makeTimelineJSON(cards: reordered, meta: meta)
        skeletonTimelineSync = artifacts.skeletonTimeline
        Logger.info("📅 Timeline cards reordered", category: .ai)
    }
    /// Replace entire skeleton timeline (user edit in UI)
    func replaceSkeletonTimeline(_ timeline: JSON, diff: TimelineDiff?) async {
        artifacts.skeletonTimeline = TimelineCardAdapter.normalizedTimeline(timeline)
        skeletonTimelineSync = artifacts.skeletonTimeline
        if let diff = diff {
            Logger.info("📅 Skeleton timeline replaced by user (\(diff.summary))", category: .ai)
        } else {
            Logger.info("📅 Skeleton timeline replaced by user", category: .ai)
        }
        // DO NOT emit the event here - this method is called IN RESPONSE to the event
        // The TimelineManagementService already published the event that triggered this
    }
    // MARK: - Experience & Knowledge Cards
    /// Get all experience cards
    func getExperienceCards() -> [JSON] {
        artifacts.experienceCards
    }
    /// Add knowledge card
    /// NOTE: This method is called IN RESPONSE to .knowledgeCardPersisted events.
    /// Do NOT emit .knowledgeCardPersisted here - that would create an infinite loop!
    func addKnowledgeCard(_ card: JSON) async {
        artifacts.knowledgeCards.append(card)
        Logger.info("🃏 Knowledge card added (total: \(artifacts.knowledgeCards.count))", category: .ai)
    }
    /// Set knowledge cards (bulk restore)
    func setKnowledgeCards(_ cards: [JSON]) async {
        artifacts.knowledgeCards = cards
        Logger.info("🃏 Knowledge cards loaded (total: \(artifacts.knowledgeCards.count))", category: .ai)
    }
    /// Get all knowledge cards
    func getKnowledgeCards() -> [JSON] {
        artifacts.knowledgeCards
    }

    // MARK: - Writing Samples
    /// Get all writing samples
    func getWritingSamples() -> [JSON] {
        artifacts.writingSamples
    }

    // MARK: - State Management
    /// Reset all artifacts
    func reset() {
        artifacts = OnboardingArtifacts()
        artifactRecordsSync = []
        skeletonTimelineSync = nil
        Logger.info("🔄 ArtifactRepository reset", category: .ai)
    }
}
