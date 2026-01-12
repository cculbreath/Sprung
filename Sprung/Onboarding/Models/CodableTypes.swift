//
//  CodableTypes.swift
//  Sprung
//
//  Codable data structures for type-safe internal data handling.
//  These replace SwiftyJSON patterns for internal tool processing.
//
import Foundation

// MARK: - Timeline Tool Input Types

/// Input parameters for creating a timeline card
struct CreateTimelineCardInput: Codable {
    var experienceType: ExperienceType?
    var title: String
    var organization: String
    var location: String?
    var start: String
    var end: String?
    var url: String?
}

/// Input parameters for updating a timeline card
struct UpdateTimelineCardInput: Codable {
    var experienceType: ExperienceType?
    var title: String?
    var organization: String?
    var location: String?
    var start: String?
    var end: String?
    var url: String?
}

// MARK: - Section Card Tool Input Types

/// Input parameters for creating an award section card
struct CreateAwardInput: Codable {
    var title: String
    var date: String?
    var awarder: String?
    var summary: String?
}

/// Input parameters for creating a language section card
struct CreateLanguageInput: Codable {
    var language: String
    var fluency: String?
}

/// Input parameters for creating a reference section card
struct CreateReferenceInput: Codable {
    var name: String
    var reference: String?
    var url: String?
}

/// Input parameters for updating an award section card
struct UpdateAwardInput: Codable {
    var title: String?
    var date: String?
    var awarder: String?
    var summary: String?
}

/// Input parameters for updating a language section card
struct UpdateLanguageInput: Codable {
    var language: String?
    var fluency: String?
}

/// Input parameters for updating a reference section card
struct UpdateReferenceInput: Codable {
    var name: String?
    var reference: String?
    var url: String?
}

// MARK: - Publication Card Tool Input Types

/// Input parameters for creating a publication card
struct CreatePublicationInput: Codable {
    var name: String
    var publisher: String?
    var releaseDate: String?
    var url: String?
    var summary: String?
    var authors: [String]?
    var doi: String?
}

/// Input parameters for updating a publication card
struct UpdatePublicationInput: Codable {
    var name: String?
    var publisher: String?
    var releaseDate: String?
    var url: String?
    var summary: String?
    var authors: [String]?
    var doi: String?
}
