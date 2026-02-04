//
//  CustomizationContext.swift
//  Sprung
//
//  Immutable context snapshot for resume customization.
//  Captures all relevant data at the start of a customization workflow
//  to ensure consistency throughout the process.
//

import Foundation
import SwiftyJSON

/// Immutable context snapshot for resume customization.
///
/// Similar to SeedGenerationContext but tailored for customization workflows.
/// Contains all the data needed for AI-driven resume customization including
/// the target resume, applicant profile, knowledge base, and job-specific information.
///
/// Usage:
/// ```swift
/// let context = CustomizationContext.build(
///     resume: resume,
///     skillStore: skillStore,
///     guidanceStore: guidanceStore,
///     knowledgeCardStore: knowledgeCardStore,
///     coverRefStore: coverRefStore,
///     applicantProfileStore: applicantProfileStore
/// )
/// ```
struct CustomizationContext {

    // MARK: - Core Properties

    /// The resume being customized
    let resume: Resume

    /// Applicant's profile information
    let applicantProfile: ApplicantProfileDraft

    /// Knowledge cards providing background context
    let knowledgeCards: [KnowledgeCard]

    /// Approved skills from the skill bank
    let skills: [Skill]

    /// Title sets for professional identity guidance
    let titleSets: [TitleSet]

    /// Pre-built voice context string from CoverRefStore.writersVoice
    let writersVoice: String

    /// Strategic insights from job analysis
    let dossier: JSON?

    /// The job description text from the job application
    let jobDescription: String

    /// Clarifying Q&A pairs (mutable for workflow updates)
    var clarifyingQA: [(question: ClarifyingQuestion, answer: QuestionAnswer)]?

    // MARK: - Computed Properties

    /// Returns an array of canonical skill names from the skill bank.
    var skillBankList: [String] {
        skills.map { $0.canonical }
    }

    /// Returns the company name from the job application if available.
    var companyName: String? {
        resume.jobApp?.companyName
    }

    /// Returns the job position/title from the job application if available.
    var jobPosition: String? {
        resume.jobApp?.jobPosition
    }

    // MARK: - Builder

    /// Builds a CustomizationContext by gathering data from all relevant stores.
    ///
    /// - Parameters:
    ///   - resume: The resume being customized
    ///   - skillStore: Store containing user's approved skills
    ///   - guidanceStore: Store containing inference guidance including title sets
    ///   - knowledgeCardStore: Store containing knowledge cards
    ///   - coverRefStore: Store containing writing samples and voice primer
    ///   - applicantProfileStore: Store containing applicant profile
    /// - Returns: A fully populated CustomizationContext
    @MainActor
    static func build(
        resume: Resume,
        skillStore: SkillStore,
        guidanceStore: InferenceGuidanceStore,
        knowledgeCardStore: KnowledgeCardStore,
        coverRefStore: CoverRefStore,
        applicantProfileStore: ApplicantProfileStore
    ) -> CustomizationContext {
        // Get approved skills
        let approvedSkills = skillStore.approvedSkills

        // Get title sets from guidance store
        let titleSets = guidanceStore.titleSets()

        // Get approved knowledge cards
        let knowledgeCards = knowledgeCardStore.approvedCards

        // Get applicant profile
        let profile = applicantProfileStore.currentProfile()
        let profileDraft = ApplicantProfileDraft(profile: profile)

        // Get job description from resume's job application
        let jobDescription = resume.jobApp?.jobListingString ?? ""

        return CustomizationContext(
            resume: resume,
            applicantProfile: profileDraft,
            knowledgeCards: knowledgeCards,
            skills: approvedSkills,
            titleSets: titleSets,
            writersVoice: coverRefStore.writersVoice,
            dossier: nil,  // Strategic insights can be populated separately if available
            jobDescription: jobDescription,
            clarifyingQA: nil
        )
    }
}
