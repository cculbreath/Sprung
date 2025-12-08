//
//  NextPhaseTool.swift
//  Sprung
//
//  Requests advancing to the next interview phase.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI
struct NextPhaseTool: InterviewTool {
    private static let schema: JSONSchema = {
        return JSONSchema(
            type: .object,
            description: """
                Request transition to the next interview phase (Phase 1 → Phase 2 → Phase 3 → Complete).
                Transitions immediately. If objectives are incomplete, they are listed in the response.
                RETURNS:
                - { "status": "completed", "previous_phase": "...", "new_phase": "...", "next_required_tool": "start_phase_two" or "start_phase_three" }
                - If objectives incomplete: includes "skipped_objectives" array
                - Already complete: { "status": "completed", "message": "Interview is already complete" }
                - If experience_defaults not persisted (Phase 3 → Complete): { "error": true, "reason": "missing_experience_defaults", ... }
                Phase transitions:
                - Phase 1 (Core Facts) → Phase 2 (Deep Dive) → call start_phase_two next
                - Phase 2 (Deep Dive) → Phase 3 (Writing Corpus) → call start_phase_three next
                - Phase 3 (Writing Corpus) → Complete (REQUIRES experience_defaults to be persisted first)
                IMPORTANT: Before transitioning from Phase 3 to Complete, you MUST call persist_data with dataType="experience_defaults".
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }()
    private unowned let coordinator: OnboardingInterviewCoordinator
    private let dataStore: InterviewDataStore
    init(coordinator: OnboardingInterviewCoordinator, dataStore: InterviewDataStore) {
        self.coordinator = coordinator
        self.dataStore = dataStore
    }
    var name: String { OnboardingToolName.nextPhase.rawValue }
    var description: String { "Transition to the next interview phase. Returns {status, new_phase, next_required_tool}." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        // Check if we can advance to the next phase
        let currentPhase = await coordinator.currentPhase
        let missingObjectives = await coordinator.missingObjectives()
        // Determine the next phase
        let nextPhase: InterviewPhase
        switch currentPhase {
        case .phase1CoreFacts:
            nextPhase = .phase2DeepDive
        case .phase2DeepDive:
            nextPhase = .phase3WritingCorpus
        case .phase3WritingCorpus:
            nextPhase = .complete
            // VALIDATION: experience_defaults MUST be persisted before completing the interview
            let experienceDefaults = await dataStore.list(dataType: "experience_defaults")
            if experienceDefaults.isEmpty {
                Logger.warning("⚠️ next_phase blocked: experience_defaults not persisted", category: .ai)
                var response = JSON()
                response["error"].bool = true
                response["reason"].string = "missing_experience_defaults"
                response["status"].string = "blocked"
                response["message"].string = """
                    Cannot complete interview: experience_defaults have not been persisted.
                    You MUST call persist_data with dataType="experience_defaults" before calling next_phase.
                    Use the knowledge cards and skeleton timeline to generate structured resume data with:
                    - work: Array of work experience entries from timeline
                    - education: Array of education entries from timeline
                    - projects: Array of project entries (if any)
                    - skills: Array of skill categories extracted from knowledge cards
                    Example: persist_data({"dataType": "experience_defaults", "data": {"work": [...], "education": [...], "skills": [...]}})
                    """
                return .immediate(response)
            }
            Logger.info("✅ experience_defaults validated for Phase 3 → Complete transition", category: .ai)
        case .complete:
            var response = JSON()
            response["status"].string = "completed"
            response["message"].string = "Interview is already complete"
            return .immediate(response)
        }
        // Transition immediately, regardless of objectives
        // If objectives are missing, include them in the response so LLM can inform user
        let reason = missingObjectives.isEmpty ? "All objectives completed" : "User requested advancement"
        await coordinator.requestPhaseTransition(
            from: currentPhase.rawValue,
            to: nextPhase.rawValue,
            reason: reason
        )
        var response = JSON()
        response["status"].string = "completed"
        response["previous_phase"].string = currentPhase.rawValue
        response["new_phase"].string = nextPhase.rawValue
        if missingObjectives.isEmpty {
            response["message"].string = "Phase transition completed"
        } else {
            response["message"].string = "Phase transition completed with incomplete objectives"
            response["skipped_objectives"] = JSON(missingObjectives)
        }
        // Chain to the bootstrap tool for the new phase
        if nextPhase == .phase2DeepDive {
            response["next_required_tool"].string = OnboardingToolName.startPhaseTwo.rawValue
        } else if nextPhase == .phase3WritingCorpus {
            response["next_required_tool"].string = OnboardingToolName.startPhaseThree.rawValue
        }
        return .immediate(response)
    }
}
