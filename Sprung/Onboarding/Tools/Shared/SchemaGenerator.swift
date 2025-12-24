//
//  SchemaGenerator.swift
//  Sprung
//
//  Generates JSON Schema from Swift Codable types using builder pattern.
//  Eliminates manual schema definitions and reduces duplication/errors.
//
import Foundation
import SwiftOpenAI

/// Protocol for types that provide schema metadata
protocol SchemaDescribable {
    /// Schema description for the type
    static var schemaDescription: String? { get }
}

extension SchemaDescribable {
    static var schemaDescription: String? { nil }
}

/// Builder for constructing JSON schemas with type-safe API
struct SchemaBuilder {
    private var schemaType: JSONSchemaType = .object
    private var description: String?
    private var properties: [String: JSONSchema] = [:]
    private var requiredFields: [String] = []
    private var items: JSONSchema?
    private var enumValues: [String]?
    private var additionalProperties: Bool = false

    init() {}

    // MARK: - Type Configuration

    func object(description: String? = nil) -> SchemaBuilder {
        var builder = self
        builder.schemaType = .object
        builder.description = description
        builder.additionalProperties = false
        return builder
    }

    func array(items: JSONSchema, description: String? = nil) -> SchemaBuilder {
        var builder = self
        builder.schemaType = .array
        builder.items = items
        builder.description = description
        return builder
    }

    func string(description: String? = nil, enumValues: [String]? = nil) -> SchemaBuilder {
        var builder = self
        builder.schemaType = .string
        builder.description = description
        builder.enumValues = enumValues
        return builder
    }

    func integer(description: String? = nil) -> SchemaBuilder {
        var builder = self
        builder.schemaType = .integer
        builder.description = description
        return builder
    }

    func number(description: String? = nil) -> SchemaBuilder {
        var builder = self
        builder.schemaType = .number
        builder.description = description
        return builder
    }

    func boolean(description: String? = nil) -> SchemaBuilder {
        var builder = self
        builder.schemaType = .boolean
        builder.description = description
        return builder
    }

    // MARK: - Property Configuration

    func property(_ name: String, _ schema: JSONSchema, required: Bool = false) -> SchemaBuilder {
        var builder = self
        builder.properties[name] = schema
        if required {
            builder.requiredFields.append(name)
        }
        return builder
    }

    func required(_ fields: String...) -> SchemaBuilder {
        var builder = self
        builder.requiredFields.append(contentsOf: fields)
        return builder
    }

    // MARK: - Build

    func build() -> JSONSchema {
        JSONSchema(
            type: schemaType,
            description: description,
            properties: properties.isEmpty ? nil : properties,
            items: items,
            required: requiredFields.isEmpty ? nil : requiredFields,
            additionalProperties: additionalProperties,
            enum: enumValues
        )
    }
}

/// Convenience constructors for common schema patterns
enum SchemaGenerator {

    // MARK: - Primitive Types

    static func string(description: String? = nil, enumValues: [String]? = nil) -> JSONSchema {
        SchemaBuilder()
            .string(description: description, enumValues: enumValues)
            .build()
    }

    static func integer(description: String? = nil) -> JSONSchema {
        SchemaBuilder()
            .integer(description: description)
            .build()
    }

    static func number(description: String? = nil) -> JSONSchema {
        SchemaBuilder()
            .number(description: description)
            .build()
    }

    static func boolean(description: String? = nil) -> JSONSchema {
        SchemaBuilder()
            .boolean(description: description)
            .build()
    }

    // MARK: - Complex Types

    static func array(of itemType: JSONSchema, description: String? = nil) -> JSONSchema {
        SchemaBuilder()
            .array(items: itemType, description: description)
            .build()
    }

    static func object(
        description: String? = nil,
        properties: [String: JSONSchema],
        required: [String] = []
    ) -> JSONSchema {
        var builder = SchemaBuilder().object(description: description)

        for (name, schema) in properties {
            let isRequired = required.contains(name)
            builder = builder.property(name, schema, required: isRequired)
        }

        return builder.build()
    }

    // MARK: - Optional Types

    static func optional(_ schema: JSONSchema) -> JSONSchema {
        JSONSchema(
            type: .union([schema.type ?? .string, .null]),
            description: schema.description,
            properties: schema.properties,
            items: schema.items,
            required: schema.required,
            additionalProperties: schema.additionalProperties ?? false,
            enum: schema.enum
        )
    }

    // MARK: - Enum Helper

    static func enumSchema<E: RawRepresentable>(
        _ enumType: E.Type,
        description: String? = nil
    ) -> JSONSchema where E.RawValue == String, E: CaseIterable {
        let values = enumType.allCases.map { $0.rawValue }
        return string(description: description, enumValues: values)
    }
}

// MARK: - Usage Examples

/*
 EXAMPLE 1: Simple string property

     let nameSchema = SchemaGenerator.string(
         description: "User's full name"
     )

 EXAMPLE 2: Enum values

     enum UploadKind: String, CaseIterable {
         case resume, artifact, portfolio
     }

     let uploadTypeSchema = SchemaGenerator.enumSchema(
         UploadKind.self,
         description: "Type of upload expected"
     )

 EXAMPLE 3: Array of strings

     let tagsSchema = SchemaGenerator.array(
         of: SchemaGenerator.string(),
         description: "List of tags"
     )

 EXAMPLE 4: Complex object using builder pattern

     let uploadSchema = SchemaBuilder()
         .object(description: "File upload request")
         .property("upload_type", SchemaGenerator.string(description: "Upload category"), required: true)
         .property("prompt_to_user", SchemaGenerator.string(description: "Instructions for user"), required: true)
         .property("allowed_types", SchemaGenerator.array(of: SchemaGenerator.string(), description: "Allowed extensions"))
         .property("allow_multiple", SchemaGenerator.boolean(description: "Allow multiple files"))
         .build()

 EXAMPLE 5: Object with explicit required fields

     let cardSchema = SchemaGenerator.object(
         description: "Timeline card entry",
         properties: [
             "title": SchemaGenerator.string(description: "Position title"),
             "organization": SchemaGenerator.string(description: "Company name"),
             "start": SchemaGenerator.string(description: "Start date"),
             "end": SchemaGenerator.string(description: "End date or 'Present'"),
             "location": SchemaGenerator.string(description: "City, State")
         ],
         required: ["title", "organization", "start"]
     )

 EXAMPLE 6: Reusing existing schema definitions

     // Define reusable components
     let artifactIdSchema = SchemaGenerator.string(
         description: "Unique artifact identifier"
     )

     let metadataSchema = SchemaGenerator.object(
         description: "Metadata updates",
         properties: [:],  // Allow any properties
         required: []
     )

     // Compose into tool schema
     let toolSchema = SchemaGenerator.object(
         description: "Update artifact metadata",
         properties: [
             "artifact_id": artifactIdSchema,
             "metadata_updates": metadataSchema
         ],
         required: ["artifact_id", "metadata_updates"]
     )

 EXAMPLE 7: Optional fields (union with null)

     let optionalEmailSchema = SchemaGenerator.optional(
         SchemaGenerator.string(description: "Email address")
     )
     // Results in: type: ["string", "null"]
 */
