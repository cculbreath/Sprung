//
//  GetUserUploadTool.swift
//  Sprung
//
//  Presents a file upload request to the user and returns stored artifacts
//  along with naive text extraction.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI
import UniformTypeIdentifiers

struct GetUserUploadTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Request one or more files from the user.",
            properties: [
                "uploadType": JSONSchema(
                    type: .string,
                    description: "Expected file category.",
                    enum: ["resume", "coverletter", "portfolio", "transcript", "certificate", "other"]
                ),
                "prompt": JSONSchema(
                    type: .string,
                    description: "Instructions to display alongside the file picker."
                ),
                "acceptedFormats": JSONSchema(
                    type: .array,
                    description: "Allowed file extensions (without dot).",
                    items: JSONSchema(type: .string),
                    additionalProperties: false
                )
            ],
            required: ["uploadType"],
            additionalProperties: false
        )
    }()

    private let service: OnboardingInterviewService
    private let storage = UploadStorage()

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

        await service.presentUploadRequest(
            OnboardingUploadRequest(
                id: requestId,
                kind: requestPayload.kind,
                metadata: requestPayload.metadata
            ),
            continuationId: continuationId
        )

        let token = ContinuationToken(
            id: continuationId,
            toolName: name,
            resumeHandler: { input in
                do {
                    let userResponse = try UploadUserResponse(json: input)

                    switch userResponse.status {
                    case .skipped:
                        var response = JSON()
                        response["status"].string = "skipped"
                        response["uploads"] = JSON([])
                        return .immediate(response)
                    case .uploaded(let files):
                        let processed = try files.map { try storage.processFile(at: $0) }
                        let uploadsJSON = processed.map { $0.toJSON() }
                        var response = JSON()
                        response["status"].string = "uploaded"
                        response["uploads"] = JSON(uploadsJSON)
                        return .immediate(response)
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

    init(json: JSON) throws {
        guard let rawType = json["uploadType"].string else {
            throw ToolError.invalidParameters("uploadType must be provided for get_user_upload tool.")
        }

        let normalizedType = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let kind = OnboardingUploadKind.allCases.first(where: { $0.rawValue.lowercased() == normalizedType }) else {
            let options = OnboardingUploadKind.allCases.map { $0.rawValue }.joined(separator: ", ")
            throw ToolError.invalidParameters("uploadType must be one of: \(options)")
        }
        self.kind = kind

        let prompt = json["prompt"].string ?? UploadRequestPayload.defaultPrompt(for: kind)
        let formats = (json["acceptedFormats"].arrayObject as? [String]) ?? ["pdf", "docx", "txt", "md"]
        let normalized = formats.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        self.metadata = OnboardingUploadMetadata(
            title: UploadRequestPayload.title(for: kind),
            instructions: prompt,
            accepts: normalized,
            allowMultiple: kind != .resume
        )

        self.waitingMessage = "Waiting for user to upload: \(prompt)"
    }

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
    }

    let status: Status

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
        default:
            throw ToolError.invalidParameters("Unknown upload status: \(status)")
        }
    }
}

// MARK: - Storage & Extraction

private struct ProcessedUpload {
    let id: String
    let filename: String
    let storageURL: URL
    let extractedText: String

    func toJSON() -> JSON {
        var json = JSON()
        json["id"].string = id
        json["filename"].string = filename
        json["storageUrl"].string = storageURL.absoluteString
        json["extractedText"].string = extractedText
        return json
    }
}

private struct UploadStorage {
    private let uploadsDirectory: URL
    private let fileManager = FileManager.default

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Onboarding/Uploads", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                debugLog("Failed to create uploads directory: \(error)")
            }
        }
        uploadsDirectory = directory
    }

    func processFile(at sourceURL: URL) throws -> ProcessedUpload {
        let identifier = UUID().uuidString
        let destinationFilename = "\(identifier)_\(sourceURL.lastPathComponent)"
        let destinationURL = uploadsDirectory.appendingPathComponent(destinationFilename)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw ToolError.executionFailed("Failed to store uploaded file: \(error.localizedDescription)")
        }

        let extractedText = extractText(from: destinationURL) ?? ""

        return ProcessedUpload(
            id: identifier,
            filename: sourceURL.lastPathComponent,
            storageURL: destinationURL,
            extractedText: extractedText
        )
    }

    private func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        if let type = UTType(filenameExtension: ext), type.conforms(to: .plainText) || type.conforms(to: .text) {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        // Fall back to naive UTF-8 decode for other formats; may fail silently.
        if let data = try? Data(contentsOf: url), let string = String(data: data, encoding: .utf8) {
            return string
        }

        return nil
    }
}
