import Foundation
import SwiftyJSON
import SwiftOpenAI
struct UpdateTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = {
        let fieldsSchema = JSONSchema(
            type: .object,
            description: "Timeline card fields to update (PATCH semantics - only include fields you want to change). Maps to JSON Resume work entry schema.",
            properties: [
                "title": JSONSchema(
                    type: .string,
                    description: "Position or role title (e.g., 'Senior Software Engineer', 'Graduate Student')"
                ),
                "organization": JSONSchema(
                    type: .string,
                    description: "Company or institution name (e.g., 'Acme Corp', 'Stanford University')"
                ),
                "location": JSONSchema(
                    type: .string,
                    description: "City, State format (e.g., 'San Francisco, CA'). Optional."
                ),
                "start": JSONSchema(
                    type: .string,
                    description: "ISO 8601 date when position began. Accepts YYYY-MM-DD, YYYY-MM, or YYYY formats."
                ),
                "end": JSONSchema(
                    type: .string,
                    description: "ISO 8601 date when position ended. Accepts YYYY-MM-DD, YYYY-MM, or YYYY formats. Use empty string \"\" for current/ongoing positions."
                ),
                "url": JSONSchema(
                    type: .string,
                    description: "Organization website URL."
                )
            ],
            required: [],
            additionalProperties: false
        )
        return JSONSchema(
            type: .object,
            description: """
                Update an existing timeline card with partial field changes (PATCH semantics).
                Only include fields you want to change - omitted fields remain unchanged. Use this to correct errors or add missing information to existing cards.
                RETURNS: { "success": true, "id": "<card-id>" }
                USAGE: Call when user provides corrections or additional details for an existing timeline entry. The UI will reflect changes immediately.
                DO NOT: Include summary or highlights in Phase 1 - skeleton cards contain only basic facts.
                """,
            properties: [
                "id": JSONSchema(
                    type: .string,
                    description: "Unique identifier of the timeline card to update"
                ),
                "fields": fieldsSchema
            ],
            required: ["id", "fields"],
            additionalProperties: false
        )
    }()
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.updateTimelineCard.rawValue }
    var description: String { "Update existing timeline card with partial changes (PATCH). Returns {success, id}. Only include changed fields." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let id = params["id"].string, !id.isEmpty else {
            throw ToolError.invalidParameters("id must be provided")
        }
        guard let fields = params["fields"].dictionary else {
            throw ToolError.invalidParameters("fields must be provided")
        }
        // Normalize fields for Phase 1 skeleton timeline constraints
        let normalizedFields = try normalizePhaseOneFields(JSON(fields))
        // Update timeline card via coordinator (which emits events)
        let result = await coordinator.updateTimelineCard(id: id, fields: normalizedFields)
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
        // Validate and keep start date if provided
        if let start = fields["start"].string {
            guard isValidISO8601Date(start) else {
                throw ToolError.invalidParameters("start date must be a valid ISO 8601 string (e.g., '2020-01-15')")
            }
            normalized["start"].string = start
        }
        // Validate and keep end date if provided (empty string means "present")
        if fields["end"].exists() {
            let end = fields["end"].string ?? ""
            if !end.isEmpty {
                guard isValidISO8601Date(end) else {
                    throw ToolError.invalidParameters("end date must be a valid ISO 8601 string or empty for present positions")
                }
            }
            normalized["end"].string = end
        }
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
