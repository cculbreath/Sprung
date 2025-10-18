import Foundation
import SwiftData

@Model
final class OnboardingArtifactRecord {
    @Attribute(.unique) var id: UUID
    var applicantProfileData: Data?
    var defaultValuesData: Data?
    var knowledgeCardsData: Data?
    var skillMapData: Data?
    var factLedgerData: Data?
    var styleProfileData: Data?
    var writingSamplesData: Data?
    var profileContext: String?
    var needsVerification: [String]
    var conversationStateData: Data?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        applicantProfileData: Data? = nil,
        defaultValuesData: Data? = nil,
        knowledgeCardsData: Data? = nil,
        skillMapData: Data? = nil,
        factLedgerData: Data? = nil,
        styleProfileData: Data? = nil,
        writingSamplesData: Data? = nil,
        profileContext: String? = nil,
        needsVerification: [String] = [],
        conversationStateData: Data? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.applicantProfileData = applicantProfileData
        self.defaultValuesData = defaultValuesData
        self.knowledgeCardsData = knowledgeCardsData
        self.skillMapData = skillMapData
        self.factLedgerData = factLedgerData
        self.styleProfileData = styleProfileData
        self.writingSamplesData = writingSamplesData
        self.profileContext = profileContext
        self.needsVerification = needsVerification
        self.conversationStateData = conversationStateData
        self.updatedAt = updatedAt
    }
}
