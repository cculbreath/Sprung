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
            description: "Retrieve full artifact with extracted_text content. Use artifact_id from list_artifacts.",
            properties: [
                "artifact_id": artifactId
            ],
            required: ["artifact_id"],
            additionalProperties: false
        )
    }

    /// Complete schema for list_artifacts tool
    static var listArtifacts: JSONSchema {
        JSONSchema(
            type: .object,
            description: "List all artifacts with summary metadata (id, filename, content_type). Use get_artifact for full content.",
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }

    /// Complete schema for update_artifact_metadata tool
    static var updateArtifactMetadata: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Update metadata fields on an artifact record. Performs field-level merge (adds/updates specified fields without removing others).",
            properties: [
                "artifact_id": artifactId,
                "metadata_updates": metadataUpdates
            ],
            required: ["artifact_id", "metadata_updates"],
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
