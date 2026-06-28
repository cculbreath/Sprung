//
//  SeedGenerationContextBuilder.swift
//  Sprung
//
//  Assembles a SeedGenerationContext from onboarding artifacts and stores.
//  Extracted from AppDelegate to live alongside the seed-generation feature.
//
import Foundation
import SwiftyJSON

@MainActor
enum SeedGenerationContextBuilder {
    static func build(
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        applicantProfileStore: ApplicantProfileStore?,
        coverRefStore: CoverRefStore?,
        candidateDossierStore: CandidateDossierStore?,
        titleSetStore: TitleSetStore?
    ) async -> SeedGenerationContext? {
        let defaults = experienceDefaultsStore.currentDefaults()

        // Get applicant profile
        let applicantProfile: ApplicantProfileDraft
        if let profileStore = applicantProfileStore {
            applicantProfile = ApplicantProfileDraft(profile: profileStore.currentProfile())
        } else {
            applicantProfile = ApplicantProfileDraft()
        }

        // All knowledge cards feed generation — both onboarding-derived and any the
        // user added manually in the Knowledge Card browser.
        let knowledgeCards = knowledgeCardStore.knowledgeCards

        // Get title sets from library for LLM selection
        let titleSets = titleSetStore?.allTitleSets ?? []

        // Strategic dossier (job-search context, strengths/pitfalls, and the
        // career through-lines synthesis) as JSON for the generators' role
        // preamble. Encoded via the model's Codable (camelCase keys match what
        // PromptCacheService.buildDossierSection reads).
        let dossierJSON: JSON? = candidateDossierStore?.dossier.flatMap { dossier in
            guard let data = try? JSONEncoder().encode(dossier) else { return nil }
            return try? JSON(data: data)
        }

        return SeedGenerationContext.build(
            from: defaults,
            applicantProfile: applicantProfile,
            knowledgeCards: knowledgeCards,
            skills: skillStore.skills,
            writersVoice: coverRefStore?.writersVoice ?? "",
            voiceSummary: coverRefStore?.voiceSummary ?? "",
            dossier: dossierJSON,
            titleSets: titleSets
        )
    }
}
