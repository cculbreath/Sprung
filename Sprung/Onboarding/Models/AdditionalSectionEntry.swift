//
//  AdditionalSectionEntry.swift
//  Sprung
//
//  Model for non-chronological resume sections during onboarding.
//  Handles awards, languages, and references with type-specific fields.
//

import Foundation
import SwiftyJSON

/// Type of additional section entry for non-chronological resume sections
enum AdditionalSectionType: String, Codable, CaseIterable {
    case award
    case language
    case reference

    var displayName: String {
        switch self {
        case .award: return "Award"
        case .language: return "Language"
        case .reference: return "Reference"
        }
    }

    var pluralName: String {
        switch self {
        case .award: return "Awards"
        case .language: return "Languages"
        case .reference: return "References"
        }
    }

    var icon: String {
        switch self {
        case .award: return "trophy"
        case .language: return "globe"
        case .reference: return "person.text.rectangle"
        }
    }
}

/// An entry representing a non-chronological resume section during onboarding
struct AdditionalSectionEntry: Identifiable, Equatable, Codable {
    var id: String
    var sectionType: AdditionalSectionType

    // MARK: - Award Fields
    var title: String?
    var date: String?
    var awarder: String?
    var awardSummary: String?

    // MARK: - Language Fields
    var language: String?
    var fluency: String?

    // MARK: - Reference Fields
    var referenceName: String?
    var referenceText: String?
    var referenceUrl: String?

    init(
        id: String = UUID().uuidString,
        sectionType: AdditionalSectionType,
        title: String? = nil,
        date: String? = nil,
        awarder: String? = nil,
        awardSummary: String? = nil,
        language: String? = nil,
        fluency: String? = nil,
        referenceName: String? = nil,
        referenceText: String? = nil,
        referenceUrl: String? = nil
    ) {
        self.id = id
        self.sectionType = sectionType
        self.title = title
        self.date = date
        self.awarder = awarder
        self.awardSummary = awardSummary
        self.language = language
        self.fluency = fluency
        self.referenceName = referenceName
        self.referenceText = referenceText
        self.referenceUrl = referenceUrl
    }

    /// Initialize from JSON with type-specific field extraction
    init?(json: JSON, sectionType: AdditionalSectionType) {
        guard let idString = json["id"].string, !idString.isEmpty else {
            return nil
        }
        self.id = idString
        self.sectionType = sectionType

        switch sectionType {
        case .award:
            self.title = json["title"].string
            self.date = json["date"].string
            self.awarder = json["awarder"].string
            self.awardSummary = json["summary"].string
        case .language:
            self.language = json["language"].string
            self.fluency = json["fluency"].string
        case .reference:
            self.referenceName = json["name"].string
            self.referenceText = json["reference"].string
            self.referenceUrl = json["url"].string
        }
    }

    /// Initialize with fields JSON for tool-based creation
    init(id: String = UUID().uuidString, sectionType: AdditionalSectionType, fields: JSON) {
        self.id = id
        self.sectionType = sectionType

        switch sectionType {
        case .award:
            self.title = fields["title"].string
            self.date = fields["date"].string
            self.awarder = fields["awarder"].string
            self.awardSummary = fields["summary"].string
        case .language:
            self.language = fields["language"].string
            self.fluency = fields["fluency"].string
        case .reference:
            self.referenceName = fields["name"].string
            self.referenceText = fields["reference"].string
            self.referenceUrl = fields["url"].string
        }
    }

    /// Apply partial field updates (PATCH semantics)
    func applying(fields: JSON) -> AdditionalSectionEntry {
        var updated = self

        switch sectionType {
        case .award:
            if let v = fields["title"].string { updated.title = v }
            if let v = fields["date"].string { updated.date = v }
            if let v = fields["awarder"].string { updated.awarder = v }
            if let v = fields["summary"].string { updated.awardSummary = v }
        case .language:
            if let v = fields["language"].string { updated.language = v }
            if let v = fields["fluency"].string { updated.fluency = v }
        case .reference:
            if let v = fields["name"].string { updated.referenceName = v }
            if let v = fields["reference"].string { updated.referenceText = v }
            if let v = fields["url"].string { updated.referenceUrl = v }
        }

        return updated
    }

    /// Convert to JSON for tool responses
    var json: JSON {
        var payload = JSON()
        payload["id"].string = id
        payload["sectionType"].string = sectionType.rawValue

        switch sectionType {
        case .award:
            if let v = title { payload["title"].string = v }
            if let v = date { payload["date"].string = v }
            if let v = awarder { payload["awarder"].string = v }
            if let v = awardSummary { payload["summary"].string = v }
        case .language:
            if let v = language { payload["language"].string = v }
            if let v = fluency { payload["fluency"].string = v }
        case .reference:
            if let v = referenceName { payload["name"].string = v }
            if let v = referenceText { payload["reference"].string = v }
            if let v = referenceUrl { payload["url"].string = v }
        }

        return payload
    }

    /// Display title for UI
    var displayTitle: String {
        switch sectionType {
        case .award:
            return title?.isEmpty == false ? title! : "Untitled Award"
        case .language:
            return language?.isEmpty == false ? language! : "Untitled Language"
        case .reference:
            return referenceName?.isEmpty == false ? referenceName! : "Untitled Reference"
        }
    }

    /// Display subtitle for UI
    var displaySubtitle: String? {
        switch sectionType {
        case .award:
            var parts: [String] = []
            if let a = awarder, !a.isEmpty { parts.append(a) }
            if let d = date, !d.isEmpty { parts.append(d) }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")
        case .language:
            return fluency
        case .reference:
            return referenceText?.prefix(80).description
        }
    }
}
