import Foundation
import SwiftData
@Model
final class ExperienceCustomField {
    var id: UUID = UUID()
    var key: String
    var index: Int
    @Relationship(deleteRule: .cascade, inverse: \ExperienceCustomFieldValue.field)
    var values: [ExperienceCustomFieldValue]
    weak var defaults: ExperienceDefaults?
    init(
        key: String,
        index: Int,
        values: [ExperienceCustomFieldValue] = [],
        defaults: ExperienceDefaults? = nil
    ) {
        self.key = key
        self.index = index
        self.values = values
        self.defaults = defaults
        values.forEach { $0.field = self }
    }
}
@Model
final class ExperienceCustomFieldValue {
    var id: UUID = UUID()
    var value: String
    var index: Int
    weak var field: ExperienceCustomField?
    init(value: String, index: Int, field: ExperienceCustomField? = nil) {
        self.value = value
        self.index = index
        self.field = field
    }
}
