//
//  SectionCardSchema.swift
//  Sprung
//
//  Shared JSON schema definitions for section card tools.
//  Handles non-chronological sections: awards, languages, references.
//
import Foundation
import SwiftOpenAI

/// Shared schema definitions for section card fields
enum SectionCardSchema {
    // MARK: - Field Schemas

    /// Section card unique identifier
    static let id = JSONSchema(
        type: .string,
        description: "Unique identifier of the section card. Must match an existing card ID."
    )

    /// Section type discriminator
    static let sectionType = JSONSchema(
        type: .string,
        description: "Type of section: 'award', 'language', or 'reference'.",
        enum: ["award", "language", "reference"]
    )

    // MARK: - Type-Specific Field Schemas

    /// Award fields schema
    static let awardFields = JSONSchema(
        type: .object,
        description: "Fields for an award entry",
        properties: [
            "title": JSONSchema(
                type: .string,
                description: "Award name or title (e.g., 'Best Paper Award', 'Employee of the Year')"
            ),
            "date": JSONSchema(
                type: .string,
                description: "Date received (e.g., '2023', 'March 2022')"
            ),
            "awarder": JSONSchema(
                type: .string,
                description: "Organization that gave the award (e.g., 'ACM', 'Company Name')"
            ),
            "summary": JSONSchema(
                type: .string,
                description: "Brief description of the award or achievement"
            )
        ],
        required: ["title"],
        additionalProperties: false
    )

    /// Language fields schema
    static let languageFields = JSONSchema(
        type: .object,
        description: "Fields for a language entry",
        properties: [
            "language": JSONSchema(
                type: .string,
                description: "Language name (e.g., 'English', 'Spanish', 'Mandarin')"
            ),
            "fluency": JSONSchema(
                type: .string,
                description: "Proficiency level (e.g., 'Native', 'Fluent', 'Professional', 'Conversational', 'Basic')"
            )
        ],
        required: ["language"],
        additionalProperties: false
    )

    /// Reference fields schema
    static let referenceFields = JSONSchema(
        type: .object,
        description: "Fields for a reference entry",
        properties: [
            "name": JSONSchema(
                type: .string,
                description: "Reference person's name"
            ),
            "reference": JSONSchema(
                type: .string,
                description: "Reference text, testimonial, or relationship description"
            ),
            "url": JSONSchema(
                type: .string,
                description: "LinkedIn profile or contact URL (optional)"
            )
        ],
        required: ["name"],
        additionalProperties: false
    )

    // MARK: - Combined Schemas

    /// Schema for create_section_card tool
    static let createSchema = JSONSchema(
        type: .object,
        description: "Create a new section card for a non-chronological resume section",
        properties: [
            "sectionType": sectionType,
            "fields": JSONSchema(
                type: .object,
                description: "Type-specific fields. For award: title, date, awarder, summary. For language: language, fluency. For reference: name, reference, url."
            )
        ],
        required: ["sectionType", "fields"],
        additionalProperties: false
    )

    /// Schema for update_section_card tool
    static let updateSchema = JSONSchema(
        type: .object,
        description: "Update an existing section card with partial field changes",
        properties: [
            "id": id,
            "fields": JSONSchema(
                type: .object,
                description: "Fields to update (PATCH semantics - only provided fields change)"
            )
        ],
        required: ["id", "fields"],
        additionalProperties: false
    )

    /// Schema for delete_section_card tool
    static let deleteSchema = JSONSchema(
        type: .object,
        description: "Delete a section card by ID",
        properties: [
            "id": id
        ],
        required: ["id"],
        additionalProperties: false
    )
}
