import Foundation
import SwiftData

@Model
final class ExperienceDefaults {
    @Attribute(.unique) var id: UUID

    var isWorkEnabled: Bool
    var isVolunteerEnabled: Bool
    var isEducationEnabled: Bool
    var isProjectsEnabled: Bool
    var isSkillsEnabled: Bool
    var isAwardsEnabled: Bool
    var isCertificatesEnabled: Bool
    var isPublicationsEnabled: Bool
    var isLanguagesEnabled: Bool
    var isInterestsEnabled: Bool
    var isReferencesEnabled: Bool

    @Relationship(deleteRule: .cascade, inverse: \WorkExperienceDefault.defaults)
    var workExperiences: [WorkExperienceDefault]

    @Relationship(deleteRule: .cascade, inverse: \VolunteerExperienceDefault.defaults)
    var volunteerExperiences: [VolunteerExperienceDefault]

    @Relationship(deleteRule: .cascade, inverse: \EducationExperienceDefault.defaults)
    var educationRecords: [EducationExperienceDefault]

    @Relationship(deleteRule: .cascade, inverse: \ProjectExperienceDefault.defaults)
    var projects: [ProjectExperienceDefault]

    @Relationship(deleteRule: .cascade, inverse: \SkillExperienceDefault.defaults)
    var skills: [SkillExperienceDefault]

    @Relationship(deleteRule: .cascade, inverse: \AwardExperienceDefault.defaults)
    var awards: [AwardExperienceDefault]

    @Relationship(deleteRule: .cascade, inverse: \CertificateExperienceDefault.defaults)
    var certificates: [CertificateExperienceDefault]

    @Relationship(deleteRule: .cascade, inverse: \PublicationExperienceDefault.defaults)
    var publications: [PublicationExperienceDefault]

    @Relationship(deleteRule: .cascade, inverse: \LanguageExperienceDefault.defaults)
    var languages: [LanguageExperienceDefault]

    @Relationship(deleteRule: .cascade, inverse: \InterestExperienceDefault.defaults)
    var interests: [InterestExperienceDefault]

    @Relationship(deleteRule: .cascade, inverse: \ReferenceExperienceDefault.defaults)
    var references: [ReferenceExperienceDefault]

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
        workExperiences: [WorkExperienceDefault] = [],
        volunteerExperiences: [VolunteerExperienceDefault] = [],
        educationRecords: [EducationExperienceDefault] = [],
        projects: [ProjectExperienceDefault] = [],
        skills: [SkillExperienceDefault] = [],
        awards: [AwardExperienceDefault] = [],
        certificates: [CertificateExperienceDefault] = [],
        publications: [PublicationExperienceDefault] = [],
        languages: [LanguageExperienceDefault] = [],
        interests: [InterestExperienceDefault] = [],
        references: [ReferenceExperienceDefault] = []
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
        self.workExperiences = workExperiences
        self.volunteerExperiences = volunteerExperiences
        self.educationRecords = educationRecords
        self.projects = projects
        self.skills = skills
        self.awards = awards
        self.certificates = certificates
        self.publications = publications
        self.languages = languages
        self.interests = interests
        self.references = references

        establishInverseRelationships()
    }

    private func establishInverseRelationships() {
        workExperiences.forEach { $0.defaults = self }
        volunteerExperiences.forEach { $0.defaults = self }
        educationRecords.forEach { $0.defaults = self }
        projects.forEach { $0.defaults = self }
        skills.forEach { $0.defaults = self }
        awards.forEach { $0.defaults = self }
        certificates.forEach { $0.defaults = self }
        publications.forEach { $0.defaults = self }
        languages.forEach { $0.defaults = self }
        interests.forEach { $0.defaults = self }
        references.forEach { $0.defaults = self }
    }
}

// MARK: - Work Experience
@Model
final class WorkExperienceDefault {
    @Attribute(.unique) var id: UUID
    var name: String
    var position: String
    var location: String
    var url: String
    var startDate: String
    var endDate: String
    var summary: String

    @Relationship(deleteRule: .cascade, inverse: \WorkHighlightDefault.workExperience)
    var highlights: [WorkHighlightDefault]

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        name: String = "",
        position: String = "",
        location: String = "",
        url: String = "",
        startDate: String = "",
        endDate: String = "",
        summary: String = "",
        highlights: [WorkHighlightDefault] = [],
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.location = location
        self.url = url
        self.startDate = startDate
        self.endDate = endDate
        self.summary = summary
        self.highlights = highlights
        self.defaults = defaults

        self.highlights.forEach { $0.workExperience = self }
    }
}

@Model
final class WorkHighlightDefault {
    @Attribute(.unique) var id: UUID
    var text: String

    var workExperience: WorkExperienceDefault?

    init(
        id: UUID = UUID(),
        text: String = "",
        workExperience: WorkExperienceDefault? = nil
    ) {
        self.id = id
        self.text = text
        self.workExperience = workExperience
    }
}

// MARK: - Volunteer Experience
@Model
final class VolunteerExperienceDefault {
    @Attribute(.unique) var id: UUID
    var organization: String
    var position: String
    var url: String
    var startDate: String
    var endDate: String
    var summary: String

    @Relationship(deleteRule: .cascade, inverse: \VolunteerHighlightDefault.volunteerExperience)
    var highlights: [VolunteerHighlightDefault]

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        organization: String = "",
        position: String = "",
        url: String = "",
        startDate: String = "",
        endDate: String = "",
        summary: String = "",
        highlights: [VolunteerHighlightDefault] = [],
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.organization = organization
        self.position = position
        self.url = url
        self.startDate = startDate
        self.endDate = endDate
        self.summary = summary
        self.highlights = highlights
        self.defaults = defaults

        self.highlights.forEach { $0.volunteerExperience = self }
    }
}

@Model
final class VolunteerHighlightDefault {
    @Attribute(.unique) var id: UUID
    var text: String

    var volunteerExperience: VolunteerExperienceDefault?

    init(
        id: UUID = UUID(),
        text: String = "",
        volunteerExperience: VolunteerExperienceDefault? = nil
    ) {
        self.id = id
        self.text = text
        self.volunteerExperience = volunteerExperience
    }
}

// MARK: - Education
@Model
final class EducationExperienceDefault {
    @Attribute(.unique) var id: UUID
    var institution: String
    var url: String
    var area: String
    var studyType: String
    var startDate: String
    var endDate: String
    var score: String

    @Relationship(deleteRule: .cascade, inverse: \EducationCourseDefault.education)
    var courses: [EducationCourseDefault]

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        institution: String = "",
        url: String = "",
        area: String = "",
        studyType: String = "",
        startDate: String = "",
        endDate: String = "",
        score: String = "",
        courses: [EducationCourseDefault] = [],
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.institution = institution
        self.url = url
        self.area = area
        self.studyType = studyType
        self.startDate = startDate
        self.endDate = endDate
        self.score = score
        self.courses = courses
        self.defaults = defaults

        self.courses.forEach { $0.education = self }
    }
}

@Model
final class EducationCourseDefault {
    @Attribute(.unique) var id: UUID
    var name: String

    var education: EducationExperienceDefault?

    init(
        id: UUID = UUID(),
        name: String = "",
        education: EducationExperienceDefault? = nil
    ) {
        self.id = id
        self.name = name
        self.education = education
    }
}

// MARK: - Projects
@Model
final class ProjectExperienceDefault {
    @Attribute(.unique) var id: UUID
    var name: String
    var descriptionText: String
    var startDate: String
    var endDate: String
    var url: String
    @Attribute(originalName: "entity")
    var organization: String
    var type: String

    @Relationship(deleteRule: .cascade, inverse: \ProjectHighlightDefault.project)
    var highlights: [ProjectHighlightDefault]

    @Relationship(deleteRule: .cascade, inverse: \ProjectKeywordDefault.project)
    var keywords: [ProjectKeywordDefault]

    @Relationship(deleteRule: .cascade, inverse: \ProjectRoleDefault.project)
    var roles: [ProjectRoleDefault]

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        name: String = "",
        descriptionText: String = "",
        startDate: String = "",
        endDate: String = "",
        url: String = "",
        organization: String = "",
        type: String = "",
        highlights: [ProjectHighlightDefault] = [],
        keywords: [ProjectKeywordDefault] = [],
        roles: [ProjectRoleDefault] = [],
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.startDate = startDate
        self.endDate = endDate
        self.url = url
        self.organization = organization
        self.type = type
        self.highlights = highlights
        self.keywords = keywords
        self.roles = roles
        self.defaults = defaults

        self.highlights.forEach { $0.project = self }
        self.keywords.forEach { $0.project = self }
        self.roles.forEach { $0.project = self }
    }
}

@Model
final class ProjectHighlightDefault {
    @Attribute(.unique) var id: UUID
    var text: String

    var project: ProjectExperienceDefault?

    init(
        id: UUID = UUID(),
        text: String = "",
        project: ProjectExperienceDefault? = nil
    ) {
        self.id = id
        self.text = text
        self.project = project
    }
}

@Model
final class ProjectKeywordDefault {
    @Attribute(.unique) var id: UUID
    var keyword: String

    var project: ProjectExperienceDefault?

    init(
        id: UUID = UUID(),
        keyword: String = "",
        project: ProjectExperienceDefault? = nil
    ) {
        self.id = id
        self.keyword = keyword
        self.project = project
    }
}

@Model
final class ProjectRoleDefault {
    @Attribute(.unique) var id: UUID
    var role: String

    var project: ProjectExperienceDefault?

    init(
        id: UUID = UUID(),
        role: String = "",
        project: ProjectExperienceDefault? = nil
    ) {
        self.id = id
        self.role = role
        self.project = project
    }
}

// MARK: - Skills
@Model
final class SkillExperienceDefault {
    @Attribute(.unique) var id: UUID
    var name: String
    var level: String

    @Relationship(deleteRule: .cascade, inverse: \SkillKeywordDefault.skill)
    var keywords: [SkillKeywordDefault]

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        name: String = "",
        level: String = "",
        keywords: [SkillKeywordDefault] = [],
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.name = name
        self.level = level
        self.keywords = keywords
        self.defaults = defaults

        self.keywords.forEach { $0.skill = self }
    }
}

@Model
final class SkillKeywordDefault {
    @Attribute(.unique) var id: UUID
    var keyword: String

    var skill: SkillExperienceDefault?

    init(
        id: UUID = UUID(),
        keyword: String = "",
        skill: SkillExperienceDefault? = nil
    ) {
        self.id = id
        self.keyword = keyword
        self.skill = skill
    }
}

// MARK: - Awards
@Model
final class AwardExperienceDefault {
    @Attribute(.unique) var id: UUID
    var title: String
    var date: String
    var awarder: String
    var summary: String

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        title: String = "",
        date: String = "",
        awarder: String = "",
        summary: String = "",
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.awarder = awarder
        self.summary = summary
        self.defaults = defaults
    }
}

// MARK: - Certificates
@Model
final class CertificateExperienceDefault {
    @Attribute(.unique) var id: UUID
    var name: String
    var date: String
    var issuer: String
    var url: String

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        name: String = "",
        date: String = "",
        issuer: String = "",
        url: String = "",
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.issuer = issuer
        self.url = url
        self.defaults = defaults
    }
}

// MARK: - Publications
@Model
final class PublicationExperienceDefault {
    @Attribute(.unique) var id: UUID
    var name: String
    var publisher: String
    var releaseDate: String
    var url: String
    var summary: String

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        name: String = "",
        publisher: String = "",
        releaseDate: String = "",
        url: String = "",
        summary: String = "",
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.name = name
        self.publisher = publisher
        self.releaseDate = releaseDate
        self.url = url
        self.summary = summary
        self.defaults = defaults
    }
}

// MARK: - Languages
@Model
final class LanguageExperienceDefault {
    @Attribute(.unique) var id: UUID
    var language: String
    var fluency: String

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        language: String = "",
        fluency: String = "",
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.language = language
        self.fluency = fluency
        self.defaults = defaults
    }
}

// MARK: - Interests
@Model
final class InterestExperienceDefault {
    @Attribute(.unique) var id: UUID
    var name: String

    @Relationship(deleteRule: .cascade, inverse: \InterestKeywordDefault.interest)
    var keywords: [InterestKeywordDefault]

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        name: String = "",
        keywords: [InterestKeywordDefault] = [],
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.defaults = defaults

        self.keywords.forEach { $0.interest = self }
    }
}

@Model
final class InterestKeywordDefault {
    @Attribute(.unique) var id: UUID
    var keyword: String

    var interest: InterestExperienceDefault?

    init(
        id: UUID = UUID(),
        keyword: String = "",
        interest: InterestExperienceDefault? = nil
    ) {
        self.id = id
        self.keyword = keyword
        self.interest = interest
    }
}

// MARK: - References
@Model
final class ReferenceExperienceDefault {
    @Attribute(.unique) var id: UUID
    var name: String
    var reference: String
    var url: String

    var defaults: ExperienceDefaults?

    init(
        id: UUID = UUID(),
        name: String = "",
        reference: String = "",
        url: String = "",
        defaults: ExperienceDefaults? = nil
    ) {
        self.id = id
        self.name = name
        self.reference = reference
        self.url = url
        self.defaults = defaults
    }
}
