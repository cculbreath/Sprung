import Foundation
import SwiftyJSON

enum ExperienceDefaultsDecoder {
    static func draft(from json: JSON) -> ExperienceDefaultsDraft {
        var draft = ExperienceDefaultsDraft()
        let dictionary = json.dictionaryValue

        if let workArray = dictionary["work"]?.array {
            draft.isWorkEnabled = workArray.isEmpty == false
            draft.work = workArray.map(decodeWork)
        }

        if let volunteerArray = dictionary["volunteer"]?.array {
            draft.isVolunteerEnabled = volunteerArray.isEmpty == false
            draft.volunteer = volunteerArray.map(decodeVolunteer)
        }

        if let educationArray = dictionary["education"]?.array {
            draft.isEducationEnabled = educationArray.isEmpty == false
            draft.education = educationArray.map(decodeEducation)
        }

        if let projectsArray = dictionary["projects"]?.array {
            draft.isProjectsEnabled = projectsArray.isEmpty == false
            draft.projects = projectsArray.map(decodeProject)
        }

        if let skillsArray = dictionary["skills"]?.array {
            draft.isSkillsEnabled = skillsArray.isEmpty == false
            draft.skills = skillsArray.map(decodeSkill)
        }

        if let awardsArray = dictionary["awards"]?.array {
            draft.isAwardsEnabled = awardsArray.isEmpty == false
            draft.awards = awardsArray.map(decodeAward)
        }

        if let certificatesArray = dictionary["certificates"]?.array {
            draft.isCertificatesEnabled = certificatesArray.isEmpty == false
            draft.certificates = certificatesArray.map(decodeCertificate)
        }

        if let publicationsArray = dictionary["publications"]?.array {
            draft.isPublicationsEnabled = publicationsArray.isEmpty == false
            draft.publications = publicationsArray.map(decodePublication)
        }

        if let languagesArray = dictionary["languages"]?.array {
            draft.isLanguagesEnabled = languagesArray.isEmpty == false
            draft.languages = languagesArray.map(decodeLanguage)
        }

        if let interestsArray = dictionary["interests"]?.array {
            draft.isInterestsEnabled = interestsArray.isEmpty == false
            draft.interests = interestsArray.map(decodeInterest)
        }

        if let referencesArray = dictionary["references"]?.array {
            draft.isReferencesEnabled = referencesArray.isEmpty == false
            draft.references = referencesArray.map(decodeReference)
        }

        return draft
    }

    private static func decodeWork(from json: JSON) -> WorkExperienceDraft {
        var draft = WorkExperienceDraft()
        draft.name = json["name"].stringValue.trimmed()
        draft.position = json["position"].stringValue.trimmed()
        draft.location = json["location"].stringValue.trimmed()
        draft.url = json["url"].stringValue.trimmed()
        draft.startDate = json["startDate"].stringValue.trimmed()
        draft.endDate = json["endDate"].stringValue.trimmed()
        draft.summary = json["summary"].stringValue
        draft.highlights = json["highlights"].arrayValue.map { highlightJSON in
            var highlight = HighlightDraft()
            highlight.text = highlightJSON.stringValue
            return highlight
        }
        return draft
    }

    private static func decodeVolunteer(from json: JSON) -> VolunteerExperienceDraft {
        var draft = VolunteerExperienceDraft()
        draft.organization = json["organization"].stringValue.trimmed()
        draft.position = json["position"].stringValue.trimmed()
        draft.url = json["url"].stringValue.trimmed()
        draft.startDate = json["startDate"].stringValue.trimmed()
        draft.endDate = json["endDate"].stringValue.trimmed()
        draft.summary = json["summary"].stringValue
        draft.highlights = json["highlights"].arrayValue.map { entry in
            var highlight = VolunteerHighlightDraft()
            highlight.text = entry.stringValue
            return highlight
        }
        return draft
    }

    private static func decodeEducation(from json: JSON) -> EducationExperienceDraft {
        var draft = EducationExperienceDraft()
        draft.institution = json["institution"].stringValue.trimmed()
        draft.url = json["url"].stringValue.trimmed()
        draft.area = json["area"].stringValue.trimmed()
        draft.studyType = json["studyType"].stringValue.trimmed()
        draft.startDate = json["startDate"].stringValue.trimmed()
        draft.endDate = json["endDate"].stringValue.trimmed()
        draft.score = json["score"].stringValue.trimmed()
        draft.courses = json["courses"].arrayValue.map {
            var course = CourseDraft()
            course.name = $0.stringValue
            return course
        }
        return draft
    }

    private static func decodeProject(from json: JSON) -> ProjectExperienceDraft {
        var draft = ProjectExperienceDraft()
        draft.name = json["name"].stringValue.trimmed()
        draft.description = json["description"].stringValue
        draft.startDate = json["startDate"].stringValue.trimmed()
        draft.endDate = json["endDate"].stringValue.trimmed()
        draft.url = json["url"].stringValue.trimmed()
        draft.entity = json["entity"].stringValue.trimmed()
        draft.type = json["type"].stringValue.trimmed()
        draft.highlights = json["highlights"].arrayValue.map {
            var highlight = ProjectHighlightDraft()
            highlight.text = $0.stringValue
            return highlight
        }
        draft.keywords = json["keywords"].arrayValue.map(makeKeyword)
        draft.roles = json["roles"].arrayValue.map(makeRole)
        return draft
    }

    private static func decodeSkill(from json: JSON) -> SkillExperienceDraft {
        var draft = SkillExperienceDraft()
        draft.name = json["name"].stringValue.trimmed()
        draft.level = json["level"].stringValue.trimmed()
        draft.keywords = json["keywords"].arrayValue.map(makeKeyword)
        return draft
    }

    private static func decodeAward(from json: JSON) -> AwardExperienceDraft {
        var draft = AwardExperienceDraft()
        draft.title = json["title"].stringValue.trimmed()
        draft.date = json["date"].stringValue.trimmed()
        draft.awarder = json["awarder"].stringValue.trimmed()
        draft.summary = json["summary"].stringValue
        return draft
    }

    private static func decodeCertificate(from json: JSON) -> CertificateExperienceDraft {
        var draft = CertificateExperienceDraft()
        draft.name = json["name"].stringValue.trimmed()
        draft.date = json["date"].stringValue.trimmed()
        draft.issuer = json["issuer"].stringValue.trimmed()
        draft.url = json["url"].stringValue.trimmed()
        return draft
    }

    private static func decodePublication(from json: JSON) -> PublicationExperienceDraft {
        var draft = PublicationExperienceDraft()
        draft.name = json["name"].stringValue.trimmed()
        draft.publisher = json["publisher"].stringValue.trimmed()
        draft.releaseDate = json["releaseDate"].stringValue.trimmed()
        draft.url = json["url"].stringValue.trimmed()
        draft.summary = json["summary"].stringValue
        return draft
    }

    private static func decodeLanguage(from json: JSON) -> LanguageExperienceDraft {
        var draft = LanguageExperienceDraft()
        draft.language = json["language"].stringValue.trimmed()
        draft.fluency = json["fluency"].stringValue.trimmed()
        return draft
    }

    private static func decodeInterest(from json: JSON) -> InterestExperienceDraft {
        var draft = InterestExperienceDraft()
        draft.name = json["name"].stringValue.trimmed()
        draft.keywords = json["keywords"].arrayValue.map(makeKeyword)
        return draft
    }

    private static func decodeReference(from json: JSON) -> ReferenceExperienceDraft {
        var draft = ReferenceExperienceDraft()
        draft.name = json["name"].stringValue.trimmed()
        draft.reference = json["reference"].stringValue
        draft.url = json["url"].stringValue.trimmed()
        return draft
    }

    private static func makeKeyword(from json: JSON) -> KeywordDraft {
        var keyword = KeywordDraft()
        if let dict = json.dictionary, let value = dict["keyword"]?.string {
            keyword.keyword = value.trimmed()
        } else {
            keyword.keyword = json.stringValue.trimmed()
        }
        return keyword
    }

    private static func makeRole(from json: JSON) -> RoleDraft {
        var role = RoleDraft()
        if let dict = json.dictionary, let value = dict["role"]?.string {
            role.role = value.trimmed()
        } else {
            role.role = json.stringValue.trimmed()
        }
        return role
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
