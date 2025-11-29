//
//  ToolInteractionCoordinator.swift
//  Sprung
//
//  Coordinator that handles all tool UI interactions and presentations.
//  Extracted from OnboardingInterviewCoordinator to reduce complexity.
//
import Foundation
import SwiftyJSON
/// Coordinator responsible for tool UI interactions (uploads, choices, validation, profile intake)
@MainActor
final class ToolInteractionCoordinator {
    // MARK: - Properties
    private let eventBus: EventCoordinator
    private let toolRouter: ToolHandler
    private let dataStore: InterviewDataStore
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        toolRouter: ToolHandler,
        dataStore: InterviewDataStore
    ) {
        self.eventBus = eventBus
        self.toolRouter = toolRouter
        self.dataStore = dataStore
    }
    // MARK: - Tool UI Presentations
    func presentUploadRequest(_ request: OnboardingUploadRequest) {
        Task {
            await eventBus.publish(.uploadRequestPresented(request: request))
        }
    }
    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt) {
        Task {
            await eventBus.publish(.choicePromptRequested(prompt: prompt))
        }
    }
    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt) {
        Task {
            await eventBus.publish(.validationPromptRequested(prompt: prompt))
        }
    }
    // MARK: - Tool Response Handling
    func completeUpload(id: UUID, fileURLs: [URL]) async -> JSON? {
        let result = await toolRouter.completeUpload(id: id, fileURLs: fileURLs)
        Task {
            await eventBus.publish(.uploadRequestCancelled(id: id))
        }
        return result
    }
    func skipUpload(id: UUID) async -> JSON? {
        let result = await toolRouter.skipUpload(id: id)
        Task {
            await eventBus.publish(.uploadRequestCancelled(id: id))
        }
        return result
    }
    func submitChoice(optionId: String) -> JSON? {
        let result = toolRouter.promptHandler.resolveChoice(selectionIds: [optionId])
        if result != nil {
            Task {
                await eventBus.publish(.choicePromptCleared)
            }
        }
        return result
    }
    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) async -> JSON? {
        let pendingValidation = toolRouter.pendingValidationPrompt
        // Special handling for knowledge card persistence
        if let validation = pendingValidation,
           validation.dataType == "knowledge_card",
           let data = updatedData,
           data != .null,
           ["approved", "modified"].contains(status.lowercased()) {
            do {
                _ = try await dataStore.persist(dataType: "knowledge_card", payload: data)
            } catch {
                Logger.error("Failed to persist knowledge card: \\(error)", category: .ai)
            }
            await eventBus.publish(.knowledgeCardPersisted(card: data))
        }
        let result = toolRouter.submitValidationResponse(
            status: status,
            updatedData: updatedData,
            changes: changes,
            notes: notes
        )
        if result != nil {
            Task {
                await eventBus.publish(.validationPromptCleared)
            }
            // Mark skeleton_timeline objective as complete when user confirms validation
            if let validation = pendingValidation,
               validation.dataType == "skeleton_timeline",
               ["confirmed", "confirmed_with_changes", "approved", "modified"].contains(status.lowercased()) {
                await eventBus.publish(.objectiveStatusUpdateRequested(
                    id: "skeleton_timeline",
                    status: "completed",
                    source: "ui_timeline_validated",
                    notes: "Timeline validated by user",
                    details: nil
                ))
                Logger.info("✅ skeleton_timeline objective marked complete after validation", category: .ai)
            }
        }
        return result
    }
    // MARK: - Applicant Profile Intake Facades
    func beginProfileUpload() -> OnboardingUploadRequest {
        toolRouter.beginApplicantProfileUpload()
    }
    func beginProfileURLEntry() {
        toolRouter.beginApplicantProfileURL()
    }
    func beginProfileContactsFetch() {
        toolRouter.beginApplicantProfileContactsFetch()
    }
    func beginProfileManualEntry() {
        toolRouter.beginApplicantProfileManualEntry()
    }
    func resetProfileIntakeToOptions() {
        toolRouter.resetApplicantProfileIntakeToOptions()
    }
}
