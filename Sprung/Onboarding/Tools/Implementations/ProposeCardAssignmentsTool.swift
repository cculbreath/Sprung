//
//  ProposeCardAssignmentsTool.swift
//  Sprung
//
//  Tool for the main coordinator to propose card-to-document assignments.
//  Maps timeline entries to artifact sources and identifies documentation gaps.
//

import Foundation
import SwiftyJSON

/// Tool that allows the coordinator to map documents to knowledge cards.
/// The coordinator reviews artifact summaries and proposes which documents
/// should inform which knowledge cards, while identifying documentation gaps.
struct ProposeCardAssignmentsTool: InterviewTool {
    private static let assignmentSchema = JSONSchema(
        type: .object,
        description: "A proposed assignment linking a knowledge card to artifacts",
        properties: [
            "card_id": JSONSchema(
                type: .string,
                description: "Unique UUID for this card"
            ),
            "card_title": JSONSchema(
                type: .string,
                description: "Descriptive title (e.g., 'Senior Engineer at Company X')"
            ),
            "card_type": JSONSchema(
                type: .string,
                description: "Card type: 'job' or 'skill'"
            ),
            "timeline_entry_id": JSONSchema(
                type: .string,
                description: "Optional: ID of the timeline entry this card relates to"
            ),
            "artifact_ids": JSONSchema(
                type: .array,
                description: "Artifact IDs assigned to inform this card",
                items: JSONSchema(type: .string)
            ),
            "notes": JSONSchema(
                type: .string,
                description: "Brief notes explaining why these artifacts were assigned"
            )
        ],
        required: ["card_id", "card_title", "card_type", "artifact_ids"]
    )

    private static let gapSchema = JSONSchema(
        type: .object,
        description: """
            A documentation gap with SPECIFIC recommendations. Do not use generic descriptions.
            For each gap, recommend actual document types the user likely has.
            """,
        properties: [
            "card_id": JSONSchema(
                type: .string,
                description: "UUID of the card with insufficient documentation"
            ),
            "card_title": JSONSchema(
                type: .string,
                description: "Title of the card lacking documentation"
            ),
            "role_category": JSONSchema(
                type: .string,
                description: "Role category: 'engineering', 'management', 'sales', 'product', 'design', 'other'"
            ),
            "recommended_doc_types": JSONSchema(
                type: .array,
                description: """
                    SPECIFIC document types to request. Be concrete, not generic.
                    Good: "performance reviews", "design docs", "job description"
                    Bad: "any documents", "more information"
                    """,
                items: JSONSchema(type: .string)
            ),
            "example_prompt": JSONSchema(
                type: .string,
                description: """
                    Example prompt to show the user. Be specific and helpful.
                    Example: "For your Senior Engineer role at Acme, do you have any performance reviews?
                    Most companies do annual reviews - even informal email summaries would help."
                    """
            ),
            "gap_severity": JSONSchema(
                type: .string,
                description: "'critical' (no artifacts at all), 'moderate' (some artifacts, missing key types), 'minor' (has artifacts, could use more)"
            )
        ],
        required: ["card_id", "card_title", "recommended_doc_types", "example_prompt"]
    )

    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Propose assignments mapping artifacts to knowledge cards.

                WHEN TO CALL:
                After reviewing artifact summaries (from start_phase_two), call this tool to:
                1. Assign artifacts to each planned knowledge card
                2. Identify cards that lack sufficient documentation (gaps)

                WHAT HAPPENS:
                - Assignments are recorded for use by dispatch_kc_agents
                - Gaps trigger a prompt for the user to upload additional documents
                - Returns summary of assignments and next steps

                WORKFLOW:
                1. start_phase_two → receive timeline + artifact summaries
                2. propose_card_assignments → map docs to cards, identify gaps
                3. (optional) User uploads additional docs for gaps
                4. dispatch_kc_agents → parallel card generation
                """,
            properties: [
                "assignments": JSONSchema(
                    type: .array,
                    description: "Card-to-artifact assignments",
                    items: assignmentSchema
                ),
                "gaps": JSONSchema(
                    type: .array,
                    description: "Documentation gaps identified (cards without sufficient artifacts)",
                    items: gapSchema
                ),
                "summary": JSONSchema(
                    type: .string,
                    description: "Brief summary explaining the assignments and any gaps"
                )
            ],
            required: ["assignments", "summary"],
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
        let assignmentsJSON = params["assignments"].arrayValue
        let gapsJSON = params["gaps"].arrayValue
        _ = params["summary"].stringValue  // Summary included in response

        Logger.info("📋 ProposeCardAssignmentsTool: \(assignmentsJSON.count) assignments, \(gapsJSON.count) gaps", category: .ai)

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
            return """
                ⚠️ USER VALIDATION REQUIRED before dispatch_kc_agents.

                1. Present the assignments and gaps to the user using the validation_message
                2. Use the structured gap data to make SPECIFIC document requests
                3. WAIT for user to either:
                   - Upload additional documents (then call propose_card_assignments again)
                   - Request changes to the plan (modify and call propose_card_assignments again)
                   - Confirm they're ready to proceed
                4. DO NOT call dispatch_kc_agents until user explicitly approves

                The user may say "generate cards", "looks good", "proceed", or click a Generate button.
                """
        } else {
            return """
                ✅ All cards have document assignments.

                Present the assignments to the user for review. They may want to:
                - Adjust which documents inform which cards
                - Add or remove cards from the plan
                - Upload additional documents

                WAIT for user confirmation before calling dispatch_kc_agents.
                The user may say "generate cards", "looks good", "proceed", or click a Generate button.
                """
        }
    }
}
