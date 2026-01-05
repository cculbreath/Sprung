//
//  CoachingToolHandler.swift
//  Sprung
//
//  Handles tool calls for the coaching service.
//  Extracted from CoachingService for single responsibility.
//

import Foundation
import SwiftData
import SwiftyJSON

/// Handles tool calls for the coaching service
@MainActor
struct CoachingToolHandler {
    private let modelContext: ModelContext
    private let jobAppStore: JobAppStore

    init(modelContext: ModelContext, jobAppStore: JobAppStore) {
        self.modelContext = modelContext
        self.jobAppStore = jobAppStore
    }

    /// Handle get_knowledge_card tool call
    func handleGetKnowledgeCard(_ args: JSON, knowledgeCards: [KnowledgeCardDraft]) -> String {
        let cardId = args["card_id"].stringValue
        let startLine = args["start_line"].int
        let endLine = args["end_line"].int

        guard let card = knowledgeCards.first(where: { $0.id.uuidString == cardId }) else {
            return JSON(["error": "Knowledge card not found: \(cardId)"]).rawString() ?? "{}"
        }

        var content = card.content

        // Apply line range if specified
        if let start = startLine, let end = endLine {
            let lines = content.components(separatedBy: "\n")
            let safeStart = max(0, start - 1)  // 1-indexed to 0-indexed
            let safeEnd = min(lines.count, end)
            if safeStart < safeEnd {
                content = lines[safeStart..<safeEnd].joined(separator: "\n")
            }
        }

        var result = JSON()
        result["card_id"].string = cardId
        result["title"].string = card.title
        result["type"].string = card.cardType
        result["organization"].string = card.organization
        result["time_period"].string = card.timePeriod
        result["content"].string = content
        result["word_count"].int = card.wordCount

        return result.rawString() ?? "{}"
    }

    /// Handle get_job_description tool call
    func handleGetJobDescription(_ args: JSON) -> String {
        let jobAppId = args["job_app_id"].stringValue

        guard let uuid = UUID(uuidString: jobAppId),
              let jobApp = jobAppStore.jobApps.first(where: { $0.id == uuid }) else {
            return JSON(["error": "Job application not found: \(jobAppId)"]).rawString() ?? "{}"
        }

        var result = JSON()
        result["job_app_id"].string = jobAppId
        result["company"].string = jobApp.companyName
        result["position"].string = jobApp.jobPosition
        result["status"].string = jobApp.status.displayName
        result["job_description"].string = jobApp.jobDescription
        result["job_url"].string = jobApp.postingURL.isEmpty ? jobApp.jobApplyLink : jobApp.postingURL
        result["notes"].string = jobApp.notes
        result["applied_date"].string = jobApp.appliedDate?.ISO8601Format()

        return result.rawString() ?? "{}"
    }

    /// Handle get_resume tool call
    func handleGetResume(_ args: JSON) async -> String {
        let resumeId = args["resume_id"].stringValue
        let section = args["section"].string

        let descriptor = FetchDescriptor<Resume>()
        guard let resumes = try? modelContext.fetch(descriptor),
              let uuid = UUID(uuidString: resumeId),
              let resume = resumes.first(where: { $0.id == uuid }) else {
            return JSON(["error": "Resume not found: \(resumeId)"]).rawString() ?? "{}"
        }

        var result = JSON()
        result["resume_id"].string = resumeId
        result["template"].string = resume.template?.name ?? "Unknown Template"

        // Get resume content from TreeNode
        if let rootNode = resume.rootNode {
            if let section = section {
                // Get specific section
                if let sectionNode = rootNode.children?.first(where: { $0.label == section }) {
                    result["section"].string = section
                    result["content"].string = extractNodeText(sectionNode)
                }
            } else {
                // Get summary of all sections
                var sections: [String] = []
                for child in rootNode.children ?? [] {
                    sections.append(child.label)
                }
                result["available_sections"].arrayObject = sections
                if let summaryNode = resume.rootNode?.children?.first(where: { $0.label == "summary" }) {
                    result["summary"].string = extractNodeText(summaryNode)
                }
            }
        }

        return result.rawString() ?? "{}"
    }

    /// Handle choose_best_jobs tool call - triggers the job selection workflow
    func handleChooseBestJobs(
        _ args: JSON,
        agentService: DiscoveryAgentService?,
        knowledgeCards: [KnowledgeCardDraft],
        dossierEntries: [JSON]
    ) async -> String {
        guard let agent = agentService else {
            return JSON(["error": "Agent service not configured"]).rawString() ?? "{}"
        }

        let count = min(max(args["count"].intValue, 1), 10)
        let reason = args["reason"].stringValue

        Logger.info("🎯 Coaching: triggering choose best jobs (count: \(count), reason: \(reason))", category: .ai)

        // Get all jobs in new (identified) status
        let identifiedJobs = jobAppStore.jobApps(forStatus: .new)
        guard !identifiedJobs.isEmpty else {
            return JSON([
                "success": false,
                "error": "No jobs in Identified status to choose from",
                "identified_count": 0
            ]).rawString() ?? "{}"
        }

        // Build job tuples for agent
        let jobTuples = identifiedJobs.map { job in
            (
                id: job.id,
                company: job.companyName,
                role: job.jobPosition,
                description: job.jobDescription
            )
        }

        // Build knowledge context from cached knowledge cards
        let knowledgeContext = knowledgeCards
            .map { card in
                let typeLabel = card.cardType ?? "general"
                return "[\(typeLabel)] \(card.title):\n\(card.content)"
            }
            .joined(separator: "\n\n")

        // Build dossier context from cached dossier entries
        let dossierContext = dossierEntries
            .map { entry in
                let section = entry["section"].stringValue
                let value = entry["value"].stringValue
                return "\(section): \(value)"
            }
            .joined(separator: "\n")

        do {
            let result = try await agent.chooseBestJobs(
                jobs: jobTuples,
                knowledgeContext: knowledgeContext,
                dossierContext: dossierContext,
                count: count
            )

            // Advance selected jobs to Queued status
            for selection in result.selections {
                if let jobApp = jobAppStore.jobApp(byId: selection.jobId) {
                    jobAppStore.setStatus(jobApp, to: .queued)
                }
            }

            // Build response for LLM
            var response = JSON()
            response["success"].bool = true
            response["selected_count"].int = result.selections.count
            response["identified_count"].int = identifiedJobs.count

            var selections: [JSON] = []
            for selection in result.selections {
                var sel = JSON()
                sel["company"].string = selection.company
                sel["role"].string = selection.role
                sel["match_score"].double = selection.matchScore
                sel["reasoning"].string = selection.reasoning
                selections.append(sel)
            }
            response["selections"].arrayObject = selections.map { $0.object }
            response["overall_analysis"].string = result.overallAnalysis
            response["considerations"].arrayObject = result.considerations

            Logger.info("✅ Choose best jobs completed: \(result.selections.count) selected", category: .ai)
            return response.rawString() ?? "{}"

        } catch {
            Logger.error("Failed to choose best jobs: \(error)", category: .ai)
            return JSON([
                "success": false,
                "error": error.localizedDescription,
                "identified_count": identifiedJobs.count
            ]).rawString() ?? "{}"
        }
    }

    /// Extract text content from a TreeNode and its children
    func extractNodeText(_ node: TreeNode) -> String {
        var text = node.value
        if let children = node.children {
            for child in children.sorted(by: { $0.myIndex < $1.myIndex }) {
                let childText = extractNodeText(child)
                if !childText.isEmpty {
                    if !text.isEmpty { text += "\n" }
                    if !child.name.isEmpty {
                        text += "\(child.name): "
                    }
                    text += childText
                }
            }
        }
        return text
    }
}
