//
//  CoveragePlannerService.swift
//  Sprung
//
//  Cross-document coverage planner for the onboarding interview.
//
//  At the boundary leaving Phase 3 (Evidence Collection), runs ONE structured
//  Anthropic call over a compact digest of the skeleton timeline, dossier
//  themes, and the knowledge-card index, asking which timeline entries or
//  dossier themes have zero or weak card coverage. The resulting gap list is
//  delivered back to the interview as a single queued coordinator message so
//  the interviewer prioritizes those areas during Phase 4.
//
//  Failure tolerance: the planner never blocks a phase transition. If the
//  model is unconfigured or the call fails, it logs a warning and the
//  interview continues untouched.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

// MARK: - Output Types

/// One coverage gap identified by the planner.
struct CoverageGap: Codable {
    let area: String
    let whyWeak: String
    let suggestedQuestion: String
}

/// Structured response from the coverage-planning call.
struct CoverageGapReport: Codable {
    let gaps: [CoverageGap]
}

/// Planner-internal failures (tolerated: logged, never blocks the interview).
private enum CoveragePlannerError: Error, LocalizedError {
    case llmUnavailable

    var errorDescription: String? {
        switch self {
        case .llmUnavailable: return "LLM facade not configured"
        }
    }
}

// MARK: - CoveragePlannerService

@MainActor
final class CoveragePlannerService {
    // MARK: Digest Bounds

    /// Maximum knowledge cards included in the digest (keeps the call cheap).
    private static let maxCards = 200
    /// Maximum timeline entries included in the digest.
    private static let maxTimelineEntries = 50

    // MARK: Dependencies

    private let eventBus: EventCoordinator
    private let artifactRepository: ArtifactRepository
    private let knowledgeCardStore: KnowledgeCardStore
    private let candidateDossierStore: CandidateDossierStore
    private let llmFacade: LLMFacade?

    // MARK: State

    /// Once-per-interview guard. Re-armed whenever a pre-Phase-4 transition
    /// is applied (every fresh interview starts by applying Phase 1), so a
    /// restarted interview in the same app launch gets its own planner run.
    private var hasRun = false
    private var subscriptionTask: Task<Void, Never>?

    // MARK: Initialization

    init(
        eventBus: EventCoordinator,
        artifactRepository: ArtifactRepository,
        knowledgeCardStore: KnowledgeCardStore,
        candidateDossierStore: CandidateDossierStore,
        llmFacade: LLMFacade?
    ) {
        self.eventBus = eventBus
        self.artifactRepository = artifactRepository
        self.knowledgeCardStore = knowledgeCardStore
        self.candidateDossierStore = candidateDossierStore
        self.llmFacade = llmFacade
        Logger.info("🧭 CoveragePlannerService initialized", category: .ai)
    }

    // MARK: - Event Subscription

    /// Subscribe to phase events and run the planner once when the interview
    /// enters Phase 4 (i.e. leaves the Phase 3 ingestion phase).
    func start() {
        guard subscriptionTask == nil else { return }
        let bus = eventBus
        subscriptionTask = Task { @MainActor [weak self] in
            for await event in await bus.stream(topic: .phase) {
                guard let self else { return }
                guard case .phase(.transitionApplied(let phaseRaw, _)) = event,
                      let phase = InterviewPhase(rawValue: phaseRaw) else { continue }
                if phase == .phase4StrategicSynthesis {
                    self.runPlannerIfNeeded()
                } else if phase.order < InterviewPhase.phase4StrategicSynthesis.order {
                    // A fresh interview applies Phase 1 at start
                    // (InterviewLifecycleController.startLLM), and phases only
                    // move forward within an interview — so any pre-Phase-4
                    // application means a new run toward the Phase 4 boundary.
                    if self.hasRun {
                        Logger.info("🧭 CoveragePlannerService re-armed for new interview run", category: .ai)
                    }
                    self.hasRun = false
                }
            }
        }
        Logger.info("🧭 CoveragePlannerService subscribed to phase events", category: .ai)
    }

    private func runPlannerIfNeeded() {
        guard !hasRun else { return }
        hasRun = true
        // Run detached from the event loop so the planner never blocks
        // phase-transition processing.
        Task { @MainActor [weak self] in
            await self?.runPlanner()
        }
    }

    // MARK: - Planner Execution

    private func runPlanner() async {
        do {
            let report = try await generateCoverageReport()
            await deliver(report)
        } catch {
            // Never block the interview: log and continue.
            Logger.warning("🧭 Coverage planner skipped (interview continues): \(error.localizedDescription)", category: .ai)
        }
    }

    private func generateCoverageReport() async throws -> CoverageGapReport {
        guard let facade = llmFacade else {
            throw CoveragePlannerError.llmUnavailable
        }
        // Interview model; throws ModelConfigurationError when unconfigured.
        let modelId = try OnboardingModelConfig.currentModelId()

        let digest = await buildDigest()
        Logger.info("🧭 Coverage planner running over digest (\(digest.count) chars) with model \(modelId)", category: .ai)

        return try await facade.executeStructuredWithAnthropicBlocks(
            systemContent: [AnthropicSystemBlock(text: Self.systemPrompt)],
            userBlocks: [
                .text(AnthropicTextBlock(text: digest)),
                .text(AnthropicTextBlock(text: Self.instructions))
            ],
            modelId: modelId,
            responseType: CoverageGapReport.self,
            schema: Self.gapSchema,
            maxTokens: 4096
        )
    }

    // MARK: - Result Delivery

    private func deliver(_ report: CoverageGapReport) async {
        guard !report.gaps.isEmpty else {
            Logger.info("🧭 Coverage planner: no coverage gaps found", category: .ai)
            return
        }

        let gaps = Array(report.gaps.prefix(10))
        for (index, gap) in gaps.enumerated() {
            Logger.info("🧭 Coverage gap \(index + 1)/\(gaps.count): \(gap.area) — \(gap.whyWeak) → ask: \(gap.suggestedQuestion)", category: .ai)
        }

        var lines = ["Coverage gaps found — prioritize asking about:"]
        for (index, gap) in gaps.enumerated() {
            lines.append("\(index + 1). \(gap.area)")
            lines.append("   Why coverage is weak: \(gap.whyWeak)")
            lines.append("   Suggested question: \"\(gap.suggestedQuestion)\"")
        }
        lines.append("Weave these into the Phase 4 conversation naturally; do not read this list verbatim to the user.")

        var payload = JSON()
        payload["text"].string = lines.joined(separator: "\n")
        await eventBus.publish(.llm(.sendCoordinatorMessage(payload: payload)))
        Logger.info("🧭 Coverage planner delivered \(gaps.count) gap(s) as coordinator message", category: .ai)
    }

    // MARK: - Digest Construction

    private func buildDigest() async -> String {
        let timeline = await timelineDigest()
        let dossier = dossierDigest()
        let cards = cardIndexDigest()
        return """
        COVERAGE DIGEST

        TIMELINE ENTRIES:
        \(timeline)

        DOSSIER THEMES:
        \(dossier)

        KNOWLEDGE CARD INDEX:
        \(cards)
        """
    }

    private func timelineDigest() async -> String {
        guard let entries = await artifactRepository.getSkeletonTimeline()?["experiences"].array,
              !entries.isEmpty else {
            return "(no timeline captured)"
        }
        var lines: [String] = []
        for entry in entries.prefix(Self.maxTimelineEntries) {
            let title = entry["title"].stringValue
            let org = entry["organization"].stringValue
            let start = entry["start"].stringValue
            let end = entry["end"].stringValue.isEmpty ? "present" : entry["end"].stringValue
            lines.append("- \(title) @ \(org) (\(start)–\(end))")
        }
        if entries.count > Self.maxTimelineEntries {
            lines.append("…and \(entries.count - Self.maxTimelineEntries) more entries")
        }
        return lines.joined(separator: "\n")
    }

    private func dossierDigest() -> String {
        guard let dossier = candidateDossierStore.dossier else {
            return "(no dossier captured)"
        }
        var lines: [String] = []
        func add(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            lines.append("- \(label): \(Self.oneLine(value, limit: 300))")
        }
        add("jobSearchContext", dossier.jobSearchContext)
        add("strengthsToEmphasize", dossier.strengthsToEmphasize)
        add("pitfallsToAvoid", dossier.pitfallsToAvoid)
        add("workArrangementPreferences", dossier.workArrangementPreferences)
        add("availability", dossier.availability)
        add("uniqueCircumstances", dossier.uniqueCircumstances)
        add("interviewerNotes", dossier.interviewerNotes)
        return lines.isEmpty ? "(no dossier captured)" : lines.joined(separator: "\n")
    }

    private func cardIndexDigest() -> String {
        let cards = knowledgeCardStore.knowledgeCards
        guard !cards.isEmpty else {
            return "(no knowledge cards generated)"
        }
        var lines: [String] = []
        for card in cards.prefix(Self.maxCards) {
            let title = Self.oneLine(card.title, limit: 80)
            let type = card.cardTypeRaw ?? "card"
            var context: [String] = []
            if let org = card.organization, !org.isEmpty { context.append(org) }
            if let range = card.dateRange, !range.isEmpty { context.append(range) }
            let contextText = context.isEmpty ? "" : " (\(context.joined(separator: ", ")))"
            let summary = Self.oneLine(card.narrative, limit: 140)
            let source = card.evidenceAnchors.first?.documentId ?? "interview"
            let pending = card.isPending ? " [pending]" : ""
            lines.append("- [\(type)] \(title)\(contextText) — \(summary) [source: \(source)]\(pending)")
        }
        if cards.count > Self.maxCards {
            lines.append("…and \(cards.count - Self.maxCards) more cards")
        }
        return lines.joined(separator: "\n")
    }

    /// Collapse text to a single truncated line for the digest.
    private static func oneLine(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    // MARK: - Prompts & Schema

    private static let systemPrompt = """
    You are a coverage-analysis assistant for a resume-building interview. \
    You compare a candidate's career timeline and dossier themes against the \
    index of evidence-backed knowledge cards collected so far, and identify \
    where evidence coverage is missing or weak. Respond with JSON that \
    conforms exactly to the requested schema.
    """

    private static let instructions = """
    Review the coverage digest above. Which timeline entries or dossier themes \
    have ZERO or WEAK knowledge-card coverage? A timeline entry is weakly \
    covered when no card (or only a thin, generic card) documents concrete \
    work, outcomes, or skills from that role. A dossier theme is weakly \
    covered when the claimed strength or concern has no supporting evidence \
    card.

    For each gap, report:
    - area: the timeline entry or dossier theme with weak coverage
    - whyWeak: what evidence is missing (be specific about what kind of card or detail is absent)
    - suggestedQuestion: one concrete question the interviewer should ask the candidate to fill the gap

    Order gaps by importance (most career-significant first). Return at most \
    10 gaps. If coverage is genuinely complete, return an empty gaps array.
    """

    private static let gapSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "gaps": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "area": [
                            "type": "string",
                            "description": "Timeline entry or dossier theme with zero/weak card coverage"
                        ],
                        "whyWeak": [
                            "type": "string",
                            "description": "What evidence is missing for this area"
                        ],
                        "suggestedQuestion": [
                            "type": "string",
                            "description": "Question the interviewer should ask to fill the gap"
                        ]
                    ],
                    "required": ["area", "whyWeak", "suggestedQuestion"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["gaps"],
        "additionalProperties": false
    ]
}
