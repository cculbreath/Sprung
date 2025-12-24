//
//  ProposeCardAssignmentsTool.swift
//  Sprung
//
//  Tool for the main coordinator to propose card-to-document assignments.
//  Maps timeline entries to artifact sources and identifies documentation gaps.
//
//  Supports auto-assignment mode to minimize LLM data construction.
//  Part of Milestone 6: ID-based updates
//

import Foundation
import SwiftyJSON

/// Tool that allows the coordinator to map documents to knowledge cards.
/// Supports auto-assignment mode for efficient ID-based workflows.
struct ProposeCardAssignmentsTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Map artifacts to knowledge cards. Use auto_assign=true for system auto-assignment, or manual mode for adjustments.",
            properties: [
                "auto_assign": JSONSchema(
                    type: .boolean,
                    description: "If true, system auto-assigns based on artifact metadata. Recommended for initial assignment."
                ),
                "assignments": KnowledgeCardSchemas.assignmentsArray,
                "gaps": KnowledgeCardSchemas.gapsArray,
                "summary": KnowledgeCardSchemas.proposalSummary
            ],
            required: [],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.proposeCardAssignments.rawValue }

    var description: String {
        "Map artifacts to knowledge cards and identify documentation gaps"
    }

    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let autoAssign = params["auto_assign"].bool ?? false

        // Auto-assignment mode: system generates assignments from state
        if autoAssign {
            return try await executeAutoAssign()
        }

        // Manual mode: use provided assignments
        let assignmentsJSON = params["assignments"].arrayValue
        let gapsJSON = params["gaps"].arrayValue
        _ = params["summary"].stringValue  // Summary included in response

        Logger.info("📋 ProposeCardAssignmentsTool: \(assignmentsJSON.count) assignments, \(gapsJSON.count) gaps (manual mode)", category: .ai)

        // Validate assignments have at least one artifact
        var validAssignments: [JSON] = []
        var assignmentsWithoutArtifacts: [String] = []

        for assignment in assignmentsJSON {
            let artifactIds = assignment["artifact_ids"].arrayValue
            let cardTitle = assignment["card_title"].stringValue

            if artifactIds.isEmpty {
                assignmentsWithoutArtifacts.append(cardTitle)
            } else {
                validAssignments.append(assignment)
            }
        }

        // Store assignments in session state for later use by dispatch_kc_agents
        var proposalsToStore = JSON([])
        for assignment in validAssignments {
            var proposal = JSON()
            proposal["card_id"].string = assignment["card_id"].stringValue
            proposal["card_type"].string = assignment["card_type"].stringValue
            proposal["title"].string = assignment["card_title"].stringValue
            proposal["timeline_entry_id"].string = assignment["timeline_entry_id"].string
            proposal["assigned_artifact_ids"].arrayObject = assignment["artifact_ids"].arrayValue.map { $0.stringValue }
            proposal["notes"].string = assignment["notes"].string
            proposalsToStore.arrayObject?.append(proposal.dictionaryObject ?? [:])
        }

        // Store proposals in state for dispatch_kc_agents to use
        await coordinator.state.storeCardProposals(proposalsToStore)

        // Gate dispatch_kc_agents until user approves assignments
        await coordinator.state.excludeTool(OnboardingToolName.dispatchKCAgents.rawValue)

        // Emit event for UI/coordinator awareness
        await coordinator.eventBus.publish(.cardAssignmentsProposed(
            assignmentCount: validAssignments.count,
            gapCount: gapsJSON.count
        ))

        // Build response
        var response = JSON()
        response["status"].string = "completed"
        response["valid_assignment_count"].int = validAssignments.count
        response["gap_count"].int = gapsJSON.count

        if !assignmentsWithoutArtifacts.isEmpty {
            response["assignments_without_artifacts"].arrayObject = assignmentsWithoutArtifacts
            response["warning"].string = "\(assignmentsWithoutArtifacts.count) cards have no artifacts assigned"
        }

        // Include gaps for user notification
        if !gapsJSON.isEmpty {
            response["gaps"] = JSON(gapsJSON)
            response["has_gaps"].bool = true
        } else {
            response["has_gaps"].bool = false
        }

        // Signal that user validation is required before dispatch
        response["requires_user_validation"].bool = true
        response["validation_message"].string = buildValidationMessage(
            assignmentCount: validAssignments.count,
            gapCount: gapsJSON.count,
            assignmentsWithoutArtifacts: assignmentsWithoutArtifacts
        )

        // Provide next step instructions
        response["next_action"].string = buildNextActionInstructions(hasGaps: !gapsJSON.isEmpty)

        return .immediate(response)
    }

    // MARK: - Auto-Assignment Mode

    /// Execute auto-assignment: system matches artifacts to timeline entries
    /// Returns compact summary instead of requiring LLM to construct arrays
    private func executeAutoAssign() async throws -> ToolResult {
        Logger.info("📋 ProposeCardAssignmentsTool: Auto-assignment mode", category: .ai)

        // Get timeline entries
        let artifacts = await coordinator.state.artifacts
        guard let timeline = artifacts.skeletonTimeline,
              let entries = timeline["experiences"].array, !entries.isEmpty else {
            var error = JSON()
            error["status"].string = "error"
            error["message"].string = "No timeline entries found. Complete Phase 1 first."
            return .immediate(error)
        }

        // Get artifact summaries
        let summaries = await coordinator.artifactQueries.listArtifactSummaries()

        // Auto-generate card proposals from timeline entries
        var proposals = JSON([])
        var gaps: [JSON] = []
        var totalArtifactsAssigned = 0

        for entry in entries {
            guard let entryId = entry["id"].string else { continue }

            let cardId = UUID().uuidString
            let org = entry["organization"].string ?? "Unknown"
            let title = entry["title"].string ?? "Position"
            let cardTitle = "\(title) at \(org)"

            // Find matching artifacts by organization name or entry ID reference
            let matchingArtifactIds = findMatchingArtifacts(
                for: entry,
                from: summaries
            )

            var proposal = JSON()
            proposal["card_id"].string = cardId
            proposal["card_type"].string = "job"
            proposal["title"].string = cardTitle
            proposal["timeline_entry_id"].string = entryId
            proposal["assigned_artifact_ids"].arrayObject = matchingArtifactIds.map { $0 as Any }

            proposals.arrayObject?.append(proposal.dictionaryObject ?? [:])
            totalArtifactsAssigned += matchingArtifactIds.count

            // Track gaps (cards with no artifacts)
            if matchingArtifactIds.isEmpty {
                var gap = JSON()
                gap["card_id"].string = cardId
                gap["card_title"].string = cardTitle
                gap["recommended_doc_types"].arrayObject = ["resume", "performance review", "project docs"]
                gap["example_prompt"].string = "Do you have any documents from your time at \(org)?"
                gaps.append(gap)
            }
        }

        // Store proposals for dispatch_kc_agents
        await coordinator.state.storeCardProposals(proposals)

        // Gate dispatch_kc_agents until user approves
        await coordinator.state.excludeTool(OnboardingToolName.dispatchKCAgents.rawValue)

        // Emit event for UI
        await coordinator.eventBus.publish(.cardAssignmentsProposed(
            assignmentCount: proposals.count,
            gapCount: gaps.count
        ))

        // Build compact response (no full arrays)
        var response = JSON()
        response["status"].string = "completed"
        response["mode"].string = "auto"
        response["card_count"].int = proposals.count
        response["total_artifacts_assigned"].int = totalArtifactsAssigned
        response["gap_count"].int = gaps.count
        response["has_gaps"].bool = !gaps.isEmpty

        // Compact card index (IDs only)
        var cardIndex: [[String: Any]] = []
        for proposal in proposals.arrayValue {
            cardIndex.append([
                "card_id": proposal["card_id"].stringValue,
                "title": proposal["title"].stringValue,
                "artifact_count": proposal["assigned_artifact_ids"].arrayValue.count
            ])
        }
        response["card_index"].arrayObject = cardIndex

        // Gap summaries if any
        if !gaps.isEmpty {
            response["gap_titles"].arrayObject = gaps.map { $0["card_title"].stringValue as Any }
        }

        response["requires_user_validation"].bool = true
        response["next_action"].string = gaps.isEmpty
            ? "Present summary to user. When approved, call dispatch_kc_agents with no arguments."
            : "Present summary and gaps to user. May need additional docs before dispatch."

        return .immediate(response)
    }

    /// Find artifacts that match a timeline entry based on metadata
    private func findMatchingArtifacts(for entry: JSON, from summaries: [JSON]) -> [String] {
        let org = entry["organization"].string?.lowercased() ?? ""
        let title = entry["title"].string?.lowercased() ?? ""
        let entryId = entry["id"].string ?? ""

        var matchingIds: [String] = []

        for summary in summaries {
            guard let artifactId = summary["id"].string else { continue }

            // Check if artifact references this entry
            let targetObjectives = summary["metadata"]["target_phase_objectives"].arrayValue
            if targetObjectives.contains(where: { $0.stringValue == entryId }) {
                matchingIds.append(artifactId)
                continue
            }

            // Check filename or description for org/title match
            let filename = summary["filename"].string?.lowercased() ?? ""
            let desc = summary["brief_description"].string?.lowercased() ?? summary["summary"].string?.lowercased() ?? ""

            if !org.isEmpty && (filename.contains(org) || desc.contains(org)) {
                matchingIds.append(artifactId)
            } else if !title.isEmpty && (filename.contains(title) || desc.contains(title)) {
                matchingIds.append(artifactId)
            }
        }

        return matchingIds
    }

    // MARK: - UI Messages

    private func buildValidationMessage(
        assignmentCount: Int,
        gapCount: Int,
        assignmentsWithoutArtifacts: [String]
    ) -> String {
        var message = "I've mapped your documents to \(assignmentCount) knowledge card(s)."

        if gapCount > 0 {
            message += " I've identified \(gapCount) area(s) where additional documentation would help."
        }

        if !assignmentsWithoutArtifacts.isEmpty {
            message += " Note: \(assignmentsWithoutArtifacts.count) card(s) have no documents assigned yet."
        }

        message += """


        **Please review the assignments above.** You can:
        - Ask me to reassign documents to different cards
        - Request I add or remove cards from the plan
        - Upload additional documents for any gaps
        - Tell me to proceed when you're satisfied

        When you're ready, say "generate cards" or click the Generate button.
        """

        return message
    }

    private func buildNextActionInstructions(hasGaps: Bool) -> String {
        if hasGaps {
            return "Present gaps to user. Wait for approval before dispatch_kc_agents."
        } else {
            return "Present summary to user. Wait for approval before dispatch_kc_agents."
        }
    }
}
