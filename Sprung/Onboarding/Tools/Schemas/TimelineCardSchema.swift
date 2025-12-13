//
//  TimelineCardSchema.swift
//  Sprung
//
//  Shared JSON schema definitions for timeline card tools.
//  DRY: Used by CreateTimelineCardTool, UpdateTimelineCardTool, and other timeline tools.
//
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Shared schema definitions for timeline card fields
enum TimelineCardSchema {
    /// Schema for timeline card fields used in create/update operations
    /// - Parameter requireFields: Fields that should be marked as required (for create vs update)
    static func fieldsSchema(required: [String] = []) -> JSONSchema {
        JSONSchema(
            type: .object,
            description: "Timeline card fields mapping to JSON Resume work entry schema. Phase 1 skeleton entries contain only basic facts (who, what, where, when) - no descriptions or highlights.",
            properties: [
                "experience_type": JSONSchema(
                    type: .string,
                    description: "Type of experience: 'work', 'education', 'volunteer', 'project'. Defaults to 'work' if not specified.",
                    enum: ["work", "education", "volunteer", "project"]
                ),
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
                    description: "Date when position began in human-readable format (e.g., 'January 2020', 'March 2019', '2018'). Required for create."
                ),
                "end": JSONSchema(
                    type: .string,
                    description: "Date when position ended in human-readable format (e.g., 'December 2022', 'June 2021'). Use 'Present' or empty string for current/ongoing positions."
                ),
                "url": JSONSchema(
                    type: .string,
                    description: "Organization website URL. Optional."
                )
            ],
            required: required,
            additionalProperties: false
        )
    }

    /// Normalizes timeline card fields to enforce Phase 1 skeleton-only constraints.
    /// Keeps only: experience_type, title, organization, location, start, end, url
    /// Drops summary/highlights which are added in Phase 2.
    static func normalizePhaseOneFields(_ fields: JSON, includeExperienceType: Bool = true) -> JSON {
        var normalized = JSON()

        // Keep experience type if requested (for create, not update)
        if includeExperienceType {
            normalized["experience_type"].string = fields["experience_type"].string ?? "work"
        }

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

        // Keep start date - accepts human-readable format
        if let start = fields["start"].string {
            normalized["start"].string = start
        }

        // Keep end date (empty string or "Present" means current position)
        if fields["end"].exists() {
            normalized["end"].string = fields["end"].string ?? ""
        }

        // Phase 1: explicitly drop summary and highlights
        // (They will be added in Phase 2)
        return normalized
    }
}
