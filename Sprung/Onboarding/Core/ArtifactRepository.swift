import Foundation
import SwiftyJSON

/// Domain service for artifact storage and management.
/// Owns all artifact state including timeline cards, knowledge cards, and uploaded documents.
actor ArtifactRepository: OnboardingEventEmitter {
    // MARK: - Event System

    let eventBus: EventCoordinator

    // MARK: - Artifact Storage

    private var artifacts = OnboardingArtifacts()

    struct OnboardingArtifacts {
        var applicantProfile: JSON?
        var skeletonTimeline: JSON?
        var enabledSections: Set<String> = []
        var experienceCards: [JSON] = []
        var writingSamples: [JSON] = []
        var artifactRecords: [JSON] = []
        var knowledgeCards: [JSON] = [] // Phase 3: Knowledge card storage
    }

    // MARK: - Synchronous Caches (for SwiftUI)

    nonisolated(unsafe) private(set) var artifactRecordsSync: [JSON] = []
    nonisolated(unsafe) private(set) var applicantProfileSync: JSON?
    nonisolated(unsafe) private(set) var skeletonTimelineSync: JSON?
    nonisolated(unsafe) private(set) var enabledSectionsSync: Set<String> = []
    nonisolated(unsafe) private(set) var knowledgeCardsSync: [JSON] = []

    // MARK: - Initialization

    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
        Logger.info("📦 ArtifactRepository initialized", category: .ai)
    }

    // MARK: - Core Artifacts

    /// Set applicant profile artifact
    func setApplicantProfile(_ profile: JSON?) async {
        artifacts.applicantProfile = profile
        applicantProfileSync = profile
        Logger.info("👤 Applicant profile \(profile != nil ? "saved" : "cleared")", category: .ai)

        // Emit event for state coordinator to update objectives
        if profile != nil {
            await emit(.applicantProfileStored(profile: profile!))
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
            await emit(.skeletonTimelineStored(timeline: timeline!))
        }
    }

    /// Get skeleton timeline
    func getSkeletonTimeline() -> JSON? {
        artifacts.skeletonTimeline
    }

    /// Set enabled sections
    func setEnabledSections(_ sections: Set<String>) async {
        artifacts.enabledSections = sections
        enabledSectionsSync = sections
        Logger.info("📑 Enabled sections updated: \(sections.count) sections", category: .ai)

        // Emit event for state coordinator to update objectives
        await emit(.enabledSectionsUpdated(sections: sections))
    }

    /// Get enabled sections
    func getEnabledSections() -> Set<String> {
        artifacts.enabledSections
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
            let targetObjectives = artifact["metadata"]["target_phase_objectives"].arrayValue
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
        await emit(.artifactMetadataUpdated(artifact: artifact))
    }

    /// List artifact summaries (id, filename, size, content_type)
    func listArtifactSummaries() -> [JSON] {
        artifacts.artifactRecords.map { artifact in
            var summary = JSON()
            summary["id"].string = artifact["id"].string ?? artifact["sha256"].string
            summary["filename"].string = artifact["filename"].string
            summary["size_bytes"].int = artifact["size_bytes"].int
            summary["content_type"].string = artifact["content_type"].string
            return summary
        }
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

        // Emit event to notify state coordinator
        await emit(.timelineCardCreated(card: card))
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

        // Emit event to notify state coordinator
        await emit(.timelineCardUpdated(id: id, fields: fields))
    }

    /// Delete a timeline card
    func deleteTimelineCard(id: String) async {
        var (cards, meta) = currentTimelineCards()

        cards.removeAll { $0.id == id }
        artifacts.skeletonTimeline = TimelineCardAdapter.makeTimelineJSON(cards: cards, meta: meta)
        skeletonTimelineSync = artifacts.skeletonTimeline
        Logger.info("📅 Timeline card \(id) deleted", category: .ai)

        // Emit event to notify state coordinator
        await emit(.timelineCardDeleted(id: id))
    }

    /// Reorder timeline cards
    func reorderTimelineCards(orderedIds: [String]) async {
        let (cards, meta) = currentTimelineCards()

        let cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let reordered = orderedIds.compactMap { cardMap[$0] }

        artifacts.skeletonTimeline = TimelineCardAdapter.makeTimelineJSON(cards: reordered, meta: meta)
        skeletonTimelineSync = artifacts.skeletonTimeline
        Logger.info("📅 Timeline cards reordered", category: .ai)

        // Emit event to notify state coordinator
        await emit(.timelineCardsReordered(orderedIds: orderedIds))
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

        // Emit event for state coordinator to mark objective complete
        await emit(.skeletonTimelineReplaced(timeline: timeline, diff: diff, timestamp: Date()))
    }

    // MARK: - Experience & Knowledge Cards

    /// Add experience card
    func addExperienceCard(_ card: JSON) async {
        artifacts.experienceCards.append(card)
        Logger.info("💼 Experience card added (total: \(artifacts.experienceCards.count))", category: .ai)
    }

    /// Get all experience cards
    func getExperienceCards() -> [JSON] {
        artifacts.experienceCards
    }

    /// Add knowledge card
    func addKnowledgeCard(_ card: JSON) async {
        artifacts.knowledgeCards.append(card)
        knowledgeCardsSync = artifacts.knowledgeCards
        Logger.info("🃏 Knowledge card added (total: \(artifacts.knowledgeCards.count))", category: .ai)

        // Emit event for persistence
        await emit(.knowledgeCardPersisted(card: card))
    }

    /// Set knowledge cards (bulk restore)
    func setKnowledgeCards(_ cards: [JSON]) async {
        artifacts.knowledgeCards = cards
        knowledgeCardsSync = cards
        Logger.info("🃏 Knowledge cards loaded (total: \(artifacts.knowledgeCards.count))", category: .ai)
    }

    /// Get all knowledge cards
    func getKnowledgeCards() -> [JSON] {
        artifacts.knowledgeCards
    }

    // MARK: - Writing Samples

    /// Add writing sample
    func addWritingSample(_ sample: JSON) async {
        artifacts.writingSamples.append(sample)
        Logger.info("✍️ Writing sample added (total: \(artifacts.writingSamples.count))", category: .ai)
    }

    /// Get all writing samples
    func getWritingSamples() -> [JSON] {
        artifacts.writingSamples
    }

    // MARK: - Scratchpad Summary

    /// Build artifact summary for LLM scratchpad
    func scratchpadSummary() -> [String] {
        var lines: [String] = []

        lines.append("applicant_profile_status=\(artifacts.applicantProfile == nil ? "missing" : "stored")")
        lines.append("skeleton_timeline_status=\(artifacts.skeletonTimeline == nil ? "missing" : "stored")")

        if !artifacts.enabledSections.isEmpty {
            lines.append("enabled_sections=\(artifacts.enabledSections.sorted().joined(separator: ", "))")
        } else {
            lines.append("enabled_sections=pending")
        }

        if !artifacts.experienceCards.isEmpty {
            lines.append("experience_cards=\(artifacts.experienceCards.count)")
        }

        if !artifacts.writingSamples.isEmpty {
            lines.append("writing_samples=\(artifacts.writingSamples.count)")
        }

        if !artifacts.artifactRecords.isEmpty {
            let hints = artifacts.artifactRecords
                .compactMap { record -> String? in
                    if let purpose = record["metadata"]["purpose"].string, !purpose.isEmpty {
                        return purpose
                    }
                    if let label = record["metadata"]["title"].string, !label.isEmpty {
                        return label
                    }
                    return record["id"].string
                }
            if !hints.isEmpty {
                let preview = hints.prefix(5).joined(separator: ", ")
                lines.append("artifact_hints=\(preview)")
            }
            lines.append("artifact_count=\(artifacts.artifactRecords.count)")
        }

        return lines
    }

    // MARK: - State Management

    /// Reset all artifacts
    func reset() {
        artifacts = OnboardingArtifacts()
        artifactRecordsSync = []
        applicantProfileSync = nil
        skeletonTimelineSync = nil
        enabledSectionsSync = []
        knowledgeCardsSync = []
        Logger.info("🔄 ArtifactRepository reset", category: .ai)
    }
}
