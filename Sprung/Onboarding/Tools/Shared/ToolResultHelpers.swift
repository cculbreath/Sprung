//
//  ToolResultHelpers.swift
//  Sprung
//
//  Helper utilities for creating consistent tool results.
//  Provides convenience methods for common tool result patterns.
//
import Foundation
import SwiftyJSON

/// Helper functions for creating consistent tool results
enum ToolResultHelpers {

    // MARK: - Success Responses

    /// Creates an immediate success result with a message
    /// - Parameter message: Optional success message
    /// - Returns: ToolResult with immediate JSON response
    static func success(message: String? = nil) -> ToolResult {
        var response = JSON()
        response["success"].bool = true
        if let message = message {
            response["message"].string = message
        }
        return .immediate(response)
    }

    /// Creates an immediate success result with custom data
    /// - Parameter data: The data to include in the response
    /// - Returns: ToolResult with immediate JSON response
    static func success(data: JSON) -> ToolResult {
        var response = data
        response["success"].bool = true
        return .immediate(response)
    }

    /// Creates an immediate success result with a simple key-value pair
    /// - Parameters:
    ///   - key: The key for the data
    ///   - value: The value for the data
    /// - Returns: ToolResult with immediate JSON response
    static func success(key: String, value: String) -> ToolResult {
        var response = JSON()
        response["success"].bool = true
        response[key].string = value
        return .immediate(response)
    }

    // MARK: - Error Responses

    /// Creates an error result for invalid parameters
    /// - Parameter message: Description of what parameters are invalid
    /// - Returns: ToolResult with error
    static func invalidParameters(_ message: String) -> ToolResult {
        .error(.invalidParameters(message))
    }

    /// Creates an error result for execution failures
    /// - Parameter message: Description of what failed
    /// - Returns: ToolResult with error
    static func executionFailed(_ message: String) -> ToolResult {
        .error(.executionFailed(message))
    }

    /// Creates an error result for missing required fields
    /// - Parameter fields: List of missing field names
    /// - Returns: ToolResult with error
    static func missingRequiredFields(_ fields: [String]) -> ToolResult {
        let fieldList = fields.joined(separator: ", ")
        return .error(.invalidParameters("Missing required fields: \(fieldList)"))
    }

    // MARK: - Validation Helpers

    /// Validates that a required string parameter is present and non-empty
    /// - Parameters:
    ///   - value: The optional string value
    ///   - name: The parameter name for error messages
    /// - Returns: The validated string
    /// - Throws: ToolError.invalidParameters if validation fails
    static func requireString(_ value: String?, named name: String) throws -> String {
        guard let value = value, !value.isEmpty else {
            throw ToolError.invalidParameters("\(name) is required and must not be empty")
        }
        return value
    }

    /// Validates that a required array parameter is present and non-empty
    /// - Parameters:
    ///   - value: The optional array value
    ///   - name: The parameter name for error messages
    /// - Returns: The validated array
    /// - Throws: ToolError.invalidParameters if validation fails
    static func requireNonEmptyArray(_ value: [JSON]?, named name: String) throws -> [JSON] {
        guard let value = value, !value.isEmpty else {
            throw ToolError.invalidParameters("\(name) is required and must contain at least one item")
        }
        return value
    }

    /// Validates that a required object parameter is present
    /// - Parameters:
    ///   - value: The optional dictionary value
    ///   - name: The parameter name for error messages
    /// - Returns: The validated dictionary
    /// - Throws: ToolError.invalidParameters if validation fails
    static func requireObject(_ value: [String: JSON]?, named name: String) throws -> [String: JSON] {
        guard let validatedValue = value else {
            throw ToolError.invalidParameters("\(name) is required and must be an object")
        }
        return validatedValue
    }

    // MARK: - Response Building Helpers

    /// Builds a paginated response with items and metadata
    /// - Parameters:
    ///   - items: The items to include in the response
    ///   - total: The total number of items available
    ///   - offset: The offset used for pagination
    ///   - limit: The limit used for pagination
    /// - Returns: ToolResult with paginated data
    static func paginatedResponse(
        items: [JSON],
        total: Int,
        offset: Int = 0,
        limit: Int? = nil
    ) -> ToolResult {
        var response = JSON()
        response["success"].bool = true
        response["items"].arrayObject = items.map { $0.object }
        response["count"].int = items.count
        response["total"].int = total
        response["offset"].int = offset
        if let limit = limit {
            response["limit"].int = limit
        }
        return .immediate(response)
    }

    /// Builds a response for a list of items with count
    /// - Parameter items: The items to include
    /// - Returns: ToolResult with list data
    static func listResponse(items: [JSON]) -> ToolResult {
        var response = JSON()
        response["success"].bool = true
        response["items"].arrayObject = items.map { $0.object }
        response["count"].int = items.count
        return .immediate(response)
    }

    /// Builds a response with a status field
    /// - Parameters:
    ///   - status: The status value
    ///   - message: Optional message
    ///   - additionalData: Additional data to include
    /// - Returns: ToolResult with status data
    static func statusResponse(
        status: String,
        message: String? = nil,
        additionalData: JSON? = nil
    ) -> ToolResult {
        var response = JSON()
        response["success"].bool = true
        response["status"].string = status
        if let message = message {
            response["message"].string = message
        }
        if let data = additionalData {
            // Merge additional data
            for (key, value) in data.dictionaryValue {
                response[key] = value
            }
        }
        return .immediate(response)
    }
}

/// Extension to ToolError for common validation patterns
extension ToolError {

    /// Creates an invalidParameters error for a missing field
    /// - Parameter fieldName: The name of the missing field
    /// - Returns: ToolError.invalidParameters
    static func missingField(_ fieldName: String) -> ToolError {
        .invalidParameters("\(fieldName) is required")
    }

    /// Creates an invalidParameters error for an invalid enum value
    /// - Parameters:
    ///   - fieldName: The field name
    ///   - value: The invalid value
    ///   - validValues: List of valid values
    /// - Returns: ToolError.invalidParameters
    static func invalidEnum(
        field fieldName: String,
        value: String,
        validValues: [String]
    ) -> ToolError {
        let options = validValues.joined(separator: ", ")
        return .invalidParameters(
            "\(fieldName) must be one of: \(options). Got: '\(value)'"
        )
    }

    /// Creates an invalidParameters error for a value that's too short
    /// - Parameters:
    ///   - fieldName: The field name
    ///   - minLength: The minimum required length
    ///   - actualLength: The actual length
    /// - Returns: ToolError.invalidParameters
    static func tooShort(
        field fieldName: String,
        minLength: Int,
        actualLength: Int
    ) -> ToolError {
        .invalidParameters(
            "\(fieldName) must be at least \(minLength) characters. Got: \(actualLength)"
        )
    }
}
