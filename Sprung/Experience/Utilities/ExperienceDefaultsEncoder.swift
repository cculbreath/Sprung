import Foundation

enum ExperienceDefaultsEncoder {
    static func makeSeedDictionary(from defaults: ExperienceDefaults) -> [String: Any] {
        var result: [String: Any] = [:]

        if defaults.isWorkEnabled {
            let items = defaults.workExperiences
                .map(encodeWork)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["work"] = items
            }
        }

        if defaults.isVolunteerEnabled {
            let items = defaults.volunteerExperiences
                .map(encodeVolunteer)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["volunteer"] = items
            }
        }

        if defaults.isEducationEnabled {
            let items = defaults.educationRecords
                .map(encodeEducation)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["education"] = items
            }
        }

        if defaults.isProjectsEnabled {
            let items = defaults.projects
                .map(encodeProject)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["projects"] = items
            }
        }

        if defaults.isSkillsEnabled {
            let items = defaults.skills
                .map(encodeSkill)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["skills"] = items
            }
        }

        if defaults.isAwardsEnabled {
            let items = defaults.awards
                .map(encodeAward)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["awards"] = items
            }
        }

        if defaults.isCertificatesEnabled {
            let items = defaults.certificates
                .map(encodeCertificate)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["certificates"] = items
            }
        }

        if defaults.isPublicationsEnabled {
            let items = defaults.publications
                .map(encodePublication)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["publications"] = items
            }
        }

        if defaults.isLanguagesEnabled {
            let items = defaults.languages
                .map(encodeLanguage)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["languages"] = items
            }
        }

        if defaults.isInterestsEnabled {
            let items = defaults.interests
                .map(encodeInterest)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["interests"] = items
            }
        }

        if defaults.isReferencesEnabled {
            let items = defaults.references
                .map(encodeReference)
                .filter { $0.isEmpty == false }
            if items.isEmpty == false {
                result["references"] = items
            }
        }

        return result
    }

    private static func encodeWork(_ model: WorkExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.name) { payload["name"] = value }
        if let value = sanitized(model.position) { payload["position"] = value }
        if let value = sanitized(model.location) { payload["location"] = value }
        if let value = sanitized(model.url) { payload["url"] = value }
        if let value = sanitized(model.startDate) { payload["startDate"] = value }
        if let value = sanitized(model.endDate) { payload["endDate"] = value }
        if let value = sanitized(model.summary) { payload["summary"] = value }
        let highlights = model.highlights.compactMap { sanitized($0.text) }
        if highlights.isEmpty == false { payload["highlights"] = highlights }
        return payload
    }

    private static func encodeVolunteer(_ model: VolunteerExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.organization) { payload["organization"] = value }
        if let value = sanitized(model.position) { payload["position"] = value }
        if let value = sanitized(model.url) { payload["url"] = value }
        if let value = sanitized(model.startDate) { payload["startDate"] = value }
        if let value = sanitized(model.endDate) { payload["endDate"] = value }
        if let value = sanitized(model.summary) { payload["summary"] = value }
        let highlights = model.highlights.compactMap { sanitized($0.text) }
        if highlights.isEmpty == false { payload["highlights"] = highlights }
        return payload
    }

    private static func encodeEducation(_ model: EducationExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.institution) { payload["institution"] = value }
        if let value = sanitized(model.url) { payload["url"] = value }
        if let value = sanitized(model.studyType) { payload["studyType"] = value }
        if let value = sanitized(model.area) { payload["area"] = value }
        if let value = sanitized(model.startDate) { payload["startDate"] = value }
        if let value = sanitized(model.endDate) { payload["endDate"] = value }
        if let value = sanitized(model.score) { payload["score"] = value }
        let courses = model.courses.compactMap { sanitized($0.name) }
        if courses.isEmpty == false { payload["courses"] = courses }
        return payload
    }

    private static func encodeProject(_ model: ProjectExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.name) { payload["name"] = value }
        if let value = sanitized(model.descriptionText) { payload["description"] = value }
        if let value = sanitized(model.startDate) { payload["startDate"] = value }
        if let value = sanitized(model.endDate) { payload["endDate"] = value }
        if let value = sanitized(model.url) { payload["url"] = value }
        if let value = sanitized(model.organization) { payload["entity"] = value }
        if let value = sanitized(model.type) { payload["type"] = value }
        let highlights = model.highlights.compactMap { sanitized($0.text) }
        if highlights.isEmpty == false { payload["highlights"] = highlights }
        let keywords = model.keywords.compactMap { sanitized($0.keyword) }
        if keywords.isEmpty == false { payload["keywords"] = keywords }
        let roles = model.roles.compactMap { sanitized($0.role) }
        if roles.isEmpty == false { payload["roles"] = roles }
        return payload
    }

    private static func encodeSkill(_ model: SkillExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.name) { payload["name"] = value }
        if let value = sanitized(model.level) { payload["level"] = value }
        let keywords = model.keywords.compactMap { sanitized($0.keyword) }
        if keywords.isEmpty == false { payload["keywords"] = keywords }
        return payload
    }

    private static func encodeAward(_ model: AwardExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.title) { payload["title"] = value }
        if let value = sanitized(model.date) { payload["date"] = value }
        if let value = sanitized(model.awarder) { payload["awarder"] = value }
        if let value = sanitized(model.summary) { payload["summary"] = value }
        return payload
    }

    private static func encodeCertificate(_ model: CertificateExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.name) { payload["name"] = value }
        if let value = sanitized(model.date) { payload["date"] = value }
        if let value = sanitized(model.issuer) { payload["issuer"] = value }
        if let value = sanitized(model.url) { payload["url"] = value }
        return payload
    }

    private static func encodePublication(_ model: PublicationExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.name) { payload["name"] = value }
        if let value = sanitized(model.publisher) { payload["publisher"] = value }
        if let value = sanitized(model.releaseDate) { payload["releaseDate"] = value }
        if let value = sanitized(model.url) { payload["url"] = value }
        if let value = sanitized(model.summary) { payload["summary"] = value }
        return payload
    }

    private static func encodeLanguage(_ model: LanguageExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.language) { payload["language"] = value }
        if let value = sanitized(model.fluency) { payload["fluency"] = value }
        return payload
    }

    private static func encodeInterest(_ model: InterestExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.name) { payload["name"] = value }
        let keywords = model.keywords.compactMap { sanitized($0.keyword) }
        if keywords.isEmpty == false { payload["keywords"] = keywords }
        return payload
    }

    private static func encodeReference(_ model: ReferenceExperienceDefault) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = sanitized(model.name) { payload["name"] = value }
        if let value = sanitized(model.reference) { payload["reference"] = value }
        if let value = sanitized(model.url) { payload["url"] = value }
        return payload
    }

    private static func sanitized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
