//
//  StartPhaseTwoTool.swift
//  Sprung
//
//  Bootstrap tool for Phase 2 that returns timeline entries and provides
//  explicit instructions for generating the knowledge card plan.
//  Similar to agent_ready for Phase 1, this tool guides the LLM's first actions.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Bootstrap tool for Phase 2 that:
/// 1. Returns all timeline entries from Phase 1
/// 2. Provides explicit instructions for knowledge card generation
/// 3. Mandates calling open_document_collection next (via toolChoice chaining)
struct StartPhaseTwoTool: InterviewTool {
    private static let schema: JSONSchema = PhaseSchemas.startPhaseTwoSchema()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.startPhaseTwo.rawValue }

    var description: String {
        "Bootstrap Phase 2. Returns timeline entries and instructions. MUST be followed by open_document_collection."
    }

    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Get timeline entries from Phase 1
        let timeline = await coordinator.state.artifacts.skeletonTimeline
        let entries = timeline?["experiences"].arrayValue ?? []

        // Extract just the IDs for minimal response
        let entryIds = entries.compactMap { $0["id"].string }

        var result = JSON()
        result["status"].string = "completed"
        result["timeline_entry_count"].int = entries.count
        result["timeline_entry_ids"] = JSON(entryIds)
        result["disable_after_use"].bool = true
        result["next_required_tool"].string = OnboardingToolName.openDocumentCollection.rawValue

        return .immediate(result)
    }
}
