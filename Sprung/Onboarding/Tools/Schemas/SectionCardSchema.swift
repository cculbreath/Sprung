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
