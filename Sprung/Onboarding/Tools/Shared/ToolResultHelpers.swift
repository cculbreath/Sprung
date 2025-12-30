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

    // MARK: - Response Building Helpers

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
}
