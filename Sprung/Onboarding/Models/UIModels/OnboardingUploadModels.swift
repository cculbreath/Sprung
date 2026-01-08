import Foundation

/// Metadata for an upload request
struct OnboardingUploadMetadata: Codable {
    var title: String
    var instructions: String
    var accepts: [String]
    var allowMultiple: Bool
    var allowURL: Bool = true
    var targetKey: String?
    var cancelMessage: String?
    var targetPhaseObjectives: [String]?
    var targetDeliverable: String?
    var userValidated: Bool?
}

/// Types of uploads that can be requested
enum OnboardingUploadKind: String, CaseIterable, Codable {
    case resume
    case linkedIn
    case artifact
    case generic
    case writingSample
    case coverletter
    case portfolio
    case transcript
    case certificate
}

/// An upload request from the LLM
struct OnboardingUploadRequest: Identifiable, Codable {
    let id: UUID
    let kind: OnboardingUploadKind
    let metadata: OnboardingUploadMetadata

    init(id: UUID = UUID(), kind: OnboardingUploadKind, metadata: OnboardingUploadMetadata) {
        self.id = id
        self.kind = kind
        self.metadata = metadata
    }
}

/// A file that has been uploaded
struct OnboardingUploadedItem: Identifiable, Codable {
    let id: UUID
    let filename: String
    let url: URL
    let uploadedAt: Date
}
