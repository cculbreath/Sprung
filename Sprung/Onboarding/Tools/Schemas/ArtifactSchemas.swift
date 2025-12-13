//
//  ArtifactSchemas.swift
//  Sprung
//
//  Shared JSON schema definitions for artifact-related tools.
//  DRY: Used by GetArtifactRecordTool, ListArtifactsTool, UpdateArtifactMetadataTool, and RequestRawArtifactFileTool.
//
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Shared schema definitions for artifact fields
enum ArtifactSchemas {

    // MARK: - Field Schemas

    /// Schema for artifact_id field used across multiple tools
    static var artifactId: JSONSchema {
        JSONSchema(
            type: .string,
            description: "Unique identifier of the artifact. Obtain from list_artifacts response."
        )
    }

    /// Schema for metadata_updates field in update operations
    static var metadataUpdates: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Object containing metadata fields to add or update. Each field will be merged into the artifact's metadata. Supports nested paths like 'target_phase_objectives', 'target_deliverable', 'user_validated', etc.",
            additionalProperties: true
        )
    }

    // MARK: - Tool Schemas

    /// Complete schema for get_artifact tool
    static var getArtifact: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Retrieve artifact content. Use max_chars to limit extracted_text size. Returns {artifact: {...}}.",
            properties: [
                "artifact_id": artifactId,
                "max_chars": JSONSchema(
                    type: .integer,
                    description: "Max chars for extracted_text (default: unlimited). Use 2000-5000 for bounded retrieval."
                )
            ],
            required: ["artifact_id"],
            additionalProperties: false
        )
    }

    /// Complete schema for list_artifacts tool
    static var listArtifacts: JSONSchema {
        JSONSchema(
            type: .object,
            description: "List artifacts with pagination. Default returns minimal fields. Use get_artifact for content.",
            properties: [
                "limit": JSONSchema(
                    type: .integer,
                    description: "Max items to return (default: 10, max: 50)"
                ),
                "offset": JSONSchema(
                    type: .integer,
                    description: "Skip first N items for pagination (default: 0)"
                ),
                "include_summary": JSONSchema(
                    type: .boolean,
                    description: "Include brief description/summary (default: false to reduce tokens)"
                )
            ],
            required: [],
            additionalProperties: false
        )
    }

    /// Complete schema for update_artifact_metadata tool
    static var updateArtifactMetadata: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Update metadata fields on an artifact record. Performs field-level merge.",
            properties: [
                "artifact_id": artifactId,
                "metadata_updates": metadataUpdates
            ],
            required: ["artifact_id", "metadata_updates"],
            additionalProperties: false
        )
    }

    /// Complete schema for get_context_pack tool
    static var getContextPack: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Get curated context bundle for a purpose. Single call instead of multiple retrievals.",
            properties: [
                "purpose": JSONSchema(
                    type: .string,
                    description: "Context purpose: timeline_review, artifact_overview, card_context, gap_analysis",
                    enum: ["timeline_review", "artifact_overview", "card_context", "gap_analysis"]
                ),
                "max_chars": JSONSchema(
                    type: .integer,
                    description: "Max total chars for pack (default: 3000). Includes all items."
                ),
                "card_id": JSONSchema(
                    type: .string,
                    description: "For card_context: specific card ID to get context for"
                )
            ],
            required: ["purpose"],
            additionalProperties: false
        )
    }

    /// Complete schema for request_raw_file tool
    static var requestRawFile: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Get original file URL (for images/binary files). Use get_artifact for text content instead.",
            properties: [
                "artifact_id": artifactId
            ],
            required: ["artifact_id"],
            additionalProperties: false
        )
    }
}
