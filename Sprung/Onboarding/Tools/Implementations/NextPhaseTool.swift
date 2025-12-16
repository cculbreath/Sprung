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
    private static let schema: JSONSchema = PhaseSchemas.phaseTransitionSchema()
    private unowned let coordinator: OnboardingInterviewCoordinator
    private let dataStore: InterviewDataStore
    init(coordinator: OnboardingInterviewCoordinator, dataStore: InterviewDataStore) {
        self.coordinator = coordinator
        self.dataStore = dataStore
    }
    var name: String { OnboardingToolName.nextPhase.rawValue }
    var description: String {
        """
        Skip to the next interview phase. Use this when user wants to skip remaining steps \
        or when stuck. Normal progression uses phase-specific tools (submit_for_validation, \
        configure_enabled_sections, dispatch_kc_agents, etc.). Returns {status, new_phase, \
        skipped_objectives, next_required_tool}.
        """
    }
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
            // VALIDATION: skeleton_timeline MUST have at least one entry before Phase 2
            let timeline = await coordinator.ui.skeletonTimeline
            let experiences = timeline?["experiences"].array ?? []
            if experiences.isEmpty {
                Logger.warning("⚠️ next_phase blocked: skeleton_timeline is empty", category: .ai)
                var response = JSON()
                response["error"].bool = true
                response["reason"].string = "missing_skeleton_timeline"
                response["status"].string = "incomplete"
                response["message"].string = """
                    Cannot advance to Phase 2: No timeline entries exist. \
                    You must create skeleton timeline cards from the user's resume or work history before proceeding. \
                    Use create_timeline_card to add work experience, education, and other entries. \
                    If user uploaded a resume, extract the positions and create cards for each.
                    """
                return .immediate(response)
            }
            Logger.info("✅ skeleton_timeline validated (\(experiences.count) entries) for Phase 1 → Phase 2", category: .ai)
        case .phase2DeepDive:
            nextPhase = .phase3WritingCorpus
            // VALIDATION: Warn if no evidence documents were uploaded
            let artifacts = await dataStore.list(dataType: "artifact")
            let knowledgeCards = await dataStore.list(dataType: "knowledge_card")
            if artifacts.isEmpty && knowledgeCards.isEmpty {
                Logger.warning("⚠️ next_phase warning: no evidence documents or knowledge cards", category: .ai)
                var response = JSON()
                response["status"].string = "incomplete"
                response["warning"].string = "no_evidence_collected"
                response["message"].string = """
                    No evidence documents were uploaded and no knowledge cards were generated. \
                    This will result in generic resume content without specific achievements. \
                    Are you sure you want to proceed to Phase 3? If so, call next_phase again with \
                    confirm_skip=true. Otherwise, use open_document_collection to upload evidence.
                    """
                // Check if user confirmed the skip
                let confirmSkip = params["confirm_skip"].boolValue
                if !confirmSkip {
                    return .immediate(response)
                }
                Logger.info("✅ User confirmed skip to Phase 3 without evidence", category: .ai)
            }
        case .phase3WritingCorpus:
            nextPhase = .complete
            // VALIDATION: experience_defaults MUST be persisted before completing the interview
            let experienceDefaults = await dataStore.list(dataType: "experience_defaults")
            if experienceDefaults.isEmpty {
                Logger.warning("⚠️ next_phase blocked: experience_defaults not persisted", category: .ai)
                var response = JSON()
                response["error"].bool = true
                response["reason"].string = "missing_experience_defaults"
                response["status"].string = "incomplete"
                response["message"].string = """
                    Cannot complete interview: experience_defaults have not been persisted.
                    You MUST call submit_experience_defaults (or persist_data) before calling next_phase.
                    Use the knowledge cards and skeleton timeline to generate structured resume data with:
                    - work: Array of work experience entries from timeline
                    - education: Array of education entries from timeline
                    - projects: Array of project entries (if any)
                    - skills: Array of skill categories extracted from knowledge cards
                    Example: submit_experience_defaults({"work": [...], "education": [...], "skills": [...]})
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
