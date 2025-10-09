import Foundation
import SwiftData

@Model
final class TemplateAsset {
    @Attribute(.unique) var id: UUID
    var filename: String
    var mimeType: String
    var data: Data

    @Relationship(deleteRule: .nullify)
    var template: Template?

    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        data: Data,
        template: Template? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.template = template
    }
}
