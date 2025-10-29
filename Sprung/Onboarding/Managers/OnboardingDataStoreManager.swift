//
//  OnboardingDataStoreManager.swift
//  Sprung
//
//  Centralized persistence for onboarding interview artifacts.
//  Owns applicant profile, skeleton timeline, artifact records, and knowledge cards.
//

import Foundation
import Observation
import SwiftyJSON

@MainActor
@Observable
final class OnboardingDataStoreManager {
    // MARK: - Observable State

    private(set) var artifacts = OnboardingArtifacts()
    private(set) var applicantProfileJSON: JSON?
    private(set) var skeletonTimelineJSON: JSON?

    // MARK: - Dependencies

    private let applicantProfileStore: ApplicantProfileStore
    private let dataStore: InterviewDataStore

    // MARK: - Init

    init(
        applicantProfileStore: ApplicantProfileStore,
        dataStore: InterviewDataStore
    ) {
        self.applicantProfileStore = applicantProfileStore
        self.dataStore = dataStore
    }

    // MARK: - Applicant Profile

    /// Stores the applicant profile JSON and syncs it to SwiftData.
    func storeApplicantProfile(_ json: JSON) {
        applicantProfileJSON = json
        let draft = ApplicantProfileDraft(json: json)
        let profile = applicantProfileStore.currentProfile()
        draft.apply(to: profile, replaceMissing: false)
        applicantProfileStore.save(profile)
        artifacts.applicantProfile = json

        Logger.debug("📝 ApplicantProfile stored: \(json.dictionaryValue.keys.joined(separator: ", "))", category: .ai)
    }

    /// Updates the applicant profile image and syncs to SwiftData.
    func storeApplicantProfileImage(data: Data, mimeType: String?) {
        let profile = applicantProfileStore.currentProfile()
        profile.pictureData = data
        profile.pictureMimeType = mimeType
        applicantProfileStore.save(profile)

        var json = applicantProfileJSON ?? JSON()
        json["image"].string = data.base64EncodedString()
        if let mimeType {
            json["image_mime_type"].string = mimeType
        }
        applicantProfileJSON = json
        artifacts.applicantProfile = json

        Logger.debug("📸 Applicant profile image updated (\(data.count) bytes, mime: \(mimeType ?? "unknown"))", category: .ai)
    }

    // MARK: - Skeleton Timeline

    /// Stores the skeleton timeline JSON.
    func storeSkeletonTimeline(_ json: JSON) {
        skeletonTimelineJSON = json
        artifacts.skeletonTimeline = json

        Logger.debug("📅 Skeleton timeline stored", category: .ai)
    }

    // MARK: - Artifact Records

    /// Stores an artifact record, deduplicating by SHA256 if present.
    func storeArtifactRecord(_ artifact: JSON) {
        guard artifact != .null else { return }

        if let sha = artifact["sha256"].string {
            artifacts.artifactRecords.removeAll { $0["sha256"].stringValue == sha }
        }
        artifacts.artifactRecords.append(artifact)

        Logger.debug("📦 Artifact record stored (sha256: \(artifact["sha256"].stringValue))", category: .ai)
    }

    // MARK: - Knowledge Cards

    /// Stores a knowledge card, deduplicating by ID if present.
    func storeKnowledgeCard(_ card: JSON) {
        guard card != .null else { return }

        if let identifier = card["id"].string, !identifier.isEmpty {
            artifacts.knowledgeCards.removeAll { $0["id"].stringValue == identifier }
        }
        artifacts.knowledgeCards.append(card)

        Logger.debug("🃏 Knowledge card stored (id: \(card["id"].stringValue))", category: .ai)
    }

    // MARK: - Enabled Sections

    /// Updates the enabled sections list.
    func updateEnabledSections(_ sections: [String]) {
        artifacts.enabledSections = sections
        Logger.debug("🧩 Enabled sections updated: \(sections.joined(separator: ", "))", category: .ai)
    }

    // MARK: - Lifecycle

    /// Loads persisted artifacts from the data store.
    func loadPersistedArtifacts() async {
        // Load artifact records
        let records = await dataStore.list(dataType: "artifact_record")
        var deduped: [JSON] = []
        var seen: Set<String> = []
        for record in records {
            if let sha = record["sha256"].string, !sha.isEmpty {
                if seen.contains(sha) { continue }
                seen.insert(sha)
            }
            deduped.append(record)
        }
        artifacts.artifactRecords = deduped

        // Load knowledge cards
        let storedKnowledgeCards = await dataStore.list(dataType: "knowledge_card")
        artifacts.knowledgeCards = storedKnowledgeCards

        Logger.debug("📂 Loaded \(deduped.count) artifact records, \(storedKnowledgeCards.count) knowledge cards", category: .ai)
    }

    /// Clears all artifact state (for interview reset).
    func clearArtifacts() {
        applicantProfileJSON = nil
        skeletonTimelineJSON = nil
        artifacts.applicantProfile = nil
        artifacts.skeletonTimeline = nil
        artifacts.artifactRecords = []
        artifacts.enabledSections = []
        artifacts.knowledgeCards = []

        Logger.debug("🗑️ All artifacts cleared", category: .ai)
    }

    /// Removes all persisted onboarding data from disk.
    func resetStore() async {
        await dataStore.reset()
        Logger.debug("🧹 Interview data store cleared", category: .ai)
    }
}
