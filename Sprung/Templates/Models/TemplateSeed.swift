import Foundation
import SwiftData

@Model
final class TemplateSeed {
    @Attribute(.unique) var id: UUID
    var slug: String
    var seedData: Data
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Template.seeds)
    var template: Template?

    init(
        id: UUID = UUID(),
        slug: String,
        seedData: Data,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        template: Template? = nil
    ) {
        self.id = id
        self.slug = slug.lowercased()
        self.seedData = seedData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.template = template
    }

    var jsonString: String {
        get {
            String(data: seedData, encoding: .utf8) ?? "{}"
        }
        set {
            seedData = newValue.data(using: .utf8) ?? Data()
            updatedAt = Date()
        }
    }
}
