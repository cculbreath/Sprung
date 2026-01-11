//
//  OnboardingDataResetService.swift
//  Sprung
//
//  Service responsible for clearing onboarding interview data.
//  Extracted from OnboardingInterviewCoordinator to follow Single Responsibility Principle.
//

import Foundation

/// Service responsible for clearing all onboarding data when user chooses "Start Over".
/// This clears interview-specific data (session, knowledge cards, skills, CoverRefs, etc.)
/// without performing a full factory reset of the application.
@MainActor
final class OnboardingDataResetService {
    private let sessionPersistenceHandler: SwiftDataSessionPersistenceHandler
    private let knowledgeCardStore: KnowledgeCardStore
    private let skillStore: SkillStore
    private let coverRefStore: CoverRefStore
    private let experienceDefaultsStore: ExperienceDefaultsStore
    private let applicantProfileStore: ApplicantProfileStore
    private let artifactRecordStore: ArtifactRecordStore

    init(
        sessionPersistenceHandler: SwiftDataSessionPersistenceHandler,
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        coverRefStore: CoverRefStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        applicantProfileStore: ApplicantProfileStore,
        artifactRecordStore: ArtifactRecordStore
    ) {
        self.sessionPersistenceHandler = sessionPersistenceHandler
        self.knowledgeCardStore = knowledgeCardStore
        self.skillStore = skillStore
        self.coverRefStore = coverRefStore
        self.experienceDefaultsStore = experienceDefaultsStore
        self.applicantProfileStore = applicantProfileStore
        self.artifactRecordStore = artifactRecordStore
    }

    /// Delete the current SwiftData session
    func deleteCurrentSession() {
        if let session = sessionPersistenceHandler.getActiveSession() {
            sessionPersistenceHandler.deleteSession(session)
        }
    }

    /// Clear all onboarding data: session, knowledge cards, skills, CoverRefs, ExperienceDefaults, and ApplicantProfile.
    /// Used when user chooses "Start Over" to begin fresh.
    /// Writing sample artifacts are deleted while non-writing artifacts are preserved in the archive.
    func clearAllOnboardingData() {
        Logger.info("🗑️ Clearing all onboarding data", category: .ai)

        // Handle artifact cleanup before deleting the session
        // Writing samples are deleted, non-writing artifacts are demoted to archive
        if let session = sessionPersistenceHandler.getActiveSession() {
            cleanupSessionArtifacts(session: session)
        }

        // Delete session
        deleteCurrentSession()

        // Delete onboarding knowledge cards
        knowledgeCardStore.deleteOnboardingCards()

        // Delete onboarding skills
        skillStore.deleteOnboardingSkills()

        // Delete all CoverRefs
        for coverRef in coverRefStore.storedCoverRefs {
            coverRefStore.deleteCoverRef(coverRef)
        }
        Logger.debug("🗑️ Deleted all CoverRefs", category: .ai)

        // Clear ExperienceDefaults
        clearExperienceDefaults()

        // Reset ApplicantProfile to defaults (including photo)
        applicantProfileStore.reset()
        Logger.debug("🗑️ Reset ApplicantProfile", category: .ai)
    }

    /// Clean up session artifacts: delete writing samples, demote others to archive
    private func cleanupSessionArtifacts(session: OnboardingSession) {
        let artifacts = artifactRecordStore.artifacts(for: session)
        var deletedCount = 0
        var archivedCount = 0

        for artifact in artifacts {
            if ArtifactRecordService.isWritingSample(artifact) {
                // Writing samples are deleted on "start over"
                artifactRecordStore.deleteArtifact(artifact)
                deletedCount += 1
            } else {
                // Non-writing artifacts are demoted to archive for reuse
                artifactRecordStore.demoteArtifact(artifact)
                archivedCount += 1
            }
        }

        Logger.info("🗑️ Artifact cleanup: deleted \(deletedCount) writing samples, archived \(archivedCount) documents", category: .ai)
    }

    /// Clear only session-specific data (keep skills/cards for reuse)
    func clearSessionData() {
        Logger.info("🗑️ Clearing session data only", category: .ai)
        deleteCurrentSession()
        Logger.debug("🗑️ Session data cleared", category: .ai)
    }

    // MARK: - Private Helpers

    private func clearExperienceDefaults() {
        let defaults = experienceDefaultsStore.currentDefaults()
        defaults.work.removeAll()
        defaults.education.removeAll()
        defaults.volunteer.removeAll()
        defaults.projects.removeAll()
        defaults.skills.removeAll()
        defaults.awards.removeAll()
        defaults.certificates.removeAll()
        defaults.publications.removeAll()
        defaults.languages.removeAll()
        defaults.interests.removeAll()
        defaults.references.removeAll()
        experienceDefaultsStore.save(defaults)
        experienceDefaultsStore.clearCache()
        Logger.debug("🗑️ Cleared ExperienceDefaults", category: .ai)
    }
}
