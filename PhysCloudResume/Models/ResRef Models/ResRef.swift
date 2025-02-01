import Foundation
import SwiftData

@Model
class ResRef: Identifiable {
    var id: UUID // Change from String to UUID
    var content: String
    var name: String
    var enabledByDefault: Bool

    var enabledResumes: [Resume] = []

    init(
        name: String = "", content: String = "",
        enabledByDefault: Bool = false
    ) {
        id = UUID() // Ensure UUID is used correctly
        self.content = content
        self.name = name
        self.enabledByDefault = enabledByDefault
    }
}
