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
                description: "Structured payload shown in the validation UI. Populate this with the fields the user should confirm. For applicant profiles, include basics/location/profiles and omit hidden helper fields (e.g. contact suggestions).",
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
    var description: String {
        "Present a structured payload to the user for confirmation. Call this after you have finished populating the `data` object for the specified `dataType`. The tool opens the validation UI, collects either an approval or requested edits, and returns a structured result. When the user still needs to act, the tool responds with a waiting status so you can resume later. Applicant profile payloads that already include `meta.validation_state == \"user_validated\"` are auto-approved and returned immediately."
    }
    var parameters: JSONSchema { Self.schema }

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        var normalizedParams = params

        let rawType = normalizedParams["dataType"].stringValue
        let canonicalType = rawType
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if normalizedParams["data"] == .null {
            let attempts = await service.registerMissingValidationPayload(for: canonicalType)
            if attempts <= 2 {
                throw ToolError.invalidParameters("missing data payload for \(canonicalType)")
            }

            if let fallback = await service.fallbackValidationPayload(for: canonicalType) {
                normalizedParams["data"] = fallback
                if canonicalType == "applicant_profile" {
                    let existingMessage = normalizedParams["message"].string
                    let fallbackNotice = "Auto-filled from cached applicant profile after repeated missing payloads."
                    normalizedParams["message"].string = [existingMessage, fallbackNotice]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n\n")
                }
                await service.resetValidationRetry(for: canonicalType)
                Logger.warning("⚠️ submit_for_validation falling back to cached \(canonicalType) data after \(attempts) attempts.", category: .ai)
            } else {
                throw ToolError.executionFailed("No cached payload available for \(canonicalType).")
            }
        } else {
            await service.resetValidationRetry(for: canonicalType)
        }

        let payload = try ValidationPayload(json: normalizedParams)

        if payload.isApplicantProfile,
           payload.payload["meta"]["validation_state"].stringValue.lowercased() != "user_validated" {
            await service.recordObjective(
                "contact_data_collected",
                status: .inProgress,
                source: "llm_proposed"
            )
        }

        if payload.isApplicantProfile,
           payload.payload["meta"]["validation_state"].stringValue.lowercased() == "user_validated" {
            await service.resetValidationRetry(for: canonicalType)
            let sanitizedData = ApplicantProfileDraft.removeHiddenEmailOptions(from: payload.payload)
            await service.persistApplicantProfile(sanitizedData)

            var response = JSON()
            response["status"].string = "approved"
            response["message"].string = "Validated data automatically approved."
            response["data"] = sanitizedData

            var meta = JSON()
            meta["reason"].string = "already_validated"
            meta["validated_via"] = payload.payload["meta"]["validated_via"]
            meta["validated_at"] = payload.payload["meta"]["validated_at"]
            response["metadata"] = meta

            await service.recordObjective(
                "contact_data_validated",
                status: .completed,
                source: "auto_validator",
                details: ["reason": "already_validated"]
            )

            Logger.info("✅ Auto-approved applicant profile validation (already validated).", category: .ai)
            return .immediate(response)
        }

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

        var waitingPayload = JSON()
        waitingPayload["status"].string = "waiting"
        waitingPayload["tool"].string = name
        waitingPayload["data_type"].string = payload.canonicalType
        waitingPayload["message"].string = payload.waitingMessage
        waitingPayload["validation_state"].string = payload.payload["meta"]["validation_state"].string

        let token = ContinuationToken(
            id: tokenId,
            toolName: name,
            initialPayload: waitingPayload,
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
                    response["data"] = ApplicantProfileDraft.removeHiddenEmailOptions(from: input["data"])
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
