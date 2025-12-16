//
//  GetContextPackTool.swift
//  Sprung
//
//  Provides curated context bundles to minimize multi-call retrieval thrash.
//  Part of Milestone 5: Retrieval tools + context packs
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetContextPackTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.getContextPack
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.getContextPack.rawValue }
    var description: String { "Get curated context bundle. Returns bounded pack instead of multiple retrievals." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let hasBatchInProgress = await MainActor.run { coordinator.ui.hasBatchUploadInProgress }
        if hasBatchInProgress {
            throw ToolError.executionFailed(
                "Cannot call get_context_pack while document uploads are in progress. " +
                "Wait for the user to finish uploading and click 'Done with uploads', then try again."
            )
        }

        guard let purpose = params["purpose"].string else {
            throw ToolError.invalidParameters("purpose is required")
        }

        let maxChars = params["max_chars"].int ?? 3000
        let cardId = params["card_id"].string

        var response = JSON()
        response["status"].string = "completed"
        response["purpose"].string = purpose

        switch purpose {
        case "timeline_review":
            response["pack"] = await buildTimelinePack(maxChars: maxChars)
        case "artifact_overview":
            response["pack"] = await buildArtifactPack(maxChars: maxChars)
        case "card_context":
            response["pack"] = await buildCardContextPack(cardId: cardId, maxChars: maxChars)
        case "gap_analysis":
            response["pack"] = await buildGapAnalysisPack(maxChars: maxChars)
        default:
            throw ToolError.invalidParameters("Unknown purpose: \(purpose)")
        }

        return .immediate(response)
    }

    // MARK: - Pack Builders

    private func buildTimelinePack(maxChars: Int) async -> JSON {
        var pack = JSON()
        var usedChars = 0

        // Get timeline entries
        let artifacts = await coordinator.state.artifacts
        guard let entries = artifacts.skeletonTimeline?["experiences"].array else {
            pack["entries"].arrayObject = []
            return pack
        }

        var timelineItems: [JSON] = []
        for entry in entries {
            var item = JSON()
            item["id"].string = entry["id"].string
            item["experience_type"].string = entry["experience_type"].string
            item["organization"].string = entry["organization"].string
            item["title"].string = entry["title"].string
            item["start"].string = entry["start"].string
            item["end"].string = entry["end"].string

            let itemStr = item.rawString() ?? ""
            if usedChars + itemStr.count > maxChars { break }
            usedChars += itemStr.count
            timelineItems.append(item)
        }

        pack["entries"] = JSON(timelineItems)
        pack["total_entries"].int = entries.count
        pack["chars_used"].int = usedChars
        return pack
    }

    private func buildArtifactPack(maxChars: Int) async -> JSON {
        var pack = JSON()
        var usedChars = 0

        let summaries = await coordinator.listArtifactSummaries()

        var artifactItems: [JSON] = []
        for summary in summaries {
            var item = JSON()
            item["id"].string = summary["id"].string
            item["filename"].string = summary["filename"].string
            item["content_type"].string = summary["content_type"].string

            // Add brief description if available
            if let desc = summary["brief_description"].string, !desc.isEmpty {
                item["description"].string = String(desc.prefix(150))
            } else if let summ = summary["summary"].string, !summ.isEmpty {
                item["description"].string = String(summ.prefix(150))
            }

            let itemStr = item.rawString() ?? ""
            if usedChars + itemStr.count > maxChars { break }
            usedChars += itemStr.count
            artifactItems.append(item)
        }

        pack["artifacts"] = JSON(artifactItems)
        pack["total_artifacts"].int = summaries.count
        pack["chars_used"].int = usedChars
        return pack
    }

    private func buildCardContextPack(cardId: String?, maxChars: Int) async -> JSON {
        var pack = JSON()
        var usedChars = 0

        // Get card plan
        let planItems = await MainActor.run { coordinator.ui.knowledgeCardPlan }

        if let targetId = cardId, let card = planItems.first(where: { $0.id == targetId }) {
            // Build context for specific card
            var cardInfo = JSON()
            cardInfo["id"].string = card.id
            cardInfo["title"].string = card.title
            cardInfo["type"].string = card.type.rawValue
            cardInfo["status"].string = card.status.rawValue

            pack["target_card"] = cardInfo
            usedChars += (cardInfo.rawString() ?? "").count

            // Find assigned artifacts for this card (from proposals)
            let proposals = await coordinator.state.getCardProposals()
            if let proposal = proposals["cards"].array?.first(where: { $0["card_id"].string == targetId }) {
                if let artifactIds = proposal["assigned_artifact_ids"].array {
                    var excerpts: [JSON] = []
                    for aid in artifactIds.prefix(3) {
                        guard let id = aid.string else { continue }
                        if let artifact = await coordinator.getArtifactRecord(id: id) {
                            var excerpt = JSON()
                            excerpt["artifact_id"].string = id
                            excerpt["filename"].string = artifact["filename"].string

                            // Include truncated extracted text
                            if let text = artifact["extracted_text"].string {
                                let remaining = maxChars - usedChars - 200
                                let excerptLen = min(remaining / max(1, artifactIds.count - excerpts.count), 800)
                                excerpt["text_excerpt"].string = String(text.prefix(excerptLen))
                            }

                            let excerptStr = excerpt.rawString() ?? ""
                            if usedChars + excerptStr.count > maxChars { break }
                            usedChars += excerptStr.count
                            excerpts.append(excerpt)
                        }
                    }
                    pack["assigned_artifacts"] = JSON(excerpts)
                }
            }
        } else {
            // Overview of all cards
            var cardItems: [JSON] = []
            for card in planItems.prefix(10) {
                var item = JSON()
                item["id"].string = card.id
                item["title"].string = card.title
                item["type"].string = card.type.rawValue
                item["status"].string = card.status.rawValue

                let itemStr = item.rawString() ?? ""
                if usedChars + itemStr.count > maxChars { break }
                usedChars += itemStr.count
                cardItems.append(item)
            }
            pack["cards"] = JSON(cardItems)
            pack["total_cards"].int = planItems.count
        }

        pack["chars_used"].int = usedChars
        return pack
    }

    private func buildGapAnalysisPack(maxChars: Int) async -> JSON {
        var pack = JSON()
        var usedChars = 0

        // Get card plan and proposals
        let planItems = await MainActor.run { coordinator.ui.knowledgeCardPlan }
        let proposals = await coordinator.state.getCardProposals()
        let summaries = await coordinator.listArtifactSummaries()

        // Find cards without sufficient documentation
        var gaps: [JSON] = []
        for card in planItems where card.status == .pending {
            let proposal = proposals["cards"].array?.first { $0["card_id"].string == card.id }
            let assignedCount = proposal?["assigned_artifact_ids"].array?.count ?? 0

            if assignedCount < 2 {  // Threshold for "gap"
                var gap = JSON()
                gap["card_id"].string = card.id
                gap["title"].string = card.title
                gap["assigned_artifacts"].int = assignedCount

                let gapStr = gap.rawString() ?? ""
                if usedChars + gapStr.count > maxChars { break }
                usedChars += gapStr.count
                gaps.append(gap)
            }
        }

        pack["gaps"] = JSON(gaps)
        pack["total_cards"].int = planItems.count
        pack["total_artifacts"].int = summaries.count
        pack["chars_used"].int = usedChars
        return pack
    }
}
