//
//  MiscSchemas.swift
//  Sprung
//
//  Shared JSON schema definitions for miscellaneous onboarding tools.
//  DRY: Common schemas extracted from multiple tool implementations.
//
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Shared schema definitions for resume sections and other common structures
enum MiscSchemas {
    // MARK: - Writing Sample Schemas

    /// Writing sample type enum values
    static var writingSampleTypes: [String] {
        ["cover_letter", "email", "essay", "proposal", "report", "blog_post", "documentation", "other"]
    }

    // MARK: - IngestWritingSampleTool Schemas

    /// Writing sample name schema
    static let writingSampleName = JSONSchema(
        type: .string,
        description: "Descriptive name for the writing sample (e.g., 'Cover letter for Google', 'Professional email to client', 'Graduate school essay')"
    )

    /// Writing sample content schema
    static let writingSampleContent = JSONSchema(
        type: .string,
        description: "The full text content of the writing sample. Include the complete text exactly as provided by the user."
    )

    /// Writing sample type schema
    static let writingSampleType = JSONSchema(
        type: .string,
        description: "Type of writing sample",
        enum: writingSampleTypes
    )

    /// Writing sample context schema
    static let writingSampleContext = JSONSchema(
        type: .string,
        description: "Optional context about the writing sample (when written, purpose, audience)"
    )

    // MARK: - ConfigureEnabledSectionsTool Schemas

    /// Proposed sections schema for ConfigureEnabledSectionsTool
    static let proposedSections = JSONSchema(
        type: .object,
        description: """
            Object mapping JSON Resume top-level section keys to boolean enabled/disabled state.
            Valid section keys (from JSON Resume schema):
            - work: Work experience entries
            - education: Educational background
            - volunteer: Volunteer experience
            - awards: Professional awards and recognitions
            - certificates: Professional certifications
            - publications: Published works
            - skills: Technical and professional skills
            - languages: Languages spoken with fluency levels
            - interests: Personal interests and hobbies
            - references: Professional references
            - projects: Career projects and portfolio items
            Example: { "work": true, "education": true, "skills": true, "publications": false, "projects": true, "awards": false }
            """,
        additionalProperties: true
    )

    /// Section configuration rationale schema
    static let sectionConfigRationale = JSONSchema(
        type: .string,
        description: "Optional explanation or context for the proposed sections"
    )

}
