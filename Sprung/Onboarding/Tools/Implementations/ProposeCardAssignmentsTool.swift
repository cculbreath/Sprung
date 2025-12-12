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
        description: "A documentation gap identified by the coordinator",
        properties: [
            "card_id": JSONSchema(
                type: .string,
                description: "UUID of the card with insufficient documentation"
            ),
            "card_title": JSONSchema(
                type: .string,
                description: "Title of the card lacking documentation"
            ),
            "gap_description": JSONSchema(
                type: .string,
                description: "Description of what documentation is missing"
            )
        ],
        required: ["card_id", "card_title", "gap_description"]
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

        // Provide next step instructions
        if gapsJSON.isEmpty {
            response["next_action"].string = """
                All cards have artifact assignments. You may now:
                1. Call dispatch_kc_agents to generate knowledge cards in parallel
                2. Or ask the user if they want to upload additional documents first
                """
        } else {
            response["next_action"].string = """
                Documentation gaps identified. You should:
                1. Present the gaps to the user and ask if they have additional documents
                2. Wait for user response
                3. If user uploads docs, call propose_card_assignments again with updated assignments
                4. When ready, call dispatch_kc_agents to generate cards
                """
        }

        return .immediate(response)
    }
}
