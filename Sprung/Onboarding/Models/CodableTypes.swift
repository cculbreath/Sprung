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

    enum CodingKeys: String, CodingKey {
        case experienceType = "experience_type"
        case title
        case organization
        case location
        case start
        case end
        case url
    }
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

    enum CodingKeys: String, CodingKey {
        case experienceType = "experience_type"
        case title
        case organization
        case location
        case start
        case end
        case url
    }
}
