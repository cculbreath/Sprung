import Foundation
@preconcurrency import SwiftyJSON

extension JSON: @unchecked Sendable {}

enum OnboardingPhase: String, CaseIterable {
    case coreFacts
    case deepDive
    case personalContext
}

extension OnboardingPhase {
    var displayName: String {
        switch self {
        case .coreFacts: return "Core Facts"
        case .deepDive: return "Deep Dive"
        case .personalContext: return "Personal Context"
        }
    }

    var focusSummary: String {
        switch self {
        case .coreFacts:
            return "Verify identity details and establish the default résumé structure using confirmed résumé or LinkedIn data."
        case .deepDive:
            return "Run narrative interviews on each role or artifact to produce evidence-backed knowledge cards and skills mapping."
        case .personalContext:
            return "Capture career goals, constraints, preferences, and any outstanding clarifications required before drafting deliverables."
        }
    }

    var expectedOutputs: [String] {
        switch self {
        case .coreFacts:
            return [
                "delta_update entries for applicant_profile or default_values",
                "needs_verification notes for uncertain fields",
                "tool_calls for parse_resume / parse_linkedin when sourcing structured data"
            ]
        case .deepDive:
            return [
                "knowledge_cards summarizing high-impact stories",
                "skill_map_delta linking skills to evidence",
                "tool_calls for summarize_artifact or web_lookup when referencing uploads or public sources",
                "delta_update refinements for structured résumé data"
            ]
        case .personalContext:
            return [
                "profile_context narrative capturing goals and constraints",
                "next_questions prompting any outstanding clarifications",
                "persist_delta confirmations for final schema adjustments",
                "needs_verification cleanup so only unresolved gaps remain"
            ]
        }
    }

    var interviewPrompts: [String] {
        switch self {
        case .coreFacts:
            return [
                "Request the most recent résumé PDF or LinkedIn URL and confirm extracted fields with the user.",
                "Fill required applicant profile fields (name, email, phone, city, state) before moving on.",
                "Flag gaps or uncertain timeline fields in needs_verification so we can revisit them."
            ]
        case .deepDive:
            return [
                "Ask story-driven questions for each experience: challenges, actions, outcomes, metrics, and collaborators.",
                "Surface opportunities to quantify impact (dollars saved, growth %, time reduced) and capture them in knowledge_cards.",
                "Invite uploads or URLs for supporting artifacts and summarize them with the summarize_artifact tool when provided."
            ]
        case .personalContext:
            return [
                "Clarify target roles, industries, salary expectations, work preferences, and geographic or schedule constraints.",
                "Document voice & tone preferences plus narrative themes for future résumé or cover-letter drafts.",
                "Ensure all open needs_verification items have a plan—either collect answers now or log why they remain open."
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
    let target: String?

    init(id: String, text: String, target: String? = nil) {
        self.id = id
        self.text = text
        self.target = target
    }
}

struct OnboardingArtifacts {
    var applicantProfile: JSON?
    var defaultValues: JSON?
    var knowledgeCards: [JSON]
    var skillMap: JSON?
    var profileContext: String?
    var needsVerification: [String]

    init(
        applicantProfile: JSON? = nil,
        defaultValues: JSON? = nil,
        knowledgeCards: [JSON] = [],
        skillMap: JSON? = nil,
        profileContext: String? = nil,
        needsVerification: [String] = []
    ) {
        self.applicantProfile = applicantProfile
        self.defaultValues = defaultValues
        self.knowledgeCards = knowledgeCards
        self.skillMap = skillMap
        self.profileContext = profileContext
        self.needsVerification = needsVerification
    }
}
