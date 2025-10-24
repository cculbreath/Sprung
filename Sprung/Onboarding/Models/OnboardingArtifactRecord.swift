import Foundation
import SwiftData

@Model
final class OnboardingArtifactRecord {
    var id: UUID
    var createdAt: Date
    var kind: String
    var payload: String?

    init(id: UUID = UUID(), createdAt: Date = Date(), kind: String, payload: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.payload = payload
    }
}
