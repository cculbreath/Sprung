import Foundation
import SwiftyJSON

struct AnyExperienceSectionCodec: Identifiable {
    let key: ExperienceSectionKey
    private let isEnabledClosure: (ExperienceDefaultsDraft) -> Bool
    private let encodeItemsClosure: (ExperienceDefaultsDraft) -> [[String: Any]]
    private let decodeClosure: (JSON?, inout ExperienceDefaultsDraft) -> Void

    var id: ExperienceSectionKey { key }

    init<Item>(
        key: ExperienceSectionKey,
        metadata: ExperienceSectionMetadata,
        itemsKeyPath: WritableKeyPath<ExperienceDefaultsDraft, [Item]>,
        encodeItem: @escaping (Item) -> [String: Any],
        decodeItem: @escaping (JSON) -> Item
    ) where Item: Identifiable & Equatable, Item.ID == UUID {
        self.key = key
        isEnabledClosure = { draft in
            draft[keyPath: metadata.isEnabledKeyPath]
        }

        encodeItemsClosure = { draft in
            guard draft[keyPath: metadata.isEnabledKeyPath] else { return [] }
            return draft[keyPath: itemsKeyPath]
                .map(encodeItem)
                .filter { $0.isEmpty == false }
        }

        decodeClosure = { sectionJSON, draft in
            guard let sectionJSON else {
                draft[keyPath: metadata.isEnabledKeyPath] = false
                draft[keyPath: itemsKeyPath] = []
                return
            }

            if sectionJSON.type != .array {
                Logger.warning("📄 Experience codec expected array for section \(key.rawValue); received \(sectionJSON.type.rawValue)")
                draft[keyPath: metadata.isEnabledKeyPath] = false
                draft[keyPath: itemsKeyPath] = []
                return
            }

            let array = sectionJSON.arrayValue
            draft[keyPath: metadata.isEnabledKeyPath] = array.isEmpty == false
            draft[keyPath: itemsKeyPath] = array.map(decodeItem)
        }
    }

    func isEnabled(in draft: ExperienceDefaultsDraft) -> Bool {
        isEnabledClosure(draft)
    }

    func encodeSection(from draft: ExperienceDefaultsDraft) -> [[String: Any]]? {
        let encoded = encodeItemsClosure(draft)
        return encoded.isEmpty ? nil : encoded
    }

    func decodeSection(from json: JSON?, into draft: inout ExperienceDefaultsDraft) {
        decodeClosure(json, &draft)
    }
}

enum ExperienceSectionCodecs {
    static let all: [AnyExperienceSectionCodec] = [
        work(),
        volunteer(),
        education(),
        projects(),
        skills(),
        awards(),
        certificates(),
        publications(),
        languages(),
        interests(),
        references()
    ]
}

private extension ExperienceSectionCodecs {
    static func work() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .work,
            metadata: ExperienceSectionKey.work.metadata,
            itemsKeyPath: \.work,
            encodeItem: encodeWork,
            decodeItem: decodeWork
        )
    }

    static func volunteer() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .volunteer,
            metadata: ExperienceSectionKey.volunteer.metadata,
            itemsKeyPath: \.volunteer,
            encodeItem: encodeVolunteer,
            decodeItem: decodeVolunteer
        )
    }

    static func education() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .education,
            metadata: ExperienceSectionKey.education.metadata,
            itemsKeyPath: \.education,
            encodeItem: encodeEducation,
            decodeItem: decodeEducation
        )
    }

    static func projects() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .projects,
            metadata: ExperienceSectionKey.projects.metadata,
            itemsKeyPath: \.projects,
            encodeItem: encodeProject,
            decodeItem: decodeProject
        )
    }

    static func skills() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .skills,
            metadata: ExperienceSectionKey.skills.metadata,
            itemsKeyPath: \.skills,
            encodeItem: encodeSkill,
            decodeItem: decodeSkill
        )
    }

    static func awards() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .awards,
            metadata: ExperienceSectionKey.awards.metadata,
            itemsKeyPath: \.awards,
            encodeItem: encodeAward,
            decodeItem: decodeAward
        )
    }

    static func certificates() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .certificates,
            metadata: ExperienceSectionKey.certificates.metadata,
            itemsKeyPath: \.certificates,
            encodeItem: encodeCertificate,
            decodeItem: decodeCertificate
        )
    }

    static func publications() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .publications,
            metadata: ExperienceSectionKey.publications.metadata,
            itemsKeyPath: \.publications,
            encodeItem: encodePublication,
            decodeItem: decodePublication
        )
    }

    static func languages() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .languages,
            metadata: ExperienceSectionKey.languages.metadata,
            itemsKeyPath: \.languages,
            encodeItem: encodeLanguage,
            decodeItem: decodeLanguage
        )
    }

    static func interests() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .interests,
            metadata: ExperienceSectionKey.interests.metadata,
            itemsKeyPath: \.interests,
            encodeItem: encodeInterest,
            decodeItem: decodeInterest
        )
    }

    static func references() -> AnyExperienceSectionCodec {
        AnyExperienceSectionCodec(
            key: .references,
            metadata: ExperienceSectionKey.references.metadata,
            itemsKeyPath: \.references,
            encodeItem: encodeReference,
            decodeItem: decodeReference
        )
    }
}

// MARK: - Encoding helpers
private func encodeWork(_ draft: WorkExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.name) { payload["name"] = value }
    if let value = sanitized(draft.position) { payload["position"] = value }
    if let value = sanitized(draft.location) { payload["location"] = value }
    if let value = sanitized(draft.url) { payload["url"] = value }
    if let value = sanitized(draft.startDate) { payload["startDate"] = value }
    if let value = sanitized(draft.endDate) { payload["endDate"] = value }
    if let value = sanitized(draft.summary) { payload["summary"] = value }
    let highlights = draft.highlights.compactMap { sanitized($0.text) }
    if highlights.isEmpty == false { payload["highlights"] = highlights }
    return payload
}

private func encodeVolunteer(_ draft: VolunteerExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.organization) { payload["organization"] = value }
    if let value = sanitized(draft.position) { payload["position"] = value }
    if let value = sanitized(draft.url) { payload["url"] = value }
    if let value = sanitized(draft.startDate) { payload["startDate"] = value }
    if let value = sanitized(draft.endDate) { payload["endDate"] = value }
    if let value = sanitized(draft.summary) { payload["summary"] = value }
    let highlights = draft.highlights.compactMap { sanitized($0.text) }
    if highlights.isEmpty == false { payload["highlights"] = highlights }
    return payload
}

private func encodeEducation(_ draft: EducationExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.institution) { payload["institution"] = value }
    if let value = sanitized(draft.url) { payload["url"] = value }
    if let value = sanitized(draft.studyType) { payload["studyType"] = value }
    if let value = sanitized(draft.area) { payload["area"] = value }
    if let value = sanitized(draft.startDate) { payload["startDate"] = value }
    if let value = sanitized(draft.endDate) { payload["endDate"] = value }
    if let value = sanitized(draft.score) { payload["score"] = value }
    let courses = draft.courses.compactMap { sanitized($0.name) }
    if courses.isEmpty == false { payload["courses"] = courses }
    return payload
}

private func encodeProject(_ draft: ProjectExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.name) { payload["name"] = value }
    if let value = sanitized(draft.description) { payload["description"] = value }
    if let value = sanitized(draft.startDate) { payload["startDate"] = value }
    if let value = sanitized(draft.endDate) { payload["endDate"] = value }
    if let value = sanitized(draft.url) { payload["url"] = value }
    if let value = sanitized(draft.organization) { payload["entity"] = value }
    if let value = sanitized(draft.type) { payload["type"] = value }
    let highlights = draft.highlights.compactMap { sanitized($0.text) }
    if highlights.isEmpty == false { payload["highlights"] = highlights }
    let keywords = draft.keywords.compactMap { sanitized($0.keyword) }
    if keywords.isEmpty == false { payload["keywords"] = keywords }
    let roles = draft.roles.compactMap { sanitized($0.role) }
    if roles.isEmpty == false { payload["roles"] = roles }
    return payload
}

private func encodeSkill(_ draft: SkillExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.name) { payload["name"] = value }
    if let value = sanitized(draft.level) { payload["level"] = value }
    let keywords = draft.keywords.compactMap { sanitized($0.keyword) }
    if keywords.isEmpty == false { payload["keywords"] = keywords }
    return payload
}

private func encodeAward(_ draft: AwardExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.title) { payload["title"] = value }
    if let value = sanitized(draft.date) { payload["date"] = value }
    if let value = sanitized(draft.awarder) { payload["awarder"] = value }
    if let value = sanitized(draft.summary) { payload["summary"] = value }
    return payload
}

private func encodeCertificate(_ draft: CertificateExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.name) { payload["name"] = value }
    if let value = sanitized(draft.date) { payload["date"] = value }
    if let value = sanitized(draft.issuer) { payload["issuer"] = value }
    if let value = sanitized(draft.url) { payload["url"] = value }
    return payload
}

private func encodePublication(_ draft: PublicationExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.name) { payload["name"] = value }
    if let value = sanitized(draft.publisher) { payload["publisher"] = value }
    if let value = sanitized(draft.releaseDate) { payload["releaseDate"] = value }
    if let value = sanitized(draft.url) { payload["url"] = value }
    if let value = sanitized(draft.summary) { payload["summary"] = value }
    return payload
}

private func encodeLanguage(_ draft: LanguageExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.language) { payload["language"] = value }
    if let value = sanitized(draft.fluency) { payload["fluency"] = value }
    return payload
}

private func encodeInterest(_ draft: InterestExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.name) { payload["name"] = value }
    let keywords = draft.keywords.compactMap { sanitized($0.keyword) }
    if keywords.isEmpty == false { payload["keywords"] = keywords }
    return payload
}

private func encodeReference(_ draft: ReferenceExperienceDraft) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(draft.name) { payload["name"] = value }
    if let value = sanitized(draft.reference) { payload["reference"] = value }
    if let value = sanitized(draft.url) { payload["url"] = value }
    return payload
}

// MARK: - Decoding helpers
private func decodeWork(_ json: JSON) -> WorkExperienceDraft {
    var draft = WorkExperienceDraft()
    draft.name = json["name"].stringValue.trimmed()
    draft.position = json["position"].stringValue.trimmed()
    draft.location = json["location"].stringValue.trimmed()
    draft.url = json["url"].stringValue.trimmed()
    draft.startDate = json["startDate"].stringValue.trimmed()
    draft.endDate = json["endDate"].stringValue.trimmed()
    draft.summary = json["summary"].stringValue
    draft.highlights = json["highlights"].arrayValue.map { entry in
        var highlight = HighlightDraft()
        highlight.text = entry.stringValue.trimmed()
        return highlight
    }
    return draft
}

private func decodeVolunteer(_ json: JSON) -> VolunteerExperienceDraft {
    var draft = VolunteerExperienceDraft()
    draft.organization = json["organization"].stringValue.trimmed()
    draft.position = json["position"].stringValue.trimmed()
    draft.url = json["url"].stringValue.trimmed()
    draft.startDate = json["startDate"].stringValue.trimmed()
    draft.endDate = json["endDate"].stringValue.trimmed()
    draft.summary = json["summary"].stringValue
    draft.highlights = json["highlights"].arrayValue.map { entry in
        var highlight = VolunteerHighlightDraft()
        highlight.text = entry.stringValue.trimmed()
        return highlight
    }
    return draft
}

private func decodeEducation(_ json: JSON) -> EducationExperienceDraft {
    var draft = EducationExperienceDraft()
    draft.institution = json["institution"].stringValue.trimmed()
    draft.url = json["url"].stringValue.trimmed()
    draft.area = json["area"].stringValue.trimmed()
    draft.studyType = json["studyType"].stringValue.trimmed()
    draft.startDate = json["startDate"].stringValue.trimmed()
    draft.endDate = json["endDate"].stringValue.trimmed()
    draft.score = json["score"].stringValue.trimmed()
    draft.courses = json["courses"].arrayValue.map { entry in
        var course = CourseDraft()
        course.name = entry.stringValue.trimmed()
        return course
    }
    return draft
}

private func decodeProject(_ json: JSON) -> ProjectExperienceDraft {
    var draft = ProjectExperienceDraft()
    draft.name = json["name"].stringValue.trimmed()
    draft.description = json["description"].stringValue
    draft.startDate = json["startDate"].stringValue.trimmed()
    draft.endDate = json["endDate"].stringValue.trimmed()
    draft.url = json["url"].stringValue.trimmed()
    draft.organization = json["entity"].stringValue.trimmed()
    draft.type = json["type"].stringValue.trimmed()
    draft.highlights = json["highlights"].arrayValue.map { entry in
        var highlight = ProjectHighlightDraft()
        highlight.text = entry.stringValue.trimmed()
        return highlight
    }
    draft.keywords = json["keywords"].arrayValue.map(makeKeyword)
    draft.roles = json["roles"].arrayValue.map(makeRole)
    return draft
}

private func decodeSkill(_ json: JSON) -> SkillExperienceDraft {
    var draft = SkillExperienceDraft()
    draft.name = json["name"].stringValue.trimmed()
    draft.level = json["level"].stringValue.trimmed()
    draft.keywords = json["keywords"].arrayValue.map(makeKeyword)
    return draft
}

private func decodeAward(_ json: JSON) -> AwardExperienceDraft {
    var draft = AwardExperienceDraft()
    draft.title = json["title"].stringValue.trimmed()
    draft.date = json["date"].stringValue.trimmed()
    draft.awarder = json["awarder"].stringValue.trimmed()
    draft.summary = json["summary"].stringValue
    return draft
}

private func decodeCertificate(_ json: JSON) -> CertificateExperienceDraft {
    var draft = CertificateExperienceDraft()
    draft.name = json["name"].stringValue.trimmed()
    draft.date = json["date"].stringValue.trimmed()
    draft.issuer = json["issuer"].stringValue.trimmed()
    draft.url = json["url"].stringValue.trimmed()
    return draft
}

private func decodePublication(_ json: JSON) -> PublicationExperienceDraft {
    var draft = PublicationExperienceDraft()
    draft.name = json["name"].stringValue.trimmed()
    draft.publisher = json["publisher"].stringValue.trimmed()
    draft.releaseDate = json["releaseDate"].stringValue.trimmed()
    draft.url = json["url"].stringValue.trimmed()
    draft.summary = json["summary"].stringValue
    return draft
}

private func decodeLanguage(_ json: JSON) -> LanguageExperienceDraft {
    var draft = LanguageExperienceDraft()
    draft.language = json["language"].stringValue.trimmed()
    draft.fluency = json["fluency"].stringValue.trimmed()
    return draft
}

private func decodeInterest(_ json: JSON) -> InterestExperienceDraft {
    var draft = InterestExperienceDraft()
    draft.name = json["name"].stringValue.trimmed()
    draft.keywords = json["keywords"].arrayValue.map(makeKeyword)
    return draft
}

private func decodeReference(_ json: JSON) -> ReferenceExperienceDraft {
    var draft = ReferenceExperienceDraft()
    draft.name = json["name"].stringValue.trimmed()
    draft.reference = json["reference"].stringValue.trimmed()
    draft.url = json["url"].stringValue.trimmed()
    return draft
}

private func makeKeyword(_ json: JSON) -> KeywordDraft {
    var keyword = KeywordDraft()
    keyword.keyword = json.stringValue.trimmed()
    return keyword
}

private func makeRole(_ json: JSON) -> RoleDraft {
    var role = RoleDraft()
    role.role = json.stringValue.trimmed()
    return role
}

private func sanitized(_ raw: String) -> String? {
    let trimmed = raw.trimmed()
    return trimmed.isEmpty ? nil : trimmed
}
