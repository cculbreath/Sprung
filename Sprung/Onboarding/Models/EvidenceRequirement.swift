import Foundation
/// Represents a specific piece of evidence requested by the Lead Investigator.
struct EvidenceRequirement: Codable, Identifiable, Equatable {
    let id: String
    let timelineEntryId: String
    let description: String
    let category: EvidenceCategory
    var status: EvidenceStatus
    var linkedArtifactId: String?

    enum EvidenceCategory: String, Codable {
        case paper
        case code
        case website
        case portfolio
        case degree
        case other
    }

    enum EvidenceStatus: String, Codable {
        case requested
        case fulfilled
        case skipped
    }

    init(
        id: String = UUID().uuidString,
        timelineEntryId: String,
        description: String,
        category: EvidenceCategory,
        status: EvidenceStatus = .requested,
        linkedArtifactId: String? = nil
    ) {
        self.id = id
        self.timelineEntryId = timelineEntryId
        self.description = description
        self.category = category
        self.status = status
        self.linkedArtifactId = linkedArtifactId
    }
}
