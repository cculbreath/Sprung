//
//  CodableTypes.swift
//  Sprung
//
//  Codable data structures for type-safe internal data handling.
//  These replace SwiftyJSON patterns for internal tool processing.
//
import Foundation

// MARK: - Generic Tool Response Wrapper

/// Generic wrapper for type-safe tool responses
/// Allows decoding tool outputs with proper typing at the boundary
struct ToolResponse<T: Codable>: Codable {
    var success: Bool
    var data: T?
    var message: String?
    var error: String?

    init(success: Bool, data: T? = nil, message: String? = nil, error: String? = nil) {
        self.success = success
        self.data = data
        self.message = message
        self.error = error
    }
}

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
