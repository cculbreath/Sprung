//
//  DataPersistenceService.swift
//  Sprung
//
//  Service for managing data persistence and artifact loading.
//  Extracted from OnboardingInterviewCoordinator to reduce complexity.
//

import Foundation
import SwiftyJSON

/// Service that handles data persistence operations
actor DataPersistenceService: OnboardingEventEmitter {
    // MARK: - Properties

    let eventBus: EventCoordinator
    private let state: StateCoordinator
    private let dataStore: InterviewDataStore
    private let applicantProfileStore: ApplicantProfileStore
    private let chatTranscriptStore: ChatTranscriptStore
    private let toolRouter: ToolHandler
    private let wizardTracker: WizardProgressTracker

    // MARK: - Initialization

    init(
        eventBus: EventCoordinator,
        state: StateCoordinator,
        dataStore: InterviewDataStore,
        applicantProfileStore: ApplicantProfileStore,
        chatTranscriptStore: ChatTranscriptStore,
        toolRouter: ToolHandler,
        wizardTracker: WizardProgressTracker
    ) {
        self.eventBus = eventBus
        self.state = state
        self.dataStore = dataStore
        self.applicantProfileStore = applicantProfileStore
        self.chatTranscriptStore = chatTranscriptStore
        self.toolRouter = toolRouter
        self.wizardTracker = wizardTracker
    }

    // MARK: - Artifact Loading

    func loadPersistedArtifacts() async {
        let profileRecords = (await dataStore.list(dataType: "applicant_profile")).filter { $0 != .null }
        let timelineRecords = (await dataStore.list(dataType: "skeleton_timeline")).filter { $0 != .null }
        let artifactRecords = (await dataStore.list(dataType: "artifact_record")).filter { $0 != .null }
        let knowledgeCardRecords = (await dataStore.list(dataType: "knowledge_card")).filter { $0 != .null }

        if let profile = profileRecords.last {
            // Publish event instead of direct state mutation
            await eventBus.publish(.applicantProfileStored(profile))
            await persistApplicantProfileToSwiftData(json: profile)
        }

        if let timeline = timelineRecords.last {
            // Publish event instead of direct state mutation
            await eventBus.publish(.skeletonTimelineStored(timeline))
        }

        if !artifactRecords.isEmpty {
            await state.setArtifactRecords(artifactRecords)
        }

        if !knowledgeCardRecords.isEmpty {
            await state.setKnowledgeCards(knowledgeCardRecords)
        }

        if profileRecords.isEmpty && timelineRecords.isEmpty && artifactRecords.isEmpty && knowledgeCardRecords.isEmpty {
            Logger.info("📂 No persisted artifacts discovered", category: .ai)
        } else {
            Logger.info(
                "📂 Loaded persisted artifacts",
                category: .ai,
                metadata: [
                    "applicant_profile_count": "\(profileRecords.count)",
                    "skeleton_timeline_count": "\(timelineRecords.count)",
                    "artifact_record_count": "\(artifactRecords.count)",
                    "knowledge_card_count": "\(knowledgeCardRecords.count)"
                ]
            )
        }
    }

    // MARK: - Store Management

    func clearArtifacts() async {
        await dataStore.reset()
    }

    func resetStore() async {
        await state.reset()
        await MainActor.run {
            chatTranscriptStore.reset()
            toolRouter.reset()
            wizardTracker.reset()
        }
    }

    // MARK: - Persistence Helpers

    private func persistApplicantProfileToSwiftData(json: JSON) async {
        await MainActor.run {
            let draft = ApplicantProfileDraft(json: json)
            let profile = applicantProfileStore.currentProfile()
            draft.apply(to: profile, replaceMissing: false)
            applicantProfileStore.save(profile)
            Logger.info("💾 Applicant profile persisted to SwiftData", category: .ai)
        }
    }
}