import Foundation
import SwiftyJSON
import SwiftOpenAI

struct NextPhaseTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Request advancing to the next onboarding phase, optionally proposing overrides for unmet objectives.",
            properties: [
                "overrides": JSONSchema(
                    type: .array,
                    description: "Objectives the LLM proposes to bypass.",
                    items: JSONSchema(type: .string)
                ),
                "reason": JSONSchema(
                    type: .string,
                    description: "Justification for advancing when overrides are proposed."
                )
            ],
            required: ["overrides"],
            additionalProperties: false
        )
    }()

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "next_phase" }
    var description: String { "Request advancing to the next interview phase." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let overrides = params["overrides"].arrayValue.compactMap { $0.string?.lowercased() }
        let reason = params["reason"].string?.trimmingCharacters(in: .whitespacesAndNewlines)

        let session = await service.currentSession()
        guard let nextPhase = await service.nextPhaseIdentifier() else {
            var response = JSON()
            response["status"].string = "denied"
            response["message"].string = "Interview is already complete."
            return .immediate(response)
        }

        if await service.hasActivePhaseAdvanceRequest() {
            if let awaiting = await service.currentPhaseAdvanceAwaitingPayload() {
                return .immediate(awaiting)
            }
            var response = JSON()
            response["status"].string = "awaiting_user_approval"
            response["missing_objectives"] = JSON(await service.missingObjectives())
            response["message"].string = "User approval dialog already presented."
            return .immediate(response)
        }

        let missing = await service.missingObjectives()
        if let cached = await service.cachedPhaseAdvanceBlockedResponse(missing: missing, overrides: overrides) {
            return .immediate(cached)
        }

        if missing.isEmpty && overrides.isEmpty {
            _ = await service.advancePhase()
            var response = JSON()
            response["status"].string = "approved"
            response["advanced_to"].string = nextPhase.rawValue
            await service.logPhaseAdvanceEvent(
                status: "auto_approved",
                overrides: [],
                missing: [],
                reason: nil,
                userDecision: "approved",
                advancedTo: nextPhase,
                currentPhase: session.phase
            )
            return .immediate(response)
        }

        if missing.isEmpty && !overrides.isEmpty {
            var response = JSON()
            response["status"].string = "blocked"
            response["message"].string = "No overrides required. All objectives are already complete."
            await service.cachePhaseAdvanceBlockedResponse(missing: missing, overrides: overrides, response: response)
            return .immediate(response)
        }

        if overrides.isEmpty {
            var response = JSON()
            response["status"].string = "blocked"
            response["missing_objectives"] = JSON(missing)
            await service.cachePhaseAdvanceBlockedResponse(missing: missing, overrides: overrides, response: response)
            return .immediate(response)
        }

        guard let reason, !reason.isEmpty else {
            var response = JSON()
            response["status"].string = "blocked"
            response["missing_objectives"] = JSON(missing)
            response["message"].string = "Provide a reason when proposing overrides for unmet objectives."
            await service.cachePhaseAdvanceBlockedResponse(missing: missing, overrides: overrides, response: response)
            return .immediate(response)
        }

        let lowerMissing = missing.map { $0.lowercased() }
        let invalidOverrides = overrides.filter { !lowerMissing.contains($0) }
        if !invalidOverrides.isEmpty {
            var response = JSON()
            response["status"].string = "blocked"
            response["missing_objectives"] = JSON(missing)
            response["invalid_overrides"] = JSON(invalidOverrides)
            await service.cachePhaseAdvanceBlockedResponse(missing: missing, overrides: overrides, response: response)
            return .immediate(response)
        }

        let continuationId = UUID()
        let request = OnboardingPhaseAdvanceRequest(
            id: continuationId,
            currentPhase: session.phase,
            nextPhase: nextPhase,
            missingObjectives: missing,
            reason: reason,
            proposedOverrides: overrides
        )

        await service.presentPhaseAdvanceRequest(request, continuationId: continuationId)

        var awaitingPayload = JSON()
        awaitingPayload["status"].string = "awaiting_user_approval"
        awaitingPayload["tool"].string = name
        awaitingPayload["message"].string = "Awaiting user approval to advance to the next phase."
        awaitingPayload["action_required"].string = "phase_advance_decision"
        awaitingPayload["missing_objectives"] = JSON(missing)
        awaitingPayload["proposed_overrides"] = JSON(overrides)
        if !reason.isEmpty {
            awaitingPayload["reason"].string = reason
        }

        let token = ContinuationToken(
            id: continuationId,
            toolName: name,
            initialPayload: awaitingPayload
        ) { payload in
            .immediate(payload)
        }

        return .waiting(
            message: "Awaiting user approval to advance to the next phase.",
            continuation: token
        )
    }
}
