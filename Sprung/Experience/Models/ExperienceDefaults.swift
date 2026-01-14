import Foundation
import SwiftData

/// Consolidated experience defaults model using Codable arrays instead of @Relationship.
/// This eliminates 27+ child @Model classes and simplifies the data model.
@Model
final class ExperienceDefaults {
    @Attribute(.unique) var id: UUID

    /// Flag indicating whether seed generation has been run or manual edits saved
    var seedCreated: Bool = false

    // Section enablement flags
    var isWorkEnabled: Bool = false
    var isVolunteerEnabled: Bool = false
    var isEducationEnabled: Bool = false
    var isProjectsEnabled: Bool = false
    var isSkillsEnabled: Bool = false
    var isAwardsEnabled: Bool = false
    var isCertificatesEnabled: Bool = false
    var isPublicationsEnabled: Bool = false
    var isLanguagesEnabled: Bool = false
    var isInterestsEnabled: Bool = false
    var isReferencesEnabled: Bool = false
    var isCustomEnabled: Bool = false

    // Section data stored as Codable arrays (no @Relationship needed)
    var customFields: [CustomFieldValue] = []
    var work: [WorkExperienceDraft] = []
    var volunteer: [VolunteerExperienceDraft] = []
    var education: [EducationExperienceDraft] = []
    var projects: [ProjectExperienceDraft] = []
    var skills: [SkillExperienceDraft] = []
    var awards: [AwardExperienceDraft] = []
    var certificates: [CertificateExperienceDraft] = []
    var publications: [PublicationExperienceDraft] = []
    var languages: [LanguageExperienceDraft] = []
    var interests: [InterestExperienceDraft] = []
    var references: [ReferenceExperienceDraft] = []

    init(
        id: UUID = UUID(),
        isWorkEnabled: Bool = false,
        isVolunteerEnabled: Bool = false,
        isEducationEnabled: Bool = false,
        isProjectsEnabled: Bool = false,
        isSkillsEnabled: Bool = false,
        isAwardsEnabled: Bool = false,
        isCertificatesEnabled: Bool = false,
        isPublicationsEnabled: Bool = false,
        isLanguagesEnabled: Bool = false,
        isInterestsEnabled: Bool = false,
        isReferencesEnabled: Bool = false,
        isCustomEnabled: Bool = false,
        customFields: [CustomFieldValue] = [],
        work: [WorkExperienceDraft] = [],
        volunteer: [VolunteerExperienceDraft] = [],
        education: [EducationExperienceDraft] = [],
        projects: [ProjectExperienceDraft] = [],
        skills: [SkillExperienceDraft] = [],
        awards: [AwardExperienceDraft] = [],
        certificates: [CertificateExperienceDraft] = [],
        publications: [PublicationExperienceDraft] = [],
        languages: [LanguageExperienceDraft] = [],
        interests: [InterestExperienceDraft] = [],
        references: [ReferenceExperienceDraft] = []
    ) {
        self.id = id
        self.isWorkEnabled = isWorkEnabled
        self.isVolunteerEnabled = isVolunteerEnabled
        self.isEducationEnabled = isEducationEnabled
        self.isProjectsEnabled = isProjectsEnabled
        self.isSkillsEnabled = isSkillsEnabled
        self.isAwardsEnabled = isAwardsEnabled
        self.isCertificatesEnabled = isCertificatesEnabled
        self.isPublicationsEnabled = isPublicationsEnabled
        self.isLanguagesEnabled = isLanguagesEnabled
        self.isInterestsEnabled = isInterestsEnabled
        self.isReferencesEnabled = isReferencesEnabled
        self.isCustomEnabled = isCustomEnabled
        self.customFields = customFields
        self.work = work
        self.volunteer = volunteer
        self.education = education
        self.projects = projects
        self.skills = skills
        self.awards = awards
        self.certificates = certificates
        self.publications = publications
        self.languages = languages
        self.interests = interests
        self.references = references
    }
}
