import Foundation
import SwiftData

@Model
final class Template {
    @Attribute(.unique) var id: UUID
    var name: String
    var slug: String
    var htmlContent: String?
    var textContent: String?
    var cssContent: String?
    var manifestData: Data?
    var createdAt: Date
    var updatedAt: Date
    var isCustom: Bool
    var isDefault: Bool

    @Relationship(deleteRule: .cascade)
    var seeds: [TemplateSeed]

    @Relationship(deleteRule: .nullify)
    var resumes: [Resume]

    init(
        id: UUID = UUID(),
        name: String,
        slug: String,
        htmlContent: String? = nil,
        textContent: String? = nil,
        cssContent: String? = nil,
        manifestData: Data? = nil,
        isCustom: Bool = false,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        seeds: [TemplateSeed] = []
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.htmlContent = htmlContent
        self.textContent = textContent
        self.cssContent = cssContent
        self.manifestData = manifestData
        self.isCustom = isCustom
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resumes = []
        self.seeds = seeds
    }
}
