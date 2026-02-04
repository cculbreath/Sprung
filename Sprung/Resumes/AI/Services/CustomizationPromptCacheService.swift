//
//  CustomizationPromptCacheService.swift
//  Sprung
//
//  Builds shared preamble for LLM prompt caching during resume customization.
//  The preamble contains context that's shared across all customization tasks,
//  allowing providers like Anthropic to cache it for efficiency.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Rich context for building resume customization prompts.
/// Contains all the background materials needed for LLM prompt construction.
struct CustomizationPromptContext {
    /// Applicant profile data
    let applicantProfile: ApplicantProfileDraft

    /// Knowledge cards from document extraction
    let knowledgeCards: [KnowledgeCard]

    /// Skills from the skill bank
    let skills: [Skill]

    /// Pre-built voice context string from CoverRefStore.writersVoice
    let writersVoice: String

    /// Candidate dossier with strategic insights (if available)
    let dossier: JSON?

    /// Available title sets for professional identity
    let titleSets: [TitleSetRecord]

    /// The job application being customized for
    let jobApp: JobApp
}

/// Service for building cacheable prompt preambles for resume customization.
/// The preamble is built once from context and reused across all customization tasks.
@MainActor
final class CustomizationPromptCacheService {
    // MARK: - Configuration

    private let backend: LLMFacade.Backend

    // MARK: - Cached State

    private var cachedPreamble: String?
    private var cachedContextHash: Int?
    private var clarifyingQA: [(ClarifyingQuestion, QuestionAnswer)] = []

    init(backend: LLMFacade.Backend = .openRouter) {
        self.backend = backend
    }

    // MARK: - Public API

    /// Build the cacheable preamble from customization context.
    /// This preamble is shared across all customization tasks.
    /// - Parameter context: The customization context
    /// - Returns: The preamble string to prepend to all prompts
    func buildPreamble(context: CustomizationPromptContext) -> String {
        // Check cache
        let contextHash = hashContext(context)
        if let cached = cachedPreamble, cachedContextHash == contextHash {
            return cached
        }

        // Build new preamble
        var sections: [String] = []

        // 1. Role and purpose
        sections.append(buildRolePreamble())

        // 2. Applicant profile summary
        sections.append(buildProfileSection(context.applicantProfile))

        // 3. Voice and style guidelines
        if !context.writersVoice.isEmpty {
            sections.append(context.writersVoice)
        }

        // 4. Knowledge card summaries
        if !context.knowledgeCards.isEmpty {
            sections.append(buildKnowledgeCardSection(context.knowledgeCards))
        }

        // 5. Skill bank
        if !context.skills.isEmpty {
            sections.append(buildSkillBankSection(context.skills))
        }

        // 6. Title set library
        if !context.titleSets.isEmpty {
            sections.append(buildTitleSetSection(context.titleSets))
        }

        // 7. Dossier insights
        if let dossier = context.dossier {
            sections.append(buildDossierSection(dossier))
        }

        // 8. Job description
        sections.append(buildJobDescriptionSection(context.jobApp))

        // 9. Clarifying Q&A (if any)
        if !clarifyingQA.isEmpty {
            sections.append(buildClarifyingQASection())
        }

        let preamble = sections.joined(separator: "\n\n---\n\n")
        cachedPreamble = preamble
        cachedContextHash = contextHash
        return preamble
    }

    /// Combine preamble with section-specific instructions.
    /// - Parameters:
    ///   - preamble: The cached preamble
    ///   - sectionPrompt: Section-specific generation instructions
    ///   - taskContext: Task-specific context (e.g., which section to customize)
    /// - Returns: Complete prompt ready for LLM
    func buildPrompt(preamble: String, sectionPrompt: String, taskContext: String) -> String {
        """
        \(preamble)

        ---

        ## Current Task

        \(sectionPrompt)

        ## Context for This Task

        \(taskContext)
        """
    }

    /// Build structured system content blocks for Anthropic caching.
    /// The preamble is marked with cache_control for server-side caching.
    /// - Parameters:
    ///   - context: The customization context
    ///   - sectionPrompt: Section-specific generation instructions
    ///   - taskContext: Task-specific context
    /// - Returns: Array of AnthropicSystemBlock with cache control on the preamble
    func buildAnthropicSystemContent(
        context: CustomizationPromptContext,
        sectionPrompt: String,
        taskContext: String
    ) -> [AnthropicSystemBlock] {
        let preamble = buildPreamble(context: context)

        // The preamble (large, static context) gets cache_control
        // The task-specific content is dynamic and not cached
        let taskContent = """
        ## Current Task

        \(sectionPrompt)

        ## Context for This Task

        \(taskContext)
        """

        // Build system blocks with cache_control on the preamble
        let cachedPreambleBlock = AnthropicSystemBlock(
            text: preamble,
            cacheControl: AnthropicCacheControl()  // defaults to "ephemeral"
        )

        let taskBlock = AnthropicSystemBlock(text: taskContent)

        return [cachedPreambleBlock, taskBlock]
    }

    /// Append clarifying Q&A and invalidate cache
    /// - Parameter qa: Array of question-answer pairs
    func appendClarifyingQA(_ qa: [(ClarifyingQuestion, QuestionAnswer)]) {
        clarifyingQA.append(contentsOf: qa)
        invalidateCache()
    }

    /// Check if this service is configured for Anthropic caching
    var usesCaching: Bool {
        backend == .anthropic
    }

    /// Invalidate cached preamble (call when context changes)
    func invalidateCache() {
        cachedPreamble = nil
        cachedContextHash = nil
    }

    // MARK: - Private Builders

    private func buildRolePreamble() -> String {
        """
        # Role: Resume Content Generator

        You are generating customized resume content for a specific candidate targeting a particular job opportunity.
        Your goal is to tailor the candidate's existing experience to highlight the most relevant aspects for this role.

        ## CRITICAL CONSTRAINTS

        ### 1. NO FABRICATED METRICS

        You may ONLY include quantitative claims that appear VERBATIM in the Knowledge Cards.
        If no metric exists in the source material, describe the work narratively without inventing numbers.

        FORBIDDEN (unless exact figures appear in a Knowledge Card):
        - "reduced time by 40%"
        - "improved efficiency by 25%"
        - "increased engagement by 3x"
        - "significantly improved"
        - Any percentage or multiplier not directly quoted from evidence

        ALLOWED:
        - "resulted in 3 peer-reviewed publications" (if KC states exactly this)
        - "built a system that..." (narrative description)
        - "developed novel approach to..." (qualitative impact)

        ### 2. NO GENERIC RESUME VOICE

        Do NOT write in formulaic LinkedIn/corporate style. Avoid:
        - "Spearheaded initiatives that drove..."
        - "Leveraged expertise to deliver..."
        - "Collaborated cross-functionally to..."
        - "Proven track record of..."

        Instead, write in the candidate's actual voice as demonstrated in their writing samples.
        Match their vocabulary, sentence structure, and professional register.

        ### 3. EVIDENCE-BASED ONLY

        Every factual claim must trace to a Knowledge Card. If you cannot cite evidence for a claim, do not include it.

        ### 4. SKILL SELECTION CONSTRAINT

        When selecting or suggesting skills, you may ONLY use skills from the provided Skill Bank.
        Do not invent skills or use variations not present in the bank.

        ### 5. TITLE SET AWARENESS

        The Title Set Library provides curated professional identity combinations the candidate has developed.
        When crafting summary statements or positioning, consider which title set best aligns with the target role.

        ## Role-Appropriate Framing

        Tailor bullet structure to the position type:

        **For R&D / Academic / Research positions:**
        - What problem or gap existed?
        - What novel approach was taken?
        - What was created, discovered, or published?
        - Who uses it or what opportunities did it open?

        **For Industry / Engineering / Corporate positions:**
        - What system or process did they own?
        - What was their specific technical contribution?
        - What concrete outcome resulted? (only if documented)

        **For Teaching / Education positions:**
        - What did they build or redesign?
        - What pedagogical approach did they use?
        - What was the scope and impact on students?

        Below is comprehensive context about the candidate and the target opportunity. Use this to generate content that authentically represents them while being optimally tailored for the role.
        """
    }

    private func buildProfileSection(_ profile: ApplicantProfileDraft) -> String {
        var lines = ["## Applicant Profile"]

        if !profile.name.isEmpty {
            lines.append("**Name:** \(profile.name)")
        }

        if !profile.email.isEmpty {
            lines.append("**Email:** \(profile.email)")
        }

        // Build location from components
        var locationParts: [String] = []
        if !profile.city.isEmpty { locationParts.append(profile.city) }
        if !profile.state.isEmpty { locationParts.append(profile.state) }
        if !locationParts.isEmpty {
            lines.append("**Location:** \(locationParts.joined(separator: ", "))")
        }

        if !profile.summary.isEmpty {
            lines.append("\n**Professional Summary:**\n\(profile.summary)")
        }

        return lines.joined(separator: "\n")
    }

    private func buildKnowledgeCardSection(_ cards: [KnowledgeCard]) -> String {
        var lines = ["## Knowledge Cards (Evidence Base)"]

        lines.append("""
            The following knowledge cards contain verified evidence about the candidate's
            experiences, achievements, and skills. Use these as the factual foundation
            for generated content.
            """)

        for card in cards.prefix(20) { // Limit to prevent token overflow
            lines.append("")
            lines.append("### \(card.title)")
            if let org = card.organization, !org.isEmpty {
                lines.append("**Organization:** \(org)")
            }
            if let dateRange = card.dateRange, !dateRange.isEmpty {
                lines.append("**Period:** \(dateRange)")
            }

            // Include facts
            let kcFacts = card.facts
            if !kcFacts.isEmpty {
                lines.append("**Key Facts:**")
                for fact in kcFacts.prefix(5) {
                    lines.append("- \(fact.statement)")
                }
            }

            // Include suggested bullets if available
            let bullets = card.suggestedBullets
            if !bullets.isEmpty {
                lines.append("**Highlights:**")
                for bullet in bullets.prefix(3) {
                    lines.append("- \(bullet)")
                }
            }
        }

        if cards.count > 20 {
            lines.append("\n*... and \(cards.count - 20) more knowledge cards*")
        }

        return lines.joined(separator: "\n")
    }

    private func buildSkillBankSection(_ skills: [Skill]) -> String {
        var lines = ["## Skill Bank"]

        lines.append("""
            The following skills are verified from the candidate's experience.
            Only use skills from this list - do not fabricate additional skills.
            """)

        // Group skills by source or just list them
        let sortedSkills = skills.sorted { $0.canonical < $1.canonical }

        var currentLetter = ""
        for skill in sortedSkills.prefix(100) { // Limit to prevent overflow
            let firstLetter = String(skill.canonical.prefix(1)).uppercased()
            if firstLetter != currentLetter {
                currentLetter = firstLetter
                lines.append("\n**\(currentLetter)**")
            }
            lines.append("- \(skill.canonical)")
        }

        if skills.count > 100 {
            lines.append("\n*... and \(skills.count - 100) more skills*")
        }

        return lines.joined(separator: "\n")
    }

    private func buildTitleSetSection(_ titleSets: [TitleSetRecord]) -> String {
        var lines = ["## Title Set Library"]

        lines.append("""
            The following title sets represent curated professional identity combinations.
            Each set contains 4 words that together describe the candidate's professional identity.
            Consider which combination best aligns with the target role when crafting positioning.
            """)

        for (index, titleSet) in titleSets.enumerated() {
            lines.append("")
            lines.append("### Option \(index + 1)")
            lines.append("**\(titleSet.displayString)**")
            if let notes = titleSet.notes, !notes.isEmpty {
                lines.append("*Notes:* \(notes)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func buildDossierSection(_ dossier: JSON) -> String {
        var lines = ["## Strategic Insights (Candidate Dossier)"]

        if let jobContext = dossier["jobSearchContext"].string, !jobContext.isEmpty {
            lines.append("\n### Job Search Context")
            lines.append(jobContext)
        }

        if let strengths = dossier["strengthsToEmphasize"].string, !strengths.isEmpty {
            lines.append("\n### Key Strengths to Emphasize")
            lines.append(strengths)
        }

        if let pitfalls = dossier["pitfallsToAvoid"].string, !pitfalls.isEmpty {
            lines.append("\n### Pitfalls to Avoid")
            lines.append(pitfalls)
        }

        if let notes = dossier["notes"].string, !notes.isEmpty {
            lines.append("\n### Additional Notes")
            lines.append(notes)
        }

        return lines.joined(separator: "\n")
    }

    private func buildJobDescriptionSection(_ jobApp: JobApp) -> String {
        var lines = ["## Target Job Opportunity"]

        lines.append("")
        lines.append("**Position:** \(jobApp.jobPosition)")
        lines.append("**Company:** \(jobApp.companyName)")

        if !jobApp.jobLocation.isEmpty {
            lines.append("**Location:** \(jobApp.jobLocation)")
        }

        if !jobApp.seniorityLevel.isEmpty {
            lines.append("**Seniority Level:** \(jobApp.seniorityLevel)")
        }

        if !jobApp.employmentType.isEmpty {
            lines.append("**Employment Type:** \(jobApp.employmentType)")
        }

        if !jobApp.jobFunction.isEmpty {
            lines.append("**Job Function:** \(jobApp.jobFunction)")
        }

        if !jobApp.industries.isEmpty {
            lines.append("**Industries:** \(jobApp.industries)")
        }

        if !jobApp.salary.isEmpty {
            lines.append("**Salary:** \(jobApp.salary)")
        }

        if !jobApp.jobDescription.isEmpty {
            lines.append("")
            lines.append("### Full Job Description")
            lines.append("")
            lines.append(jobApp.jobDescription)
        }

        // Include extracted requirements if available
        if let requirements = jobApp.extractedRequirements, requirements.isValid {
            lines.append("")
            lines.append("### Extracted Requirements")

            if !requirements.mustHave.isEmpty {
                lines.append("")
                lines.append("**Must Have (Required):**")
                for item in requirements.mustHave {
                    lines.append("- \(item)")
                }
            }

            if !requirements.strongSignal.isEmpty {
                lines.append("")
                lines.append("**Strong Signals (Emphasized):**")
                for item in requirements.strongSignal {
                    lines.append("- \(item)")
                }
            }

            if !requirements.preferred.isEmpty {
                lines.append("")
                lines.append("**Preferred (Nice to Have):**")
                for item in requirements.preferred {
                    lines.append("- \(item)")
                }
            }

            if !requirements.cultural.isEmpty {
                lines.append("")
                lines.append("**Cultural/Soft Skills:**")
                for item in requirements.cultural {
                    lines.append("- \(item)")
                }
            }

            if !requirements.atsKeywords.isEmpty {
                lines.append("")
                lines.append("**ATS Keywords:**")
                lines.append(requirements.atsKeywords.joined(separator: ", "))
            }
        }

        return lines.joined(separator: "\n")
    }

    private func buildClarifyingQASection() -> String {
        var lines = ["## Clarifying Q&A"]

        lines.append("""
            The following questions were asked to gather additional context for customization.
            Use these answers to inform your content generation.
            """)

        for (question, answer) in clarifyingQA {
            lines.append("")
            lines.append("**Q:** \(question.question)")
            if let context = question.context {
                lines.append("*Context:* \(context)")
            }
            if let answerText = answer.answer, !answerText.isEmpty {
                lines.append("**A:** \(answerText)")
            } else {
                lines.append("**A:** *(Question declined)*")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Hashing

    private func hashContext(_ context: CustomizationPromptContext) -> Int {
        // Simple hash combining key elements
        var hasher = Hasher()
        hasher.combine(context.applicantProfile.name)
        hasher.combine(context.applicantProfile.email)
        hasher.combine(context.knowledgeCards.count)
        hasher.combine(context.skills.count)
        hasher.combine(context.writersVoice)
        hasher.combine(context.titleSets.count)
        hasher.combine(context.jobApp.id)
        hasher.combine(clarifyingQA.count)
        return hasher.finalize()
    }
}
