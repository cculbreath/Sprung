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
    private let eventBus: EventCoordinator

    /// Provider for getting current session artifacts (avoids circular dependency with coordinator)
    private var sessionArtifactsProvider: (() -> [ArtifactRecord])?

    init(
        documentProcessingService: DocumentProcessingService,
        agentActivityTracker: AgentActivityTracker,
        cardMergeService: CardMergeService,
        knowledgeCardStore: KnowledgeCardStore,
        eventBus: EventCoordinator
    ) {
        self.documentProcessingService = documentProcessingService
        self.agentActivityTracker = agentActivityTracker
        self.cardMergeService = cardMergeService
        self.knowledgeCardStore = knowledgeCardStore
        self.eventBus = eventBus
    }

    /// Configure the provider for getting session artifacts
    func setSessionArtifactsProvider(_ provider: @escaping () -> [ArtifactRecord]) {
        self.sessionArtifactsProvider = provider
    }

    // MARK: - Regeneration Methods

    /// Clear all summaries and card inventories and regenerate them, then trigger merge
    func regenerateCardInventoriesAndMerge() async {
        Logger.debug("🔄 Clearing and regenerating ALL summaries + card inventories...", category: .ai)

        guard let sessionArtifacts = sessionArtifactsProvider?() else {
            Logger.warning("No session artifacts provider configured", category: .ai)
            return
        }

        // Get all non-writing-sample artifacts
        let artifactsToProcess = sessionArtifacts.filter { !$0.isWritingSample }

        Logger.debug("📦 Found \(artifactsToProcess.count) artifacts to regenerate", category: .ai)

        guard !artifactsToProcess.isEmpty else {
            Logger.debug("⚠️ No artifacts to process", category: .ai)
            return
        }

        // Clear existing summaries and knowledge extraction first
        for artifact in artifactsToProcess {
            artifact.summary = nil
            artifact.briefDescription = nil
            artifact.skillsJSON = nil
            artifact.narrativeCardsJSON = nil
            Logger.verbose("🗑️ Cleared summary + knowledge for: \(artifact.filename)", category: .ai)
        }

        // Use same concurrency limit as document extraction
        let maxConcurrent = UserDefaults.standard.integer(forKey: "onboardingMaxConcurrentExtractions")
        let concurrencyLimit = maxConcurrent > 0 ? maxConcurrent : 5

        Logger.debug("📦 Processing \(artifactsToProcess.count) artifacts with concurrency limit \(concurrencyLimit)", category: .ai)

        // Capture service reference for use in task group
        let processingService = documentProcessingService

        // Process with limited concurrency using TaskGroup
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var index = 0

            for artifact in artifactsToProcess {
                // Wait if we've hit the concurrency limit
                if inFlight >= concurrencyLimit {
                    await group.next()
                    inFlight -= 1
                }

                group.addTask {
                    await processingService.generateSummaryAndKnowledgeExtractionForExistingArtifact(artifact)
                }
                inFlight += 1
                index += 1
                Logger.verbose("📦 Dispatched \(index)/\(artifactsToProcess.count): \(artifact.filename)", category: .ai)
            }

            // Wait for all remaining tasks
            for await _ in group { }
        }

        Logger.debug("✅ All summary + inventory regeneration complete", category: .ai)

        // Trigger the merge
        Logger.debug("🔄 Triggering card merge...", category: .ai)
        await eventBus.publish(.doneWithUploadsClicked)
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
