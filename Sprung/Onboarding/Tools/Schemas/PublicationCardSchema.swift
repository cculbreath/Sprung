//
//  PublicationCardSchema.swift
//  Sprung
//
//  Shared JSON schema definitions for publication card tools.
//
import Foundation
import SwiftOpenAI

/// Shared schema definitions for publication card fields
enum PublicationCardSchema {
    // MARK: - Field Schemas

    /// Publication card unique identifier
    static let id = JSONSchema(
        type: .string,
        description: "Unique identifier of the publication card. Must match an existing card ID."
    )

    /// Publication fields schema for create operations
    static let createFields = JSONSchema(
        type: .object,
        description: "Fields for a publication entry",
        properties: [
            "name": JSONSchema(
                type: .string,
                description: "Publication title (required)"
            ),
            "publicationType": JSONSchema(
                type: .string,
                description: "Type of publication: article, conference, book, chapter, thesis, report",
                enum: ["article", "conference", "book", "chapter", "thesis", "report"]
            ),
            "publisher": JSONSchema(
                type: .string,
                description: "Journal, conference, or publisher name"
            ),
            "releaseDate": JSONSchema(
                type: .string,
                description: "Publication date (e.g., '2023', 'March 2022')"
            ),
            "url": JSONSchema(
                type: .string,
                description: "URL to the publication (optional)"
            ),
            "summary": JSONSchema(
                type: .string,
                description: "Brief description or abstract"
            ),
            "authors": JSONSchema(
                type: .array,
                description: "List of author names",
                items: JSONSchema(type: .string)
            ),
            "doi": JSONSchema(
                type: .string,
                description: "Digital Object Identifier (optional)"
            )
        ],
        required: ["name"],
        additionalProperties: false
    )

    /// Publication fields schema for update operations (all optional)
    static let updateFields = JSONSchema(
        type: .object,
        description: "Fields to update (PATCH semantics - only provided fields change)",
        properties: [
            "name": JSONSchema(type: .string, description: "Publication title"),
            "publicationType": JSONSchema(
                type: .string,
                description: "Type of publication: article, conference, book, chapter, thesis, report",
                enum: ["article", "conference", "book", "chapter", "thesis", "report"]
            ),
            "publisher": JSONSchema(type: .string, description: "Journal, conference, or publisher name"),
            "releaseDate": JSONSchema(type: .string, description: "Publication date"),
            "url": JSONSchema(type: .string, description: "URL to the publication"),
            "summary": JSONSchema(type: .string, description: "Brief description or abstract"),
            "authors": JSONSchema(type: .array, description: "List of author names", items: JSONSchema(type: .string)),
            "doi": JSONSchema(type: .string, description: "Digital Object Identifier")
        ],
        additionalProperties: false
    )

    // MARK: - Combined Schemas

    /// Schema for create_publication_card tool
    static let createSchema = JSONSchema(
        type: .object,
        description: "Create a new publication card",
        properties: [
            "fields": createFields
        ],
        required: ["fields"],
        additionalProperties: false
    )

    /// Schema for update_publication_card tool
    static let updateSchema = JSONSchema(
        type: .object,
        description: "Update an existing publication card with partial field changes",
        properties: [
            "id": id,
            "fields": updateFields
        ],
        required: ["id", "fields"],
        additionalProperties: false
    )

    /// Schema for delete_publication_card tool
    static let deleteSchema = JSONSchema(
        type: .object,
        description: "Delete a publication card by ID",
        properties: [
            "id": id
        ],
        required: ["id"],
        additionalProperties: false
    )
}
