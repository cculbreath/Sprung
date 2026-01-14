//
//  PromptCacheService.swift
//  Sprung
//
//  Builds shared preamble for LLM prompt caching.
//  The preamble contains context that's shared across all generation tasks,
//  allowing providers like Anthropic to cache it for efficiency.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Service for building cacheable prompt preambles.
/// The preamble is built once from context and reused across all generation tasks.
@MainActor
final class PromptCacheService {
    // MARK: - Configuration

    private let backend: LLMFacade.Backend

    // MARK: - Cached State

    private var cachedPreamble: String?
    private var cachedContextHash: Int?

    init(backend: LLMFacade.Backend = .openRouter) {
        self.backend = backend
    }

    // MARK: - Public API

    /// Build the cacheable preamble from generation context.
    /// This preamble is shared across all generation tasks.
    /// - Parameter context: The seed generation context
    /// - Returns: The preamble string to prepend to all prompts
    func buildPreamble(context: SeedGenerationContext) -> String {
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
        if !context.writingSamples.isEmpty {
            sections.append(buildVoiceSection(context.writingSamples))
        }

        // 4. Knowledge card summaries
        if !context.knowledgeCards.isEmpty {
            sections.append(buildKnowledgeCardSection(context.knowledgeCards))
        }

        // 5. Skill bank
        if !context.skills.isEmpty {
            sections.append(buildSkillBankSection(context.skills))
        }

        // 6. Dossier insights
        if let dossier = context.dossier {
            sections.append(buildDossierSection(dossier))
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
    ///   - taskContext: Task-specific context (e.g., which timeline entry)
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
    ///   - context: The seed generation context
    ///   - sectionPrompt: Section-specific generation instructions
    ///   - taskContext: Task-specific context
    /// - Returns: Array of AnthropicSystemBlock with cache control on the preamble
    func buildAnthropicSystemContent(
        context: SeedGenerationContext,
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

        You are an expert resume writer generating content for a specific candidate.
        Your task is to create compelling, professional resume content that:

        1. **Uses concrete evidence** - Draw from the candidate's actual experiences and achievements
        2. **Matches their voice** - Reflect their professional communication style
        3. **Highlights strengths** - Emphasize the candidate's unique value proposition
        4. **Is honest and accurate** - Never fabricate or exaggerate
        5. **Is concise and impactful** - Use strong action verbs and quantify where possible

        Below is comprehensive context about the candidate. Use this information to create
        tailored content that authentically represents them.
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

    private func buildVoiceSection(_ writingSamples: [CoverRef]) -> String {
        var lines = ["## Voice & Style Guidelines"]

        lines.append("""
            The candidate's writing style characteristics (derived from their writing samples):

            - Use language that matches their professional register
            - Maintain their typical sentence structure patterns
            - Reflect their vocabulary choices and industry terminology
            - Preserve their tone (formal/informal, confident/modest, etc.)
            """)

        // Include sample excerpts for context
        lines.append("\n*\(writingSamples.count) writing sample(s) analyzed for voice patterns.*")

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

    // MARK: - Hashing

    private func hashContext(_ context: SeedGenerationContext) -> Int {
        // Simple hash combining key elements
        var hasher = Hasher()
        hasher.combine(context.applicantProfile.name)
        hasher.combine(context.applicantProfile.email)
        hasher.combine(context.knowledgeCards.count)
        hasher.combine(context.skills.count)
        hasher.combine(context.writingSamples.count)
        return hasher.finalize()
    }
}
