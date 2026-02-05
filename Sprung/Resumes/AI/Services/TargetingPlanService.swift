//
//  TargetingPlanService.swift
//  Sprung
//
//  Strategic pre-analysis service that generates a TargetingPlan before
//  parallel field generation. The plan coordinates narrative angle, KC-to-section
//  mapping, emphasis themes, and work entry framing so downstream tasks
//  produce coherent, differentiated output.
//

import Foundation
import Observation
import SwiftyJSON

/// Service that generates a strategic targeting plan for resume customization.
/// Runs a single LLM call with abbreviated KC summaries and job context to
/// produce holistic guidance that coordinates all parallel field generators.
@Observable
@MainActor
final class TargetingPlanService {

    // MARK: - Public API

    /// Generate a strategic targeting plan for resume customization.
    ///
    /// - Parameters:
    ///   - context: The customization context containing KCs, skills, job description, etc.
    ///   - llmFacade: The LLM facade for API calls.
    ///   - modelId: The model ID to use (from user settings, never hardcoded).
    /// - Returns: A populated TargetingPlan with strategic guidance.
    /// - Note: On LLM failure, returns a minimal default plan rather than throwing,
    ///   since this is a quality enhancement that should not block downstream work.
    func generateTargetingPlan(
        context: CustomizationContext,
        llmFacade: LLMFacade,
        modelId: String
    ) async throws -> TargetingPlan {
        guard !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "customizationModel",
                operationName: "Targeting Plan Generation"
            )
        }

        let prompt = buildStrategicPrompt(context: context)

        do {
            let plan = try await llmFacade.executeFlexibleJSON(
                prompt: prompt,
                modelId: modelId,
                as: TargetingPlan.self,
                temperature: 0.4
            )
            Logger.info("[TargetingPlan] Generated plan with \(plan.emphasisThemes.count) themes, \(plan.workEntryGuidance.count) work entries, \(plan.lateralConnections.count) lateral connections", category: .ai)
            return plan
        } catch {
            Logger.error("[TargetingPlan] LLM call failed: \(error.localizedDescription). Returning minimal plan.", category: .ai)
            return TargetingPlan.minimal()
        }
    }

    // MARK: - Prompt Construction

    private func buildStrategicPrompt(context: CustomizationContext) -> String {
        var sections: [String] = []

        // System role and instructions
        sections.append(buildSystemInstructions())

        // Abbreviated KC summaries (breadth over depth)
        sections.append(buildAbbreviatedKCSummaries(context: context))

        // Job description with extracted requirements
        sections.append(buildJobSection(context: context))

        // Skill bank summary (top skills by category)
        sections.append(buildSkillBankSummary(context: context))

        // Resume structure overview
        sections.append(buildResumeStructure(context: context))

        // Dossier insights if available
        if let dossier = context.dossier {
            sections.append(buildDossierSummary(dossier))
        }

        // Output schema
        sections.append(buildOutputSchema())

        return sections.joined(separator: "\n\n---\n\n")
    }

    private func buildSystemInstructions() -> String {
        """
        # Role: Strategic Resume Targeting Planner

        You are a strategic career advisor analyzing a candidate's full background \
        against a specific job opportunity. Your job is to produce a TARGETING PLAN \
        that will guide downstream content generators.

        You see the candidate's full breadth of experience. The content generators \
        will each focus on individual fields. Your plan coordinates their work so \
        the resulting resume tells a coherent, compelling story.

        ## Your Analysis Should:

        1. **Identify the 3-5 most compelling angles** for this application. \
        What makes this candidate genuinely interesting for this role? Go beyond \
        obvious keyword matching.

        2. **Map knowledge cards to resume sections** — decide where each card's \
        evidence is most powerful. A card about a research project might map to \
        "work" for an industry role but "projects" for an academic role.

        3. **Determine work entry framing** — for each work entry, what angle \
        should lead? What deserves emphasis vs. de-emphasis for THIS specific job?

        4. **Find lateral connections** — non-obvious skill transfers between the \
        candidate's experience and job requirements. This is where differentiation \
        lives. A candidate's teaching experience might demonstrate communication \
        skills valued in a consulting role. A research methodology might transfer \
        to product analytics.

        5. **Prioritize skills** — which skills from the bank should be featured \
        prominently vs. mentioned in passing? Order matters.

        6. **Identify gaps honestly** — what's missing? Flag gaps to address \
        through framing, not fabrication.

        7. **Establish the narrative thread** — what single story does this \
        resume tell? "A systems thinker who bridges research and practice" is \
        a narrative. "Has many skills" is not.

        ## Anti-Patterns to AVOID:

        - Generic "leadership and technical skills" framing that could apply to anyone
        - Trying to make every knowledge card relevant — prioritize ruthlessly
        - Ignoring the candidate's actual strengths in favor of keyword matching
        - Suggesting the candidate is something they're not
        - Surface-level keyword mapping without strategic insight

        ## Output Requirements

        Respond with a single JSON object matching the schema below. \
        No markdown code fences, no explanatory text — just the JSON.
        """
    }

    private func buildAbbreviatedKCSummaries(context: CustomizationContext) -> String {
        var lines = ["## Knowledge Cards (Abbreviated for Strategic Overview)"]
        lines.append("")
        lines.append("These summaries provide breadth. Downstream generators will have full detail.")

        // Use allCards so the planner sees the full picture
        let cards = context.allCards.isEmpty ? context.knowledgeCards : context.allCards

        for card in cards {
            lines.append("")
            let typeLabel = card.cardType?.displayName ?? "General"
            lines.append("### [\(card.id.uuidString)] \(card.title)")

            var meta: [String] = ["Type: \(typeLabel)"]
            if let org = card.organization, !org.isEmpty {
                meta.append("Org: \(org)")
            }
            if let dateRange = card.dateRange, !dateRange.isEmpty {
                meta.append("Period: \(dateRange)")
            }
            lines.append(meta.joined(separator: " | "))

            // Top 3 technologies
            let techs = card.technologies
            if !techs.isEmpty {
                let topTechs = Array(techs.prefix(3))
                let suffix = techs.count > 3 ? " (+\(techs.count - 3) more)" : ""
                lines.append("Technologies: \(topTechs.joined(separator: ", "))\(suffix)")
            }

            // 1-sentence summary (~150 chars of narrative)
            if !card.narrative.isEmpty {
                let summary = String(card.narrative.prefix(150))
                let truncated = summary.count < card.narrative.count ? summary + "..." : summary
                lines.append("Summary: \(truncated)")
            }

            // Top 2 outcomes if available
            let cardOutcomes = card.outcomes
            if !cardOutcomes.isEmpty {
                let topOutcomes = Array(cardOutcomes.prefix(2))
                lines.append("Key Outcomes: \(topOutcomes.joined(separator: "; "))")
            }
        }

        // Note relevance data if available
        if !context.relevantCardIds.isEmpty {
            lines.append("")
            lines.append("**Preprocessor-identified relevant cards:** \(context.relevantCardIds.map { $0.uuidString }.joined(separator: ", "))")
            lines.append("Use this as a starting point but apply your own strategic judgment.")
        }

        return lines.joined(separator: "\n")
    }

    private func buildJobSection(context: CustomizationContext) -> String {
        var lines = ["## Target Job Opportunity"]

        if let position = context.jobPosition, !position.isEmpty {
            lines.append("**Position:** \(position)")
        }
        if let company = context.companyName, !company.isEmpty {
            lines.append("**Company:** \(company)")
        }

        if !context.jobDescription.isEmpty {
            lines.append("")
            lines.append("### Job Description")
            lines.append(context.jobDescription)
        }

        // Include extracted requirements if the resume's job app has them
        if let requirements = context.resume.jobApp?.extractedRequirements, requirements.isValid {
            lines.append("")
            lines.append("### Extracted Requirements")

            if !requirements.mustHave.isEmpty {
                lines.append("**Must Have:** \(requirements.mustHave.joined(separator: ", "))")
            }
            if !requirements.strongSignal.isEmpty {
                lines.append("**Strong Signals:** \(requirements.strongSignal.joined(separator: ", "))")
            }
            if !requirements.preferred.isEmpty {
                lines.append("**Preferred:** \(requirements.preferred.joined(separator: ", "))")
            }
            if !requirements.cultural.isEmpty {
                lines.append("**Cultural/Soft:** \(requirements.cultural.joined(separator: ", "))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func buildSkillBankSummary(context: CustomizationContext) -> String {
        var lines = ["## Skill Bank Summary"]

        // Group skills by category and show top skills per category
        let grouped = Dictionary(grouping: context.skills, by: { SkillCategoryUtils.normalizeCategory($0.categoryRaw) })
        let sortedCategories = grouped.keys.sorted()

        for category in sortedCategories {
            guard let skills = grouped[category] else { continue }
            let skillNames = skills.map { $0.canonical }.prefix(10)
            let suffix = skills.count > 10 ? " (+\(skills.count - 10) more)" : ""
            lines.append("**\(category):** \(skillNames.joined(separator: ", "))\(suffix)")
        }

        lines.append("")
        lines.append("Total skills: \(context.skills.count)")

        return lines.joined(separator: "\n")
    }

    private func buildResumeStructure(context: CustomizationContext) -> String {
        var lines = ["## Current Resume Structure"]
        lines.append("")
        lines.append("The resume has the following sections. Map knowledge cards to these sections.")

        // Walk the resume tree to identify sections and work entries
        if let rootChildren = context.resume.rootNode?.children {
            for section in rootChildren {
                let sectionName = section.displayLabel
                lines.append("")
                lines.append("### \(sectionName)")

                if let entries = section.children {
                    for entry in entries {
                        let entryName = entry.displayLabel
                        let value = entry.value
                        if !value.isEmpty && value != entryName {
                            lines.append("- \(entryName): \(String(value.prefix(80)))")
                        } else {
                            lines.append("- \(entryName)")
                        }
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func buildDossierSummary(_ dossier: SwiftyJSON.JSON) -> String {
        var lines = ["## Candidate Dossier Insights"]

        if let jobContext = dossier["jobSearchContext"].string, !jobContext.isEmpty {
            lines.append("**Job Search Context:** \(jobContext)")
        }
        if let strengths = dossier["strengthsToEmphasize"].string, !strengths.isEmpty {
            lines.append("**Key Strengths:** \(strengths)")
        }
        if let pitfalls = dossier["pitfallsToAvoid"].string, !pitfalls.isEmpty {
            lines.append("**Pitfalls to Avoid:** \(pitfalls)")
        }

        return lines.joined(separator: "\n")
    }

    private func buildOutputSchema() -> String {
        """
        ## Output Schema

        Respond with a single JSON object. All string arrays should contain meaningful, \
        specific content — not generic filler. Card IDs should be exact UUID strings \
        from the knowledge cards listed above.

        ```json
        {
          "narrativeArc": "A 2-3 sentence description of the overarching story this resume tells for this specific role.",
          "kcSectionMapping": [
            {
              "cardId": "UUID-string",
              "cardTitle": "Human-readable card title",
              "recommendedSection": "work|projects|skills|summary|education",
              "rationale": "Why this card maps here for this job"
            }
          ],
          "emphasisThemes": [
            "Theme 1: specific and actionable",
            "Theme 2: specific and actionable"
          ],
          "workEntryGuidance": [
            {
              "entryIdentifier": "Company Name - Role Title (or Project Name)",
              "leadAngle": "What to lead with for this entry",
              "emphasis": ["Aspect to highlight", "Another aspect"],
              "deEmphasis": ["Aspect to minimize"],
              "supportingCardIds": ["UUID-string"]
            }
          ],
          "lateralConnections": [
            {
              "sourceCardId": "UUID-string",
              "sourceCardTitle": "Card title",
              "targetRequirement": "The job requirement this connects to",
              "reasoning": "How this experience transfers non-obviously"
            }
          ],
          "prioritizedSkills": [
            "Most important skill for this role",
            "Second most important"
          ],
          "identifiedGaps": [
            "Specific gap relative to job requirements"
          ],
          "kcRelevanceTiers": {
            "primary": ["UUID-string"],
            "supporting": ["UUID-string"],
            "background": ["UUID-string"]
          }
        }
        ```

        Remember: Be specific and strategic. Generic guidance is worse than no guidance.
        """
    }
}
