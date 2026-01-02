import Foundation
import SwiftyJSON

/// Service responsible for knowledge card workflow: merge and generation.
/// Handles the full pipeline from "Done with Uploads" through card generation.
@MainActor
final class KnowledgeCardWorkflowService {
    private let ui: OnboardingUIState
    private let state: StateCoordinator
    private let resRefStore: ResRefStore
    private let eventBus: EventCoordinator
    private let cardMergeService: CardMergeService
    private let chatInventoryService: ChatInventoryService?
    private let agentActivityTracker: AgentActivityTracker
    private weak var sessionUIState: SessionUIState?
    private weak var phaseTransitionController: PhaseTransitionController?

    // LLM facade for prose generation (set after container init due to circular dependency)
    private var llmFacadeProvider: (() -> LLMFacade?)?

    init(
        ui: OnboardingUIState,
        state: StateCoordinator,
        resRefStore: ResRefStore,
        eventBus: EventCoordinator,
        cardMergeService: CardMergeService,
        chatInventoryService: ChatInventoryService?,
        agentActivityTracker: AgentActivityTracker,
        sessionUIState: SessionUIState,
        phaseTransitionController: PhaseTransitionController?
    ) {
        self.ui = ui
        self.state = state
        self.resRefStore = resRefStore
        self.eventBus = eventBus
        self.cardMergeService = cardMergeService
        self.chatInventoryService = chatInventoryService
        self.agentActivityTracker = agentActivityTracker
        self.sessionUIState = sessionUIState
        self.phaseTransitionController = phaseTransitionController
    }

    /// Set the LLM facade provider after container initialization
    func setLLMFacadeProvider(_ provider: @escaping () -> LLMFacade?) {
        self.llmFacadeProvider = provider
    }

    // MARK: - Event Handlers

    /// Handle "Done with Uploads" button click - runs the card merge workflow
    func handleDoneWithUploadsClicked() async {
        Logger.info("📋 Processing Done with Uploads - triggering card merge", category: .ai)

        // Deactivate document collection UI and indicate merge is in progress
        ui.isDocumentCollectionActive = false
        ui.isMergingCards = true
        await sessionUIState?.setDocumentCollectionActive(false)

        // Track merge in Agents pane
        let agentId = agentActivityTracker.trackAgent(
            type: .cardMerge,
            name: "Merging Card Inventories",
            task: nil as Task<Void, Never>?
        )

        agentActivityTracker.appendTranscript(
            agentId: agentId,
            entryType: .system,
            content: "Starting card inventory merge"
        )

        // Extract chat inventory before merge (so it's included in the merge)
        if let chatInventoryService = chatInventoryService {
            agentActivityTracker.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Extracting facts from conversation..."
            )
            do {
                if let chatArtifactId = try await chatInventoryService.extractAndCreateArtifact() {
                    agentActivityTracker.appendTranscript(
                        agentId: agentId,
                        entryType: .toolResult,
                        content: "Chat transcript artifact created",
                        details: "ID: \(chatArtifactId)"
                    )
                    Logger.info("💬 Chat inventory extracted and added to artifacts", category: .ai)
                } else {
                    agentActivityTracker.appendTranscript(
                        agentId: agentId,
                        entryType: .system,
                        content: "No career facts found in conversation"
                    )
                }
            } catch {
                Logger.warning("⚠️ Chat inventory extraction failed: \(error.localizedDescription)", category: .ai)
                agentActivityTracker.appendTranscript(
                    agentId: agentId,
                    entryType: .system,
                    content: "Chat extraction skipped: \(error.localizedDescription)"
                )
                // Continue with merge - chat extraction is optional
            }
        }

        // Get timeline for context
        let timeline = await state.artifacts.skeletonTimeline

        // Run the merge
        let mergedInventory: MergedCardInventory
        do {
            mergedInventory = try await cardMergeService.mergeInventories(timeline: timeline)
        } catch CardMergeService.CardMergeError.noInventories {
            agentActivityTracker.markFailed(agentId: agentId, error: "No document inventories available")
            ui.isMergingCards = false
            Logger.warning("⚠️ No document inventories available for merge", category: .ai)
            await sendChatMessage("I'm done uploading documents, but no card inventories were found. Please check the documents.")
            return
        } catch {
            agentActivityTracker.markFailed(agentId: agentId, error: error.localizedDescription)
            ui.isMergingCards = false
            Logger.error("❌ Card merge failed: \(error.localizedDescription)", category: .ai)
            await sendChatMessage("I'm done uploading documents. Card merge failed: \(error.localizedDescription)")
            return
        }

        // Update transcript with results
        let stats = mergedInventory.stats
        let typeBreakdown = "employment: \(stats.cardsByType.employment), project: \(stats.cardsByType.project), skill: \(stats.cardsByType.skill), achievement: \(stats.cardsByType.achievement), education: \(stats.cardsByType.education)"
        agentActivityTracker.appendTranscript(
            agentId: agentId,
            entryType: .toolResult,
            content: "Merged \(mergedInventory.mergedCards.count) cards from \(stats.totalInputCards) input cards",
            details: "Types: \(typeBreakdown)"
        )

        // Store merged inventory for detail views and gaps
        ui.mergedInventory = mergedInventory

        // Persist merged inventory to SwiftData (expensive LLM call result)
        if let inventoryJSON = try? JSONEncoder().encode(mergedInventory),
           let jsonString = String(data: inventoryJSON, encoding: .utf8) {
            await eventBus.publish(.mergedInventoryStored(inventoryJSON: jsonString))
        }

        // Mark agent complete and emit merge complete event
        agentActivityTracker.markCompleted(agentId: agentId)
        await eventBus.publish(.mergeComplete(cardCount: mergedInventory.mergedCards.count, gapCount: mergedInventory.gaps.count))

        // Update UI to show card assignments are ready
        ui.cardAssignmentsReadyForApproval = true
        ui.identifiedGapCount = mergedInventory.gaps.count

        // Build user message with card type summary and gaps
        var typeSummary: String = ""
        if stats.cardsByType.employment > 0 { typeSummary += "\(stats.cardsByType.employment) employment" }
        if stats.cardsByType.project > 0 { typeSummary += (typeSummary.isEmpty ? "" : ", ") + "\(stats.cardsByType.project) project" }
        if stats.cardsByType.skill > 0 { typeSummary += (typeSummary.isEmpty ? "" : ", ") + "\(stats.cardsByType.skill) skill" }
        if stats.cardsByType.achievement > 0 { typeSummary += (typeSummary.isEmpty ? "" : ", ") + "\(stats.cardsByType.achievement) achievement" }
        if stats.cardsByType.education > 0 { typeSummary += (typeSummary.isEmpty ? "" : ", ") + "\(stats.cardsByType.education) education" }

        var gapSummary = ""
        if !mergedInventory.gaps.isEmpty {
            let gapDescriptions = mergedInventory.gaps.prefix(5).map { gap -> String in
                let gapTypeDescription: String
                switch gap.gapType {
                case .missingPrimarySource: gapTypeDescription = "needs primary documentation"
                case .insufficientDetail: gapTypeDescription = "needs more detail"
                case .noQuantifiedOutcomes: gapTypeDescription = "needs quantified outcomes"
                }
                return "• \(gap.cardTitle): \(gapTypeDescription)"
            }
            gapSummary = "\n\nDocumentation gaps identified (\(mergedInventory.gaps.count) total):\n" + gapDescriptions.joined(separator: "\n")
            if mergedInventory.gaps.count > 5 {
                gapSummary += "\n...and \(mergedInventory.gaps.count - 5) more"
            }
        }

        // Merge complete - clear flag
        ui.isMergingCards = false

        // Notify LLM of results with gaps
        await sendChatMessage("""
            I'm done uploading documents. The system has merged card inventories and found \(mergedInventory.mergedCards.count) potential knowledge cards (\(typeSummary)). \
            Please review the proposed cards with me. I can exclude any cards that aren't relevant to me.\(gapSummary)
            """)
    }

    /// Handle "Generate Cards" button click - converts merged cards directly to ResRefs
    func handleGenerateCardsButtonClicked() async {
        Logger.info("🚀 Generate Cards button clicked - converting merged cards to ResRefs", category: .ai)

        // Get merged inventory from UI state (populated by card merge)
        guard let mergedInventory = ui.mergedInventory else {
            Logger.error("❌ No merged inventory found - user must click 'Done with Uploads' first", category: .ai)
            await eventBus.publish(.errorOccurred("No merged cards found. Please upload documents and click 'Done with Uploads' first."))
            return
        }

        // Filter out excluded cards
        let excludedIds = Set(ui.excludedCardIds)
        let cardsToConvert = mergedInventory.mergedCards.filter { !excludedIds.contains($0.cardId) }

        guard !cardsToConvert.isEmpty else {
            Logger.warning("⚠️ All cards have been excluded", category: .ai)
            await eventBus.publish(.errorOccurred("All cards have been excluded. Please include at least one card."))
            return
        }

        Logger.info("🚀 Converting \(cardsToConvert.count) merged cards to ResRefs (excluded: \(excludedIds.count))", category: .ai)

        // Build artifact ID → filename lookup for source attribution
        let allArtifacts = await state.artifactRecords
        var artifactLookup: [String: String] = [:]
        for artifact in allArtifacts {
            let id = artifact["artifact_id"].stringValue
            let filename = artifact["filename"].stringValue
            if !id.isEmpty && !filename.isEmpty {
                artifactLookup[id] = filename
            }
        }

        // Create converter with LLM facade for prose generation
        let llmFacade = llmFacadeProvider?()
        let converter = MergedCardToResRefConverter(llmFacade: llmFacade, eventBus: eventBus)

        // Update UI to show progress
        ui.isGeneratingCards = true
        var successCount = 0
        var failureCount = 0

        do {
            let resRefs = try await converter.convertAll(
                mergedCards: cardsToConvert,
                artifactLookup: artifactLookup
            ) { completed, total in
                Logger.debug("📊 Card conversion progress: \(completed)/\(total)", category: .ai)
            }

            successCount = resRefs.count
            failureCount = cardsToConvert.count - successCount

            // Persist all ResRefs and update filesystem mirror
            for resRef in resRefs {
                resRefStore.addResRef(resRef)
                // Update filesystem mirror for LLM browsing
                await phaseTransitionController?.updateResRefInFilesystem(resRef)
            }

            Logger.info("✅ Card generation complete: \(successCount) cards persisted", category: .ai)

        } catch {
            Logger.error("🚨 Card generation failed: \(error)", category: .ai)
            failureCount = cardsToConvert.count
            await eventBus.publish(.errorOccurred("Card generation failed: \(error.localizedDescription)"))
        }

        ui.isGeneratingCards = false

        // Notify LLM about the results
        await sendChatMessage("Knowledge card generation complete: \(successCount) cards created, \(failureCount) failed.")
    }

    // MARK: - Private Helpers

    private func sendChatMessage(_ text: String) async {
        var userMessage = JSON()
        userMessage["role"].string = "user"
        userMessage["content"].string = text
        await eventBus.publish(.llmEnqueueUserMessage(payload: userMessage, isSystemGenerated: true))
    }
}
