//
//  UserInteractionSchemas.swift
//  Sprung
//
//  Shared JSON schema definitions for user interaction tools.
//  DRY: Used by GetUserUploadTool, GetUserOptionTool, CancelUserUploadTool, and OpenDocumentCollectionTool.
//
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Shared schema definitions for user interaction tool fields
enum UserInteractionSchemas {
    // MARK: - Upload Tool Schemas

    /// Schema for uploadType field
    static let uploadType = JSONSchema(
        type: .string,
        description: "Expected file category. Valid types: resume, artifact, coverletter, portfolio, transcript, certificate, writingSample, generic, linkedIn",
        enum: ["resume", "artifact", "coverletter", "portfolio", "transcript", "certificate", "writingSample", "generic", "linkedIn"]
    )

    /// Schema for title field (upload card title)
    static let uploadTitle = JSONSchema(
        type: .string,
        description: "Optional custom title for the upload card (e.g., 'Upload Photo'). If omitted, auto-generated from uploadType."
    )

    /// Schema for promptToUser field
    static let promptToUser = JSONSchema(
        type: .string,
        description: "Instructions shown to user in upload card UI. Required. Be specific about what you're requesting."
    )

    /// Schema for allowedTypes field
    static let allowedTypes = JSONSchema(
        type: .array,
        description: "Allowed file extensions without dots (e.g., ['pdf', 'docx', 'jpg']). Defaults: pdf, txt, rtf, doc, docx, jpg, jpeg, png, gif, md, html, htm",
        items: JSONSchema(type: .string),
        additionalProperties: false
    )

    /// Schema for allowMultiple field
    static let allowMultiple = JSONSchema(
        type: .boolean,
        description: "Allow selecting multiple files in one upload. Defaults to true except for resume uploads."
    )

    /// Schema for allowUrl field
    static let allowUrl = JSONSchema(
        type: .boolean,
        description: "Allow user to paste URL instead of uploading file. Defaults to true."
    )

    /// Schema for targetKey field
    static let targetKey = JSONSchema(
        type: .string,
        description: "JSON Resume key path this upload should populate (e.g., 'basics.image'). Currently only 'basics.image' is supported.",
        enum: ["basics.image"]
    )

    /// Schema for cancelMessage field
    static let cancelMessage = JSONSchema(
        type: .string,
        description: "Optional message to send if user dismisses upload card without providing files."
    )

    // MARK: - Option Tool Schemas

    /// Schema for a single option object
    static let optionObject: JSONSchema = {
        let optionProperties: [String: JSONSchema] = [
            "id": JSONSchema(type: .string, description: "Stable identifier for the option"),
            "label": JSONSchema(type: .string, description: "Display label for the option"),
            "description": JSONSchema(type: .string, description: "Optional detailed description"),
            "icon": JSONSchema(type: .string, description: "Optional system icon name")
        ]
        return JSONSchema(
            type: .object,
            description: "Single selectable option",
            properties: optionProperties,
            required: ["id", "label"],
            additionalProperties: false
        )
    }()

    /// Schema for prompt field (option prompt)
    static let optionPrompt = JSONSchema(
        type: .string,
        description: "Question or instruction to display"
    )

    /// Schema for options array
    static let optionsArray = JSONSchema(
        type: .array,
        description: "Array of available options",
        items: optionObject,
        required: nil,
        additionalProperties: false
    )

    /// Schema for allowMultiple field (option selection)
    static let allowMultipleOptions = JSONSchema(
        type: .boolean,
        description: "Allow selecting multiple options"
    )

    /// Schema for required field (option selection)
    static let requiredSelection = JSONSchema(
        type: .boolean,
        description: "Is selection required to continue"
    )

    // MARK: - Cancel Upload Schemas

    /// Schema for reason field (cancel reason)
    static let cancelReason = JSONSchema(
        type: .string,
        description: "Optional explanation for why upload is being cancelled (for logging/debugging)."
    )

    // MARK: - Document Collection Schemas

    /// Schema for message field (document collection)
    static let documentCollectionMessage = JSONSchema(
        type: .string,
        description: "Optional message to display to the user (e.g., suggestions for document types)"
    )

    /// Schema for suggestedDocTypes field
    static let suggestedDocTypes = JSONSchema(
        type: .array,
        description: "List of suggested document types for the user to upload (shown as tags)",
        items: JSONSchema(type: .string)
    )

    // MARK: - Evidence Request Schemas

    /// Schema for timelineEntryId field (evidence request)
    static let timelineEntryId = JSONSchema(
        type: .string,
        description: "ID of the timeline entry this evidence relates to."
    )

    /// Schema for evidence description field
    static let evidenceDescription = JSONSchema(
        type: .string,
        description: "Clear description of what evidence is needed (e.g., 'Upload your PhD dissertation PDF')."
    )

    /// Schema for evidence category field
    static let evidenceCategory = JSONSchema(
        type: .string,
        description: "Type of evidence: 'paper', 'code', 'website', 'portfolio', 'degree', or 'other'.",
        enum: MiscSchemas.evidenceCategories
    )
}
