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

        // Update UI plan items with artifact assignments
        await updatePlanItemsWithAssignments(proposals: proposalsToStore)

        // Gate dispatch_kc_agents until user approves assignments
        // BUT only if user hasn't already clicked "Generate Cards" (which would have ungated it)
        let isAlreadyGenerating = await MainActor.run { coordinator.ui.isGeneratingCards }
        if !isAlreadyGenerating {
            await coordinator.state.excludeTool(OnboardingToolName.dispatchKCAgents.rawValue)
        } else {
            Logger.info("📋 Skipping dispatch_kc_agents gating - user already approved generation", category: .ai)
        }

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
        response["dispatch_kc_agents_locked"].bool = true
        response["validation_message"].string = buildValidationMessage(
            assignmentCount: validAssignments.count,
            gapCount: gapsJSON.count,
            assignmentsWithoutArtifacts: assignmentsWithoutArtifacts
        )

        // Provide explicit instructions that tool is locked
        response["next_action"].string = """
            IMPORTANT: dispatch_kc_agents is LOCKED until user clicks the "Generate Cards" button in the UI.
            DO NOT call dispatch_kc_agents - it will fail. Present the summary to user and WAIT.
            The system will automatically unlock the tool and prompt you when user approves.
            """

        return .immediate(response)
    }

    // MARK: - Auto-Assignment Mode

    /// Execute auto-assignment using merged card inventory from all documents
    /// Returns compact summary instead of requiring LLM to construct arrays
    private func executeAutoAssign() async throws -> ToolResult {
        Logger.info("📋 ProposeCardAssignmentsTool: Auto-assignment from merged inventory", category: .ai)

        // Get merged card inventory from all documents
        let cardMergeService = await MainActor.run { coordinator.cardMergeService }
        let timeline = await coordinator.state.artifacts.skeletonTimeline

        let mergedInventory: MergedCardInventory
        do {
            mergedInventory = try await cardMergeService.mergeInventories(timeline: timeline)
        } catch {
            Logger.warning("⚠️ Card merge failed: \(error.localizedDescription)", category: .ai)
            var errorResponse = JSON()
            errorResponse["status"].string = "error"
            errorResponse["message"].string = "Failed to merge card inventories: \(error.localizedDescription)"
            return .immediate(errorResponse)
        }

        // Convert merged cards to proposals
        var proposals = JSON([])
        var totalArtifactsAssigned = 0

        for mergedCard in mergedInventory.mergedCards {
            var proposal = JSON()
            proposal["card_id"].string = mergedCard.cardId
            proposal["card_type"].string = mergedCard.cardType
            proposal["title"].string = mergedCard.title

            // Collect all artifact IDs (primary + supporting)
            var artifactIds = [mergedCard.primarySource.documentId]
            artifactIds.append(contentsOf: mergedCard.supportingSources.map { $0.documentId })

            proposal["assigned_artifact_ids"].arrayObject = artifactIds.map { $0 as Any }
            proposal["date_range"].string = mergedCard.dateRange
            proposal["evidence_quality"].string = mergedCard.evidenceQuality.rawValue
            proposal["extraction_priority"].string = mergedCard.extractionPriority.rawValue

            // Include combined facts for context
            proposal["key_facts"].arrayObject = mergedCard.combinedKeyFacts.map { $0 as Any }
            proposal["technologies"].arrayObject = mergedCard.combinedTechnologies.map { $0 as Any }
            proposal["outcomes"].arrayObject = mergedCard.combinedOutcomes.map { $0 as Any }

            proposals.arrayObject?.append(proposal.dictionaryObject ?? [:])
            totalArtifactsAssigned += artifactIds.count
        }

        // Convert gaps from merge service
        var gaps: [JSON] = []
        for gap in mergedInventory.gaps {
            var gapJSON = JSON()
            gapJSON["card_title"].string = gap.cardTitle
            gapJSON["gap_type"].string = gap.gapType.rawValue
            gapJSON["current_evidence"].string = gap.currentEvidence
            gapJSON["recommended_docs"].arrayObject = gap.recommendedDocs.map { $0 as Any }
            gaps.append(gapJSON)
        }

        // Store proposals for dispatch_kc_agents
        await coordinator.state.storeCardProposals(proposals)

        // Update UI plan items with artifact assignments
        await updatePlanItemsFromMergedInventory(mergedInventory: mergedInventory)

        // Gate dispatch_kc_agents until user approves
        // BUT only if user hasn't already clicked "Generate Cards" (which would have ungated it)
        let isAlreadyGenerating = await MainActor.run { coordinator.ui.isGeneratingCards }
        if !isAlreadyGenerating {
            await coordinator.state.excludeTool(OnboardingToolName.dispatchKCAgents.rawValue)
        } else {
            Logger.info("📋 Skipping dispatch_kc_agents gating (auto-assign) - user already approved generation", category: .ai)
        }

        // Emit event for UI
        await coordinator.eventBus.publish(.cardAssignmentsProposed(
            assignmentCount: proposals.count,
            gapCount: gaps.count
        ))

        // Build response in format expected by phase2 prompt
        var response = JSON()
        response["status"].string = "completed"
        response["mode"].string = "merged_inventory"

        // Card counts
        response["card_count"].int = mergedInventory.mergedCards.count
        response["cards_by_type"] = JSON(mergedInventory.stats.cardsByType)
        response["strong_evidence_count"].int = mergedInventory.stats.strongEvidence
        response["needs_more_evidence_count"].int = mergedInventory.stats.needsMoreEvidence

        // Card summaries for LLM review (grouped by type with details)
        var cardsByTypeDetail: [String: [[String: Any]]] = [:]
        for mergedCard in mergedInventory.mergedCards {
            let cardInfo: [String: Any] = [
                "card_id": mergedCard.cardId,
                "title": mergedCard.title,
                "evidence_quality": mergedCard.evidenceQuality.rawValue,
                "source_count": 1 + mergedCard.supportingSources.count,
                "primary_source": mergedCard.primarySource.documentId
            ]
            if cardsByTypeDetail[mergedCard.cardType] == nil {
                cardsByTypeDetail[mergedCard.cardType] = []
            }
            cardsByTypeDetail[mergedCard.cardType]?.append(cardInfo)
        }
        response["cards_by_type_detail"].dictionaryObject = cardsByTypeDetail as [String: Any]

        // Gaps for follow-up
        if !mergedInventory.gaps.isEmpty {
            response["gaps"].arrayObject = mergedInventory.gaps.map { gap in
                [
                    "card_title": gap.cardTitle,
                    "gap_type": gap.gapType.rawValue,
                    "current_evidence": gap.currentEvidence,
                    "recommended_docs": gap.recommendedDocs
                ] as [String: Any]
            }
        }

        // Instructions for LLM
        response["requires_user_validation"].bool = true
        response["instructions"].string = """
            Review the proposed cards above with the user. Ask them to confirm before \
            calling dispatch_kc_agents. If there are gaps listed, ask about specific \
            missing documents that could strengthen those cards.

            IMPORTANT: dispatch_kc_agents is LOCKED until user clicks the "Generate Cards" button in the UI.
            DO NOT call dispatch_kc_agents - it will fail. Present the summary to user and WAIT.
            The system will automatically unlock the tool and prompt you when user approves.
            """

        return .immediate(response)
    }

    /// Convert card type string to KnowledgeCardPlanItem.ItemType
    private func planItemType(from cardType: String) -> KnowledgeCardPlanItem.ItemType {
        switch cardType {
        case "job": return .job
        case "skill": return .skill
        case "project": return .project
        case "achievement": return .achievement
        case "education": return .education
        default: return .job  // Fallback to job for unknown types
        }
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

    // MARK: - UI Plan Update

    /// Update the UI's knowledgeCardPlan with artifact assignments from proposals
    /// If no plan items exist, creates them from the proposals
    private func updatePlanItemsWithAssignments(proposals: JSON) async {
        // Get current plan items and artifact summaries
        let currentPlanItems = await MainActor.run { coordinator.ui.knowledgeCardPlan }
        let artifactSummaries = await coordinator.listArtifactSummaries()

        // Build lookup from artifact ID to summary text
        let artifactSummaryLookup = buildArtifactSummaryLookup(from: artifactSummaries)

        var updatedPlanItems: [KnowledgeCardPlanItem] = []

        // If no plan items exist, create them from proposals
        if currentPlanItems.isEmpty {
            Logger.info("📋 No existing plan items - creating from proposals", category: .ai)
            for proposal in proposals.arrayValue {
                let cardId = proposal["card_id"].string ?? UUID().uuidString
                let title = proposal["title"].string ?? "Knowledge Card"
                let cardType = proposal["card_type"].string ?? "job"
                let timelineEntryId = proposal["timeline_entry_id"].string

                let artifactIds = proposal["assigned_artifact_ids"].arrayValue.compactMap { $0.string }
                let summaries = artifactIds.compactMap { artifactSummaryLookup[$0] }

                let planItem = KnowledgeCardPlanItem(
                    id: cardId,
                    title: title,
                    type: planItemType(from: cardType),
                    description: nil,
                    status: .pending,
                    timelineEntryId: timelineEntryId,
                    assignedArtifactIds: artifactIds,
                    assignedArtifactSummaries: summaries
                )
                updatedPlanItems.append(planItem)
            }
        } else {
            // Update existing plan items with their assignments
            for planItem in currentPlanItems {
                // Find matching proposal by card_id or timeline_entry_id
                var matchedProposal: JSON?
                for proposal in proposals.arrayValue {
                    let proposalCardId = proposal["card_id"].string
                    let proposalTimelineId = proposal["timeline_entry_id"].string

                    if proposalCardId == planItem.id ||
                       (proposalTimelineId != nil && proposalTimelineId == planItem.timelineEntryId) {
                        matchedProposal = proposal
                        break
                    }
                }

                if let proposal = matchedProposal {
                    // Extract artifact IDs and build summaries
                    let artifactIds = proposal["assigned_artifact_ids"].arrayValue.compactMap { $0.string }
                    let summaries = artifactIds.compactMap { artifactSummaryLookup[$0] }

                    let updatedItem = planItem.withAssignments(artifactIds: artifactIds, summaries: summaries)
                    updatedPlanItems.append(updatedItem)
                } else {
                    // No assignment found - keep original (with empty assignments)
                    let updatedItem = planItem.withAssignments(artifactIds: [], summaries: [])
                    updatedPlanItems.append(updatedItem)
                }
            }
        }

        // Update the coordinator's plan
        await coordinator.updateKnowledgeCardPlan(
            items: updatedPlanItems,
            currentFocus: coordinator.getCurrentPlanItemFocus(),
            message: "Review artifact assignments below"
        )

        Logger.info("📋 Updated \(updatedPlanItems.count) plan items with artifact assignments", category: .ai)
    }

    /// Create plan items directly from merged inventory
    private func updatePlanItemsFromMergedInventory(mergedInventory: MergedCardInventory) async {
        let artifactSummaries = await coordinator.listArtifactSummaries()
        let artifactSummaryLookup = buildArtifactSummaryLookup(from: artifactSummaries)

        var planItems: [KnowledgeCardPlanItem] = []

        for mergedCard in mergedInventory.mergedCards {
            // Collect all artifact IDs
            var artifactIds = [mergedCard.primarySource.documentId]
            artifactIds.append(contentsOf: mergedCard.supportingSources.map { $0.documentId })

            let summaries = artifactIds.compactMap { artifactSummaryLookup[$0] }

            let planItem = KnowledgeCardPlanItem(
                id: mergedCard.cardId,
                title: mergedCard.title,
                type: planItemType(from: mergedCard.cardType),
                description: mergedCard.dateRange,
                status: .pending,
                timelineEntryId: nil,
                assignedArtifactIds: artifactIds,
                assignedArtifactSummaries: summaries
            )
            planItems.append(planItem)
        }

        // Update the coordinator's plan
        await coordinator.updateKnowledgeCardPlan(
            items: planItems,
            currentFocus: coordinator.getCurrentPlanItemFocus(),
            message: "Review card assignments below"
        )

        Logger.info("📋 Created \(planItems.count) plan items from merged inventory", category: .ai)
    }

    /// Build lookup from artifact ID to summary text
    private func buildArtifactSummaryLookup(from summaries: [JSON]) -> [String: String] {
        var lookup: [String: String] = [:]
        for summary in summaries {
            if let id = summary["id"].string {
                let filename = summary["filename"].string ?? "Document"
                let brief = summary["brief_description"].string ?? summary["summary"].string
                if let brief = brief, !brief.isEmpty {
                    lookup[id] = "\(filename): \(brief.prefix(60))..."
                } else {
                    lookup[id] = filename
                }
            }
        }
        return lookup
    }
}
