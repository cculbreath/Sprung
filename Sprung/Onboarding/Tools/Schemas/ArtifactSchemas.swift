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
            description: """
                Retrieve complete artifact record including extracted text content and full metadata.
                Use this to access the actual content of uploaded files/URLs. The artifact contains extracted text (from PDFs, DOCX, etc.) that you can parse for interview data.
                RETURNS:
                - If found: { "artifact": { "id", "filename", "extracted_text", "content_type", "uploaded_at", "target_phase_objectives", "file_url", ... } }
                - If not found: Returns error
                USAGE: Call after list_artifacts identifies relevant artifacts. Parse extracted_text to extract ApplicantProfile, timeline entries, or other structured data.
                WORKFLOW:
                1. list_artifacts to see what's available
                2. get_artifact with specific artifact_id
                3. Parse artifact.extracted_text for relevant information
                4. Extract structured data (profile, timeline, etc.)
                5. Call validate_* or create_timeline_card with extracted data
                Common patterns:
                - Resume upload → get_artifact → extract profile + timeline skeleton
                - LinkedIn URL → get_artifact → extract profile information
                - Transcript upload → get_artifact → extract education entries
                ERROR: Returns not_found status if artifact_id doesn't exist. Use list_artifacts first to verify ID.
                """,
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
            description: """
                List all stored artifacts with summary metadata (ID, filename, upload time, content type, target objectives).
                Artifacts are created when users upload files or paste URLs via get_user_upload or get_applicant_profile. Each artifact contains extracted text and metadata.
                RETURNS: { "count": <number>, "artifacts": [{ "id", "filename", "content_type", "uploaded_at", "target_phase_objectives" }] }
                USAGE: Call to see what artifacts exist before requesting full content via get_artifact. Useful for understanding what data you have to work with, especially after user uploads.
                WORKFLOW:
                1. User uploads file(s) via get_user_upload
                2. System creates ArtifactRecord(s) with extracted text
                3. Call list_artifacts to see summary of available artifacts
                4. Use get_artifact to retrieve full content for processing
                Common use cases:
                - Check if user uploaded resume before asking for timeline details
                - Identify which artifacts are tagged for specific objectives
                - Verify artifact existence before processing
                Returns empty list if no artifacts exist yet.
                """,
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
            description: """
                Request access to the original raw file (PDF, DOCX, image, etc.) associated with an artifact.
                Most artifact processing uses extracted_text from get_artifact. Use this only when you need the original file (e.g., for profile photos, PDFs requiring special handling).
                RETURNS:
                - Success: { "status": "success", "artifact_id": "<id>", "file_url": "<url>", "filename": "...", "content_type": "...", "size_bytes": ... }
                - Not found: { "status": "not_found", "artifact_id": "<id>", "message": "No artifact found..." }
                - No file: { "status": "error", "message": "Artifact does not have an associated file URL." }
                - File deleted: { "status": "file_not_found", "file_url": "<url>", "message": "The file...no longer exists." }
                USAGE: Rarely needed in Phase 1. Most text extraction is handled automatically. Use only for:
                - Profile photos (basics.image) where you need the image file URL
                - Special cases requiring original file format
                WORKFLOW:
                1. list_artifacts or get_artifact to identify artifact
                2. request_raw_file to get original file URL
                3. Use file_url for image storage or special processing
                DO NOT: Use this for text extraction - get_artifact already provides extracted_text. This is for accessing the binary/original file only.
                """,
            properties: [
                "artifact_id": artifactId
            ],
            required: ["artifact_id"],
            additionalProperties: false
        )
    }
}
