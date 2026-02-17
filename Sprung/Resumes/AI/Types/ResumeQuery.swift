//
//  ResumeQuery.swift
//  Sprung
//
//
import Foundation
import PDFKit
import AppKit
import SwiftUI
@Observable class ResumeApiQuery {
    // MARK: - Properties
    /// Set this to `true` if you want to save a debug file containing the prompt text.
    var saveDebugPrompt: Bool = false

    // Native SwiftOpenAI JSON Schema for revisions
    static let revNodeArraySchema: JSONSchema = {
        // Define the revision node schema
        let revisionNodeSchema = JSONSchema(
            type: .object,
            properties: [
                "id": JSONSchema(
                    type: .string,
                    description: "The identifier for the node provided in the original EditableNode"
                ),
                "oldValue": JSONSchema(
                    type: .string,
                    description: "The original value before revision provided in the original EditableNode"
                ),
                "newValue": JSONSchema(
                    type: .string,
                    description: "The proposed new value after revision (for scalar nodes or concatenated grouped content)"
                ),
                "oldValueArray": JSONSchema(
                    type: .array,
                    description: "For grouped nodes: the original child values as an array (optional, for reference)",
                    items: JSONSchema(type: .string)
                ),
                "newValueArray": JSONSchema(
                    type: .array,
                    description: "For grouped nodes: proposed new values as an array if adding/removing/reordering items",
                    items: JSONSchema(type: .string)
                ),
                "isGrouped": JSONSchema(
                    type: .boolean,
                    description: "Indicates if this node contains grouped content from multiple children"
                ),
                "valueChanged": JSONSchema(
                    type: .boolean,
                    description: "Indicates if the value is changed by the proposed revision"
                ),
                "why": JSONSchema(
                    type: .string,
                    description: "Explanation for the proposed revision. Leave blank if the reason is trivial or obvious"
                ),
                "isTitleNode": JSONSchema(
                    type: .boolean,
                    description: "Indicates whether the node shall be rendered as a title node. This value should not be modified from the value provided in the original EditableNode"
                ),
                "treePath": JSONSchema(
                    type: .string,
                    description: "The hierarchical path to the node (e.g., 'Resume > Experience > Bullet 1'). Return exactly the same value you received; do NOT modify it"
                )
            ],
            required: ["id", "oldValue", "newValue", "valueChanged", "why", "isTitleNode", "treePath"],
            additionalProperties: false
        )
        // Define the RevArray schema
        let revArraySchema = JSONSchema(
            type: .array,
            description: "IMPORTANT: Use exactly 'RevArray' as the property name (capital R)",
            items: revisionNodeSchema
        )
        // Define the root schema
        return JSONSchema(
            type: .object,
            properties: [
                "RevArray": revArraySchema
            ],
            required: ["RevArray"],
            additionalProperties: false
        )
    }()
    // MARK: - Generic Phase Review Schema

    /// JSON Schema for generic phase review response.
    /// Works for any section/field type - LLM proposes keep/modify/remove/add actions.
    static let phaseReviewSchema: JSONSchema = {
        let reviewItemSchema = JSONSchema(
            type: .object,
            properties: [
                "id": JSONSchema(
                    type: .string,
                    description: "The node ID from the input, or a new UUID for 'add' actions"
                ),
                "displayName": JSONSchema(
                    type: .string,
                    description: "Human-readable name for this item"
                ),
                "originalValue": JSONSchema(
                    type: .string,
                    description: "The original value (for reference)"
                ),
                "proposedValue": JSONSchema(
                    type: .string,
                    description: "The proposed new value (same as original for 'keep', new value for 'modify'/'add')"
                ),
                "action": JSONSchema(
                    type: .string,
                    description: "The proposed action: keep (no change), modify (change value), remove (delete), add (new item)",
                    enum: ["keep", "modify", "remove", "add"]
                ),
                "reason": JSONSchema(
                    type: .string,
                    description: "Explanation for the proposed action"
                ),
                "originalChildren": JSONSchema(
                    type: .array,
                    description: "For containers: original child values",
                    items: JSONSchema(type: .string)
                ),
                "proposedChildren": JSONSchema(
                    type: .array,
                    description: "For containers: proposed child values after revision",
                    items: JSONSchema(type: .string)
                )
            ],
            required: ["id", "displayName", "originalValue", "proposedValue", "action", "reason", "originalChildren", "proposedChildren"],
            additionalProperties: false
        )

        let itemsArraySchema = JSONSchema(
            type: .array,
            description: "Array of review item proposals",
            items: reviewItemSchema
        )

        return JSONSchema(
            type: .object,
            properties: [
                "section": JSONSchema(
                    type: .string,
                    description: "The section being reviewed (e.g., 'skills', 'work')"
                ),
                "phase": JSONSchema(
                    type: .integer,
                    description: "The phase number (1-indexed)"
                ),
                "field": JSONSchema(
                    type: .string,
                    description: "The field path pattern being reviewed"
                ),
                "bundled": JSONSchema(
                    type: .boolean,
                    description: "Whether items were bundled together for review"
                ),
                "items": itemsArraySchema
            ],
            required: ["section", "phase", "field", "bundled", "items"],
            additionalProperties: false
        )
    }()

    // Native SwiftOpenAI JSON Schema for clarifying questions
    static let clarifyingQuestionsSchema: JSONSchema = {
        // Define the clarifying question schema
        let questionSchema = JSONSchema(
            type: .object,
            properties: [
                "id": JSONSchema(
                    type: .string,
                    description: "A unique identifier for the question (e.g., 'q1', 'q2', 'q3')"
                ),
                "question": JSONSchema(
                    type: .string,
                    description: "The clarifying question to ask the user"
                ),
                "context": JSONSchema(
                    type: .string,
                    description: "Context explaining why this question is being asked and how it will help improve the resume"
                )
            ],
            required: ["id", "question", "context"],
            additionalProperties: false
        )
        // Define the questions array
        let questionsArraySchema = JSONSchema(
            type: .array,
            description: "Array of clarifying questions to ask the user (maximum 3 questions)",
            items: questionSchema
        )
        // Define the root schema
        return JSONSchema(
            type: .object,
            properties: [
                "questions": questionsArraySchema,
                "proceedWithRevisions": JSONSchema(
                    type: .boolean,
                    description: "Set to true if you have sufficient information to proceed with revisions without asking questions, false if you need to ask clarifying questions"
                )
            ],
            required: ["questions", "proceedWithRevisions"],
            additionalProperties: false
        )
    }()
    /// System prompt using the native SwiftOpenAI message format
    let genericSystemMessage: LLMMessage = {
        let content = loadPromptTemplate(named: "discovery_generic_system")
        return LLMMessage.text(role: .system, content: content)
    }()

    // MARK: - Prompt Loading

    private static func loadPromptTemplate(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(name)", category: .ai)
            return "Error loading prompt template"
        }
        return content
    }

    private func loadPromptTemplate(named name: String) -> String {
        Self.loadPromptTemplate(named: name)
    }

    private func loadPromptTemplateWithSubstitutions(named name: String, substitutions: [String: String]) -> String {
        var template = loadPromptTemplate(named: name)
        for (key, value) in substitutions {
            template = template.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return template
    }
    // Make this var instead of let so it can be updated
    var applicant: Applicant
    var queryString: String = ""
    let res: Resume
    private let exportCoordinator: ResumeExportCoordinator
    private let allKnowledgeCards: [KnowledgeCard]
    private let guidanceStore: InferenceGuidanceStore?
    // MARK: - Derived Properties
    var backgroundDocs: String {
        if allKnowledgeCards.isEmpty {
            Logger.debug("⚠️ [ResumeQuery] No knowledge cards available")
            return "(No background documents/knowledge cards available)"
        } else {
            Logger.debug("📚 [ResumeQuery] Including \(allKnowledgeCards.count) knowledge cards in prompt")
            return allKnowledgeCards.map { $0.title + ":\n" + $0.narrative + "\n\n" }.joined()
        }
    }
    var resumeText: String {
        res.textResume
    }
    var resumeJson: String {
        do {
            let context = try ResumeTemplateDataBuilder.buildContext(from: res)
            let data = try JSONSerialization.data(withJSONObject: context, options: [])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            Logger.warning("ResumeQuery.resumeJson: Failed to build context: \(error)")
            return "{}"
        }
    }
    var jobListing: String {
        return res.jobApp?.jobListingString ?? ""
    }
    var updatableFieldsString: String {
        guard let rootNode = res.rootNode else {
            Logger.debug("⚠️ updatableFieldsString: rootNode is nil!")
            return ""
        }
        let exportDict = TreeNode.traverseAndExportNodes(node: rootNode)
        do {
            let updatableJsonData = try JSONSerialization.data(
                withJSONObject: exportDict, options: .prettyPrinted
            )
            let returnString = String(data: updatableJsonData, encoding: .utf8) ?? ""
            Logger.verbose("🔄 Updatable resume nodes preview")
            Logger.verbose(truncateString(returnString, maxLength: 250))
            return returnString
        } catch {
            return ""
        }
    }
    // MARK: - Initialization
    init(
        resume: Resume,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfile: ApplicantProfile,
        allKnowledgeCards: [KnowledgeCard],
        guidanceStore: InferenceGuidanceStore? = nil,
        saveDebugPrompt: Bool = true
    ) {
        // Optionally let users pass in the debug flag during initialization
        res = resume
        self.exportCoordinator = exportCoordinator
        self.allKnowledgeCards = allKnowledgeCards
        self.guidanceStore = guidanceStore
        applicant = Applicant(profile: applicantProfile)
        self.saveDebugPrompt = saveDebugPrompt
    }
    // MARK: - Prompt Building
    @MainActor
    func wholeResumeQueryString() async -> String {
        // Ensure the resume's rendered text is up-to-date by awaiting the export/render process.
        try? await exportCoordinator.ensureFreshRenderedText(for: res)

        // Build the prompt from template
        let prompt = loadPromptTemplateWithSubstitutions(named: "resume_whole_resume_query", substitutions: [
            "resumeText": resumeText,
            "applicantName": applicant.name,
            "resumeJson": resumeJson,
            "jobListing": jobListing,
            "updatableFieldsString": updatableFieldsString,
            "backgroundDocs": backgroundDocs
        ])

        // If debug flag is set, save the prompt to a text file in the user's Downloads folder.
        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "promptDebug.txt")
        }
        return prompt
    }
    /// Generate prompt for clarifying questions workflow
    /// Returns resume context WITHOUT editable nodes, plus clarifying questions instructions
    @MainActor
    func clarifyingQuestionsPrompt() async -> String {
        // Get resume context WITHOUT editable nodes (clarifying questions don't need them)
        let resumeContextOnly = await clarifyingQuestionsContextString()
        // Add clarifying questions instruction
        let clarifyingQuestionsInstruction = loadPromptTemplate(named: "resume_clarifying_questions_instructions")
        return resumeContextOnly + clarifyingQuestionsInstruction
    }
    /// Generate resume context for clarifying questions (excludes editable nodes and JSON)
    /// This provides the resume text, job listing, and background docs for context
    /// but does NOT include the JSON structure or editable nodes array since clarifying questions
    /// are about gathering information, not proposing specific revisions
    @MainActor
    func clarifyingQuestionsContextString() async -> String {
        // Ensure the resume's rendered text is up-to-date
        try? await exportCoordinator.ensureFreshRenderedText(for: res)

        // Build context prompt from template
        let prompt = loadPromptTemplateWithSubstitutions(named: "resume_clarifying_questions_context", substitutions: [
            "resumeText": resumeText,
            "applicantName": applicant.name,
            "jobListing": jobListing,
            "backgroundDocs": backgroundDocs
        ])

        // If debug flag is set, save the prompt to a text file in the user's Downloads folder.
        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "clarifyingQuestionsDebug.txt")
        }
        return prompt
    }
    /// Generate revision prompt for multi-turn conversations (after clarifying questions)
    /// Only includes editable nodes and revision instructions since context is already established
    @MainActor
    func multiTurnRevisionPrompt() async -> String {
        // Ensure the resume's rendered text is up-to-date
        try? await exportCoordinator.ensureFreshRenderedText(for: res)

        // Build prompt from template
        let prompt = loadPromptTemplateWithSubstitutions(named: "resume_multi_turn_revision", substitutions: [
            "updatableFieldsString": updatableFieldsString
        ])

        // If debug flag is set, save the prompt to a text file
        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "multiTurnRevisionDebug.txt")
        }
        return prompt
    }
    // MARK: - Generic Phase Review Prompt

    /// Generate a prompt for any phase review.
    /// Works with any section/field type based on manifest configuration.
    ///
    /// - Parameters:
    ///   - section: The section being reviewed (e.g., "skills", "work")
    ///   - phaseNumber: The phase number (1-indexed)
    ///   - fieldPath: The field path pattern (e.g., "skills.*.name")
    ///   - nodes: The exported nodes to review
    ///   - isBundled: Whether all nodes are bundled into one review
    ///   - coverRefs: Cover letter references for writing sample extraction (optional)
    /// - Returns: The prompt string for the LLM
    @MainActor
    func phaseReviewPrompt(
        section: String,
        phaseNumber: Int,
        fieldPath: String,
        nodes: [ExportedReviewNode],
        isBundled: Bool,
        coverRefs: [CoverRef] = []
    ) async -> String {
        try? await exportCoordinator.ensureFreshRenderedText(for: res)

        // Build JSON representation of nodes
        let nodesJson = buildNodesJson(from: nodes)

        // Determine review type description based on whether items are containers
        let hasContainers = nodes.contains { $0.isContainer }
        let itemTypeDescription = hasContainers
            ? "These items contain child values that can be modified, reordered, added to, or reduced."
            : "These are scalar values that can be kept as-is, modified, or removed."

        let bundleDescription = isBundled
            ? "All items are presented together for holistic review. Consider relationships between items."
            : "Each item should be reviewed individually based on relevance to the target job."

        // Get the text template content
        let textTemplate = res.template?.textContent ?? "(No text template available)"

        // Check if we have preprocessed data for v2 template
        let hasPreprocessedData = res.jobApp?.hasPreprocessingComplete ?? false

        if hasPreprocessedData && !coverRefs.isEmpty {
            // Use v2 template with structured requirements and voice context
            let voiceContext = coverRefs.voiceContextForPrompt(maxSamples: 2)
            let extractedRequirements = res.jobApp?.extractedRequirements
            let formattedRequirements = formatRequirementsForPrompt(
                extractedRequirements,
                fallbackJobListing: jobListing
            )
            let cardsToInclude = selectCardsForContext(allCards: allKnowledgeCards, jobApp: res.jobApp)
            let filteredCards = formatCardsForPrompt(cardsToInclude)

            let prompt = loadPromptTemplateWithSubstitutions(named: "resume_phase_review_v2", substitutions: [
                "phaseNumber": String(phaseNumber),
                "sectionUppercase": section.uppercased(),
                "fieldPath": fieldPath,
                "applicantName": applicant.name,
                "formattedRequirements": formattedRequirements,
                "voiceContext": voiceContext,
                "resumeText": resumeText,
                "textTemplate": textTemplate,
                "filteredCards": filteredCards,
                "nodesJson": nodesJson,
                "bundleDescription": bundleDescription,
                "itemTypeDescription": itemTypeDescription,
                "section": section,
                "isBundled": String(isBundled)
            ])

            // Inject inference guidance if available
            let finalPrompt = injectGuidance(into: prompt, for: section, fieldPath: fieldPath)

            if saveDebugPrompt {
                savePromptToDownloads(content: finalPrompt, fileName: "phaseReviewPrompt_v2_\(section)_phase\(phaseNumber).txt")
            }

            return finalPrompt
        }

        // Fallback to v1 template
        var prompt = loadPromptTemplateWithSubstitutions(named: "resume_phase_review", substitutions: [
            "phaseNumber": String(phaseNumber),
            "sectionUppercase": section.uppercased(),
            "fieldPath": fieldPath,
            "applicantName": applicant.name,
            "jobListing": jobListing,
            "resumeText": resumeText,
            "textTemplate": textTemplate,
            "nodesJson": nodesJson,
            "bundleDescription": bundleDescription,
            "itemTypeDescription": itemTypeDescription,
            "backgroundDocs": backgroundDocs,
            "section": section,
            "isBundled": String(isBundled)
        ])

        // Inject inference guidance if available
        prompt = injectGuidance(into: prompt, for: section, fieldPath: fieldPath)

        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "phaseReviewPrompt_\(section)_phase\(phaseNumber).txt")
        }

        return prompt
    }

    // MARK: - Inference Guidance

    /// Look up and inject inference guidance for the given section/fieldPath
    @MainActor
    private func injectGuidance(into prompt: String, for section: String, fieldPath: String) -> String {
        guard let store = guidanceStore else { return prompt }

        // Try exact match first, then pattern match
        let nodeKey = "\(section).\(fieldPath)"
        let guidance = store.guidance(for: nodeKey)
            ?? store.guidance(for: section)
            ?? store.guidanceMatching(pattern: nodeKey)

        guard let guidance = guidance else { return prompt }

        Logger.info("📝 Injected guidance for \(nodeKey)", category: .ai)

        return prompt + """

        ================================================================================
        INFERENCE GUIDANCE
        ================================================================================

        \(guidance.renderedPrompt())

        ================================================================================
        """
    }

    // MARK: - Knowledge Card Selection

    /// Select cards based on token limit setting
    private func selectCardsForContext(allCards: [KnowledgeCard], jobApp: JobApp?) -> [KnowledgeCard] {
        let tokenLimit = UserDefaults.standard.integer(forKey: "knowledgeCardTokenLimit")
        guard tokenLimit > 0 else { return allCards }

        let totalTokens = allCards.compactMap { $0.tokenCount }.reduce(0, +)

        // Under limit: include all cards
        if totalTokens <= tokenLimit {
            return allCards
        }

        // Over limit: filter to relevant cards if preprocessing is complete
        if let relevantIds = jobApp?.relevantCardIds, !relevantIds.isEmpty {
            let relevantIdSet = Set(relevantIds)
            let filtered = allCards.filter { relevantIdSet.contains($0.id.uuidString) }
            Logger.info("📊 [ResumeQuery] Token limit exceeded (\(totalTokens)/\(tokenLimit)), using \(filtered.count) relevant cards", category: .ai)
            return filtered
        }

        // Fallback: include all cards (preprocessing not complete)
        return allCards
    }

    /// Format cards for prompt inclusion
    private func formatCardsForPrompt(_ cards: [KnowledgeCard]) -> String {
        if cards.isEmpty {
            return "(No knowledge cards available)"
        }

        return cards.map { card in
            "### \(card.title)\n\(card.narrative)"
        }.joined(separator: "\n\n---\n\n")
    }

    /// Format requirements for prompt inclusion
    private func formatRequirementsForPrompt(
        _ requirements: ExtractedRequirements?,
        fallbackJobListing: String
    ) -> String {
        guard let req = requirements, req.isValid else {
            return "JOB LISTING:\n\(fallbackJobListing)"
        }

        var sections: [String] = []

        if !req.mustHave.isEmpty {
            sections.append("MUST-HAVE (explicitly required):\n" + req.mustHave.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !req.strongSignal.isEmpty {
            sections.append("STRONG SIGNAL (emphasized):\n" + req.strongSignal.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !req.preferred.isEmpty {
            sections.append("PREFERRED (nice-to-have):\n" + req.preferred.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !req.cultural.isEmpty {
            sections.append("CULTURAL/SOFT:\n" + req.cultural.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !req.atsKeywords.isEmpty {
            sections.append("ATS KEYWORDS:\n" + req.atsKeywords.joined(separator: ", "))
        }

        return sections.joined(separator: "\n\n")
    }

    /// Build JSON representation of nodes
    private func buildNodesJson(from nodes: [ExportedReviewNode]) -> String {
        nodes.map { node in
            var json = """
            {
              "id": "\(node.id)",
              "path": "\(node.path)",
              "displayName": "\(node.displayName)",
              "value": "\(node.value)"
            """
            if let childValues = node.childValues, !childValues.isEmpty {
                let childrenJson = childValues.map { "\"\($0)\"" }.joined(separator: ", ")
                json += ",\n      \"childValues\": [\(childrenJson)]"
            }
            json += "\n    }"
            return json
        }.joined(separator: ",\n    ")
    }

    // MARK: - Phase Review Resubmission Prompt

    /// Generate a prompt for resubmitting rejected items in a phase review.
    /// Only includes items that were rejected, along with any user feedback.
    ///
    /// - Parameters:
    ///   - section: The section being reviewed
    ///   - phaseNumber: The phase number
    ///   - fieldPath: The field path pattern
    ///   - rejectedItems: Items that were rejected by the user
    ///   - isBundled: Whether items are bundled for review
    /// - Returns: The resubmission prompt string
    @MainActor
    func phaseResubmissionPrompt(
        section: String,
        phaseNumber: Int,
        fieldPath: String,
        rejectedItems: [PhaseReviewItem],
        isBundled: Bool
    ) async -> String {
        try? await exportCoordinator.ensureFreshRenderedText(for: res)

        // Build JSON representation of rejected items with feedback
        let itemsJson = rejectedItems.map { item in
            var json = """
            {
              "id": "\(item.id)",
              "displayName": "\(item.displayName)",
              "originalValue": "\(escapeJsonString(item.originalValue))",
              "previousProposal": "\(escapeJsonString(item.proposedValue))",
              "rejectionType": "\(item.userDecision == .rejectedWithFeedback ? "with_feedback" : "without_feedback")"
            """
            if item.userDecision == .rejectedWithFeedback && !item.userComment.isEmpty {
                json += ",\n      \"userFeedback\": \"\(escapeJsonString(item.userComment))\""
            }
            if let originalChildren = item.originalChildren {
                let childrenJson = originalChildren.map { "\"\(escapeJsonString($0))\"" }.joined(separator: ", ")
                json += ",\n      \"originalChildren\": [\(childrenJson)]"
            }
            if let proposedChildren = item.proposedChildren {
                let childrenJson = proposedChildren.map { "\"\(escapeJsonString($0))\"" }.joined(separator: ", ")
                json += ",\n      \"previousProposedChildren\": [\(childrenJson)]"
            }
            json += "\n    }"
            return json
        }.joined(separator: ",\n    ")

        // Build prompt from template with substitutions
        let prompt = loadPromptTemplateWithSubstitutions(named: "resume_phase_resubmission", substitutions: [
            "phaseNumber": String(phaseNumber),
            "sectionUppercase": section.uppercased(),
            "fieldPath": fieldPath,
            "jobListing": jobListing,
            "itemsJson": itemsJson,
            "backgroundDocs": backgroundDocs,
            "section": section,
            "isBundled": String(isBundled)
        ])

        if saveDebugPrompt {
            savePromptToDownloads(content: prompt, fileName: "phaseResubmissionPrompt_\(section)_phase\(phaseNumber).txt")
        }

        return prompt
    }

    /// Escape special characters for JSON string embedding
    private func escapeJsonString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Helper method to truncate strings with ellipsis
    private func truncateString(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength {
            return string
        }
        let truncated = String(string.prefix(maxLength))
        return truncated + "..."
    }
    // MARK: - Debugging Helper
    /// Saves the provided prompt text to the user's `Downloads` folder for debugging purposes.
    private func savePromptToDownloads(content: String, fileName: String) {
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.warning(
                "Failed to persist debug prompt to Downloads: \(error.localizedDescription)",
                category: .diagnostics
            )
        }
    }
}
