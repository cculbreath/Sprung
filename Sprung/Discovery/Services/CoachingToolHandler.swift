//
//  CoachingToolHandler.swift
//  Sprung
//
//  Handles tool calls for the coaching service.
//  Extracted from CoachingService for single responsibility.
//

import Foundation
import SwiftData

/// Handles tool calls for the coaching service
@MainActor
struct CoachingToolHandler {
    private let modelContext: ModelContext
    private let jobAppStore: JobAppStore

    init(modelContext: ModelContext, jobAppStore: JobAppStore) {
        self.modelContext = modelContext
        self.jobAppStore = jobAppStore
    }

    // MARK: - JSON Encoding Helper

    private func encodeToJSON<T: Encodable>(_ value: T) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "{}"
    }

    // MARK: - Tool Handlers

    /// Handle get_knowledge_card tool call
    func handleGetKnowledgeCard(arguments: String, knowledgeCards: [KnowledgeCard]) -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(GetKnowledgeCardArgs.self, from: data) else {
            return encodeToJSON(ToolErrorResult(error: "Failed to parse get_knowledge_card arguments"))
        }

        guard let card = knowledgeCards.first(where: { $0.id.uuidString == args.cardId }) else {
            return encodeToJSON(ToolErrorResult(error: "Knowledge card not found: \(args.cardId)"))
        }

        var content = card.narrative

        // Apply line range if specified
        if let start = args.startLine, let end = args.endLine {
            let lines = content.components(separatedBy: "\n")
            let safeStart = max(0, start - 1)  // 1-indexed to 0-indexed
            let safeEnd = min(lines.count, end)
            if safeStart < safeEnd {
                content = lines[safeStart..<safeEnd].joined(separator: "\n")
            }
        }

        let result = KnowledgeCardToolResult(
            cardId: args.cardId,
            title: card.title,
            type: card.cardType?.rawValue,
            organization: card.organization,
            dateRange: card.dateRange,
            content: content,
            wordCount: card.narrative.split(separator: " ").count
        )
        return encodeToJSON(result)
    }

    /// Handle get_job_description tool call
    func handleGetJobDescription(arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(GetJobDescriptionArgs.self, from: data) else {
            return encodeToJSON(ToolErrorResult(error: "Failed to parse get_job_description arguments"))
        }

        guard let uuid = UUID(uuidString: args.jobAppId),
              let jobApp = jobAppStore.jobApps.first(where: { $0.id == uuid }) else {
            return encodeToJSON(ToolErrorResult(error: "Job application not found: \(args.jobAppId)"))
        }

        let result = JobDescriptionToolResult(
            jobAppId: args.jobAppId,
            company: jobApp.companyName,
            position: jobApp.jobPosition,
            status: jobApp.status.displayName,
            jobDescription: jobApp.jobDescription,
            jobUrl: jobApp.postingURL.isEmpty ? jobApp.jobApplyLink : jobApp.postingURL,
            notes: jobApp.notes,
            appliedDate: jobApp.appliedDate?.ISO8601Format()
        )
        return encodeToJSON(result)
    }

    /// Handle get_resume tool call
    func handleGetResume(arguments: String) async -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(GetResumeArgs.self, from: data) else {
            return encodeToJSON(ToolErrorResult(error: "Failed to parse get_resume arguments"))
        }

        let descriptor = FetchDescriptor<Resume>()
        guard let resumes = try? modelContext.fetch(descriptor),
              let uuid = UUID(uuidString: args.resumeId),
              let resume = resumes.first(where: { $0.id == uuid }) else {
            return encodeToJSON(ToolErrorResult(error: "Resume not found: \(args.resumeId)"))
        }

        var sectionName: String?
        var content: String?
        var availableSections: [String]?
        var summary: String?

        // Get resume content from TreeNode
        if let rootNode = resume.rootNode {
            if let requestedSection = args.section {
                // Get specific section
                if let sectionNode = rootNode.children?.first(where: { $0.label == requestedSection }) {
                    sectionName = requestedSection
                    content = extractNodeText(sectionNode)
                }
            } else {
                // Get summary of all sections
                availableSections = (rootNode.children ?? []).map { $0.label }
                if let summaryNode = rootNode.children?.first(where: { $0.label == "summary" }) {
                    summary = extractNodeText(summaryNode)
                }
            }
        }

        let result = CoachingResumeToolResult(
            resumeId: args.resumeId,
            template: resume.template?.name ?? "Unknown Template",
            section: sectionName,
            content: content,
            availableSections: availableSections,
            summary: summary
        )
        return encodeToJSON(result)
    }

    /// Handle choose_best_jobs tool call - triggers the job selection workflow
    func handleChooseBestJobs(
        arguments: String,
        agentService: DiscoveryAgentService?,
        knowledgeCards: [KnowledgeCard],
        dossier: CandidateDossier?
    ) async -> String {
        guard let agent = agentService else {
            return encodeToJSON(ToolErrorResult(error: "Agent service not configured"))
        }

        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(ChooseBestJobsArgs.self, from: data) else {
            return encodeToJSON(ToolErrorResult(error: "Failed to parse choose_best_jobs arguments"))
        }

        let count = min(max(args.count, 1), 10)

        Logger.info("Coaching: triggering choose best jobs (count: \(count), reason: \(args.reason))", category: .ai)

        // Get all jobs in new (identified) status
        let identifiedJobs = jobAppStore.jobApps(forStatus: .new)
        guard !identifiedJobs.isEmpty else {
            return encodeToJSON(ChooseBestJobsToolResult(
                success: false,
                selectedCount: nil,
                identifiedCount: 0,
                selections: nil,
                overallAnalysis: nil,
                considerations: nil,
                error: "No jobs in Identified status to choose from"
            ))
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

        // Build knowledge context from knowledge cards
        let knowledgeContext = knowledgeCards
            .map { card in
                let typeLabel = card.cardType?.rawValue ?? "general"
                return "[\(typeLabel)] \(card.title):\n\(card.narrative)"
            }
            .joined(separator: "\n\n")

        // Build dossier context from CandidateDossier
        let dossierContext = dossier?.exportForJobMatching() ?? "No dossier available."

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

            let selections = result.selections.map { selection in
                ChooseBestJobsSelectionResult(
                    company: selection.company,
                    role: selection.role,
                    matchScore: selection.matchScore,
                    reasoning: selection.reasoning
                )
            }

            Logger.info("Choose best jobs completed: \(result.selections.count) selected", category: .ai)

            return encodeToJSON(ChooseBestJobsToolResult(
                success: true,
                selectedCount: result.selections.count,
                identifiedCount: identifiedJobs.count,
                selections: selections,
                overallAnalysis: result.overallAnalysis,
                considerations: result.considerations,
                error: nil
            ))

        } catch {
            Logger.error("Failed to choose best jobs: \(error)", category: .ai)
            return encodeToJSON(ChooseBestJobsToolResult(
                success: false,
                selectedCount: nil,
                identifiedCount: identifiedJobs.count,
                selections: nil,
                overallAnalysis: nil,
                considerations: nil,
                error: error.localizedDescription
            ))
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
