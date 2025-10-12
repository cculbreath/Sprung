import Foundation
import SwiftyJSON

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
