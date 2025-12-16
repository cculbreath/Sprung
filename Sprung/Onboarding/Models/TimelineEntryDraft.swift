import Foundation

/// Editable draft representation of a skeleton timeline entry.
/// Unlike WorkExperienceDraft, this preserves `experienceType` so education entries don't get coerced to work.
struct TimelineEntryDraft: Identifiable, Equatable {
    var id: String
    var experienceType: ExperienceType
    var title: String
    var organization: String
    var location: String
    var start: String
    var end: String
    var summary: String
    var highlights: [String]

    init(
        id: String = UUID().uuidString,
        experienceType: ExperienceType = .work,
        title: String = "",
        organization: String = "",
        location: String = "",
        start: String = "",
        end: String = "",
        summary: String = "",
        highlights: [String] = []
    ) {
        self.id = id
        self.experienceType = experienceType
        self.title = title
        self.organization = organization
        self.location = location
        self.start = start
        self.end = end
        self.summary = summary
        self.highlights = highlights
    }
}

