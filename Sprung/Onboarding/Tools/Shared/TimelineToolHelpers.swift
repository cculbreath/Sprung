//
//  TimelineToolHelpers.swift
//  Sprung
//
//  Shared helper utilities for timeline card operations.
//  Provides common validation logic and data processing for timeline tools.
//
import Foundation
import SwiftyJSON

/// Shared validation helpers for timeline card operations
enum TimelineValidation {

    /// Validates that a card ID is present and non-empty
    /// - Parameter id: The card ID to validate
    /// - Throws: `ToolError.invalidParameters` if ID is nil or empty
    static func validateCardId(_ id: String?) throws {
        guard let id = id, !id.isEmpty else {
            throw ToolError.invalidParameters("Card ID is required and must not be empty")
        }
    }

    /// Validates required fields for creating a new timeline card
    /// - Parameter fields: The field dictionary to validate
    /// - Throws: `ToolError.invalidParameters` if required fields are missing
    static func validateNewCardFields(_ fields: JSON) throws {
        // Title is required
        guard let title = fields["title"].string, !title.isEmpty else {
            throw ToolError.invalidParameters("Card title is required for new timeline cards")
        }

        // Organization is required
        guard let organization = fields["organization"].string, !organization.isEmpty else {
            throw ToolError.invalidParameters("Organization name is required for new timeline cards")
        }

        // Start date is required
        guard let start = fields["start"].string, !start.isEmpty else {
            throw ToolError.invalidParameters("Start date is required for new timeline cards (e.g., 'January 2020', 'March 2019', '2018')")
        }
    }

    /// Validates that update fields contain at least one field to update
    /// - Parameter fields: The field dictionary to validate
    /// - Throws: `ToolError.invalidParameters` if no fields are present
    static func validateUpdateFields(_ fields: JSON) throws {
        guard let dict = fields.dictionary, !dict.isEmpty else {
            throw ToolError.invalidParameters("At least one field must be provided for updates")
        }
    }

    /// Validates that ordered IDs list is not empty
    /// - Parameter orderedIds: The list of IDs to validate
    /// - Throws: `ToolError.invalidParameters` if list is empty
    static func validateOrderedIds(_ orderedIds: [String]) throws {
        guard !orderedIds.isEmpty else {
            throw ToolError.invalidParameters("Ordered IDs list must contain at least one ID")
        }
    }
}

/// Helper functions for building timeline tool responses
enum TimelineResponseBuilder {

    /// Builds a standard success response for timeline card creation
    /// - Parameters:
    ///   - id: The ID of the created card
    ///   - fields: The fields that were set
    /// - Returns: JSON response object
    static func createSuccessResponse(id: String, fields: JSON) -> JSON {
        var response = JSON()
        response["success"].bool = true
        response["id"].string = id
        response["message"].string = "Timeline card created successfully"

        // Include key fields in response for confirmation
        if let title = fields["title"].string {
            response["title"].string = title
        }
        if let organization = fields["organization"].string {
            response["organization"].string = organization
        }

        return response
    }

    /// Builds a standard success response for timeline card updates
    /// - Parameters:
    ///   - id: The ID of the updated card
    ///   - fields: The fields that were updated
    /// - Returns: JSON response object
    static func updateSuccessResponse(id: String, fields: JSON) -> JSON {
        var response = JSON()
        response["success"].bool = true
        response["id"].string = id
        response["message"].string = "Timeline card updated successfully"
        response["updated_fields"].int = fields.dictionary?.count ?? 0

        return response
    }

    /// Builds a standard success response for timeline card deletion
    /// - Parameter id: The ID of the deleted card
    /// - Returns: JSON response object
    static func deleteSuccessResponse(id: String) -> JSON {
        var response = JSON()
        response["success"].bool = true
        response["id"].string = id
        response["message"].string = "Timeline card deleted successfully"

        return response
    }

    /// Builds a standard success response for timeline card reordering
    /// - Parameter orderedIds: The new order of card IDs
    /// - Returns: JSON response object
    static func reorderSuccessResponse(orderedIds: [String]) -> JSON {
        var response = JSON()
        response["success"].bool = true
        response["message"].string = "Timeline cards reordered successfully"
        response["card_count"].int = orderedIds.count
        response["order"].arrayObject = orderedIds

        return response
    }
}

/// Helper functions for processing timeline card data
enum TimelineDataProcessor {

    /// Extracts and validates experience type from fields
    /// - Parameter fields: The field dictionary
    /// - Returns: The experience type, defaulting to "work" if not specified
    static func extractExperienceType(_ fields: JSON) -> String {
        fields["experience_type"].string ?? "work"
    }

    /// Normalizes date strings to a consistent format
    /// - Parameter dateString: The date string to normalize
    /// - Returns: Normalized date string or the original if it cannot be normalized
    static func normalizeDate(_ dateString: String?) -> String? {
        guard let dateString = dateString, !dateString.isEmpty else {
            return nil
        }

        // Normalize common variations
        let normalized = dateString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle "Present" variations
        if normalized.lowercased() == "present" || normalized.lowercased() == "current" {
            return "Present"
        }

        return normalized
    }

    /// Validates that a timeline card has the minimum required fields
    /// - Parameter card: The card JSON to validate
    /// - Returns: True if card has minimum required fields
    static func hasMinimumFields(_ card: JSON) -> Bool {
        guard let _ = card["id"].string,
              let _ = card["title"].string,
              let _ = card["organization"].string else {
            return false
        }
        return true
    }

    /// Counts the number of timeline cards in a timeline JSON object
    /// - Parameter timeline: The timeline JSON object
    /// - Returns: The number of cards, or 0 if timeline is invalid
    static func countCards(in timeline: JSON) -> Int {
        timeline["experiences"].arrayValue.count
    }
}
