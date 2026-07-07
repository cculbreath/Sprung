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
        await build(
            defaults: experienceDefaultsStore.currentDefaults(),
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore,
            applicantProfileStore: applicantProfileStore,
            coverRefStore: coverRefStore,
            candidateDossierStore: candidateDossierStore,
            titleSetStore: titleSetStore
        )
    }

    /// Build a context from an explicit `ExperienceDefaults` snapshot rather than the
    /// persisted store. Single-entry refinement passes an in-memory snapshot of the
    /// live editor draft here so unsaved edits are reflected in the generator prompt.
    static func build(
        defaults: ExperienceDefaults,
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        applicantProfileStore: ApplicantProfileStore?,
        coverRefStore: CoverRefStore?,
        candidateDossierStore: CandidateDossierStore?,
        titleSetStore: TitleSetStore?
    ) async -> SeedGenerationContext? {
        // Get applicant profile
        let applicantProfile: ApplicantProfileDraft
        if let profileStore = applicantProfileStore {
            applicantProfile = ApplicantProfileDraft(profile: profileStore.currentProfile())
        } else {
            applicantProfile = ApplicantProfileDraft()
        }

        // Only APPROVED cards feed generation. Cards persisted mid-interview
        // stay pending until the user approves them (onboarding approves its
        // own before generating; abandoned-interview ghosts never qualify).
        let knowledgeCards = knowledgeCardStore.approvedCards

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
            skills: skillStore.approvedSkills,
            writersVoice: coverRefStore?.writersVoice ?? "",
            voiceSummary: coverRefStore?.voiceSummary ?? "",
            dossier: dossierJSON,
            titleSets: titleSets
        )
    }
}
