import Foundation
struct CustomFieldValue: Codable, Equatable, Identifiable {
    var id: UUID
    var key: String
    var values: [String]
    init(id: UUID = UUID(), key: String = "", values: [String] = []) {
        self.id = id
        self.key = key
        self.values = values
    }
}
struct ExperienceDefaultsDraft: Codable, Equatable {
    /// Professional summary for resume headers and cover letter introductions
    var summary: String = ""
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

    /// Computed property for summary section enabled state (based on whether summary has content)
    var isSummaryEnabled: Bool {
        get { !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        set { if !newValue { summary = "" } }
    }
}
extension ExperienceDefaultsDraft {
    /// Initialize draft from model - now a direct copy since model stores Draft structs
    init(model: ExperienceDefaults) {
        summary = model.summary
        isWorkEnabled = model.isWorkEnabled
        isVolunteerEnabled = model.isVolunteerEnabled
        isEducationEnabled = model.isEducationEnabled
        isProjectsEnabled = model.isProjectsEnabled
        isSkillsEnabled = model.isSkillsEnabled
        isAwardsEnabled = model.isAwardsEnabled
        isCertificatesEnabled = model.isCertificatesEnabled
        isPublicationsEnabled = model.isPublicationsEnabled
        isLanguagesEnabled = model.isLanguagesEnabled
        isInterestsEnabled = model.isInterestsEnabled
        isReferencesEnabled = model.isReferencesEnabled
        isCustomEnabled = model.isCustomEnabled || !model.customFields.isEmpty
        customFields = model.customFields
        work = model.work
        volunteer = model.volunteer
        education = model.education
        projects = model.projects
        skills = model.skills
        awards = model.awards
        certificates = model.certificates
        publications = model.publications
        languages = model.languages
        interests = model.interests
        references = model.references
    }

    /// Apply draft changes to model - now a direct copy since model stores Draft structs
    func apply(to model: ExperienceDefaults) {
        model.summary = summary
        model.isWorkEnabled = isWorkEnabled
        model.isVolunteerEnabled = isVolunteerEnabled
        model.isEducationEnabled = isEducationEnabled
        model.isProjectsEnabled = isProjectsEnabled
        model.isSkillsEnabled = isSkillsEnabled
        model.isAwardsEnabled = isAwardsEnabled
        model.isCertificatesEnabled = isCertificatesEnabled
        model.isPublicationsEnabled = isPublicationsEnabled
        model.isLanguagesEnabled = isLanguagesEnabled
        model.isInterestsEnabled = isInterestsEnabled
        model.isReferencesEnabled = isReferencesEnabled
        model.isCustomEnabled = isCustomEnabled || !customFields.isEmpty
        model.customFields = customFields
        model.work = work
        model.volunteer = volunteer
        model.education = education
        model.projects = projects
        model.skills = skills
        model.awards = awards
        model.certificates = certificates
        model.publications = publications
        model.languages = languages
        model.interests = interests
        model.references = references
    }
}
// MARK: - Work
struct WorkExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var position: String = ""
    var location: String = ""
    var url: String = ""
    var startDate: String = ""
    var endDate: String = ""
    var summary: String = ""
    var highlights: [HighlightDraft] = []
}

struct HighlightDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
}
// MARK: - Volunteer
struct VolunteerExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var organization: String = ""
    var position: String = ""
    var url: String = ""
    var startDate: String = ""
    var endDate: String = ""
    var summary: String = ""
    var highlights: [VolunteerHighlightDraft] = []
}

struct VolunteerHighlightDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
}
// MARK: - Education
struct EducationExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var institution: String = ""
    var url: String = ""
    var area: String = ""
    var studyType: String = ""
    var startDate: String = ""
    var endDate: String = ""
    var score: String = ""
    var courses: [CourseDraft] = []
}

struct CourseDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
}
// MARK: - Projects
struct ProjectExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var description: String = ""
    var startDate: String = ""
    var endDate: String = ""
    var url: String = ""
    var organization: String = ""
    var type: String = ""
    var highlights: [ProjectHighlightDraft] = []
    var keywords: [KeywordDraft] = []
    var roles: [RoleDraft] = []
}

struct ProjectHighlightDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
}
struct KeywordDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var keyword: String = ""
}
struct RoleDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var role: String = ""
}
// MARK: - Skills
struct SkillExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var level: String = ""
    var keywords: [KeywordDraft] = []
}

// MARK: - Awards
struct AwardExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var date: String = ""
    var awarder: String = ""
    var summary: String = ""
}

// MARK: - Certificates
struct CertificateExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var date: String = ""
    var issuer: String = ""
    var url: String = ""
}

// MARK: - Publications
struct PublicationExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var publisher: String = ""
    var releaseDate: String = ""
    var url: String = ""
    var summary: String = ""
}

// MARK: - Languages
struct LanguageExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var language: String = ""
    var fluency: String = ""
}

// MARK: - Interests
struct InterestExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var keywords: [KeywordDraft] = []
}

// MARK: - References
struct ReferenceExperienceDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var reference: String = ""
    var url: String = ""
}
