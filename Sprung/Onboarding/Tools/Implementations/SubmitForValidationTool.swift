//
//  SubmitForValidationTool.swift
//  Sprung
//
//  Submits data for validation by the user.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI
struct SubmitForValidationTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "validationType": ValidationSchemas.validationType,
            "data": ValidationSchemas.dataPayload,
            "summary": ValidationSchemas.summary
        ]
        return JSONSchema(
            type: .object,
            properties: properties,
            required: ["validationType", "data", "summary"]
        )
    }()
    private weak var coordinator: OnboardingInterviewCoordinator?
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.submitForValidation.rawValue }
    var description: String {
        """
        Present FINAL APPROVAL card with Confirm/Reject buttons. Blocks tools until user responds. \
        Call at sub-phase end AFTER data collection complete. \
        RETURNS: { "message": "UI presented...", "status": "completed" } - user response arrives as new message. \
        validation_types: applicant_profile, skeleton_timeline (data auto-fetched), enabled_sections, \
        knowledge_card, candidate_dossier, experience_defaults (data auto-fetched), section_cards (data auto-fetched). \
        For timeline: call display_timeline_entries_for_review FIRST, then this tool. \
        For section_cards: call display_section_cards_for_review FIRST, then this tool. \
        User can Confirm, Reject, or Submit Changes Only (then re-submit). \
        DO NOT re-validate already confirmed data.
        """
    }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        var payload = try ValidationPayload(json: params)
        // Auto-fetch current data from coordinator for certain validation types
        if payload.validationType == OnboardingDataType.skeletonTimeline.rawValue {
            // Gate: user must have clicked "Done with Timeline" in the editor
            let editorStatus = await coordinator.state.getObjectiveStatus(
                OnboardingObjectiveId.timelineEnriched.rawValue
            )
            guard editorStatus == .completed else {
                var response = JSON()
                response["error"].string = "User has not completed timeline editing"
                response["message"].string = """
                    Cannot submit timeline for validation yet. The user must click "Done with Timeline" \
                    in the timeline editor before validation can proceed. Wait for the user to signal \
                    they are finished editing.
                    """
                response["status"].string = "waiting_for_user"
                return .immediate(response)
            }
            // Use the coordinator's current skeleton timeline as the data payload
            let currentTimeline = await MainActor.run {
                coordinator.ui.skeletonTimeline ?? JSON()
            }
            payload = ValidationPayload(
                validationType: payload.validationType,
                data: currentTimeline,
                summary: payload.summary
            )
        } else if payload.validationType == OnboardingDataType.experienceDefaults.rawValue {
            // Use the coordinator's current ExperienceDefaultsDraft as the data payload.
            // Data is optional for this type; we always auto-fetch to ensure consistency.
            let currentDefaults = await coordinator.currentExperienceDefaultsForValidation()
            payload = ValidationPayload(
                validationType: payload.validationType,
                data: currentDefaults,
                summary: payload.summary
            )
        } else if payload.validationType == OnboardingDataType.sectionCards.rawValue {
            // Auto-fetch section cards (awards, languages, references) and publication cards
            let sectionCardsData = await MainActor.run {
                var data = JSON()

                // Convert section cards to JSON using Codable
                let sectionCardsJSON: [JSON] = coordinator.ui.sectionCards.compactMap { card in
                    guard let jsonData = try? JSONEncoder().encode(card),
                          let jsonObject = try? JSON(data: jsonData) else {
                        return nil
                    }
                    return jsonObject
                }
                data["sectionCards"] = JSON(sectionCardsJSON)

                // Convert publication cards to JSON using Codable
                let publicationCardsJSON: [JSON] = coordinator.ui.publicationCards.compactMap { card in
                    guard let jsonData = try? JSONEncoder().encode(card),
                          let jsonObject = try? JSON(data: jsonData) else {
                        return nil
                    }
                    return jsonObject
                }
                data["publicationCards"] = JSON(publicationCardsJSON)

                return data
            }
            payload = ValidationPayload(
                validationType: payload.validationType,
                data: sectionCardsData,
                summary: payload.summary
            )
        }
        // Emit UI request to show the validation prompt
        await coordinator.eventBus.publish(.toolpane(.validationPromptRequested(prompt: payload.toValidationPrompt())))
        // Block until user completes the action or interrupts
        let result = await coordinator.uiToolContinuationManager.awaitUserAction(toolName: name)
        return .immediate(result.toJSON())
    }
}
private struct ValidationPayload {
    let validationType: String
    let data: JSON
    let summary: String
    init(json: JSON) throws {
        guard let type = json["validationType"].string, !type.isEmpty else {
            throw ToolError.invalidParameters("validationType must be provided")
        }
        let validTypes: [OnboardingDataType] = [.applicantProfile, .skeletonTimeline, .enabledSections, .knowledgeCard, .candidateDossier, .experienceDefaults, .sectionCards]
        let validTypeStrings = validTypes.map(\.rawValue)
        guard validTypeStrings.contains(type) else {
            throw ToolError.invalidParameters("validationType must be one of: \(validTypeStrings.joined(separator: ", "))")
        }
        self.validationType = type
        // For skeleton_timeline, experience_defaults, section_cards: data is optional (auto-fetched)
        // For other types, data must be provided
        let autoFetchTypes: Set<String> = [
            OnboardingDataType.skeletonTimeline.rawValue,
            OnboardingDataType.experienceDefaults.rawValue,
            OnboardingDataType.sectionCards.rawValue
        ]
        if autoFetchTypes.contains(type) {
            self.data = json["data"]
        } else {
            guard let data = json["data"].dictionary, !data.isEmpty else {
                throw ToolError.invalidParameters("Missing required 'data' parameter. For \(type) validation, you must include the complete data object to validate. Example: {\"validationType\": \"\(type)\", \"data\": {...your content...}, \"summary\": \"...\"}")
            }
            self.data = json["data"]
        }
        guard let summary = json["summary"].string, !summary.isEmpty else {
            throw ToolError.invalidParameters("summary must be provided")
        }
        self.summary = summary
    }
    // Direct initializer for creating payload with explicit values
    init(validationType: String, data: JSON, summary: String) {
        self.validationType = validationType
        self.data = data
        self.summary = summary
    }
    func toValidationPrompt() -> OnboardingValidationPrompt {
        OnboardingValidationPrompt(
            dataType: validationType,
            payload: data,
            message: summary
        )
    }
}
