//
//  VoiceProfileExtractionHandler.swift
//  Sprung
//
//  Listens for voice primer objective updates and extracts voice profile.
//

import Foundation
import SwiftyJSON

/// Handles voice profile extraction when writing samples are collected.
@MainActor
final class VoiceProfileExtractionHandler {
    private let eventBus: EventCoordinator
    private let voiceProfileService: VoiceProfileService
    private let guidanceStore: InferenceGuidanceStore
    private let artifactRecordStore: ArtifactRecordStore
    private let sessionPersistenceHandler: SwiftDataSessionPersistenceHandler
    private let agentActivityTracker: AgentActivityTracker
    private let conversationLog: ConversationLog

    private var extractionTask: Task<Void, Never>?
    private var subscriptionTask: Task<Void, Never>?
    private var agentId: String?

    init(
        eventBus: EventCoordinator,
        voiceProfileService: VoiceProfileService,
        guidanceStore: InferenceGuidanceStore,
        artifactRecordStore: ArtifactRecordStore,
        sessionPersistenceHandler: SwiftDataSessionPersistenceHandler,
        agentActivityTracker: AgentActivityTracker,
        conversationLog: ConversationLog
    ) {
        self.eventBus = eventBus
        self.voiceProfileService = voiceProfileService
        self.guidanceStore = guidanceStore
        self.artifactRecordStore = artifactRecordStore
        self.sessionPersistenceHandler = sessionPersistenceHandler
        self.agentActivityTracker = agentActivityTracker
        self.conversationLog = conversationLog
        start()
    }

    func start() {
        guard subscriptionTask == nil else { return }
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            for await event in await eventBus.stream(topic: .objective) {
                await handleObjectiveEvent(event)
            }
        }
        Logger.info("🎤 VoiceProfileExtractionHandler subscribed to objective events", category: .ai)
    }

    private func handleObjectiveEvent(_ event: OnboardingEvent) async {
        guard case .objective(.statusChanged(
            let id,
            _,
            let newStatus,
            _,
            _,
            _,
            _
        )) = event else {
            return
        }

        guard id == OnboardingObjectiveId.voicePrimersExtracted.rawValue,
              newStatus == ObjectiveStatus.inProgress.rawValue else {
            return
        }

        await triggerExtraction()
    }

    /// Manually trigger voice profile extraction (e.g., from debug UI)
    func triggerExtraction() async {
        if let agentId = agentId {
            agentActivityTracker.markFailed(agentId: agentId, error: "Superseded by new extraction")
        }
        extractionTask?.cancel()

        let samples = gatherWritingSamples()
        let trackerId = agentActivityTracker.trackAgent(
            type: .voiceProfile,
            name: "Voice Profile",
            task: nil as Task<Void, Never>?
        )
        agentId = trackerId
        agentActivityTracker.updateStatusMessage(
            agentId: trackerId,
            message: "Analyzing \(samples.count) writing sample(s)"
        )
        agentActivityTracker.appendTranscript(
            agentId: trackerId,
            entryType: .system,
            content: "Voice profile extraction started",
            details: "samples: \(samples.count)"
        )

        extractionTask = Task { [weak self] in
            guard let self else { return }
            do {
                await eventBus.publish(.artifact(.voicePrimerExtractionStarted(sampleCount: samples.count)))

                guard !samples.isEmpty else {
                    Logger.warning("🎤 No writing samples found, using default profile", category: .ai)
                    let defaultProfile = VoiceProfile()
                    voiceProfileService.storeVoiceProfile(defaultProfile, in: guidanceStore)
                    await markObjectiveComplete()
                    agentActivityTracker.appendTranscript(
                        agentId: trackerId,
                        entryType: .assistant,
                        content: "No writing samples available; stored default voice profile"
                    )
                    agentActivityTracker.markCompleted(agentId: trackerId)
                    return
                }

                let profile = try await voiceProfileService.extractVoiceProfile(from: samples)
                voiceProfileService.storeVoiceProfile(profile, in: guidanceStore)

                if let data = try? JSONEncoder().encode(profile),
                   let json = try? JSON(data: data) {
                    await eventBus.publish(.artifact(.voicePrimerExtractionCompleted(primer: json)))
                }

                await markObjectiveComplete()
                await notifyLLMOfCompletion(profile: profile)
                Logger.info("🎤 Voice profile extraction complete", category: .ai)
                agentActivityTracker.appendTranscript(
                    agentId: trackerId,
                    entryType: .assistant,
                    content: "Voice profile extracted and stored"
                )
                agentActivityTracker.markCompleted(agentId: trackerId)

            } catch {
                Logger.error("🎤 Voice profile extraction failed: \(error.localizedDescription)", category: .ai)
                await eventBus.publish(.artifact(.voicePrimerExtractionFailed(error: error.localizedDescription)))

                let defaultProfile = VoiceProfile()
                voiceProfileService.storeVoiceProfile(defaultProfile, in: guidanceStore)
                await markObjectiveComplete()
                agentActivityTracker.markFailed(agentId: trackerId, error: error.localizedDescription)
            }
        }
        if let task = extractionTask {
            agentActivityTracker.setTask(task, forAgentId: trackerId)
        }
    }

    private func gatherWritingSamples() -> [String] {
        guard let session = sessionPersistenceHandler.currentSession else {
            Logger.warning("🎤 No active session found for voice extraction", category: .ai)
            return []
        }

        let artifacts = artifactRecordStore.artifacts(for: session)
            .filter { $0.isWritingSample }

        return artifacts.compactMap { artifact in
            let content = artifact.extractedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        }
    }

    private func markObjectiveComplete() async {
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.voicePrimersExtracted.rawValue,
            status: ObjectiveStatus.completed.rawValue,
            source: "voice_profile_handler",
            notes: "Voice profile extracted and stored",
            details: nil
        )))
    }

    /// Notify the LLM of voice profile completion and request phase transition
    private func notifyLLMOfCompletion(profile: VoiceProfile) async {
        // Add system note to conversation for user visibility
        await conversationLog.appendSystemNote("📤 Voice profile analysis complete - notifying onboarding agent")

        // Build coordinator message with profile summary
        let profileSummary = buildProfileSummary(profile)
        let coordinatorText = """
        Voice profile extraction has completed successfully. The user's writing style has been analyzed and stored.

        \(profileSummary)

        Writing sample collection is complete. Please call next_phase to transition to Phase 2 where we will build the user's professional profile.
        """

        let payload = JSON(["text": coordinatorText])
        await eventBus.publish(.llm(.executeCoordinatorMessage(payload: payload)))
        Logger.info("🎤 Sent voice profile coordinator message to LLM", category: .ai)
    }

    private func buildProfileSummary(_ profile: VoiceProfile) -> String {
        var parts: [String] = []

        parts.append("Enthusiasm: \(profile.enthusiasm.rawValue)")
        parts.append("First person: \(profile.useFirstPerson ? "yes" : "no")")
        parts.append("Connective style: \(profile.connectiveStyle)")

        if !profile.aspirationalPhrases.isEmpty {
            parts.append("Aspirational phrases: \(profile.aspirationalPhrases.joined(separator: ", "))")
        }
        if !profile.avoidPhrases.isEmpty {
            parts.append("Phrases to avoid: \(profile.avoidPhrases.joined(separator: ", "))")
        }

        return "Voice profile summary:\n- " + parts.joined(separator: "\n- ")
    }
}
