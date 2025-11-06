import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CreateTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = {
        let fieldsSchema = JSONSchema(
            type: .object,
            description: "Timeline card fields (title, organization, location, start, end, summary, highlights).",
            additionalProperties: true
        )

        return JSONSchema(
            type: .object,
            description: "Create a new skeleton timeline card.",
            properties: ["fields": fieldsSchema],
            required: ["fields"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "create_timeline_card" }
    var description: String { "Append a new skeleton timeline card with the supplied fields." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let fields = params["fields"].dictionary else {
            throw ToolError.invalidParameters("fields must be provided")
        }

        // Normalize fields for Phase 1 skeleton timeline constraints
        let normalizedFields = try normalizePhaseOneFields(JSON(fields))

        // Create timeline card via coordinator (which emits events)
        let result = await coordinator.createTimelineCard(fields: normalizedFields)
        return .immediate(result)
    }

    /// Normalizes timeline card fields to enforce Phase 1 skeleton-only constraints.
    /// Keeps only: title, organization, location, start, end, url
    /// Validates ISO 8601 date strings and drops summary/highlights.
    private func normalizePhaseOneFields(_ fields: JSON) throws -> JSON {
        var normalized = JSON()

        // Keep allowed Phase 1 fields
        if let title = fields["title"].string {
            normalized["title"].string = title
        }
        if let organization = fields["organization"].string {
            normalized["organization"].string = organization
        }
        if let location = fields["location"].string {
            normalized["location"].string = location
        }
        if let url = fields["url"].string {
            normalized["url"].string = url
        }

        // Validate and keep start date (required)
        if let start = fields["start"].string {
            guard isValidISO8601Date(start) else {
                throw ToolError.invalidParameters("start date must be a valid ISO 8601 string (e.g., '2020-01-15')")
            }
            normalized["start"].string = start
        }

        // Validate and keep end date (optional, empty string means "present")
        let end = fields["end"].string ?? ""
        if !end.isEmpty {
            guard isValidISO8601Date(end) else {
                throw ToolError.invalidParameters("end date must be a valid ISO 8601 string or empty for present positions")
            }
        }
        normalized["end"].string = end

        // Phase 1: explicitly drop summary and highlights
        // (They will be added in Phase 2)

        return normalized
    }

    /// Validates that a string is a valid ISO 8601 date (YYYY-MM-DD format or partial formats).
    private func isValidISO8601Date(_ dateString: String) -> Bool {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }

        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withFullDate]

        // Try full date first (YYYY-MM-DD)
        if iso8601Formatter.date(from: trimmed) != nil {
            return true
        }

        // Also accept year-month (YYYY-MM) format
        let yearMonthPattern = "^\\d{4}-\\d{2}$"
        if trimmed.range(of: yearMonthPattern, options: .regularExpression) != nil {
            return true
        }

        // Also accept year-only (YYYY) format
        let yearPattern = "^\\d{4}$"
        if trimmed.range(of: yearPattern, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}
