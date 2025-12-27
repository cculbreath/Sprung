//
//  PhaseReviewManager.swift
//  Sprung
//
//  Manages the manifest-driven multi-phase review workflow.
//  Handles phase progression, LLM interaction, and change application.
//

// MARK: - AI Review System Architecture
//
// ═══════════════════════════════════════════════════════════════════════════════
// HOW AI REVIEW WORKS - READ THIS BEFORE MODIFYING
// ═══════════════════════════════════════════════════════════════════════════════
//
// TreeNode is the SINGLE SOURCE OF TRUTH for AI review configuration.
// Manifest patterns provide INITIAL DEFAULTS; users can modify via UI.
//
// ═══════════════════════════════════════════════════════════════════════════════
// INITIALIZATION (Tree Creation Time)
// ═══════════════════════════════════════════════════════════════════════════════
//
// ExperienceDefaultsToTree.applyDefaultAIFields() parses manifest patterns
// and sets TreeNode state:
//
// | Pattern           | TreeNode Effect                                      |
// |-------------------|------------------------------------------------------|
// | skills.*.name     | skills.bundledAttributes = ["name"]                  |
// | skills[].keywords | skills.enumeratedAttributes = ["keywords"]           |
// | custom.jobTitles[]| jobTitles.status = .aiToReplace, children marked     |
// | custom.objective  | objective.status = .aiToReplace (scalar)             |
//
// ═══════════════════════════════════════════════════════════════════════════════
// TREE NODE STATE (Source of Truth)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Each TreeNode stores:
// - `bundledAttributes: [String]?` — Attributes bundled into 1 RevNode (Phase 1)
// - `enumeratedAttributes: [String]?` — Attributes as N separate RevNodes (Phase 2)
// - `status == .aiToReplace` — Node is selected for AI review
//
// UI can modify these properties (context menu toggle, etc.) to change behavior.
//
// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT FLOW (buildReviewRounds)
// ═══════════════════════════════════════════════════════════════════════════════
//
// buildReviewRounds() walks the tree and reads TreeNode state:
//
// 1. For nodes with `bundledAttributes`:
//    → Generate pattern like "skills.*.name"
//    → Export via TreeNode.exportNodesMatchingPath() → Phase 1 RevNodes
//
// 2. For nodes with `enumeratedAttributes`:
//    → Generate pattern like "skills[].keywords"
//    → Export via TreeNode.exportNodesMatchingPath() → Phase 2 RevNodes
//
// 3. For container nodes where all children are aiToReplace:
//    → Generate pattern like "custom.jobTitles[]"
//    → Export as container enumerate → Phase 2 RevNodes
//
// 4. For scalar nodes with aiToReplace and no children:
//    → Export directly → Phase 2 RevNodes
//
// ═══════════════════════════════════════════════════════════════════════════════
// PATTERN SYNTAX (Path Specifiers)
// ═══════════════════════════════════════════════════════════════════════════════
//
// | Symbol | Meaning                 | Result                              |
// |--------|-------------------------|-------------------------------------|
// | *      | Bundle all children     | 1 RevNode with all values combined  |
// | []     | Iterate children        | N RevNodes, one per child           |
// | .name  | Navigate to field       | Match specific attribute            |
//
// Examples:
// - skills.*.name   → 1 RevNode: ["Programming", "Data Science", ...]
// - skills[].name   → 5 RevNodes: "Programming", "Data Science", ...
// - work[].bullets  → 4 RevNodes: each job's bullets array
//
// ═══════════════════════════════════════════════════════════════════════════════
// PHASE ASSIGNMENT
// ═══════════════════════════════════════════════════════════════════════════════
//
// - Phase 1: bundledAttributes patterns (need holistic review first)
// - Phase 2: Everything else (enumerated, scalars, container enumerates)
//
// Phase 1 changes are applied to tree before Phase 2 export, so Phase 2
// content can reference updated names (e.g., keywords under renamed skills).
//
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import SwiftUI
import SwiftData
import SwiftOpenAI

/// Delegate protocol for phase review manager to communicate with the view model
@MainActor
protocol PhaseReviewDelegate: AnyObject {
    var currentConversationId: UUID? { get }
    var currentModelId: String? { get }
    var openRouterService: OpenRouterService { get }

    func setConversationContext(conversationId: UUID, modelId: String)
    func showReviewSheet()
    func hideReviewSheet()
    func setProcessingRevisions(_ processing: Bool)
    func setWorkflowCompleted()
    func markWorkflowStarted()
}

/// Manages the generic manifest-driven multi-phase review workflow.
@MainActor
@Observable
class PhaseReviewManager {
    // MARK: - Dependencies
    private let llm: LLMFacade
    private let openRouterService: OpenRouterService
    private let reasoningStreamManager: ReasoningStreamManager
    private let exportCoordinator: ResumeExportCoordinator
    private let streamingService: RevisionStreamingService
    private let applicantProfileStore: ApplicantProfileStore
    private let resRefStore: ResRefStore
    private let toolRunner: ToolConversationRunner
    weak var delegate: PhaseReviewDelegate?

    // MARK: - Phase Review State
    var phaseReviewState = PhaseReviewState()

    /// Computed property for view compatibility
    var isHierarchicalReviewActive: Bool {
        phaseReviewState.isActive
    }

    init(
        llm: LLMFacade,
        openRouterService: OpenRouterService,
        reasoningStreamManager: ReasoningStreamManager,
        exportCoordinator: ResumeExportCoordinator,
        streamingService: RevisionStreamingService,
        applicantProfileStore: ApplicantProfileStore,
        resRefStore: ResRefStore,
        toolRunner: ToolConversationRunner
    ) {
        self.llm = llm
        self.openRouterService = openRouterService
        self.reasoningStreamManager = reasoningStreamManager
        self.exportCoordinator = exportCoordinator
        self.streamingService = streamingService
        self.applicantProfileStore = applicantProfileStore
        self.resRefStore = resRefStore
        self.toolRunner = toolRunner
    }

    // MARK: - Tool UI State Forwarding

    var showSkillExperiencePicker: Bool {
        get { toolRunner.showSkillExperiencePicker }
        set { toolRunner.showSkillExperiencePicker = newValue }
    }

    var pendingSkillQueries: [SkillQuery] {
        get { toolRunner.pendingSkillQueries }
        set { toolRunner.pendingSkillQueries = newValue }
    }

    func submitSkillExperienceResults(_ results: [SkillExperienceResult]) {
        toolRunner.submitSkillExperienceResults(results)
    }

    func cancelSkillExperienceQuery() {
        toolRunner.cancelSkillExperienceQuery()
    }

    // MARK: - Tool Response Parsing

    /// Parse PhaseReviewContainer from a raw LLM response string (used with tool-enabled conversations)
    private func parsePhaseReviewFromResponse(_ response: String) throws -> PhaseReviewContainer {
        // Try to extract JSON from the response
        // The response may contain markdown code blocks or just raw JSON
        let jsonString: String
        if let jsonStart = response.range(of: "{"),
           let jsonEnd = response.range(of: "}", options: .backwards) {
            jsonString = String(response[jsonStart.lowerBound...jsonEnd.upperBound])
        } else {
            jsonString = response
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw LLMError.clientError("Failed to convert response to data")
        }

        do {
            return try JSONDecoder().decode(PhaseReviewContainer.self, from: data)
        } catch {
            Logger.error("Failed to parse phase review from response: \(error.localizedDescription)")
            Logger.debug("Response was: \(response.prefix(500))...")
            throw LLMError.clientError("Failed to parse phase review response: \(error.localizedDescription)")
        }
    }

    /// Build system prompt augmentation for tool-enabled phase review
    private func buildToolSystemPromptAddendum() -> String {
        return """

            You have access to the `query_user_experience_level` tool.
            Use this tool when you suspect the applicant has a skill that strongly aligns with
            job requirements, but direct evidence is not in the background documents. For example,
            a physicist likely has familiarity with electricity and magnetism even if their docs
            only mention particle physics, or a React developer may have React Native experience.

            If the tool returns an error indicating the user skipped the query, proceed with
            your best judgment based on available information.

            After gathering any needed information via tools, provide your review proposals
            in the specified JSON format.
            """
    }

    /// Merge original values from exported nodes into review container items.
    /// LLMs may not reliably echo back original values, so we ensure they're populated from source data.
    private func mergeOriginalValues(
        into container: PhaseReviewContainer,
        from nodes: [ExportedReviewNode]
    ) -> PhaseReviewContainer {
        let nodeById = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        let mergedItems = container.items.map { item -> PhaseReviewItem in
            var merged = item
            if let sourceNode = nodeById[item.id] {
                // Ensure originalValue is populated
                if merged.originalValue.isEmpty {
                    merged.originalValue = sourceNode.value
                }
                // Ensure originalChildren is populated for containers
                if merged.originalChildren == nil || merged.originalChildren?.isEmpty == true {
                    merged.originalChildren = sourceNode.childValues
                }
            }
            return merged
        }

        return PhaseReviewContainer(
            section: container.section,
            phaseNumber: container.phaseNumber,
            fieldPath: container.fieldPath,
            isBundled: container.isBundled,
            items: mergedItems
        )
    }

    // MARK: - Phase Detection

    /// Find sections with review phases defined that have nodes selected for AI revision.
    func sectionsWithActiveReviewPhases(for resume: Resume) -> [(section: String, phases: [TemplateManifest.ReviewPhaseConfig])] {
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] Starting check...")
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] template: \(resume.template != nil ? "exists" : "nil")")
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] manifestData: \(resume.template?.manifestData != nil ? "\(resume.template!.manifestData!.count) bytes" : "nil")")
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] rootNode: \(resume.rootNode != nil ? "exists" : "nil")")

        guard let template = resume.template,
              let rootNode = resume.rootNode else {
            Logger.warning("⚠️ [sectionsWithActiveReviewPhases] Bailing - template or rootNode nil")
            return []
        }

        guard let manifest = TemplateManifestLoader.manifest(for: template) else {
            Logger.warning("⚠️ [sectionsWithActiveReviewPhases] Failed to load manifest via TemplateManifestLoader")
            return []
        }
        Logger.debug("🔍 [sectionsWithActiveReviewPhases] manifest loaded via TemplateManifestLoader")

        Logger.debug("🔍 [sectionsWithActiveReviewPhases] reviewPhases: \(manifest.reviewPhases != nil ? "\(manifest.reviewPhases!.keys.joined(separator: ", "))" : "nil")")

        var result: [(section: String, phases: [TemplateManifest.ReviewPhaseConfig])] = []

        if let reviewPhases = manifest.reviewPhases {
            for (section, phases) in reviewPhases {
                Logger.debug("🔍 [sectionsWithActiveReviewPhases] Checking section '\(section)' with \(phases.count) phases")
                if let sectionNode = rootNode.children?.first(where: { $0.name.lowercased() == section.lowercased() }) {
                    let hasSelected = sectionNode.status == .aiToReplace || sectionNode.aiStatusChildren > 0
                    Logger.debug("🔍 [sectionsWithActiveReviewPhases] Section '\(section)' found - status=\(sectionNode.status), aiStatusChildren=\(sectionNode.aiStatusChildren), hasSelected=\(hasSelected)")
                    if hasSelected && !phases.isEmpty {
                        let sortedPhases = phases.sorted { $0.phase < $1.phase }
                        result.append((section: section, phases: sortedPhases))
                        Logger.info("📋 Section '\(section)' has \(sortedPhases.count) review phases configured - USING PHASED REVIEW")
                    }
                } else {
                    Logger.debug("🔍 [sectionsWithActiveReviewPhases] Section '\(section)' NOT found in rootNode.children")
                }
            }
        } else {
            Logger.debug("🔍 [sectionsWithActiveReviewPhases] manifest.reviewPhases is nil")
        }

        Logger.debug("🔍 [sectionsWithActiveReviewPhases] Returning \(result.count) sections with active phases")
        return result
    }

    /// Build the two-round review structure from TreeNode state.
    ///
    /// TreeNode is the single source of truth for AI review configuration:
    /// - `bundledAttributes`: Attributes to bundle into 1 RevNode
    /// - `enumeratedAttributes`: Attributes to enumerate as N RevNodes
    /// - `status == .aiToReplace`: Scalar nodes or container items to review
    ///
    /// Phase assignments come from `resume.phaseAssignments` (populated from manifest defaults
    /// at tree creation time, then editable via Phase Assignments panel).
    /// Fallback: bundle=1, enumerate/scalar=2
    func buildReviewRounds(for resume: Resume) -> (phase1: [ExportedReviewNode], phase2: [ExportedReviewNode]) {
        guard let rootNode = resume.rootNode else {
            Logger.warning("⚠️ [buildReviewRounds] No rootNode")
            return ([], [])
        }

        var phase1Nodes: [ExportedReviewNode] = []
        var phase2Nodes: [ExportedReviewNode] = []
        var processedPaths = Set<String>()

        // Phase assignments: key exists = phase 1, absent = phase 2 (default)
        let phase1Keys = Set(resume.phaseAssignments.keys)

        /// Get phase for a section+attribute combination
        /// Key present in phaseAssignments = phase 1, absent = phase 2
        func phaseFor(section: String, attr: String) -> Int {
            let groupKey = "\(section)-\(attr)"
            return phase1Keys.contains(groupKey) ? 1 : 2
        }

        /// Add nodes to appropriate phase
        func addToPhase(_ nodes: [ExportedReviewNode], phase: Int, pattern: String) {
            if phase == 1 {
                phase1Nodes.append(contentsOf: nodes)
                Logger.debug("📋 [buildReviewRounds] '\(pattern)' → \(nodes.count) Phase 1 RevNodes")
            } else {
                phase2Nodes.append(contentsOf: nodes)
                Logger.debug("📋 [buildReviewRounds] '\(pattern)' → \(nodes.count) Phase 2 RevNodes")
            }
        }

        // Walk tree and collect patterns from TreeNode state
        func processNode(_ node: TreeNode, parentPath: String, sectionName: String) {
            let nodeName = node.name.isEmpty ? node.value : node.name
            let currentPath = parentPath.isEmpty ? nodeName : "\(parentPath).\(nodeName)"
            // Capitalize section name to match manifest key format (e.g., "Skills-name")
            let currentSection = (sectionName.isEmpty ? nodeName : sectionName).capitalized

            // Check for collection patterns (bundled/enumerated attributes)
            if let bundled = node.bundledAttributes, !bundled.isEmpty {
                for attr in bundled {
                    let pattern = "\(currentPath).*.\(attr)"
                    if !processedPaths.contains(pattern) {
                        processedPaths.insert(pattern)
                        let nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                        let phase = phaseFor(section: currentSection, attr: attr)
                        addToPhase(nodes, phase: phase, pattern: pattern)
                    }
                }
            }

            if let enumerated = node.enumeratedAttributes, !enumerated.isEmpty {
                for attr in enumerated {
                    // Skip container enumerate marker
                    guard attr != "*" else { continue }
                    let pattern = "\(currentPath)[].\(attr)"
                    if !processedPaths.contains(pattern) {
                        processedPaths.insert(pattern)
                        let nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                        let phase = phaseFor(section: currentSection, attr: attr)
                        addToPhase(nodes, phase: phase, pattern: pattern)
                    }
                }
            }

            // Check for container enumerate (enumeratedAttributes contains "*")
            if node.enumeratedAttributes?.contains("*") == true {
                let pattern = "\(currentPath)[]"
                if !processedPaths.contains(pattern) {
                    processedPaths.insert(pattern)
                    let nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                    let phase = phaseFor(section: currentSection, attr: "*")
                    addToPhase(nodes, phase: phase, pattern: pattern)
                }
            }

            // Check for scalar node (no children, AI-enabled)
            let isScalar = node.status == .aiToReplace &&
                           node.orderedChildren.isEmpty &&
                           node.bundledAttributes == nil &&
                           node.enumeratedAttributes == nil

            if isScalar && !processedPaths.contains(currentPath) {
                processedPaths.insert(currentPath)
                let nodes = TreeNode.exportNodesMatchingPath(currentPath, from: rootNode)
                // Scalar nodes default to phase 2
                addToPhase(nodes, phase: 2, pattern: currentPath)
            }

            // Recurse into children
            for child in node.orderedChildren {
                processNode(child, parentPath: currentPath, sectionName: currentSection)
            }
        }

        // Start from root's children (skip root itself)
        for section in rootNode.orderedChildren {
            processNode(section, parentPath: "", sectionName: "")
        }

        Logger.info("📋 Review rounds: Phase 1 has \(phase1Nodes.count) nodes, Phase 2 has \(phase2Nodes.count) nodes")
        return (phase1Nodes, phase2Nodes)
    }

    /// Tracks whether phase 1 has been completed
    private var phase1Completed = false

    /// Cached phase 2 nodes (populated after phase 1 completes)
    private var cachedPhase2Nodes: [ExportedReviewNode] = []

    // MARK: - Two-Round Workflow

    /// Start the two-round review workflow.
    /// Round 1: Phase 1 items from configured sections
    /// Round 2: Everything else (phase 2+ items + all other AI-selected nodes)
    func startTwoRoundReview(resume: Resume, modelId: String) async throws {
        delegate?.markWorkflowStarted()
        delegate?.setProcessingRevisions(true)

        // Reset state
        phase1Completed = false
        cachedPhase2Nodes = []
        phaseReviewState.reset()

        guard resume.rootNode != nil else {
            Logger.error("❌ No root node found")
            delegate?.setProcessingRevisions(false)
            delegate?.setWorkflowCompleted()
            throw NSError(domain: "PhaseReviewManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No root node found"])
        }

        // Build both rounds upfront
        let (phase1Nodes, phase2Nodes) = buildReviewRounds(for: resume)
        cachedPhase2Nodes = phase2Nodes

        // Determine which round to start with
        let nodesToReview: [ExportedReviewNode]
        let roundNumber: Int

        if !phase1Nodes.isEmpty {
            nodesToReview = phase1Nodes
            roundNumber = 1
            Logger.info("🚀 Starting Round 1 with \(phase1Nodes.count) nodes")
        } else if !phase2Nodes.isEmpty {
            nodesToReview = phase2Nodes
            roundNumber = 2
            phase1Completed = true  // Skip phase 1 if empty
            Logger.info("🚀 No Phase 1 nodes, starting Round 2 with \(phase2Nodes.count) nodes")
        } else {
            Logger.warning("⚠️ No nodes to review")
            delegate?.setProcessingRevisions(false)
            delegate?.setWorkflowCompleted()
            return
        }

        try await startRound(
            nodes: nodesToReview,
            roundNumber: roundNumber,
            resume: resume,
            modelId: modelId
        )
    }

    /// Start a review round with the given nodes
    private func startRound(
        nodes: [ExportedReviewNode],
        roundNumber: Int,
        resume: Resume,
        modelId: String
    ) async throws {
        // Detect bundle mode from tree selection pattern:
        // If any exported node is bundled (parent AI-enabled), use bundled review
        // Otherwise use per-item (unbundled) review
        let isBundledReview = nodes.contains { $0.isBundled }

        // Initialize phase review state for this round
        phaseReviewState.isActive = true
        phaseReviewState.currentSection = roundNumber == 1 ? "Phase 1" : "All Fields"
        phaseReviewState.phases = [TemplateManifest.ReviewPhaseConfig(phase: roundNumber, field: "*", bundle: isBundledReview)]
        phaseReviewState.currentPhaseIndex = 0

        Logger.info("🚀 Starting Round \(roundNumber) - \(nodes.count) nodes (bundled: \(isBundledReview))")

        do {
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                allResRefs: resRefStore.resRefs,
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            let sectionName = roundNumber == 1 ? "Phase 1" : "All Fields"
            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.phaseReviewPrompt(
                section: sectionName,
                phaseNumber: roundNumber,
                fieldPath: "*",
                nodes: nodes,
                isBundled: isBundledReview
            )

            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            let useTools = toolRunner.shouldUseTools(modelId: modelId, openRouterService: openRouterService)

            Logger.debug("🤖 [startRound] Model: \(modelId), supportsReasoning: \(supportsReasoning), useTools: \(useTools)")

            if !supportsReasoning {
                reasoningStreamManager.hideAndClear()
            }

            let reviewContainer: PhaseReviewContainer

            if supportsReasoning {
                Logger.info("🧠 Using streaming with reasoning for round \(roundNumber): \(modelId)")
                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

                let result = try await streamingService.startConversationStreaming(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema,
                    as: PhaseReviewContainer.self
                )

                delegate?.setConversationContext(conversationId: result.conversationId, modelId: modelId)
                reviewContainer = result.response

            } else if useTools {
                Logger.info("🔧 [Tools] Using tool-enabled conversation for round \(roundNumber): \(modelId)")

                let toolSystemPrompt = systemPrompt + buildToolSystemPromptAddendum()

                // Force QueryUserExperienceTool on round 2 if debug setting is enabled
                let initialToolChoice: ToolChoice?
                if roundNumber == 2 && UserDefaults.standard.bool(forKey: "forceQueryUserExperienceTool") {
                    initialToolChoice = .function(name: QueryUserExperienceLevelTool.name)
                    Logger.info("🔧 [Tools] Debug: Forcing initial tool choice to \(QueryUserExperienceLevelTool.name)")
                } else {
                    initialToolChoice = nil
                }

                let finalResponse = try await toolRunner.runConversation(
                    systemPrompt: toolSystemPrompt,
                    userPrompt: userPrompt + "\n\nPlease provide your review proposals in the specified JSON format.",
                    modelId: modelId,
                    resume: resume,
                    jobApp: nil,
                    initialToolChoice: initialToolChoice
                )

                reviewContainer = try parsePhaseReviewFromResponse(finalResponse)

            } else {
                Logger.info("📝 Using non-streaming for round \(roundNumber): \(modelId)")

                let (conversationId, _) = try await llm.startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userPrompt,
                    modelId: modelId
                )

                delegate?.setConversationContext(conversationId: conversationId, modelId: modelId)

                reviewContainer = try await llm.continueConversationStructured(
                    userMessage: "Please provide your review proposals in the specified JSON format.",
                    modelId: modelId,
                    conversationId: conversationId,
                    as: PhaseReviewContainer.self,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema
                )
            }

            // Merge original values from source nodes (LLM may not reliably echo them back)
            let mergedContainer = mergeOriginalValues(into: reviewContainer, from: nodes)
            phaseReviewState.currentReview = mergedContainer
            Logger.info("✅ Round \(roundNumber) received \(mergedContainer.items.count) review proposals")

            // Always unbundled - individual item review
            phaseReviewState.pendingItemIds = mergedContainer.items.map { $0.id }
            phaseReviewState.currentItemIndex = 0

            reasoningStreamManager.hideAndClear()
            delegate?.showReviewSheet()
            delegate?.setProcessingRevisions(false)

        } catch {
            Logger.error("❌ Round \(roundNumber) failed: \(error.localizedDescription)")
            delegate?.setProcessingRevisions(false)
            phaseReviewState.reset()
            delegate?.setWorkflowCompleted()
            throw error
        }
    }

    /// Complete the current phase and move to the next one.
    /// If there are rejected items, applies accepted changes first, then triggers resubmission.
    func completeCurrentPhase(resume: Resume, context: ModelContext) {
        guard let currentReview = phaseReviewState.currentReview,
              let rootNode = resume.rootNode else { return }

        // Check if there are rejected items that need resubmission
        if hasItemsNeedingResubmission {
            let rejectedCount = itemsNeedingResubmission.count
            let acceptedItems = currentReview.items.filter {
                $0.userDecision == .accepted || $0.userDecision == .acceptedOriginal
            }

            // Apply accepted changes NOW before resubmission
            if !acceptedItems.isEmpty {
                let acceptedReview = PhaseReviewContainer(
                    section: currentReview.section,
                    phaseNumber: currentReview.phaseNumber,
                    fieldPath: currentReview.fieldPath,
                    isBundled: currentReview.isBundled,
                    items: acceptedItems
                )
                TreeNode.applyPhaseReviewChanges(acceptedReview, to: rootNode, context: context)
                Logger.info("✅ Applied \(acceptedItems.count) accepted items before resubmission")
            }

            Logger.info("🔄 Resubmitting \(rejectedCount) rejected items")

            // Capture review before clearing for UI
            let reviewForResubmission = currentReview

            // Show loading state IMMEDIATELY before async work
            delegate?.setProcessingRevisions(true)
            phaseReviewState.currentReview = nil  // Clear so UI shows loading, not "no items"

            Task {
                do {
                    try await performPhaseResubmission(resume: resume, originalReview: reviewForResubmission)
                } catch {
                    Logger.error("❌ Resubmission failed: \(error.localizedDescription)")
                    // On failure, advance anyway
                    advanceToNextRound(resume: resume)
                }
            }
            return
        }

        // No rejected items - apply all changes and advance
        applyAllChangesAndAdvance(currentReview: currentReview, rootNode: rootNode, context: context, resume: resume)
    }

    /// Apply all accepted changes from current review and advance to next round.
    private func applyAllChangesAndAdvance(currentReview: PhaseReviewContainer, rootNode: TreeNode, context: ModelContext, resume: Resume) {
        TreeNode.applyPhaseReviewChanges(currentReview, to: rootNode, context: context)
        phaseReviewState.approvedReviews.append(currentReview)

        let roundNumber = phaseReviewState.phases.first?.phase ?? 1
        Logger.info("✅ Round \(roundNumber) complete - all items accepted")

        advanceToNextRound(resume: resume)
    }

    /// Advance to the next round (called after changes applied).
    private func advanceToNextRound(resume: Resume) {
        finishPhaseReview(resume: resume)
    }

    /// Advance to the next phase or finish the workflow.
    private func advanceToNextPhase(resume: Resume) async {
        phaseReviewState.currentPhaseIndex += 1
        phaseReviewState.currentReview = nil
        phaseReviewState.pendingItemIds = []
        phaseReviewState.currentItemIndex = 0

        if phaseReviewState.currentPhaseIndex >= phaseReviewState.phases.count {
            finishPhaseReview(resume: resume)
            return
        }

        guard let nextPhase = phaseReviewState.currentPhase,
              let rootNode = resume.rootNode,
              let modelId = delegate?.currentModelId else {
            finishPhaseReview(resume: resume)
            return
        }

        delegate?.setProcessingRevisions(true)

        do {
            let exportedNodes = TreeNode.exportNodesMatchingPath(nextPhase.field, from: rootNode)
            guard !exportedNodes.isEmpty else {
                Logger.warning("⚠️ No nodes found for phase \(nextPhase.phase)")
                await advanceToNextPhase(resume: resume)
                return
            }

            Logger.info("🚀 Starting Phase \(nextPhase.phase) - \(exportedNodes.count) nodes")

            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                allResRefs: resRefStore.resRefs,
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.phaseReviewPrompt(
                section: phaseReviewState.currentSection,
                phaseNumber: nextPhase.phase,
                fieldPath: nextPhase.field,
                nodes: exportedNodes,
                isBundled: nextPhase.bundle
            )

            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            let useTools = toolRunner.shouldUseTools(modelId: modelId, openRouterService: openRouterService)

            Logger.debug("🤖 [advanceToNextPhase] Model: \(modelId), supportsReasoning: \(supportsReasoning), useTools: \(useTools)")

            let reviewContainer: PhaseReviewContainer

            if supportsReasoning {
                guard let conversationId = delegate?.currentConversationId else {
                    Logger.error("❌ No conversation context for next phase (reasoning)")
                    finishPhaseReview(resume: resume)
                    return
                }

                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

                reviewContainer = try await streamingService.continueConversationStreaming(
                    userMessage: userPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema,
                    as: PhaseReviewContainer.self
                )

            } else if useTools {
                // Tool conversations start fresh for each phase (tool runner manages its own context)
                Logger.info("🔧 [Tools] Using tool-enabled conversation for phase \(nextPhase.phase): \(modelId)")

                let toolSystemPrompt = systemPrompt + buildToolSystemPromptAddendum()

                let finalResponse = try await toolRunner.runConversation(
                    systemPrompt: toolSystemPrompt,
                    userPrompt: userPrompt + "\n\nPlease provide your review proposals in the specified JSON format.",
                    modelId: modelId,
                    resume: resume,
                    jobApp: nil
                )

                reviewContainer = try parsePhaseReviewFromResponse(finalResponse)

            } else {
                guard let conversationId = delegate?.currentConversationId else {
                    Logger.error("❌ No conversation context for next phase (non-reasoning)")
                    finishPhaseReview(resume: resume)
                    return
                }

                reviewContainer = try await llm.continueConversationStructured(
                    userMessage: userPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    as: PhaseReviewContainer.self,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema
                )
            }

            // Merge original values from source nodes (LLM may not reliably echo them back)
            let mergedContainer = mergeOriginalValues(into: reviewContainer, from: exportedNodes)
            phaseReviewState.currentReview = mergedContainer

            if !nextPhase.bundle {
                phaseReviewState.pendingItemIds = mergedContainer.items.map { $0.id }
                phaseReviewState.currentItemIndex = 0
            }

            reasoningStreamManager.hideAndClear()
            delegate?.setProcessingRevisions(false)

        } catch {
            Logger.error("❌ Phase \(nextPhase.phase) failed: \(error.localizedDescription)")
            delegate?.setProcessingRevisions(false)
            await advanceToNextPhase(resume: resume)
        }
    }

    // MARK: - Item-Level Operations (Unbundled Phases)

    /// Accept current review item and move to next (for unbundled phases).
    func acceptCurrentItemAndMoveNext(resume: Resume, context: ModelContext) {
        guard var currentReview = phaseReviewState.currentReview,
              phaseReviewState.currentItemIndex < currentReview.items.count else { return }

        currentReview.items[phaseReviewState.currentItemIndex].userDecision = .accepted
        phaseReviewState.currentReview = currentReview

        phaseReviewState.currentItemIndex += 1

        if phaseReviewState.currentItemIndex >= currentReview.items.count {
            completeCurrentPhase(resume: resume, context: context)
        }
    }

    /// Reject current review item and move to next (for unbundled phases).
    /// This marks for LLM resubmission without feedback.
    func rejectCurrentItemAndMoveNext() {
        guard var currentReview = phaseReviewState.currentReview,
              phaseReviewState.currentItemIndex < currentReview.items.count else { return }

        currentReview.items[phaseReviewState.currentItemIndex].userDecision = .rejected
        phaseReviewState.currentReview = currentReview

        phaseReviewState.currentItemIndex += 1
    }

    /// Reject current review item with feedback and move to next.
    /// This marks for LLM resubmission with user feedback.
    func rejectCurrentItemWithFeedback(_ feedback: String) {
        guard var currentReview = phaseReviewState.currentReview,
              phaseReviewState.currentItemIndex < currentReview.items.count else { return }

        currentReview.items[phaseReviewState.currentItemIndex].userDecision = .rejectedWithFeedback
        currentReview.items[phaseReviewState.currentItemIndex].userComment = feedback
        phaseReviewState.currentReview = currentReview

        phaseReviewState.currentItemIndex += 1
    }

    /// Accept current item with user edits and move to next.
    func acceptCurrentItemWithEdits(_ editedValue: String?, editedChildren: [String]?, resume: Resume, context: ModelContext) {
        guard var currentReview = phaseReviewState.currentReview,
              phaseReviewState.currentItemIndex < currentReview.items.count else { return }

        currentReview.items[phaseReviewState.currentItemIndex].userDecision = .accepted
        currentReview.items[phaseReviewState.currentItemIndex].editedValue = editedValue
        currentReview.items[phaseReviewState.currentItemIndex].editedChildren = editedChildren
        phaseReviewState.currentReview = currentReview

        phaseReviewState.currentItemIndex += 1

        if phaseReviewState.currentItemIndex >= currentReview.items.count {
            completeCurrentPhase(resume: resume, context: context)
        }
    }

    /// Revert to original value and accept (no change applied).
    func acceptOriginalAndMoveNext(resume: Resume, context: ModelContext) {
        guard var currentReview = phaseReviewState.currentReview,
              phaseReviewState.currentItemIndex < currentReview.items.count else { return }

        currentReview.items[phaseReviewState.currentItemIndex].userDecision = .acceptedOriginal
        phaseReviewState.currentReview = currentReview

        phaseReviewState.currentItemIndex += 1

        if phaseReviewState.currentItemIndex >= currentReview.items.count {
            completeCurrentPhase(resume: resume, context: context)
        }
    }

    // MARK: - Navigation

    /// Navigate to previous item (for unbundled phases).
    func goToPreviousItem() {
        guard phaseReviewState.currentItemIndex > 0 else { return }
        phaseReviewState.currentItemIndex -= 1
    }

    /// Navigate to next item (for unbundled phases).
    func goToNextItem() {
        guard let currentReview = phaseReviewState.currentReview,
              phaseReviewState.currentItemIndex < currentReview.items.count - 1 else { return }
        phaseReviewState.currentItemIndex += 1
    }

    /// Navigate to specific item index.
    func goToItem(at index: Int) {
        guard let currentReview = phaseReviewState.currentReview,
              index >= 0 && index < currentReview.items.count else { return }
        phaseReviewState.currentItemIndex = index
    }

    /// Check if can navigate to previous item.
    var canGoToPrevious: Bool {
        phaseReviewState.currentItemIndex > 0
    }

    /// Check if can navigate to next item.
    var canGoToNext: Bool {
        guard let currentReview = phaseReviewState.currentReview else { return false }
        return phaseReviewState.currentItemIndex < currentReview.items.count - 1
    }

    /// Check if any items need LLM resubmission.
    var hasItemsNeedingResubmission: Bool {
        guard let currentReview = phaseReviewState.currentReview else { return false }
        return currentReview.items.contains { $0.userDecision == .rejected || $0.userDecision == .rejectedWithFeedback }
    }

    /// Get items that need resubmission.
    var itemsNeedingResubmission: [PhaseReviewItem] {
        guard let currentReview = phaseReviewState.currentReview else { return [] }
        return currentReview.items.filter { $0.userDecision == .rejected || $0.userDecision == .rejectedWithFeedback }
    }

    // MARK: - Resubmission

    /// Perform LLM resubmission for rejected items in current phase.
    /// After receiving new proposals, merges them back and resets for re-review.
    func performPhaseResubmission(resume: Resume, originalReview: PhaseReviewContainer) async throws {
        guard let currentPhase = phaseReviewState.currentPhase,
              let modelId = delegate?.currentModelId else {
            Logger.error("❌ Cannot perform resubmission: missing phase or model")
            return
        }

        let rejectedItems = originalReview.items.filter {
            $0.userDecision == .rejected || $0.userDecision == .rejectedWithFeedback
        }
        guard !rejectedItems.isEmpty else {
            Logger.warning("⚠️ performPhaseResubmission called but no rejected items")
            return
        }

        Logger.info("🔄 Starting phase resubmission for \(rejectedItems.count) rejected items")
        // Processing state already set by caller

        do {
            let query = ResumeApiQuery(
                resume: resume,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfileStore.currentProfile(),
                allResRefs: resRefStore.resRefs,
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )

            let systemPrompt = query.genericSystemMessage.textContent
            let userPrompt = await query.phaseResubmissionPrompt(
                section: phaseReviewState.currentSection,
                phaseNumber: currentPhase.phase,
                fieldPath: currentPhase.field,
                rejectedItems: rejectedItems,
                isBundled: currentPhase.bundle
            )

            let model = openRouterService.findModel(id: modelId)
            let supportsReasoning = model?.supportsReasoning ?? false
            let useTools = toolRunner.shouldUseTools(modelId: modelId, openRouterService: openRouterService)

            Logger.debug("🤖 [performPhaseResubmission] Model: \(modelId), supportsReasoning: \(supportsReasoning), useTools: \(useTools)")

            let resubmissionResponse: PhaseReviewContainer

            if supportsReasoning {
                guard let conversationId = delegate?.currentConversationId else {
                    Logger.error("❌ No conversation context for resubmission (reasoning)")
                    delegate?.setProcessingRevisions(false)
                    return
                }

                let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
                let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

                resubmissionResponse = try await streamingService.continueConversationStreaming(
                    userMessage: userPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    reasoning: reasoning,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema,
                    as: PhaseReviewContainer.self
                )

            } else if useTools {
                Logger.info("🔧 [Tools] Using tool-enabled conversation for resubmission: \(modelId)")

                let toolSystemPrompt = systemPrompt + buildToolSystemPromptAddendum()

                let finalResponse = try await toolRunner.runConversation(
                    systemPrompt: toolSystemPrompt,
                    userPrompt: userPrompt + "\n\nPlease provide your revised proposals in the specified JSON format.",
                    modelId: modelId,
                    resume: resume,
                    jobApp: nil
                )

                resubmissionResponse = try parsePhaseReviewFromResponse(finalResponse)

            } else {
                guard let conversationId = delegate?.currentConversationId else {
                    Logger.error("❌ No conversation context for resubmission (non-reasoning)")
                    delegate?.setProcessingRevisions(false)
                    return
                }

                resubmissionResponse = try await llm.continueConversationStructured(
                    userMessage: userPrompt,
                    modelId: modelId,
                    conversationId: conversationId,
                    as: PhaseReviewContainer.self,
                    jsonSchema: ResumeApiQuery.phaseReviewSchema
                )
            }

            // Merge resubmission results back into review
            mergeResubmissionResults(resubmissionResponse, into: originalReview)

            Logger.info("✅ Phase resubmission complete: \(resubmissionResponse.items.count) revised proposals received")

            // Reset to beginning for re-review
            phaseReviewState.currentItemIndex = 0
            reasoningStreamManager.hideAndClear()
            delegate?.setProcessingRevisions(false)

        } catch {
            Logger.error("❌ Phase resubmission failed: \(error.localizedDescription)")
            delegate?.setProcessingRevisions(false)
            throw error
        }
    }

    /// Replace the current review with ONLY the resubmitted items.
    /// Accepted items have already been applied, so we only need to track the rejected ones.
    private func mergeResubmissionResults(_ resubmission: PhaseReviewContainer, into original: PhaseReviewContainer) {
        // Get the original rejected items to preserve their originalValue
        let originalRejectedById = Dictionary(
            uniqueKeysWithValues: original.items
                .filter { $0.userDecision == .rejected || $0.userDecision == .rejectedWithFeedback }
                .map { ($0.id, $0) }
        )

        // Create new items from resubmission, preserving original values
        var newItems: [PhaseReviewItem] = []
        for newProposal in resubmission.items {
            let originalItem = originalRejectedById[newProposal.id]
            let item = PhaseReviewItem(
                id: newProposal.id,
                displayName: newProposal.displayName,
                originalValue: originalItem?.originalValue ?? newProposal.originalValue,
                proposedValue: newProposal.proposedValue,
                action: newProposal.action,
                reason: newProposal.reason,
                userDecision: .pending,
                userComment: "",
                editedValue: nil,
                editedChildren: nil,
                originalChildren: originalItem?.originalChildren ?? newProposal.originalChildren,
                proposedChildren: newProposal.proposedChildren
            )
            newItems.append(item)
            Logger.debug("🔄 Resubmitted item '\(item.displayName)' ready for re-review")
        }

        // Create fresh review container with only the resubmitted items
        let freshReview = PhaseReviewContainer(
            section: original.section,
            phaseNumber: original.phaseNumber,
            fieldPath: original.fieldPath,
            isBundled: original.isBundled,
            items: newItems
        )

        phaseReviewState.currentReview = freshReview
        Logger.info("📋 Review now contains \(newItems.count) resubmitted items for re-review")
    }

    // MARK: - Workflow Completion

    /// Finish the current round and check for more rounds.
    func finishPhaseReview(resume: Resume) {
        let completedRound = phaseReviewState.phases.first?.phase ?? 1
        Logger.info("🏁 Round \(completedRound) complete")
        Logger.info("  - Items reviewed: \(phaseReviewState.approvedReviews.count)")

        exportCoordinator.debounceExport(resume: resume)

        // Check if round 1 just completed and there's a round 2
        if !phase1Completed && !cachedPhase2Nodes.isEmpty {
            Logger.info("📋 Moving to Round 2 with \(cachedPhase2Nodes.count) nodes")
            phase1Completed = true

            guard let modelId = delegate?.currentModelId else {
                Logger.error("❌ No model ID for round 2")
                finalizeWorkflow()
                return
            }

            // Show loading state BEFORE clearing review
            delegate?.setProcessingRevisions(true)
            phaseReviewState.reset()

            Task {
                do {
                    try await startRound(
                        nodes: cachedPhase2Nodes,
                        roundNumber: 2,
                        resume: resume,
                        modelId: modelId
                    )
                } catch {
                    Logger.error("❌ Failed to start round 2: \(error.localizedDescription)")
                    finalizeWorkflow()
                }
            }
        } else {
            // All rounds complete - finalize the workflow
            Logger.info("✅ All rounds reviewed - workflow complete")
            finalizeWorkflow()
        }
    }

    /// Finalize the entire review workflow.
    private func finalizeWorkflow() {
        phase1Completed = false
        cachedPhase2Nodes = []
        phaseReviewState.reset()
        delegate?.hideReviewSheet()
        delegate?.setWorkflowCompleted()
    }

    /// Check if there are unapplied approved changes.
    func hasUnappliedApprovedChanges() -> Bool {
        !phaseReviewState.approvedReviews.isEmpty || phaseReviewState.currentReview != nil
    }

    /// Apply all approved changes and close.
    func applyApprovedChangesAndClose(resume: Resume, context: ModelContext) {
        guard let rootNode = resume.rootNode else { return }

        if let currentReview = phaseReviewState.currentReview {
            TreeNode.applyPhaseReviewChanges(currentReview, to: rootNode, context: context)
        }

        for review in phaseReviewState.approvedReviews {
            TreeNode.applyPhaseReviewChanges(review, to: rootNode, context: context)
        }

        exportCoordinator.debounceExport(resume: resume)

        phaseReviewState.reset()
        delegate?.hideReviewSheet()
        delegate?.setWorkflowCompleted()
    }

    /// Discard all changes and close.
    func discardAllAndClose() {
        phaseReviewState.reset()
        delegate?.hideReviewSheet()
        delegate?.setWorkflowCompleted()
    }
}
