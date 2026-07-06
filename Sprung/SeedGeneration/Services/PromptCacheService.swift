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

        // 6. Dossier insights
        if let dossier = context.dossier {
            sections.append(buildDossierSection(dossier))
        }

        let preamble = sections.joined(separator: "\n\n---\n\n")
        cachedPreamble = preamble
        cachedContextHash = contextHash
        Logger.info(
            "SGM preamble built: \(context.knowledgeCards.count) knowledge cards, "
                + "\(context.skills.count) skills, \(preamble.count) chars",
            category: .ai
        )
        return preamble
    }

    // MARK: - Private Builders

    private func buildRolePreamble() -> String {
        """
        # Role: Resume Content Generator

        You are generating resume content for a specific candidate based on their documented experiences.

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

        ### 4. QUANTIFY WITH RESTRAINT — NO MECHANICAL METRIC FORMULA

        Real, specific numbers are an asset — use them when they genuinely convey scale or
        impact. What's forbidden is the slop version of quantification:

        - Fabricated or implausible figures ("improved yield 5,000%", "1,001 improvements")
        - The mechanical "[verb] [thing], [+X%] result" cadence repeated on every bullet
        - Vague metric-shaped filler ("boosting efficiency", "driving significant gains")

        Use at most one meaningful number per bullet, as supporting detail — not as the spine of
        every sentence. Lead with WHAT was done and WHY it mattered; let a credible figure
        reinforce the point, not carry it.

        - BAD:  "Developed 1,001 process improvements, improving yield 5,000%"
        - OK:   "Taught ~1,200 students a year across the full intro physics sequence"
        - GOOD: "Rebuilt the intro physics sequence from scratch — my own problem sets,
                 solutions, and 120+ visualizations — because no existing version fit"

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

        Below is comprehensive context about the candidate. Use this to generate content that authentically represents them.
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

        // EVERY card is included — the preamble is the evidence base the model
        // is told to ground all claims in, so silently dropping cards degrades
        // generation quality with no signal. Store fetch order is arbitrary,
        // so sort deterministically: the preamble is a prompt-cache prefix and
        // must be byte-identical for a given card set.
        let sortedCards = cards.sorted {
            ($0.title, $0.id.uuidString) < ($1.title, $1.id.uuidString)
        }

        for card in sortedCards {
            lines.append("")
            lines.append("### \(card.title)")
            if let org = card.organization, !org.isEmpty {
                lines.append("**Organization:** \(org)")
            }
            if let dateRange = card.dateRange, !dateRange.isEmpty {
                lines.append("**Period:** \(dateRange)")
            }

            // Per-card digest caps (deliberate): the preamble carries a summary
            // of each card, not its full narrative — generators that need deeper
            // evidence (e.g. work highlights) do per-entry KC matching themselves.
            let kcFacts = card.facts
            if !kcFacts.isEmpty {
                lines.append("**Key Facts:**")
                for fact in kcFacts.prefix(5) {
                    lines.append("- \(fact.statement)")
                }
            }

            let bullets = card.suggestedBullets
            if !bullets.isEmpty {
                lines.append("**Highlights:**")
                for bullet in bullets.prefix(3) {
                    lines.append("- \(bullet)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func buildSkillBankSection(_ skills: [Skill]) -> String {
        var lines = ["## Skill Bank"]

        lines.append("""
            The following skills are verified from the candidate's experience.
            Only use skills from this list - do not fabricate additional skills.
            """)

        // EVERY skill is included — the model is explicitly told this list is
        // exhaustive ("do not fabricate additional skills"), so an A–M slice
        // would silently forbid most of the bank. Alphabetical order keeps the
        // prompt-cache prefix bytes deterministic for a given skill set.
        let sortedSkills = skills.sorted { $0.canonical < $1.canonical }

        var currentLetter = ""
        for skill in sortedSkills {
            let firstLetter = String(skill.canonical.prefix(1)).uppercased()
            if firstLetter != currentLetter {
                currentLetter = firstLetter
                lines.append("\n**\(currentLetter)**")
            }
            lines.append("- \(skill.canonical)")
        }

        return lines.joined(separator: "\n")
    }

    private func buildDossierSection(_ dossier: JSON) -> String {
        var lines = ["## Strategic Insights (Candidate Dossier)"]

        if let jobContext = dossier["jobSearchContext"].string, !jobContext.isEmpty {
            lines.append("\n### Job Search Context")
            lines.append(jobContext)
        }

        if let throughLines = dossier["careerThroughLines"].string, !throughLines.isEmpty {
            lines.append("\n### Career Through-Lines")
            lines.append(throughLines)
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

    /// Hash every input the preamble is built from. The cached preamble is
    /// returned verbatim while this hash matches, so any field that can alter
    /// preamble bytes MUST be combined here — keying on card/skill counts
    /// alone previously reused a stale digest after a card was edited.
    private func hashContext(_ context: SeedGenerationContext) -> Int {
        var hasher = Hasher()

        let profile = context.applicantProfile
        hasher.combine(profile.name)
        hasher.combine(profile.email)
        hasher.combine(profile.city)
        hasher.combine(profile.state)
        hasher.combine(profile.summary)

        hasher.combine(context.writersVoice)

        for card in context.knowledgeCards {
            hasher.combine(card.id)
            hasher.combine(card.title)
            hasher.combine(card.organization)
            hasher.combine(card.dateRange)
            hasher.combine(card.factsJSON)
            hasher.combine(card.suggestedBulletsJSON)
        }

        for skill in context.skills {
            hasher.combine(skill.canonical)
        }

        if let dossier = context.dossier {
            hasher.combine(dossier["jobSearchContext"].string)
            hasher.combine(dossier["careerThroughLines"].string)
            hasher.combine(dossier["strengthsToEmphasize"].string)
            hasher.combine(dossier["pitfallsToAvoid"].string)
            hasher.combine(dossier["notes"].string)
        }

        return hasher.finalize()
    }
}
