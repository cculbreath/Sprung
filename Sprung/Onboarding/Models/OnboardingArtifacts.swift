import Foundation
@preconcurrency import SwiftyJSON

enum OnboardingPhase: String, CaseIterable {
    case resumeIntake
    case artifactDiscovery
    case writingCorpus
    case wrapUp
}

extension OnboardingPhase {
    var displayName: String {
        switch self {
        case .resumeIntake: return "Résumé Intake"
        case .artifactDiscovery: return "Artifact Discovery"
        case .writingCorpus: return "Writing Corpus"
        case .wrapUp: return "Wrap-Up"
        }
    }

    var focusSummary: String {
        switch self {
        case .resumeIntake:
            return "Parse the résumé or LinkedIn profile into ApplicantProfile and DefaultValues, capturing uncertainties for follow-up."
        case .artifactDiscovery:
            return "Surface high-impact artifacts, summarize them into ResRefs, and build the fact ledger and skill-evidence map."
        case .writingCorpus:
            return "Collect writing samples, analyze tone and structure, and persist the resulting style profile and corpus references."
        case .wrapUp:
            return "Resolve outstanding verifications, consolidate remaining deltas, and confirm export-ready onboarding artifacts."
        }
    }

    var expectedOutputs: [String] {
        switch self {
        case .resumeIntake:
            return [
                "delta_update entries for applicant_profile or default_values",
                "needs_verification notes for uncertain fields",
                "tool_calls for parse_resume / parse_linkedin when sourcing structured data"
            ]
        case .artifactDiscovery:
            return [
                "knowledge_cards summarizing high-impact stories",
                "skill_map_delta linking skills to evidence",
                "fact_ledger additions that capture claims + provenance",
                "tool_calls for summarize_artifact or web_lookup when referencing uploads or public sources",
                "delta_update refinements for structured résumé data"
            ]
        case .writingCorpus:
            return [
                "tool_calls for summarize_writing on uploaded samples",
                "persist_style_profile calls with validated style_vector outputs",
                "CoverRef records for each confirmed writing sample"
            ]
        case .wrapUp:
            return [
                "profile_context narrative capturing goals and constraints",
                "next_questions prompting any outstanding clarifications",
                "persist_facts_from_card or persist_skill_map confirmations as needed",
                "persist_delta confirmations for final schema adjustments",
                "needs_verification cleanup so only unresolved gaps remain"
            ]
        }
    }

    var interviewPrompts: [String] {
        switch self {
        case .resumeIntake:
            return [
                "Request the most recent résumé PDF or LinkedIn URL and confirm extracted fields with the user.",
                "Fill required applicant profile fields (name, email, phone, city, state) before moving on.",
                "Flag gaps or uncertain timeline fields in needs_verification so we can revisit them."
            ]
        case .artifactDiscovery:
            return [
                "Ask story-driven questions for each experience: challenges, actions, outcomes, metrics, and collaborators.",
                "Surface opportunities to quantify impact (dollars saved, growth %, time reduced) and capture them in knowledge_cards.",
                "Invite uploads or URLs for supporting artifacts and summarize them with the summarize_artifact tool when provided."
            ]
        case .writingCorpus:
            return [
                "Invite the user to supply representative writing samples (cover letters, portfolio blurbs, emails).",
                "Run summarize_writing for each uploaded sample and highlight distinguishing traits for user confirmation.",
                "Persist a style_vector only after the user approves the findings, and ensure the full texts are saved as CoverRefs."
            ]
        case .wrapUp:
            return [
                "Clarify remaining goals, constraints, or consent settings that affect downstream deliverables.",
                "Summarize completed artifacts (ApplicantProfile, DefaultValues, ResRefs, fact ledger, style profile) and highlight open action items.",
                "Record why any needs_verification items remain unresolved and confirm export readiness."
            ]
        }
    }
}

struct OnboardingMessage: Identifiable, Equatable {
    enum Role {
        case system
        case assistant
        case user
    }

    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

struct OnboardingQuestion: Identifiable, Equatable {
    let id: String
    let text: String

    init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

struct OnboardingArtifacts {
    var applicantProfile: JSON?
    var defaultValues: JSON?
    var knowledgeCards: [JSON]
    var skillMap: JSON?
    var factLedger: [JSON]
    var styleProfile: JSON?
    var writingSamples: [JSON]
    var profileContext: String?
    var needsVerification: [String]

    init(
        applicantProfile: JSON? = nil,
        defaultValues: JSON? = nil,
        knowledgeCards: [JSON] = [],
        skillMap: JSON? = nil,
        factLedger: [JSON] = [],
        styleProfile: JSON? = nil,
        writingSamples: [JSON] = [],
        profileContext: String? = nil,
        needsVerification: [String] = []
    ) {
        self.applicantProfile = applicantProfile
        self.defaultValues = defaultValues
        self.knowledgeCards = knowledgeCards
        self.skillMap = skillMap
        self.factLedger = factLedger
        self.styleProfile = styleProfile
        self.writingSamples = writingSamples
        self.profileContext = profileContext
        self.needsVerification = needsVerification
    }
}
