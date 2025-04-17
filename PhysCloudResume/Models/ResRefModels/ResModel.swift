import Foundation
import SwiftData

@Model
class ResModel: Identifiable, Equatable, Hashable {
    var id: UUID
    var dateCreated: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \Resume.model) var resumes: [Resume]
    var name: String
    var json: String
    var renderedResumeText: String
    var style: String
    var includeFonts: Bool = false

    // Override the initializer to set the type to '.jsonSource'
    init(
        resumes: [Resume] = [],
        name: String,
        json: String,
        renderedResumeText: String,
        style: String = "Typewriter"
    ) {
        id = UUID()
        self.resumes = resumes
        self.name = name
        self.json = json
        self.renderedResumeText = renderedResumeText
        self.style = style
    }
}
