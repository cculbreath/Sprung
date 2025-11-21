import Foundation
import SwiftyJSON
struct KnowledgeCardDraft: Identifiable, Equatable {
    struct Achievement: Identifiable, Equatable {
        var id: UUID
        var claim: String
        var evidence: EvidenceItem
        init(
            id: UUID = UUID(),
            claim: String,
            evidence: EvidenceItem
        ) {
            self.id = id
            self.claim = claim
            self.evidence = evidence
        }
        init(json: JSON) {
            id = UUID(uuidString: json["id"].stringValue) ?? UUID()
            claim = json["claim"].stringValue
            evidence = EvidenceItem(json: json["evidence"])
        }
        func toJSON() -> JSON {
            var json = JSON()
            json["id"].string = id.uuidString
            json["claim"].string = claim
            json["evidence"] = evidence.toJSON()
            return json
        }
    }
    var id: UUID
    var title: String
    var summary: String
    var source: String?
    var achievements: [Achievement]
    var metrics: [String]
    var skills: [String]
    init(
        id: UUID = UUID(),
        title: String = "",
        summary: String = "",
        source: String? = nil,
        achievements: [Achievement] = [],
        metrics: [String] = [],
        skills: [String] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.source = source
        self.achievements = achievements
        self.metrics = metrics
        self.skills = skills
    }
    init(json: JSON) {
        id = UUID(uuidString: json["id"].stringValue) ?? UUID()
        title = json["title"].stringValue
        summary = json["summary"].stringValue
        source = json["source"].string
        achievements = json["achievements"].arrayValue.map { Achievement(json: $0) }
        metrics = json["metrics"].arrayValue.compactMap { $0.string }
        skills = json["skills"].arrayValue.compactMap { $0.string }
    }
    func toJSON() -> JSON {
        var json = JSON()
        json["id"].string = id.uuidString
        json["title"].string = title
        json["summary"].string = summary
        if let source {
            json["source"].string = source
        }
        json["achievements"] = JSON(achievements.map { $0.toJSON() })
        json["metrics"] = JSON(metrics)
        json["skills"] = JSON(skills)
        return json
    }
    func removing(claims identifiers: Set<UUID>) -> KnowledgeCardDraft {
        guard !identifiers.isEmpty else { return self }
        var copy = self
        copy.achievements.removeAll { identifiers.contains($0.id) }
        return copy
    }
}
struct EvidenceItem: Equatable {
    var quote: String
    var source: String
    var locator: String?
    var artifactSHA: String?
    init(
        quote: String,
        source: String,
        locator: String? = nil,
        artifactSHA: String? = nil
    ) {
        self.quote = quote
        self.source = source
        self.locator = locator
        self.artifactSHA = artifactSHA
    }
    init(json: JSON) {
        quote = json["quote"].stringValue
        source = json["source"].stringValue
        locator = json["locator"].string
        artifactSHA = json["artifact_sha"].string
    }
    func toJSON() -> JSON {
        var json = JSON()
        json["quote"].string = quote
        json["source"].string = source
        if let locator {
            json["locator"].string = locator
        }
        if let artifactSHA {
            json["artifact_sha"].string = artifactSHA
        }
        return json
    }
}
struct ArtifactRecord: Identifiable, Equatable {
    var id: String
    var filename: String
    var contentType: String?
    var sizeInBytes: Int
    var sha256: String?
    var extractedContent: String
    var metadata: JSON
    init(
        id: String = UUID().uuidString,
        filename: String,
        contentType: String? = nil,
        sizeInBytes: Int = 0,
        sha256: String? = nil,
        extractedContent: String = "",
        metadata: JSON = JSON()
    ) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.sizeInBytes = sizeInBytes
        self.sha256 = sha256
        self.extractedContent = extractedContent
        self.metadata = metadata
    }
    init(json: JSON) {
        let identifier = json["id"].string
        let sha = json["sha256"].string
        sha256 = sha
        if let identifier, !identifier.isEmpty {
            id = identifier
        } else if let sha, !sha.isEmpty {
            id = sha
        } else {
            id = UUID().uuidString
        }
        filename = json["filename"].stringValue
        contentType = json["content_type"].string
        sizeInBytes = json["size_bytes"].intValue
        extractedContent = json["extracted_content"].stringValue
        metadata = json["metadata"]
    }
    func toJSON() -> JSON {
        var json = JSON()
        json["id"].string = id
        json["filename"].string = filename
        if let contentType {
            json["content_type"].string = contentType
        }
        json["size_bytes"].int = sizeInBytes
        if let sha256 {
            json["sha256"].string = sha256
        }
        json["extracted_content"].string = extractedContent
        json["metadata"] = metadata
        return json
    }
}
struct ExperienceContext {
    var timelineEntry: JSON
    var artifacts: [ArtifactRecord]
    var transcript: String
    init(timelineEntry: JSON, artifacts: [ArtifactRecord] = [], transcript: String = "") {
        self.timelineEntry = timelineEntry
        self.artifacts = artifacts
        self.transcript = transcript
    }
}
