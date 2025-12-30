//
//  ProposeCardAssignmentsTool.swift
//  Sprung
//
//  Tool for the main coordinator to propose card-to-document assignments.
//  Uses inventory-based auto-assignment exclusively.
//

import Foundation
import SwiftyJSON

/// Tool that allows the coordinator to map documents to knowledge cards.
/// Uses inventory-based auto-assignment exclusively.
struct ProposeCardAssignmentsTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Generate card assignments from document inventories. System auto-assigns based on document analysis.",
            properties: [
                "summary": JSONSchema(
                    type: .string,
                    description: "Optional summary of why you're calling this tool"
                )
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
        // Always use inventory-based auto-assignment
        // Manual mode removed - inventory pipeline is the only path
        return try await executeAutoAssign()
    }

    // MARK: - Auto-Assignment Mode

    /// Execute auto-assignment using merged card inventory from all documents
    /// Returns compact summary instead of requiring LLM to construct arrays
    private func executeAutoAssign() async throws -> ToolResult {
        Logger.info("📋 ProposeCardAssignmentsTool: Auto-assignment from merged inventory", category: .ai)

        // Get merged card inventory from all documents
        let cardMergeService = await MainActor.run { coordinator.cardMergeService }
        let timeline = await coordinator.state.artifacts.skeletonTimeline

        // Show status while merging (Gemini 2.5 call can take 30-60s)
        await coordinator.eventBus.publish(.extractionStateChanged(true, statusMessage: "Merging card inventories..."))

        let mergedInventory: MergedCardInventory
        do {
            mergedInventory = try await cardMergeService.mergeInventories(timeline: timeline)
            await coordinator.eventBus.publish(.extractionStateChanged(false, statusMessage: nil))
        } catch CardMergeService.CardMergeError.noInventories {
            await coordinator.eventBus.publish(.extractionStateChanged(false, statusMessage: nil))
            // No fallback - tell LLM to wait for document processing
            Logger.warning("⚠️ No document inventories available yet", category: .ai)
            var response = JSON()
            response["status"].string = "waiting"
            response["error"].string = "no_inventories"
            response["message"].string = "Document inventories are still being generated. Please wait for document processing to complete, then call propose_card_assignments again."
            response["retry_after_seconds"].int = 5
            return .immediate(response)
        } catch {
            await coordinator.eventBus.publish(.extractionStateChanged(false, statusMessage: nil))
            Logger.error("❌ Card merge failed: \(error.localizedDescription)", category: .ai)
            var response = JSON()
            response["status"].string = "error"
            response["message"].string = "Failed to merge card inventories: \(error.localizedDescription)"
            return .immediate(response)
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

    // MARK: - UI Plan Update

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
