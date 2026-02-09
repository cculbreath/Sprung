//
//  RevisionTaskBuilder.swift
//  Sprung
//
//  Builds RevisionTasks from ExportedReviewNodes with node-type-specific prompts.
//  Supports compound tasks for related fields and targeting plan integration.
//

import Foundation

@MainActor
final class RevisionTaskBuilder {

    // MARK: - Public API

    /// Build revision tasks from exported review nodes with node-type-specific prompts.
    /// Groups related fields into compound tasks where possible to reduce LLM calls
    /// and improve cross-field coherence.
    /// - Parameters:
    ///   - revNodes: The nodes to build tasks for
    ///   - resume: The resume being customized
    ///   - jobDescription: The target job description
    ///   - skills: Available skills from the Skill Bank
    ///   - titleSets: Available title sets from the library
    ///   - phase: The current phase number
    ///   - targetingPlan: Optional strategic targeting plan for guidance injection
    ///   - phase1Decisions: Optional Phase 1 decisions context for Phase 2 tasks
    ///   - knowledgeCards: Knowledge cards for suggested bullet extraction
    /// - Returns: Array of revision tasks with appropriate prompts
    func buildTasks(
        from revNodes: [ExportedReviewNode],
        resume: Resume,
        jobDescription: String,
        skills: [Skill],
        titleSets: [TitleSet],
        phase: Int,
        targetingPlan: TargetingPlan? = nil,
        phase1Decisions: String? = nil,
        knowledgeCards: [KnowledgeCard] = []
    ) -> [RevisionTask] {
        // Separate specialized nodes from compound-eligible nodes
        var specializedTasks: [RevisionTask] = []
        var compoundCandidates: [ExportedReviewNode] = []

        for revNode in revNodes {
            let nodeType = detectNodeType(for: revNode)
            if nodeType != .generic {
                // Specialized nodes (skills, keywords, titles) get their own tasks
                let taskPrompt = generatePrompt(
                    for: revNode,
                    nodeType: nodeType,
                    skills: skills,
                    titleSets: titleSets,
                    targetingPlan: targetingPlan,
                    phase1Decisions: phase1Decisions,
                    knowledgeCards: knowledgeCards
                )
                specializedTasks.append(RevisionTask(
                    revNode: revNode,
                    taskPrompt: taskPrompt,
                    nodeType: nodeType,
                    phase: phase
                ))
            } else {
                compoundCandidates.append(revNode)
            }
        }

        // Group compound candidates by parent path
        let compoundGroups = buildCompoundGroups(from: compoundCandidates)

        var compoundTasks: [RevisionTask] = []
        for group in compoundGroups {
            if group.count > 1 {
                // Multiple fields share a parent -- create a compound task
                let compoundPrompt = generateCompoundPrompt(
                    for: group,
                    targetingPlan: targetingPlan,
                    phase1Decisions: phase1Decisions,
                    knowledgeCards: knowledgeCards
                )
                // Use a synthetic compound node that references all group members
                let compoundNode = buildCompoundNode(from: group)
                compoundTasks.append(RevisionTask(
                    revNode: compoundNode,
                    taskPrompt: compoundPrompt,
                    nodeType: .compound,
                    phase: phase
                ))
            } else if let single = group.first {
                // Single field in group -- build a standard task
                let taskPrompt = generatePrompt(
                    for: single,
                    nodeType: .generic,
                    skills: skills,
                    titleSets: titleSets,
                    targetingPlan: targetingPlan,
                    phase1Decisions: phase1Decisions,
                    knowledgeCards: knowledgeCards
                )
                compoundTasks.append(RevisionTask(
                    revNode: single,
                    taskPrompt: taskPrompt,
                    nodeType: .generic,
                    phase: phase
                ))
            }
        }

        return specializedTasks + compoundTasks
    }

    // MARK: - Compound Grouping

    /// Extract the parent path from a node path (e.g., "work.0.highlights" -> "work.0")
    private func parentPath(for path: String) -> String {
        let components = path.split(separator: ".")
        if components.count > 1 {
            return components.dropLast().joined(separator: ".")
        }
        return path
    }

    /// Group nodes by their parent path. Nodes sharing the same parent
    /// (e.g., work.0.position, work.0.description, work.0.highlights) are grouped together.
    private func buildCompoundGroups(from nodes: [ExportedReviewNode]) -> [[ExportedReviewNode]] {
        var groups: [String: [ExportedReviewNode]] = [:]
        var groupOrder: [String] = []

        for node in nodes {
            let parent = parentPath(for: node.path)
            if groups[parent] == nil {
                groupOrder.append(parent)
            }
            groups[parent, default: []].append(node)
        }

        return groupOrder.compactMap { groups[$0] }
    }

    /// Build a synthetic ExportedReviewNode representing a compound group.
    private func buildCompoundNode(from group: [ExportedReviewNode]) -> ExportedReviewNode {
        let paths = group.map { $0.path }
        let parent = parentPath(for: group[0].path)
        let displayNames = group.map { $0.displayName }
        let allValues = group.map { "\($0.displayName): \($0.value)" }

        return ExportedReviewNode(
            id: "compound-\(parent)",
            path: parent,
            displayName: displayNames.joined(separator: " + "),
            value: allValues.joined(separator: "\n---\n"),
            childValues: paths,
            childCount: group.count,
            isBundled: false,
            sourceNodeIds: group.map { $0.id }
        )
    }

    // MARK: - Node Type Detection

    /// Detect the node type based on path and bundling status.
    private func detectNodeType(for revNode: ExportedReviewNode) -> RevisionNodeType {
        let pathLower = revNode.path.lowercased()

        // Skills section bundled -> whole skills section
        if pathLower.contains("skills") && revNode.isBundled {
            return .skills
        }

        // Skills path ending with keywords -> skill keywords
        if pathLower.contains("skills") && pathLower.hasSuffix("keywords") {
            return .skillKeywords
        }

        // Title-related paths
        if pathLower.contains("jobtitles") || pathLower.contains("titles") {
            return .titles
        }

        return .generic
    }

    // MARK: - Prompt Generation

    /// Generate the task-specific prompt based on node type.
    private func generatePrompt(
        for revNode: ExportedReviewNode,
        nodeType: RevisionNodeType,
        skills: [Skill],
        titleSets: [TitleSet],
        targetingPlan: TargetingPlan? = nil,
        phase1Decisions: String? = nil,
        knowledgeCards: [KnowledgeCard] = []
    ) -> String {
        let targetingSection = buildTargetingSection(for: revNode, plan: targetingPlan)
        let phase1Section = phase1DecisionsSection(phase1Decisions)

        switch nodeType {
        case .skills:
            return generateSkillsPrompt(for: revNode, skills: skills) + phase1Section
        case .skillKeywords:
            return generateSkillKeywordsPrompt(for: revNode, skills: skills) + phase1Section
        case .titles:
            return generateTitlesPrompt(for: revNode, titleSets: titleSets) + phase1Section
        case .generic:
            return routeGenericPrompt(
                for: revNode,
                targetingPlanSection: targetingSection,
                phase1Decisions: phase1Decisions,
                knowledgeCards: knowledgeCards,
                targetingPlan: targetingPlan
            )
        case .compound:
            // Should not reach here -- compound is built via generateCompoundPrompt
            return ""
        }
    }

    /// Build the targeting plan section for a specific node.
    private func buildTargetingSection(for revNode: ExportedReviewNode, plan: TargetingPlan?) -> String? {
        guard let plan else { return nil }

        var sections: [String] = []
        let pathLower = revNode.path.lowercased()

        // Include narrative arc and emphasis themes for all nodes
        if !plan.narrativeArc.isEmpty {
            sections.append("**Narrative Arc:** \(plan.narrativeArc)")
        }
        if !plan.emphasisThemes.isEmpty {
            sections.append("**Emphasis Themes:** \(plan.emphasisThemes.joined(separator: "; "))")
        }

        // Work entry guidance for work-related paths
        if pathLower.contains("work") {
            // Try to match by entry index from path (e.g., "work.0.highlights" -> index 0)
            for guidance in plan.workEntryGuidance {
                let entryId = guidance.entryIdentifier.lowercased()
                // Match if path contains a work index and guidance matches
                if pathLower.contains("work") {
                    sections.append("""
                    **Work Entry: \(guidance.entryIdentifier)**
                    Lead with: \(guidance.leadAngle)
                    Emphasize: \(guidance.emphasis.joined(separator: "; "))
                    De-emphasize: \(guidance.deEmphasis.joined(separator: "; "))
                    """)
                    break
                }
            }
        }

        // Narrative/summary nodes get narrative arc and emphasis themes prominently
        if pathLower.contains("objective") || pathLower.contains("summary") {
            if !plan.prioritizedSkills.isEmpty {
                sections.append("**Prioritized Skills:** \(plan.prioritizedSkills.prefix(5).joined(separator: ", "))")
            }
            if !plan.identifiedGaps.isEmpty {
                sections.append("**Gaps to Address Through Framing:** \(plan.identifiedGaps.joined(separator: "; "))")
            }
        }

        // Description nodes get lateral connections
        if pathLower.contains("description") {
            let connections = plan.lateralConnections
            if !connections.isEmpty {
                let connectionText = connections.prefix(3).map {
                    "\($0.sourceCardTitle) -> \($0.targetRequirement): \($0.reasoning)"
                }.joined(separator: "\n")
                sections.append("**Lateral Connections:**\n\(connectionText)")
            }
        }

        if sections.isEmpty { return nil }
        return sections.joined(separator: "\n\n")
    }

    /// Build the Phase 1 decisions section for Phase 2 prompts.
    private func phase1DecisionsSection(_ decisions: String?) -> String {
        guard let decisions, !decisions.isEmpty else { return "" }
        return "\n\n## Approved Decisions from Phase 1\n\n\(decisions)\n\nThese decisions have been approved. Your content should align with and reference these skill categories and title framing."
    }

    /// Route generic nodes to field-specific prompt builders based on the field path.
    private func routeGenericPrompt(
        for revNode: ExportedReviewNode,
        targetingPlanSection: String?,
        phase1Decisions: String? = nil,
        knowledgeCards: [KnowledgeCard] = [],
        targetingPlan: TargetingPlan? = nil
    ) -> String {
        let pathLower = revNode.path.lowercased()
        let phase1Section = phase1DecisionsSection(phase1Decisions)

        if pathLower.contains("highlights") {
            let bulletSection = suggestedBulletsSection(
                for: revNode,
                knowledgeCards: knowledgeCards,
                targetingPlan: targetingPlan
            )
            return generateHighlightsPrompt(
                for: revNode,
                targetingPlanSection: targetingPlanSection,
                suggestedBullets: bulletSection
            ) + phase1Section
        }

        // Match objective or summary at the section level (custom.objective, custom.summary, basics.summary)
        if pathLower.contains("objective") || pathLower.contains("summary") {
            return generateNarrativePrompt(for: revNode, targetingPlanSection: targetingPlanSection) + phase1Section
        }

        if pathLower.contains("description") {
            return generateDescriptionPrompt(for: revNode, targetingPlanSection: targetingPlanSection) + phase1Section
        }

        return generateDefaultGenericPrompt(for: revNode, targetingPlanSection: targetingPlanSection) + phase1Section
    }

    // MARK: - Suggested Bullets

    /// Extract suggested bullets from knowledge cards matching this work entry
    /// via the targeting plan's KC section mapping.
    private func suggestedBulletsSection(
        for revNode: ExportedReviewNode,
        knowledgeCards: [KnowledgeCard],
        targetingPlan: TargetingPlan?
    ) -> String? {
        guard let plan = targetingPlan else { return nil }

        // Find supporting card IDs for this work entry via work entry guidance
        var supportingCardIds: [String] = []
        for guidance in plan.workEntryGuidance {
            supportingCardIds.append(contentsOf: guidance.supportingCardIds)
        }

        // Also check KC section mappings for "work" section
        let workMappings = plan.cardMappings(forSection: "work")
        supportingCardIds.append(contentsOf: workMappings.map { $0.cardId })

        // Deduplicate
        let uniqueIds = Set(supportingCardIds)
        guard !uniqueIds.isEmpty else { return nil }

        // Extract suggested bullets from matching KCs
        var allBullets: [String] = []
        for card in knowledgeCards {
            if uniqueIds.contains(card.id.uuidString) {
                let bullets = card.suggestedBullets
                if !bullets.isEmpty {
                    allBullets.append(contentsOf: bullets)
                }
            }
        }

        guard !allBullets.isEmpty else { return nil }

        let bulletList = allBullets.prefix(8).map { "- \($0)" }.joined(separator: "\n")
        return """
        ## Pre-Extracted Bullet Templates

        The following bullet templates were extracted from source documents.
        Use these as starting points -- adapt the [BRACKETED_PLACEHOLDERS]
        for this specific job application. You may restructure or combine them,
        but prefer adapting existing templates over generating from scratch.

        \(bulletList)
        """
    }

    // MARK: - Compound Prompt Generation

    /// Generate a compound prompt for a group of related fields.
    private func generateCompoundPrompt(
        for group: [ExportedReviewNode],
        targetingPlan: TargetingPlan?,
        phase1Decisions: String?,
        knowledgeCards: [KnowledgeCard]
    ) -> String {
        let parent = parentPath(for: group[0].path)
        let phase1Section = phase1DecisionsSection(phase1Decisions)

        // Build targeting guidance for this entry
        var targetingSection = ""
        if let plan = targetingPlan {
            // Find matching work entry guidance
            for guidance in plan.workEntryGuidance {
                targetingSection += """

                **Work Entry: \(guidance.entryIdentifier)**
                Lead with: \(guidance.leadAngle)
                Emphasize: \(guidance.emphasis.joined(separator: "; "))
                De-emphasize: \(guidance.deEmphasis.joined(separator: "; "))

                """
                break
            }

            if !plan.narrativeArc.isEmpty {
                targetingSection += "\n**Narrative Arc:** \(plan.narrativeArc)"
            }
            if !plan.emphasisThemes.isEmpty {
                targetingSection += "\n**Emphasis Themes:** \(plan.emphasisThemes.joined(separator: "; "))"
            }
        }

        // Build suggested bullets section for highlight fields in this group
        var bulletSection = ""
        let hasHighlights = group.contains { $0.path.lowercased().contains("highlights") }
        if hasHighlights, let plan = targetingPlan {
            var supportingCardIds: [String] = []
            for guidance in plan.workEntryGuidance {
                supportingCardIds.append(contentsOf: guidance.supportingCardIds)
            }
            let workMappings = plan.cardMappings(forSection: "work")
            supportingCardIds.append(contentsOf: workMappings.map { $0.cardId })
            let uniqueIds = Set(supportingCardIds)

            var allBullets: [String] = []
            for card in knowledgeCards {
                if uniqueIds.contains(card.id.uuidString) {
                    let bullets = card.suggestedBullets
                    if !bullets.isEmpty {
                        allBullets.append(contentsOf: bullets)
                    }
                }
            }

            if !allBullets.isEmpty {
                let bulletList = allBullets.prefix(8).map { "- \($0)" }.joined(separator: "\n")
                bulletSection = """

                ## Pre-Extracted Bullet Templates

                The following bullet templates were extracted from source documents.
                Use these as starting points for highlights -- adapt the [BRACKETED_PLACEHOLDERS]
                for this specific job application.

                \(bulletList)
                """
            }
        }

        // Build the fields list
        var fieldsList: [String] = []
        for (index, node) in group.enumerated() {
            let fieldName = node.path.split(separator: ".").last.map(String.init) ?? node.displayName
            fieldsList.append("\(index + 1). **\(fieldName)** (path: \(node.path), id: \(node.id))")
            fieldsList.append("   Current value: \(node.value)")
        }

        let nodeIds = group.map { "\"\($0.id)\"" }.joined(separator: ", ")
        let fieldPaths = group.map { "\"\($0.path)\"" }.joined(separator: ", ")

        return """
        ## Task: Revise Related Fields as a Coherent Unit

        Revise the following fields for this entry (\(parent)) as a coherent unit.
        The description should set up what the highlights demonstrate.
        Highlights should not repeat the description.
        Position title should align with the targeting plan's framing.

        ## Fields to Revise

        \(fieldsList.joined(separator: "\n"))
        \(targetingSection.isEmpty ? "" : "\n## Strategic Guidance\n\n\(targetingSection)")
        \(bulletSection)

        ## Requirements

        1. **Ground every claim in Knowledge Card evidence** -- do not fabricate facts, metrics, or capabilities
        2. **Match the candidate's authentic voice** -- study writing samples in the preamble
        3. **Ensure cross-field coherence** -- description sets up highlights; title aligns with framing
        4. **Vary sentence structure across highlights** -- do NOT start every bullet with an action verb

        ## FORBIDDEN

        - Fabricated metrics, percentages, or numbers not in Knowledge Cards
        - Generic resume phrases: "spearheaded", "leveraged", "drove results", "proven track record"
        - Vague impact claims: "significantly improved", "enhanced capabilities"
        - Repeating the same information across description and highlights

        ## Output Format

        Return a JSON object with this structure:
        {
          "compoundFields": [
            {
              "id": "<node id>",
              "path": "<node path>",
              "oldValue": "<current value>",
              "newValue": "<revised value>",
              "valueChanged": true,
              "why": "<explanation>",
              "nodeType": "scalar" or "list",
              "newValueArray": ["item1", "item2"] // only for list nodes
            }
          ]
        }

        Node IDs in order: [\(nodeIds)]
        Node paths in order: [\(fieldPaths)]

        If no changes are needed for a field, set "valueChanged" to false and copy the current value.
        \(phase1Section)
        """
    }

    /// Generate prompt for skills section revision.
    private func generateSkillsPrompt(for revNode: ExportedReviewNode, skills: [Skill]) -> String {
        let skillBank = formatSkillBank(skills)

        return """
        Re-select skills from the Skill Bank for each category to better match this job posting.

        CRITICAL CONSTRAINTS:
        - PRESERVE the existing category names exactly as shown below
        - DO NOT rename, merge, or reorganize categories
        - ONLY change which skills appear under each category
        - Select skills ONLY from the Skill Bank below - do NOT invent skills
        - Prefer higher-proficiency skills (expert > proficient > familiar) when multiple skills match the job

        ## Available Skills from Skill Bank

        \(skillBank)

        Current skills on resume (preserve these category names):
        \(revNode.value)

        Your task: For each existing category, select the most job-relevant skills from the Skill Bank.
        Keep the same category names but optimize the skill selection within each.

        Return a JSON object with this structure:
        {
          "id": "\(revNode.id)",
          "oldValue": "\(escapeForJSON(revNode.value))",
          "newValue": "{{categories with updated skills as comma-separated list}}",
          "valueChanged": true,
          "why": "explanation of skill selection changes (not category changes)",
          "treePath": "\(revNode.path)",
          "nodeType": "list",
          "newValueArray": ["ExistingCategory1: skill1, skill2", "ExistingCategory2: skill3, skill4"]
        }

        Remember: Category names must match the original exactly. Only the skills within each category should change.
        """
    }

    /// Generate prompt for skill keywords revision.
    private func generateSkillKeywordsPrompt(for revNode: ExportedReviewNode, skills: [Skill]) -> String {
        let categoryName = extractCategoryName(from: revNode)
        let matchedCategory = matchCategory(from: revNode, skills: skills)

        // Build primary skills list (matching category)
        let primarySkills: [Skill]
        let otherSkills: [Skill]
        if let category = matchedCategory {
            primarySkills = skills.filter { $0.category == category }
                .sorted { ($0.proficiency.sortOrder, $0.canonical) < ($1.proficiency.sortOrder, $1.canonical) }
            otherSkills = skills.filter { $0.category != category }
        } else {
            primarySkills = []
            otherSkills = skills
        }

        var skillReference = ""
        if !primarySkills.isEmpty {
            let lines = primarySkills.map { "- \($0.canonical) (\($0.proficiency.rawValue))" }
            skillReference += """
            ## Skills in "\(categoryName)" Category
            \(lines.joined(separator: "\n"))
            """
        }

        if !otherSkills.isEmpty {
            let otherNames = otherSkills
                .sorted { ($0.proficiency.sortOrder, $0.canonical) < ($1.proficiency.sortOrder, $1.canonical) }
                .map { $0.canonical }
            skillReference += "\n\n## Other Available Skills (secondary reference)\n\(otherNames.joined(separator: ", "))"
        }

        return """
        Re-select skills from the Skill Bank for the "\(categoryName)" category.
        Choose skills that best match the job requirements.
        ONLY use skills from the Skill Bank below - do NOT invent new skills.
        Prefer higher-proficiency skills (expert > proficient > familiar) when multiple skills match.

        \(skillReference)

        Current skills: \(revNode.value)

        Return a JSON object with this structure:
        {
          "id": "\(revNode.id)",
          "oldValue": "\(escapeForJSON(revNode.value))",
          "newValue": "{{new skill selection as comma-separated list}}",
          "valueChanged": true,
          "why": "explanation of skill selection changes",
          "treePath": "\(revNode.path)",
          "nodeType": "list",
          "newValueArray": ["skill1", "skill2", "skill3"]
        }
        """
    }

    /// Generate prompt for titles revision.
    private func generateTitlesPrompt(for revNode: ExportedReviewNode, titleSets: [TitleSet]) -> String {
        if titleSets.isEmpty {
            return """
            No title sets are available in the Title Set Library. Propose original job titles that best position the applicant for this specific job based on the job description and the applicant's background.

            Current titles: \(revNode.value)

            Return a JSON object with this structure:
            {
              "id": "\(revNode.id)",
              "oldValue": "\(escapeForJSON(revNode.value))",
              "newValue": "{{proposed titles as period-separated string}}",
              "valueChanged": true,
              "why": "explanation of why these titles were chosen",
              "treePath": "\(revNode.path)",
              "nodeType": "scalar"
            }
            """
        }

        // Build title set reference
        let titleSetReference = titleSets.enumerated().map { index, set in
            let emphasis = set.emphasis.displayName
            let suggestedUses = set.suggestedFor.isEmpty ? "general" : set.suggestedFor.joined(separator: ", ")
            return "Set \(index): \(set.displayString) [Emphasis: \(emphasis), Suggested for: \(suggestedUses)]"
        }.joined(separator: "\n")

        return """
        Select the best title set from the Title Set Library for this job application.

        Evaluate which set best positions the applicant for this specific job based on:
        - Job requirements and keywords
        - Title set emphasis alignment
        - Suggested use cases

        Title Set Library Reference:
        \(titleSetReference)

        Current titles: \(revNode.value)

        Return a JSON object with this structure:
        {
          "id": "\(revNode.id)",
          "oldValue": "\(escapeForJSON(revNode.value))",
          "newValue": "{{titles from selected set as period-separated string}}",
          "valueChanged": true,
          "why": "explanation of why this title set was selected",
          "treePath": "\(revNode.path)",
          "nodeType": "scalar"
        }

        Include "selectedSetIndex" in your response indicating which set (0-indexed) you selected.
        """
    }

    // MARK: - Field-Specific Generic Prompts

    /// Build the optional strategic guidance section for prompts.
    private func strategicGuidanceSection(_ targetingPlanSection: String?) -> String {
        guard let section = targetingPlanSection, !section.isEmpty else { return "" }
        return """

        ## Strategic Guidance for This Field

        \(section)
        """
    }

    /// Build the standard JSON response instruction block.
    private func jsonResponseBlock(for revNode: ExportedReviewNode) -> String {
        """
        ## Output Format

        Return a JSON object with this structure:
        {
          "id": "\(revNode.id)",
          "oldValue": "\(escapeForJSON(revNode.value))",
          "newValue": "{{proposed revision}}",
          "valueChanged": true,
          "why": "explanation of changes",
          "treePath": "\(revNode.path)",
          "nodeType": "\(revNode.isContainer ? "list" : "scalar")\(revNode.isContainer ? "\",\n  \"newValueArray\": [\"item1\", \"item2\", \"item3\"]" : "\"")"
        }

        If no changes are needed, set "valueChanged" to false and copy the current value to "newValue".
        """
    }

    /// Generate prompt for work highlights (bullet points).
    /// Adapted from WorkHighlightsGenerator with evidence-based constraints, forbidden patterns,
    /// and structural guidance.
    private func generateHighlightsPrompt(
        for revNode: ExportedReviewNode,
        targetingPlanSection: String?,
        suggestedBullets: String? = nil
    ) -> String {
        let bulletReference = suggestedBullets.map { "\n\n\($0)" } ?? ""

        return """
        ## Task: Revise Work Highlights

        Revise the resume bullet points for this position to better target the job posting.

        ## Field Context

        **Field:** \(revNode.displayName)
        **Path:** \(revNode.path)
        **Current highlights:**
        \(revNode.value)
        \(strategicGuidanceSection(targetingPlanSection))
        \(bulletReference)

        ## Requirements

        Generate 3-5 bullet points that:

        1. **Use ONLY facts from the Knowledge Cards** — every claim must trace to evidence in the KCs provided in the preamble. If no metric exists in the source material, describe the work narratively without inventing numbers.

        2. **Match the candidate's authentic voice** — write in their natural style as shown in writing samples (see Voice section in preamble), not in generic resume-speak. Study their vocabulary, sentence length, and professional register.

        3. **Describe work narratively** — focus on what was built, created, discovered, solved, or shipped. Frame contributions as stories of problems tackled and outcomes produced.

        4. **Vary sentence structure across bullets** — do NOT start every bullet with an action verb. Mix leading with context, outcomes, or technical details. Some bullets can begin with what was built; others with why it mattered.

        5. **Lead with the strongest evidence** — place the most impactful, well-documented bullet first. Subsequent bullets should still be strong but can cover different facets of the role.

        ## Role-Appropriate Framing

        Tailor bullet structure to the position type:

        **For R&D / Academic / Research positions:**
        - What problem or gap existed?
        - What novel approach was taken?
        - What was created, discovered, or published?

        **For Industry / Engineering / Corporate positions:**
        - What system or process did they own?
        - What was their specific technical contribution?
        - What concrete outcome resulted? (only if documented)

        **For Teaching / Education positions:**
        - What did they build or redesign?
        - What pedagogical approach did they use?
        - What was the scope and impact on students?

        ## FORBIDDEN

        - Fabricated metrics, percentages, or numbers not explicitly stated in Knowledge Cards
        - Generic phrases: "spearheaded", "leveraged", "drove results", "collaborated cross-functionally"
        - Vague impact claims: "significantly improved", "enhanced capabilities", "streamlined processes"
        - Formulaic structure: "[Action verb] [thing] resulting in [X]% improvement"
        - LinkedIn buzzwords: "synergized", "thought leadership", "paradigm shift"
        - Starting every bullet identically (e.g., all beginning with past-tense verbs)

        \(jsonResponseBlock(for: revNode))
        """
    }

    /// Generate prompt for objective/summary narrative fields.
    /// Adapted from ObjectiveGenerator with word count constraints, value proposition focus,
    /// and voice matching.
    private func generateNarrativePrompt(for revNode: ExportedReviewNode, targetingPlanSection: String?) -> String {
        """
        ## Task: Revise Professional Summary

        Revise the professional summary (objective statement) to position the candidate for this specific job.

        ## Field Context

        **Field:** \(revNode.displayName)
        **Path:** \(revNode.path)
        **Current summary:**
        \(revNode.value)
        \(strategicGuidanceSection(targetingPlanSection))

        ## Requirements

        Generate a professional summary that:

        1. **Is 3-5 sentences, 60-100 words** — concise and dense with meaning, not padded with filler
        2. **Leads with the core value proposition** — what does this candidate uniquely offer for the target role?
        3. **Conveys professional identity** — how the candidate frames their expertise and career focus
        4. **References key skills naturally** — weave in the most relevant skills from the preamble without listing them mechanically
        5. **Matches the candidate's voice** — study writing samples carefully (see Voice section in preamble) and write in their natural style, not generic resume-speak

        ## CONSTRAINTS

        1. Use ONLY facts from the provided Knowledge Cards and documented experience
        2. Do NOT invent metrics, percentages, or quantitative claims not present in KCs
        3. Do NOT pad with vague qualifiers ("extensive experience", "deep expertise")
        4. The summary should feel like the candidate wrote it themselves

        ## FORBIDDEN

        - Fabricated numbers ("X years of experience", "reduced by Y%") unless exact figures appear in KCs
        - Generic phrases: "results-driven", "passionate about", "proven track record", "detail-oriented professional"
        - Vague claims: "significantly improved", "extensive experience in", "strong background in"
        - LinkedIn buzzwords: "leveraged", "spearheaded", "synergized"
        - Opening with "Experienced professional with..." or "Results-driven [title] with..."

        \(jsonResponseBlock(for: revNode))
        """
    }

    /// Generate prompt for project/work description fields.
    /// Adapted from ProjectsGenerator with KC-specific technology references and concise
    /// narrative structure.
    private func generateDescriptionPrompt(for revNode: ExportedReviewNode, targetingPlanSection: String?) -> String {
        """
        ## Task: Revise Description

        Revise this description to better target the job posting while staying grounded in documented evidence.

        ## Field Context

        **Field:** \(revNode.displayName)
        **Path:** \(revNode.path)
        **Current description:**
        \(revNode.value)
        \(strategicGuidanceSection(targetingPlanSection))

        ## Requirements

        Generate a description that:

        1. **Is 2-3 sentences for project descriptions, 1-2 sentences for work descriptions** — tight and purposeful
        2. **Explains what was built and why** — lead with the purpose or problem, then the approach and candidate's role
        3. **References specific technologies from the Knowledge Cards** — name the actual tools, languages, and frameworks documented in KCs rather than using vague terms like "various technologies"
        4. **Angles toward the target job** — emphasize the aspects most relevant to the job posting without distorting what actually happened
        5. **Matches the candidate's voice** — study writing samples (see Voice section in preamble)

        ## CONSTRAINTS

        1. Use ONLY facts from the provided Knowledge Cards — every technology, tool, and claim must trace to KC evidence
        2. Do NOT invent metrics or quantitative claims
        3. Do NOT add capabilities or technologies not documented in KCs
        4. Keep descriptions focused — avoid trying to cover everything; pick the angle that best serves the job target

        ## FORBIDDEN

        - Fabricated numbers ("increased by X%", "reduced by Y%") unless exact figures appear in KCs
        - Generic phrases: "spearheaded", "leveraged", "cutting-edge", "state-of-the-art"
        - Vague claims: "significantly improved", "enhanced performance"
        - Technology name-dropping not backed by KC evidence
        - Overstuffing with every possible keyword

        \(jsonResponseBlock(for: revNode))
        """
    }

    /// Improved default generic prompt for fields that don't match highlights, narrative, or description patterns.
    /// Still enforces evidence constraints, forbidden patterns, and voice matching.
    private func generateDefaultGenericPrompt(for revNode: ExportedReviewNode, targetingPlanSection: String?) -> String {
        """
        ## Task: Revise Resume Content

        Revise this resume field to better target the job posting.

        ## Field Context

        **Field:** \(revNode.displayName)
        **Path:** \(revNode.path)
        **Current value:**
        \(revNode.value)
        \(strategicGuidanceSection(targetingPlanSection))

        ## Requirements

        1. **Ground every claim in Knowledge Card evidence** — do not fabricate facts, metrics, or capabilities. If the KCs don't support a claim, omit it.

        2. **Match the candidate's authentic voice** — study the writing samples in the preamble. Mirror their vocabulary, sentence structure, and professional register. Do not default to generic resume-speak.

        3. **Target the job posting** — emphasize the aspects of this field that are most relevant to the target role, but do not distort or fabricate to create a better fit.

        4. **Be concise** — prefer fewer, stronger words over padding with qualifiers and filler phrases.

        ## FORBIDDEN

        - Fabricated metrics, percentages, or numbers not in Knowledge Cards
        - Generic resume phrases: "spearheaded", "leveraged", "drove results", "proven track record"
        - Vague impact claims: "significantly improved", "enhanced capabilities"
        - LinkedIn buzzwords: "synergized", "thought leadership"

        \(jsonResponseBlock(for: revNode))
        """
    }

    // MARK: - Phase 1 Decisions Builder

    /// Build a Phase 1 decisions context string from approved review items.
    /// Called after Phase 1 review is complete, before Phase 2 execution.
    static func buildPhase1DecisionsContext(from approvedItems: [CustomizationReviewItem]) -> String {
        var sections: [String] = []

        // Extract skill categories and keywords
        var skillDecisions: [String] = []
        var titleDecisions: [String] = []
        var otherDecisions: [String] = []

        for item in approvedItems {
            let finalValue: String
            if item.userAction == .useOriginal {
                // User kept the original — report original value, not the LLM proposal
                if let oldArray = item.revision.oldValueArray, !oldArray.isEmpty {
                    finalValue = oldArray.joined(separator: ", ")
                } else {
                    finalValue = item.revision.oldValue
                }
            } else if let edited = item.editedContent {
                finalValue = edited
            } else if let editedChildren = item.editedChildren, !editedChildren.isEmpty {
                finalValue = editedChildren.joined(separator: ", ")
            } else if let newArray = item.revision.newValueArray, !newArray.isEmpty {
                finalValue = newArray.joined(separator: ", ")
            } else {
                finalValue = item.revision.newValue
            }

            switch item.task.nodeType {
            case .skills, .skillKeywords:
                skillDecisions.append("- \(item.task.revNode.displayName): \(finalValue)")
            case .titles:
                titleDecisions.append("- \(finalValue)")
            default:
                otherDecisions.append("- \(item.task.revNode.displayName): \(finalValue)")
            }
        }

        if !skillDecisions.isEmpty {
            sections.append("### Selected Skill Categories\n\(skillDecisions.joined(separator: "\n"))")
        }

        if !titleDecisions.isEmpty {
            sections.append("### Selected Job Titles\n\(titleDecisions.joined(separator: "\n"))")
        }

        if !otherDecisions.isEmpty {
            sections.append("### Other Phase 1 Decisions\n\(otherDecisions.joined(separator: "\n"))")
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    /// Extract category name from display name or path.
    private func extractCategoryName(from revNode: ExportedReviewNode) -> String {
        // Try display name first
        if !revNode.displayName.isEmpty && revNode.displayName != revNode.path {
            return revNode.displayName
        }

        // Extract from path (e.g., "skills.0.keywords" -> look for parent name)
        let components = revNode.path.split(separator: ".")
        if components.count >= 2 {
            // Return the second-to-last meaningful component
            return String(components[components.count - 2])
        }

        return "Skills"
    }

    /// Format the full skill bank grouped by category with proficiency levels.
    private func formatSkillBank(_ skills: [Skill]) -> String {
        let grouped = Dictionary(grouping: skills) { $0.category }
        var sections: [String] = []

        for category in SkillCategoryUtils.sortedCategories(from: skills) {
            guard let categorySkills = grouped[category], !categorySkills.isEmpty else { continue }
            let sorted = categorySkills.sorted {
                ($0.proficiency.sortOrder, $0.canonical) < ($1.proficiency.sortOrder, $1.canonical)
            }
            var lines = ["### \(category)"]
            for skill in sorted {
                lines.append("- \(skill.canonical) (\(skill.proficiency.rawValue))")
            }
            sections.append(lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    /// Match a review node's category name to a skill category string.
    private func matchCategory(from revNode: ExportedReviewNode, skills: [Skill]) -> String? {
        let name = extractCategoryName(from: revNode).lowercased()
        let allCategories = SkillCategoryUtils.sortedCategories(from: skills)
        return allCategories.first {
            name.contains($0.lowercased()) || $0.lowercased().contains(name)
        }
    }

    /// Escape string for inclusion in JSON template.
    private func escapeForJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
