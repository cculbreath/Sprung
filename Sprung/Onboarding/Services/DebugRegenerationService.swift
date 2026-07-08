#if DEBUG
//
//  DebugRegenerationService.swift
//  Sprung
//
//  Debug-only service for regenerating onboarding data.
//  Useful for testing and development workflows.
//  Extracted from OnboardingInterviewCoordinator to follow Single Responsibility Principle.
//

import Foundation

/// Thread-safe counter for tracking completed operations in concurrent tasks
private actor Counter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

/// Debug-only service for regenerating knowledge card inventories and summaries.
/// Used in development to re-extract data from existing artifacts.
@MainActor
final class DebugRegenerationService {
    private let documentProcessingService: DocumentProcessingService
    private let agentActivityTracker: AgentActivityTracker
    private let cardMergeService: CardMergeService
    private let knowledgeCardStore: KnowledgeCardStore
    private let skillStore: SkillStore
    private let candidateDossierStore: CandidateDossierStore
    private let llmFacade: LLMFacade?
    private let eventBus: EventBus

    /// Provider for getting current session artifacts (avoids circular dependency with coordinator)
    private var sessionArtifactsProvider: (() -> [ArtifactRecord])?

    init(
        documentProcessingService: DocumentProcessingService,
        agentActivityTracker: AgentActivityTracker,
        cardMergeService: CardMergeService,
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        candidateDossierStore: CandidateDossierStore,
        llmFacade: LLMFacade?,
        eventBus: EventBus
    ) {
        self.documentProcessingService = documentProcessingService
        self.agentActivityTracker = agentActivityTracker
        self.cardMergeService = cardMergeService
        self.knowledgeCardStore = knowledgeCardStore
        self.skillStore = skillStore
        self.candidateDossierStore = candidateDossierStore
        self.llmFacade = llmFacade
        self.eventBus = eventBus
    }

    /// Configure the provider for getting session artifacts
    func setSessionArtifactsProvider(_ provider: @escaping () -> [ArtifactRecord]) {
        self.sessionArtifactsProvider = provider
    }

    // MARK: - Regeneration Methods

    /// Regenerate the candidate's career through-lines synthesis from the
    /// existing knowledge cards + skill bank + dossier strategic notes, and
    /// persist it onto the dossier. Read-over-existing-artifacts: no document
    /// re-ingest, no re-transcription — cheap to re-run. Returns the synthesized
    /// text on success (nil on skip/failure) so callers can surface it.
    @discardableResult
    func regenerateCareerSynthesis() async -> String? {
        guard let llmFacade else {
            Logger.warning("Career synthesis skipped: LLM facade unavailable", category: .ai)
            return nil
        }
        let cards = knowledgeCardStore.knowledgeCards
        guard !cards.isEmpty else {
            Logger.warning("Career synthesis skipped: no knowledge cards available", category: .ai)
            return nil
        }

        // Orientation only: job-search context + strengths + pitfalls. Excludes
        // private circumstances and the prior synthesis (no self-feedback loop).
        let strategicNotes: String? = candidateDossierStore.dossier.map { dossier in
            var parts: [String] = []
            if !dossier.jobSearchContext.isEmpty {
                parts.append("Job search context: \(dossier.jobSearchContext)")
            }
            if let strengths = dossier.strengthsToEmphasize, !strengths.isEmpty {
                parts.append("Strengths to emphasize: \(strengths)")
            }
            if let pitfalls = dossier.pitfallsToAvoid, !pitfalls.isEmpty {
                parts.append("Pitfalls to avoid: \(pitfalls)")
            }
            return parts.joined(separator: "\n\n")
        }

        Logger.info("🔄 Regenerating career synthesis from \(cards.count) cards...", category: .ai)
        do {
            let service = CareerSynthesisService(llmFacade: llmFacade)
            let text = try await service.generate(
                cards: cards,
                skills: skillStore.skills,
                strategicNotes: strategicNotes
            )
            candidateDossierStore.setCareerThroughLines(text)
            Logger.info("✅ Career synthesis regenerated (\(text.count) chars)", category: .ai)
            return text
        } catch {
            Logger.error("❌ Career synthesis failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Selective regeneration based on user choices from RegenOptionsDialog
    func regenerateSelected(
        artifactIds: Set<String>,
        regenerateSummary: Bool,
        regenerateSkills: Bool,
        regenerateNarrativeCards: Bool,
        dedupeNarratives: Bool = false
    ) async {
        Logger.debug("🔄 Selective regeneration: \(artifactIds.count) artifacts, summary=\(regenerateSummary), skills=\(regenerateSkills), cards=\(regenerateNarrativeCards), dedupe=\(dedupeNarratives)", category: .ai)

        guard let sessionArtifacts = sessionArtifactsProvider?() else {
            Logger.warning("No session artifacts provider configured", category: .ai)
            return
        }

        // Get selected artifacts
        let artifactsToProcess = sessionArtifacts.filter { artifactIds.contains($0.idString) }

        guard !artifactsToProcess.isEmpty else {
            Logger.debug("⚠️ No artifacts selected", category: .ai)
            return
        }

        // Build operation description
        var ops: [String] = []
        if regenerateSummary { ops.append("summary") }
        if regenerateSkills { ops.append("skills") }
        if regenerateNarrativeCards { ops.append("cards") }
        let opsDesc = ops.joined(separator: "+")

        // Track the regeneration as an agent
        let agentId = agentActivityTracker.trackAgent(
            type: .documentRegen,
            name: "Regen \(artifactsToProcess.count) docs (\(opsDesc))",
            task: nil as Task<Void, Never>?
        )

        agentActivityTracker.appendTranscript(
            agentId: agentId,
            entryType: .system,
            content: "Starting regeneration",
            details: "Artifacts: \(artifactsToProcess.count), Summary: \(regenerateSummary), Skills: \(regenerateSkills), Cards: \(regenerateNarrativeCards), Dedupe: \(dedupeNarratives)"
        )

        // Clear selected fields first
        for artifact in artifactsToProcess {
            if regenerateSummary {
                artifact.summary = nil
                artifact.briefDescription = nil
            }
            if regenerateSkills {
                artifact.skillsJSON = nil
            }
            if regenerateNarrativeCards {
                artifact.narrativeCardsJSON = nil
            }
            Logger.verbose("🗑️ Cleared selected fields for: \(artifact.filename)", category: .ai)
        }

        // Use same concurrency limit as document extraction
        let maxConcurrent = UserDefaults.standard.integer(forKey: "onboardingMaxConcurrentExtractions")
        let concurrencyLimit = maxConcurrent > 0 ? maxConcurrent : 5

        let processingService = documentProcessingService
        let tracker = agentActivityTracker

        // Track completed count
        let completedCount = Counter()

        // Process with limited concurrency
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var index = 0

            for artifact in artifactsToProcess {
                if inFlight >= concurrencyLimit {
                    await group.next()
                    inFlight -= 1
                }

                let artifactName = artifact.filename
                let total = artifactsToProcess.count

                group.addTask {
                    // Handle summary
                    if regenerateSummary {
                        await processingService.generateSummaryForExistingArtifact(artifact)
                    }

                    // Handle skills and narrative cards
                    if regenerateSkills && regenerateNarrativeCards {
                        // Both - use the combined method for efficiency
                        await processingService.generateKnowledgeExtractionForExistingArtifact(artifact)
                    } else if regenerateSkills {
                        await processingService.generateSkillsOnlyForExistingArtifact(artifact)
                    } else if regenerateNarrativeCards {
                        await processingService.generateNarrativeCardsOnlyForExistingArtifact(artifact)
                    }

                    // Track completion
                    let completed = await completedCount.increment()
                    await MainActor.run {
                        tracker.appendTranscript(
                            agentId: agentId,
                            entryType: .toolResult,
                            content: "Completed \(completed)/\(total): \(artifactName)"
                        )
                        tracker.updateStatusMessage(agentId: agentId, message: "Processing \(completed)/\(total)...")
                    }
                }
                inFlight += 1
                index += 1
                Logger.verbose("📦 Dispatched \(index)/\(artifactsToProcess.count): \(artifact.filename)", category: .ai)
            }

            for await _ in group { }
        }

        Logger.debug("✅ Selective regeneration complete", category: .ai)

        agentActivityTracker.appendTranscript(
            agentId: agentId,
            entryType: .system,
            content: "Regeneration complete",
            details: "Processed \(artifactsToProcess.count) artifacts"
        )

        if dedupeNarratives {
            Logger.debug("🔀 Running narrative deduplication...", category: .ai)
            agentActivityTracker.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Running narrative deduplication..."
            )
            await deduplicateNarratives()
        }

        agentActivityTracker.markCompleted(agentId: agentId)
    }

    /// Run narrative card deduplication manually.
    /// Uses LLM to identify and merge duplicate cards across documents.
    func deduplicateNarratives() async {
        do {
            let result = try await cardMergeService.getAllNarrativeCardsDeduped()
            Logger.info("✅ Deduplication complete: \(result.cards.count) cards, \(result.mergeLog.count) merges", category: .ai)

            // Clear existing pending cards and add deduplicated ones
            await MainActor.run {
                knowledgeCardStore.deletePendingCards()
                for card in result.cards {
                    card.isFromOnboarding = true
                    card.isPending = true
                }
                knowledgeCardStore.addAll(result.cards)
            }

            // Log merge decisions for debugging
            for entry in result.mergeLog {
                Logger.debug("🔀 \(entry.action.rawValue): \(entry.inputCardIds.joined(separator: " + ")) → \(entry.outputCardId ?? "N/A")", category: .ai)
            }
        } catch {
            Logger.error("❌ Deduplication failed: \(error.localizedDescription)", category: .ai)
        }
    }
}
#endif
