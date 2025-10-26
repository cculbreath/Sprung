//
//  SubmitForValidationTool.swift
//  Sprung
//
//  Displays collected data for user review and captures their decision.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct SubmitForValidationTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "dataType": JSONSchema(
                type: .string,
                description: "Type of data being validated. e.g. applicantProfile, experience, education, knowledgeCard."
            ),
            "data": JSONSchema(
                type: .object,
                description: "The data object to display to the user for validation.",
                additionalProperties: true
            ),
            "message": JSONSchema(
                type: .string,
                description: "Optional context message for the user."
            )
        ]

        return JSONSchema(
            type: .object,
            description: "Parameters for the submit_for_validation tool.",
            properties: properties,
            required: ["dataType", "data"],
            additionalProperties: false
        )
    }()

    private let service: OnboardingInterviewService
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var name: String { "submit_for_validation" }
    var description: String { "Display collected data to the user for review, capturing approval or requested changes." }
    var parameters: JSONSchema { Self.schema }

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        let payload = try ValidationPayload(json: params)
        let tokenId = UUID()

        if payload.isApplicantProfile {
            await service.presentApplicantProfileRequest(
                payload.toApplicantProfileRequest(),
                continuationId: tokenId
            )
        } else {
            await service.presentValidationPrompt(
                prompt: payload.toValidationPrompt(),
                continuationId: tokenId
            )
        }

        let token = ContinuationToken(
            id: tokenId,
            toolName: name,
            resumeHandler: { input in
                if payload.isApplicantProfile {
                    await service.clearApplicantProfileRequest(continuationId: tokenId)
                } else {
                    await service.clearValidationPrompt(continuationId: tokenId)
                }

                if input["cancelled"].boolValue {
                    return .error(.userCancelled)
                }

                guard let status = input["status"].string, !status.isEmpty else {
                    return .error(.invalidParameters("Validation response requires a status value."))
                }

                var response = JSON()
                response["status"].string = status

                if input["data"] != .null {
                    response["data"] = input["data"]
                }

                if input["changes"] != .null {
                    response["changes"] = input["changes"]
                }

                if let notes = input["userNotes"].string, !notes.isEmpty {
                    response["userNotes"].string = notes
                }

                response["timestamp"].string = dateFormatter.string(from: Date())
                return .immediate(response)
            }
        )

        return .waiting(message: payload.waitingMessage, continuation: token)
    }
}

private struct ValidationPayload {
    let dataType: String
    let canonicalType: String
    let payload: JSON
    let message: String?
    let sources: [String]
    let waitingMessage: String

    var normalizedType: String {
        canonicalType
    }

    var isApplicantProfile: Bool {
        normalizedType == "applicant_profile"
    }

    init(json: JSON) throws {
        guard let dataType = json["dataType"].string, !dataType.isEmpty else {
            throw ToolError.invalidParameters("dataType must be a non-empty string")
        }
        let data = json["data"]
        guard data != .null else {
            throw ToolError.invalidParameters("data must be an object containing the payload to review")
        }

        let normalizedType = dataType.lowercased().replacingOccurrences(of: " ", with: "_")
        self.dataType = dataType
        self.canonicalType = normalizedType.replacingOccurrences(of: "-", with: "_")
        self.payload = data
        self.message = json["message"].string
        self.sources = (json["sources"].array ?? data["sources"].array ?? [])
            .compactMap { $0.string }

        if self.canonicalType == "applicant_profile" {
            waitingMessage = "Waiting for applicant profile review"
        } else if let message, !message.isEmpty {
            waitingMessage = "Waiting for user review: \(message)"
        } else {
            waitingMessage = "Awaiting user validation review"
        }
    }

    func toValidationPrompt() -> OnboardingValidationPrompt {
        OnboardingValidationPrompt(dataType: canonicalType, payload: payload, message: message)
    }

    func toApplicantProfileRequest() -> OnboardingApplicantProfileRequest {
        OnboardingApplicantProfileRequest(proposedProfile: payload, sources: sources)
    }
}
