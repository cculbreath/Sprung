//
//  SeedGenerationContextBuilder.swift
//  Sprung
//
//  Assembles a SeedGenerationContext from onboarding artifacts and stores.
//  Extracted from AppDelegate to live alongside the seed-generation feature.
//
import Foundation

@MainActor
enum SeedGenerationContextBuilder {
    static func build(
        coordinator: OnboardingInterviewCoordinator,
        skillStore: SkillStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        applicantProfileStore: ApplicantProfileStore?,
        coverRefStore: CoverRefStore?,
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

        // Get knowledge cards from onboarding
        let knowledgeCards = coordinator.getKnowledgeCardStore().onboardingCards

        // Get title sets from library for LLM selection
        let titleSets = titleSetStore?.allTitleSets ?? []

        return SeedGenerationContext.build(
            from: defaults,
            applicantProfile: applicantProfile,
            knowledgeCards: knowledgeCards,
            skills: skillStore.skills,
            writersVoice: coverRefStore?.writersVoice ?? "",
            dossier: nil,
            titleSets: titleSets
        )
    }
}
