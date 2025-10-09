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

    @Relationship(deleteRule: .cascade, inverse: \TemplateAsset.template)
    var assets: [TemplateAsset]

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
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        assets: [TemplateAsset] = []
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.htmlContent = htmlContent
        self.textContent = textContent
        self.cssContent = cssContent
        self.manifestData = manifestData
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.assets = assets
        self.resumes = []
    }
}
