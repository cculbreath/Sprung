//
//  ValidationSchemas.swift
//  Sprung
//
//  Shared JSON schema definitions for validation tools.
//  DRY: Used by SubmitForValidationTool, ValidateApplicantProfileTool, and related validation tools.
//
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Shared schema definitions for validation-related fields
enum ValidationSchemas {
    /// Schema for validationType enum used across validation tools
    /// Note: Enum values match OnboardingDataType raw values for backwards compatibility
    static let validationType = JSONSchema(
        type: .string,
        description: "Type of data being validated. Each type presents specialized validation UI.",
        enum: ["applicant_profile", "skeleton_timeline", "enabled_sections", "knowledge_card", "candidate_dossier", "experience_defaults"]
    )

    /// Schema for validation data payload
    static let dataPayload = JSONSchema(
        type: .object,
        description: "The complete data payload to validate. For skeleton_timeline, this is optional and will be auto-fetched from current timeline state. For other types, provide the complete data object."
    )

    /// Schema for validation summary message
    static let summary = JSONSchema(
        type: .string,
        description: "Human-readable summary shown to user in validation card. Explain what was collected and what they're confirming."
    )

    /// Schema for applicant profile data payload
    static let applicantProfileData = JSONSchema(
        type: .object,
        description: "The applicant profile data to validate (name, email, phone, location, URLs, social profiles). Should match ApplicantProfile schema."
    )

    /// Schema for timeline review summary message
    static let timelineReviewSummary = JSONSchema(
        type: .string,
        description: "Optional summary message shown to user in timeline review card. Explain what they're reviewing and what to check for."
    )
}
