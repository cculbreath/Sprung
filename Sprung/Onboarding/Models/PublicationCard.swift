//
//  PublicationCard.swift
//  Sprung
//
//  Model for publications during onboarding.
//  Supports multiple source types: BibTeX import, CV parsing, or interview.
//

import Foundation
import SwiftyJSON

/// How the publication was collected during onboarding
enum PublicationSourceType: String, Codable {
    case bibtex     // Parsed from .bib file
    case cv         // Extracted from CV/resume document
    case interview  // Collected via conversational interview
}

/// A card representing a publication entry during onboarding
struct PublicationCard: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var publisher: String
    var releaseDate: String
    var url: String
    var summary: String
    var sourceType: PublicationSourceType

    // Optional BibTeX metadata for reference
    var bibtexKey: String?
    var bibtexType: String?  // article, inproceedings, book, etc.
    var authors: [String]?
    var doi: String?

    init(
        id: String = UUID().uuidString,
        name: String = "",
        publisher: String = "",
        releaseDate: String = "",
        url: String = "",
        summary: String = "",
        sourceType: PublicationSourceType = .interview,
        bibtexKey: String? = nil,
        bibtexType: String? = nil,
        authors: [String]? = nil,
        doi: String? = nil
    ) {
        self.id = id
        self.name = name
        self.publisher = publisher
        self.releaseDate = releaseDate
        self.url = url
        self.summary = summary
        self.sourceType = sourceType
        self.bibtexKey = bibtexKey
        self.bibtexType = bibtexType
        self.authors = authors
        self.doi = doi
    }

    /// Initialize from JSON
    init?(json: JSON) {
        guard let idString = json["id"].string, !idString.isEmpty else {
            return nil
        }
        self.id = idString
        self.name = json["name"].stringValue
        self.publisher = json["publisher"].stringValue
        self.releaseDate = json["releaseDate"].stringValue
        self.url = json["url"].stringValue
        self.summary = json["summary"].stringValue
        self.sourceType = PublicationSourceType(rawValue: json["sourceType"].stringValue) ?? .interview
        self.bibtexKey = json["bibtexKey"].string
        self.bibtexType = json["bibtexType"].string
        self.authors = json["authors"].array?.compactMap { $0.string }
        self.doi = json["doi"].string
    }

    /// Initialize with fields JSON for tool-based creation
    init(id: String = UUID().uuidString, fields: JSON, sourceType: PublicationSourceType = .interview) {
        self.id = id
        self.name = fields["name"].stringValue
        self.publisher = fields["publisher"].stringValue
        self.releaseDate = fields["releaseDate"].stringValue
        self.url = fields["url"].stringValue
        self.summary = fields["summary"].stringValue
        self.sourceType = sourceType
        self.bibtexKey = fields["bibtexKey"].string
        // Support both bibtexType (internal) and publicationType (from LLM tool)
        self.bibtexType = fields["publicationType"].string ?? fields["bibtexType"].string
        self.authors = fields["authors"].array?.compactMap { $0.string }
        self.doi = fields["doi"].string
    }

    /// Apply partial field updates (PATCH semantics)
    func applying(fields: JSON) -> PublicationCard {
        var updated = self

        if let v = fields["name"].string { updated.name = v }
        if let v = fields["publicationType"].string ?? fields["bibtexType"].string { updated.bibtexType = v }
        if let v = fields["publisher"].string { updated.publisher = v }
        if let v = fields["releaseDate"].string { updated.releaseDate = v }
        if let v = fields["url"].string { updated.url = v }
        if let v = fields["summary"].string { updated.summary = v }
        if let v = fields["doi"].string { updated.doi = v }
        if let arr = fields["authors"].array {
            updated.authors = arr.compactMap { $0.string }
        }

        return updated
    }

    /// Convert to JSON for tool responses
    var json: JSON {
        var payload = JSON()
        payload["id"].string = id
        payload["name"].string = name
        payload["publisher"].string = publisher
        payload["releaseDate"].string = releaseDate
        payload["url"].string = url
        payload["summary"].string = summary
        payload["sourceType"].string = sourceType.rawValue

        if let key = bibtexKey { payload["bibtexKey"].string = key }
        if let type = bibtexType { payload["bibtexType"].string = type }
        if let authors = authors { payload["authors"] = JSON(authors) }
        if let doi = doi { payload["doi"].string = doi }

        return payload
    }

    /// Display title for UI
    var displayTitle: String {
        name.isEmpty ? "Untitled Publication" : name
    }

    /// Display subtitle for UI
    var displaySubtitle: String? {
        var parts: [String] = []
        if !publisher.isEmpty { parts.append(publisher) }
        if !releaseDate.isEmpty { parts.append(releaseDate) }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    /// Author list as comma-separated string
    var authorString: String? {
        guard let authors = authors, !authors.isEmpty else { return nil }
        return authors.joined(separator: ", ")
    }
}
