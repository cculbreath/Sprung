//
//  GetUserUploadTool.swift
//  Sprung
//
//  Presents a file upload request to the user and returns stored artifacts
//  plus basic metadata. Text extraction happens via the extract_document tool.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetUserUploadTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Present an upload card in the tool pane to request files or URLs from the user.

                Users can upload files directly or paste URLs. Uploaded files are automatically processed - text is extracted and packaged as ArtifactRecords.

                RETURNS: { "message": "UI presented. Awaiting user input.", "status": "completed" }

                The tool completes immediately after presenting UI. User uploads arrive as new user messages with artifact metadata.

                USAGE: Use during skeleton_timeline to gather resume/LinkedIn/transcripts, or for profile photos. Always set target_phase_objectives to help route artifacts to correct workflow stages.

                WORKFLOW:
                1. Call get_user_upload with appropriate prompt
                2. Tool returns immediately - card is now active in tool pane
                3. User uploads file(s) or pastes URL
                4. System extracts text and creates ArtifactRecord(s)
                5. You receive artifact notification and can process contents

                ERROR: Will fail if prompt_to_user is empty or upload_type is invalid.
                """,
            properties: [
                "upload_type": JSONSchema(
                    type: .string,
                    description: "Expected file category. Valid types: resume, artifact, coverletter, portfolio, transcript, certificate, writingSample, generic, linkedIn",
                    enum: ["resume", "artifact", "coverletter", "portfolio", "transcript", "certificate", "writingSample", "generic", "linkedIn"]
                ),
                "title": JSONSchema(
                    type: .string,
                    description: "Optional custom title for the upload card (e.g., 'Upload Photo'). If omitted, auto-generated from upload_type."
                ),
                "prompt_to_user": JSONSchema(
                    type: .string,
                    description: "Instructions shown to user in upload card UI. Required. Be specific about what you're requesting."
                ),
                "allowed_types": JSONSchema(
                    type: .array,
                    description: "Allowed file extensions without dots (e.g., ['pdf', 'docx', 'jpg']). Defaults: pdf, txt, rtf, doc, docx, jpg, jpeg, png, gif, md, html, htm",
                    items: JSONSchema(type: .string),
                    additionalProperties: false
                ),
                "allow_multiple": JSONSchema(
                    type: .boolean,
                    description: "Allow selecting multiple files in one upload. Defaults to true except for resume uploads."
                ),
                "allow_url": JSONSchema(
                    type: .boolean,
                    description: "Allow user to paste URL instead of uploading file. Defaults to true."
                ),
                "target_key": JSONSchema(
                    type: .string,
                    description: "JSON Resume key path this upload should populate (e.g., 'basics.image'). Currently only 'basics.image' is supported.",
                    enum: ["basics.image"]
                ),
                "cancel_message": JSONSchema(
                    type: .string,
                    description: "Optional message to send if user dismisses upload card without providing files."
                )
            ],
            required: ["prompt_to_user"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator
    private let storage = OnboardingUploadStorage()

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "get_user_upload" }
    var description: String { "Present upload card for files/URLs. Returns immediately - uploads arrive as artifacts. Use for resume, LinkedIn, transcripts, photos." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let requestPayload = try UploadRequestPayload(json: params)
        let requestId = UUID()

        let uploadRequest = OnboardingUploadRequest(
            id: requestId,
            kind: requestPayload.kind,
            metadata: requestPayload.metadata
        )

        // Emit UI request to show the upload picker
        await coordinator.eventBus.publish(.uploadRequestPresented(request: uploadRequest))

        // Return completed - the tool's job is to present UI, which it has done
        // User's upload will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"

        return .immediate(response)
    }
}


// MARK: - Payload Parsing

private struct UploadRequestPayload {
    let kind: OnboardingUploadKind
    let metadata: OnboardingUploadMetadata
    let waitingMessage: String
    let targetKey: String?
    let cancelMessage: String?

    init(json: JSON) throws {
        if let rawType = json["upload_type"].string {
            let normalizedType = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let parsedKind = OnboardingUploadKind.allCases.first(where: { $0.rawValue.lowercased() == normalizedType }) else {
                let options = OnboardingUploadKind.allCases.map { $0.rawValue }.joined(separator: ", ")
                throw ToolError.invalidParameters("upload_type must be one of: \(options)")
            }
            kind = parsedKind
        } else {
            kind = .generic
        }

        guard let prompt = json["prompt_to_user"].string?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else {
            throw ToolError.invalidParameters("prompt_to_user must be provided and non-empty.")
        }

        let formats = (json["allowed_types"].arrayObject as? [String]) ?? ["pdf", "txt", "rtf", "doc", "docx", "jpg", "jpeg", "png", "gif", "md", "html", "htm"]
        let normalized = formats.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let allowMultiple = json["allow_multiple"].bool ?? (kind != .resume)
        let allowURL = json["allow_url"].bool ?? true
        if let cancel = json["cancel_message"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cancel.isEmpty {
            cancelMessage = cancel
        } else {
            cancelMessage = nil
        }

        if let target = json["target_key"].string?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty {
            guard UploadRequestPayload.allowedTargetKeys.contains(target) else {
                throw ToolError.invalidParameters("Unsupported target_key: \(target)")
            }
            targetKey = target
        } else {
            targetKey = nil
        }

        // Use custom title if provided, otherwise generate from kind
        let cardTitle: String
        if let customTitle = json["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customTitle.isEmpty {
            cardTitle = customTitle
        } else {
            cardTitle = UploadRequestPayload.title(for: kind)
        }

        self.metadata = OnboardingUploadMetadata(
            title: cardTitle,
            instructions: prompt,
            accepts: normalized,
            allowMultiple: allowMultiple,
            allowURL: allowURL,
            targetKey: targetKey,
            cancelMessage: cancelMessage
        )

        self.waitingMessage = "Waiting for user to upload: \(prompt)"
    }

    private static let allowedTargetKeys: Set<String> = ["basics.image"]

    private static func title(for kind: OnboardingUploadKind) -> String {
        switch kind {
        case .resume:
            return "Upload Resume"
        case .artifact:
            return "Upload Artifact"
        case .coverletter:
            return "Upload Cover Letter"
        case .portfolio:
            return "Upload Portfolio Artifact"
        case .transcript:
            return "Upload Transcript"
        case .certificate:
            return "Upload Certificate"
        case .writingSample:
            return "Upload Writing Sample"
        case .generic:
            return "Upload File"
        case .linkedIn:
            return "Upload LinkedIn Export"
        }
    }

    private static func defaultPrompt(for kind: OnboardingUploadKind) -> String {
        switch kind {
        case .resume:
            return "Please upload your most recent resume."
        case .artifact:
            return "Upload relevant supporting artifacts."
        case .coverletter:
            return "Upload a relevant cover letter (optional)."
        case .portfolio:
            return "Provide supporting portfolio material."
        case .transcript:
            return "Upload an unofficial transcript."
        case .certificate:
            return "Upload a professional certificate."
        case .writingSample:
            return "Upload a writing sample."
        case .generic:
            return "Provide the requested file."
        case .linkedIn:
            return "Upload your latest LinkedIn export or resume."
        }
    }
}

private struct UploadUserResponse {
    enum Status {
        case skipped
        case uploaded([URL])
        case failed(String)
    }

    let status: Status
    let targetKey: String?

    init(json: JSON) throws {
        guard let status = json["status"].string else {
            throw ToolError.invalidParameters("Missing status in upload response.")
        }

        switch status {
        case "skipped":
            self.status = .skipped
        case "uploaded":
            let filesJSON = json["files"].array ?? []
            let urls: [URL] = try filesJSON.map { item in
                guard let urlString = item["url"].string,
                      let url = URL(string: urlString) else {
                    throw ToolError.invalidParameters("Invalid file URL supplied by UI.")
                }
                return url
            }
            guard !urls.isEmpty else {
                throw ToolError.invalidParameters("Uploaded status requires at least one file.")
            }
            self.status = .uploaded(urls)
        case "failed":
            let message = json["error"].string ?? "Upload failed"
            self.status = .failed(message)
        default:
            throw ToolError.invalidParameters("Unknown upload status: \(status)")
        }

        if let target = json["targetKey"].string, !target.isEmpty {
            targetKey = target
        } else {
            targetKey = nil
        }
    }
}

// MARK: - Storage & Extraction

// Upload storage helper moved to shared utility file.
