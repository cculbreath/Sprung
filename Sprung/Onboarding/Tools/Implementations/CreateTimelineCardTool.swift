import Foundation
import SwiftyJSON
import SwiftOpenAI
struct CreateTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = {
        let fieldsSchema = JSONSchema(
            type: .object,
            description: "Timeline card fields mapping to JSON Resume work entry schema. Phase 1 skeleton entries contain only basic facts (who, what, where, when) - no descriptions or highlights.",
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
                    description: "ISO 8601 date when position began. Accepts YYYY-MM-DD, YYYY-MM, or YYYY formats. Required."
                ),
                "end": JSONSchema(
                    type: .string,
                    description: "ISO 8601 date when position ended. Accepts YYYY-MM-DD, YYYY-MM, or YYYY formats. Use empty string \"\" for current/ongoing positions. Optional."
                ),
                "url": JSONSchema(
                    type: .string,
                    description: "Organization website URL. Optional."
                )
            ],
            required: ["title", "organization", "start"],
            additionalProperties: false
        )
        return JSONSchema(
            type: .object,
            description: """
                Create a skeleton timeline card for a position, role, or educational experience.
                Phase 1 cards capture only basic timeline facts - title, organization, dates, and location. Summary and highlights are added in later phases.
                RETURNS: { "success": true, "id": "<card-id>" }
                USAGE: Call after gathering position details via chat or artifact extraction. Cards are displayed in the timeline editor UI where users can review and edit them.
                DO NOT: Generate descriptions or bullet points in Phase 1 - defer to Phase 2 deep dive.
                """,
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
    var description: String { "Create skeleton timeline card with basic facts (title, org, dates, location). Returns {success, id}. Phase 1 only - no descriptions." }
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
