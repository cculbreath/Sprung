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
    private let dataPersistenceService: DataPersistenceService

    init(
        sessionPersistenceHandler: SwiftDataSessionPersistenceHandler,
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        coverRefStore: CoverRefStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        applicantProfileStore: ApplicantProfileStore,
        artifactRecordStore: ArtifactRecordStore,
        dataPersistenceService: DataPersistenceService
    ) {
        self.sessionPersistenceHandler = sessionPersistenceHandler
        self.knowledgeCardStore = knowledgeCardStore
        self.skillStore = skillStore
        self.coverRefStore = coverRefStore
        self.experienceDefaultsStore = experienceDefaultsStore
        self.applicantProfileStore = applicantProfileStore
        self.artifactRecordStore = artifactRecordStore
        self.dataPersistenceService = dataPersistenceService
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

        // Also delete any archived writing samples (orphaned from previous sessions)
        cleanupArchivedWritingSamples()

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

    /// Clean up any archived writing samples (orphaned from previous sessions)
    private func cleanupArchivedWritingSamples() {
        let archivedArtifacts = artifactRecordStore.archivedArtifacts
        var deletedCount = 0

        for artifact in archivedArtifacts {
            if ArtifactRecordService.isWritingSample(artifact) {
                artifactRecordStore.deleteArtifact(artifact)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            Logger.info("🗑️ Cleaned up \(deletedCount) archived writing sample(s)", category: .ai)
        }
    }

    /// Clear only session-specific data (keep skills/cards for reuse)
    func clearSessionData() {
        Logger.info("🗑️ Clearing session data only", category: .ai)
        deleteCurrentSession()
        Logger.debug("🗑️ Session data cleared", category: .ai)
    }

    // MARK: - Full Debug Reset

    #if DEBUG
    /// Reset all onboarding data including files on disk, profile, artifacts, and interview state.
    /// Used from the debug menu for a complete fresh start.
    func resetAllOnboardingData() async {
        Logger.info("🗑️ Resetting all onboarding data", category: .ai)
        // Delete SwiftData session
        deleteCurrentSession()
        Logger.verbose("✅ SwiftData session deleted", category: .ai)
        await MainActor.run {
            // Delete onboarding knowledge cards
            knowledgeCardStore.deleteOnboardingCards()
            Logger.verbose("✅ Onboarding knowledge cards deleted", category: .ai)

            let profile = applicantProfileStore.currentProfile()
            profile.name = "John Doe"
            profile.email = "applicant@example.com"
            profile.phone = "(555) 123-4567"
            profile.address = "123 Main Street"
            profile.city = "Austin"
            profile.state = "Texas"
            profile.zip = "78701"
            profile.websites = "example.com"
            profile.pictureData = nil
            profile.pictureMimeType = nil
            profile.profiles.removeAll()
            applicantProfileStore.save(profile)
            applicantProfileStore.clearCache()
            Logger.info("✅ ApplicantProfile reset and photo removed", category: .ai)
        }
        await dataPersistenceService.clearArtifacts()
        Logger.info("✅ Upload artifacts cleared", category: .ai)
        let uploadsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Sprung")
            .appendingPathComponent("Onboarding")
            .appendingPathComponent("Uploads")
        if FileManager.default.fileExists(atPath: uploadsDir.path) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: uploadsDir, includingPropertiesForKeys: nil)
                for file in files {
                    try FileManager.default.removeItem(at: file)
                }
                Logger.info("✅ Deleted \(files.count) uploaded files from storage", category: .ai)
            } catch {
                Logger.error("❌ Failed to delete uploaded files: \(error.localizedDescription)", category: .ai)
            }
        }
        await dataPersistenceService.resetStore()
        Logger.info("✅ Interview state reset", category: .ai)
        Logger.info("🎉 All onboarding data has been reset", category: .ai)
    }
    #endif

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
