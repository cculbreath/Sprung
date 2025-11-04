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
            description: "Request one or more files from the user.",
            properties: [
                "upload_type": JSONSchema(
                    type: .string,
                    description: "Expected file category (resume, coverletter, portfolio, transcript, certificate, other)."
                ),
                "title": JSONSchema(
                    type: .string,
                    description: "Optional custom title for the upload card (e.g., 'Upload Photo'). If not provided, a title will be auto-generated from upload_type."
                ),
                "prompt_to_user": JSONSchema(
                    type: .string,
                    description: "Instructions to display alongside the upload UI."
                ),
                "allowed_types": JSONSchema(
                    type: .array,
                    description: "Allowed file extensions (without dot).",
                    items: JSONSchema(type: .string),
                    additionalProperties: false
                ),
                "allow_multiple": JSONSchema(
                    type: .boolean,
                    description: "Allow selecting multiple files in one submission."
                ),
                "allow_url": JSONSchema(
                    type: .boolean,
                    description: "Allow the user to provide a URL instead of uploading a file."
                ),
                "target_key": JSONSchema(
                    type: .string,
                    description: "Optional JSON Resume key path this upload should populate (e.g., basics.image)."
                ),
                "cancel_message": JSONSchema(
                    type: .string,
                    description: "Optional message the assistant should send if the upload is dismissed without files."
                )
            ],
            required: ["prompt_to_user"],
            additionalProperties: false
        )
    }()

    private let service: OnboardingInterviewService
    private let storage = OnboardingUploadStorage()

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "get_user_upload" }
    var description: String { "Present a file picker to collect resume or supporting documents from the user." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let requestPayload = try UploadRequestPayload(json: params)
        let requestId = UUID()
        let continuationId = UUID()

        let uploadRequest = OnboardingUploadRequest(
            id: requestId,
            kind: requestPayload.kind,
            metadata: requestPayload.metadata
        )

        var waitingPayload = JSON()
        waitingPayload["status"].string = "waiting"
        waitingPayload["tool"].string = name
        waitingPayload["message"].string = requestPayload.waitingMessage
        waitingPayload["upload_kind"].string = requestPayload.kind.rawValue
        waitingPayload["cancel_tool"].string = "cancel_user_upload"
        if let targetKey = requestPayload.targetKey {
            waitingPayload["target_key"].string = targetKey
        }
        if let cancelMessage = requestPayload.metadata.cancelMessage {
            waitingPayload["cancel_message"].string = cancelMessage
        }

        let token = ContinuationToken(
            id: continuationId,
            toolName: name,
            initialPayload: waitingPayload,
            uiRequest: .uploadRequest(uploadRequest),
            resumeHandler: { input in
                do {
                    let userResponse = try UploadUserResponse(json: input)

                    switch userResponse.status {
                    case .skipped:
                        var response = JSON()
                        response["status"].string = "skipped"
                        response["uploads"] = JSON([])
                        if let target = userResponse.targetKey {
                            response["targetKey"].string = target
                        }
                        return .immediate(response)
                    case .uploaded(let files):
                        let processed = try files.map { try storage.processFile(at: $0) }
                        let uploadsJSON = processed.map { $0.toJSON() }
                        var response = JSON()
                        response["status"].string = "uploaded"
                        response["uploads"] = JSON(uploadsJSON)
                        if let target = userResponse.targetKey {
                            response["targetKey"].string = target
                        }
                        return .immediate(response)
                    case .failed(let message):
                        return .error(.executionFailed(message))
                    }
                } catch {
                    return .error(.executionFailed("Upload failed: \(error.localizedDescription)"))
                }
            }
        )

        return .waiting(message: requestPayload.waitingMessage, continuation: token)
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
