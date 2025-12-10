import Foundation
import SwiftData
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
struct ExperienceDefaultsDraft: Equatable {
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
}
extension ExperienceDefaultsDraft {
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
        isCustomEnabled = model.isCustomEnabled || model.customFields.isEmpty == false
        customFields = model.customFields.sorted { $0.index < $1.index }.map { field in
            let sortedValues = field.values.sorted { $0.index < $1.index }.map { $0.value }
            return CustomFieldValue(key: field.key, values: sortedValues)
        }
        work = model.workExperiences.map(WorkExperienceDraft.init)
        volunteer = model.volunteerExperiences.map(VolunteerExperienceDraft.init)
        education = model.educationRecords.map(EducationExperienceDraft.init)
        projects = model.projects.map(ProjectExperienceDraft.init)
        skills = model.skills.map(SkillExperienceDraft.init)
        awards = model.awards.map(AwardExperienceDraft.init)
        certificates = model.certificates.map(CertificateExperienceDraft.init)
        publications = model.publications.map(PublicationExperienceDraft.init)
        languages = model.languages.map(LanguageExperienceDraft.init)
        interests = model.interests.map(InterestExperienceDraft.init)
        references = model.references.map(ReferenceExperienceDraft.init)
    }
    func apply(to model: ExperienceDefaults, in context: ModelContext) {
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
        model.isCustomEnabled = isCustomEnabled || customFields.isEmpty == false
        // Rebuild custom fields relationship
        model.customFields.forEach { field in
            field.values.forEach { value in value.field = nil }
        }
        model.customFields.removeAll()
        for (fieldIndex, field) in customFields.enumerated() {
            let fieldModel = ExperienceCustomField(key: field.key, index: fieldIndex, values: [], defaults: model)
            let values = field.values.enumerated().map { idx, val in
                ExperienceCustomFieldValue(value: val, index: idx, field: fieldModel)
            }
            fieldModel.values = values
            model.customFields.append(fieldModel)
        }
        model.workExperiences = rebuildWorkExperiences(in: context, owner: model)
        model.volunteerExperiences = rebuildVolunteerExperiences(in: context, owner: model)
        model.educationRecords = rebuildEducation(in: context, owner: model)
        model.projects = rebuildProjects(in: context, owner: model)
        model.skills = rebuildSkills(in: context, owner: model)
        model.awards = rebuildAwards(in: context, owner: model)
        model.certificates = rebuildCertificates(in: context, owner: model)
        model.publications = rebuildPublications(in: context, owner: model)
        model.languages = rebuildLanguages(in: context, owner: model)
        model.interests = rebuildInterests(in: context, owner: model)
        model.references = rebuildReferences(in: context, owner: model)
    }
    private func rebuildWorkExperiences(in context: ModelContext, owner: ExperienceDefaults) -> [WorkExperienceDefault] {
        owner.workExperiences.forEach(context.delete)
        return work.map { draft in
            let highlights = draft.highlights.map { WorkHighlightDefault(text: $0.text) }
            let model = WorkExperienceDefault(
                id: draft.id,
                name: draft.name,
                position: draft.position,
                location: draft.location,
                url: draft.url,
                startDate: draft.startDate,
                endDate: draft.endDate,
                summary: draft.summary,
                highlights: highlights,
                defaults: owner
            )
            highlights.forEach { $0.workExperience = model }
            highlights.forEach(context.insert)
            context.insert(model)
            return model
        }
    }
    private func rebuildVolunteerExperiences(in context: ModelContext, owner: ExperienceDefaults) -> [VolunteerExperienceDefault] {
        owner.volunteerExperiences.forEach(context.delete)
        return volunteer.map { draft in
            let highlights = draft.highlights.map { VolunteerHighlightDefault(text: $0.text) }
            let model = VolunteerExperienceDefault(
                id: draft.id,
                organization: draft.organization,
                position: draft.position,
                url: draft.url,
                startDate: draft.startDate,
                endDate: draft.endDate,
                summary: draft.summary,
                highlights: highlights,
                defaults: owner
            )
            highlights.forEach { $0.volunteerExperience = model }
            highlights.forEach(context.insert)
            context.insert(model)
            return model
        }
    }
    private func rebuildEducation(in context: ModelContext, owner: ExperienceDefaults) -> [EducationExperienceDefault] {
        owner.educationRecords.forEach(context.delete)
        return education.map { draft in
            let courses = draft.courses.map { EducationCourseDefault(name: $0.name) }
            let model = EducationExperienceDefault(
                id: draft.id,
                institution: draft.institution,
                url: draft.url,
                area: draft.area,
                studyType: draft.studyType,
                startDate: draft.startDate,
                endDate: draft.endDate,
                score: draft.score,
                courses: courses,
                defaults: owner
            )
            courses.forEach { $0.education = model }
            courses.forEach(context.insert)
            context.insert(model)
            return model
        }
    }
    private func rebuildProjects(in context: ModelContext, owner: ExperienceDefaults) -> [ProjectExperienceDefault] {
        owner.projects.forEach(context.delete)
        return projects.map { draft in
            let highlights = draft.highlights.map { ProjectHighlightDefault(text: $0.text) }
            let keywords = draft.keywords.map { ProjectKeywordDefault(keyword: $0.keyword) }
            let roles = draft.roles.map { ProjectRoleDefault(role: $0.role) }
            let model = ProjectExperienceDefault(
                id: draft.id,
                name: draft.name,
                descriptionText: draft.description,
                startDate: draft.startDate,
                endDate: draft.endDate,
                url: draft.url,
                organization: draft.organization,
                type: draft.type,
                highlights: highlights,
                keywords: keywords,
                roles: roles,
                defaults: owner
            )
            highlights.forEach { $0.project = model }
            keywords.forEach { $0.project = model }
            roles.forEach { $0.project = model }
            highlights.forEach(context.insert)
            keywords.forEach(context.insert)
            roles.forEach(context.insert)
            context.insert(model)
            return model
        }
    }
    private func rebuildSkills(in context: ModelContext, owner: ExperienceDefaults) -> [SkillExperienceDefault] {
        owner.skills.forEach(context.delete)
        return skills.map { draft in
            let keywords = draft.keywords.map { SkillKeywordDefault(keyword: $0.keyword) }
            let model = SkillExperienceDefault(
                id: draft.id,
                name: draft.name,
                level: draft.level,
                keywords: keywords,
                defaults: owner
            )
            keywords.forEach { $0.skill = model }
            keywords.forEach(context.insert)
            context.insert(model)
            return model
        }
    }
    private func rebuildAwards(in context: ModelContext, owner: ExperienceDefaults) -> [AwardExperienceDefault] {
        owner.awards.forEach(context.delete)
        return awards.map { draft in
            let model = AwardExperienceDefault(
                id: draft.id,
                title: draft.title,
                date: draft.date,
                awarder: draft.awarder,
                summary: draft.summary,
                defaults: owner
            )
            context.insert(model)
            return model
        }
    }
    private func rebuildCertificates(in context: ModelContext, owner: ExperienceDefaults) -> [CertificateExperienceDefault] {
        owner.certificates.forEach(context.delete)
        return certificates.map { draft in
            let model = CertificateExperienceDefault(
                id: draft.id,
                name: draft.name,
                date: draft.date,
                issuer: draft.issuer,
                url: draft.url,
                defaults: owner
            )
            context.insert(model)
            return model
        }
    }
    private func rebuildPublications(in context: ModelContext, owner: ExperienceDefaults) -> [PublicationExperienceDefault] {
        owner.publications.forEach(context.delete)
        return publications.map { draft in
            let model = PublicationExperienceDefault(
                id: draft.id,
                name: draft.name,
                publisher: draft.publisher,
                releaseDate: draft.releaseDate,
                url: draft.url,
                summary: draft.summary,
                defaults: owner
            )
            context.insert(model)
            return model
        }
    }
    private func rebuildLanguages(in context: ModelContext, owner: ExperienceDefaults) -> [LanguageExperienceDefault] {
        owner.languages.forEach(context.delete)
        return languages.map { draft in
            let model = LanguageExperienceDefault(
                id: draft.id,
                language: draft.language,
                fluency: draft.fluency,
                defaults: owner
            )
            context.insert(model)
            return model
        }
    }
    private func rebuildInterests(in context: ModelContext, owner: ExperienceDefaults) -> [InterestExperienceDefault] {
        owner.interests.forEach(context.delete)
        return interests.map { draft in
            let keywords = draft.keywords.map { keywordDraft in
                InterestKeywordDefault(keyword: keywordDraft.keyword)
            }
            let model = InterestExperienceDefault(
                id: draft.id,
                name: draft.name,
                keywords: keywords,
                defaults: owner
            )
            keywords.forEach { $0.interest = model }
            keywords.forEach(context.insert)
            context.insert(model)
            return model
        }
    }
    private func rebuildReferences(in context: ModelContext, owner: ExperienceDefaults) -> [ReferenceExperienceDefault] {
        owner.references.forEach(context.delete)
        return references.map { draft in
            let model = ReferenceExperienceDefault(
                id: draft.id,
                name: draft.name,
                reference: draft.reference,
                url: draft.url,
                defaults: owner
            )
            context.insert(model)
            return model
        }
    }
}
// MARK: - Work
struct WorkExperienceDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var position: String = ""
    var location: String = ""
    var url: String = ""
    var startDate: String = ""
    var endDate: String = ""
    var summary: String = ""
    var highlights: [HighlightDraft] = []
    init() {}
    init(model: WorkExperienceDefault) {
        id = model.id
        name = model.name
        position = model.position
        location = model.location
        url = model.url
        startDate = model.startDate
        endDate = model.endDate
        summary = model.summary
        highlights = model.highlights.map(HighlightDraft.init)
    }
}
struct HighlightDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
    init() {}
    init(model: WorkHighlightDefault) {
        id = model.id
        text = model.text
    }
}
// MARK: - Volunteer
struct VolunteerExperienceDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var organization: String = ""
    var position: String = ""
    var url: String = ""
    var startDate: String = ""
    var endDate: String = ""
    var summary: String = ""
    var highlights: [VolunteerHighlightDraft] = []
    init() {}
    init(model: VolunteerExperienceDefault) {
        id = model.id
        organization = model.organization
        position = model.position
        url = model.url
        startDate = model.startDate
        endDate = model.endDate
        summary = model.summary
        highlights = model.highlights.map(VolunteerHighlightDraft.init)
    }
}
struct VolunteerHighlightDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
    init() {}
    init(model: VolunteerHighlightDefault) {
        id = model.id
        text = model.text
    }
}
// MARK: - Education
struct EducationExperienceDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var institution: String = ""
    var url: String = ""
    var area: String = ""
    var studyType: String = ""
    var startDate: String = ""
    var endDate: String = ""
    var score: String = ""
    var courses: [CourseDraft] = []
    init() {}
    init(model: EducationExperienceDefault) {
        id = model.id
        institution = model.institution
        url = model.url
        area = model.area
        studyType = model.studyType
        startDate = model.startDate
        endDate = model.endDate
        score = model.score
        courses = model.courses.map(CourseDraft.init)
    }
}
struct CourseDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    init() {}
    init(model: EducationCourseDefault) {
        id = model.id
        name = model.name
    }
}
// MARK: - Projects
struct ProjectExperienceDraft: Identifiable, Equatable {
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
    init() {}
    init(model: ProjectExperienceDefault) {
        id = model.id
        name = model.name
        description = model.descriptionText
        startDate = model.startDate
        endDate = model.endDate
        url = model.url
        organization = model.organization
        type = model.type
        highlights = model.highlights.map(ProjectHighlightDraft.init)
        keywords = model.keywords.map { KeywordDraft(id: $0.id, keyword: $0.keyword) }
        roles = model.roles.map { RoleDraft(id: $0.id, role: $0.role) }
    }
}
struct ProjectHighlightDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
    init() {}
    init(model: ProjectHighlightDefault) {
        id = model.id
        text = model.text
    }
}
struct KeywordDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var keyword: String = ""
}
struct RoleDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var role: String = ""
}
// MARK: - Skills
struct SkillExperienceDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var level: String = ""
    var keywords: [KeywordDraft] = []
    init() {}
    init(model: SkillExperienceDefault) {
        id = model.id
        name = model.name
        level = model.level
        keywords = model.keywords.map { KeywordDraft(id: $0.id, keyword: $0.keyword) }
    }
}
// MARK: - Awards
struct AwardExperienceDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var date: String = ""
    var awarder: String = ""
    var summary: String = ""
    init() {}
    init(model: AwardExperienceDefault) {
        id = model.id
        title = model.title
        date = model.date
        awarder = model.awarder
        summary = model.summary
    }
}
// MARK: - Certificates
struct CertificateExperienceDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var date: String = ""
    var issuer: String = ""
    var url: String = ""
    init() {}
    init(model: CertificateExperienceDefault) {
        id = model.id
        name = model.name
        date = model.date
        issuer = model.issuer
        url = model.url
    }
}
// MARK: - Publications
struct PublicationExperienceDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var publisher: String = ""
    var releaseDate: String = ""
    var url: String = ""
    var summary: String = ""
    init() {}
    init(model: PublicationExperienceDefault) {
        id = model.id
        name = model.name
        publisher = model.publisher
        releaseDate = model.releaseDate
        url = model.url
        summary = model.summary
    }
}
// MARK: - Languages
struct LanguageExperienceDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var language: String = ""
    var fluency: String = ""
    init() {}
    init(model: LanguageExperienceDefault) {
        id = model.id
        language = model.language
        fluency = model.fluency
    }
}
// MARK: - Interests
struct InterestExperienceDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var keywords: [KeywordDraft] = []
    init() {}
    init(model: InterestExperienceDefault) {
        id = model.id
        name = model.name
        keywords = model.keywords.map { KeywordDraft(id: $0.id, keyword: $0.keyword) }
    }
}
// MARK: - References
struct ReferenceExperienceDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var reference: String = ""
    var url: String = ""
    init() {}
    init(model: ReferenceExperienceDefault) {
        id = model.id
        name = model.name
        reference = model.reference
        url = model.url
    }
}
