import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ValidateApplicantProfileTool: InterviewTool {
    private static let schema: JSONSchema = {
        let metaProperties: [String: JSONSchema] = [
            "validation_state": JSONSchema(type: .string, description: "Validation status (set to user_validated once confirmed)."),
            "validated_via": JSONSchema(type: .string, description: "Source that confirmed the data, e.g. contacts, manual, validation_card."),
            "validated_at": JSONSchema(type: .string, description: "ISO8601 timestamp for when validation occurred.")
        ]

        let properties: [String: JSONSchema] = [
            "name": JSONSchema(type: .string, description: "Full name exactly as it should appear."),
            "meta": JSONSchema(
                type: .object,
                description: "Validation metadata supplied by the coordinator. If validation_state == user_validated, the tool will auto-approve.",
                properties: metaProperties,
                additionalProperties: true
            )
        ]

        let description = """
        Applicant profile payload awaiting human confirmation. Include any collected fields (email, phone, location, profiles, etc.) in the top-level object alongside `name`. Do not call this tool when `meta.validation_state == "user_validated"`—the coordinator already confirmed those details and will reject duplicate reviews.
        """

        return JSONSchema(
            type: .object,
            description: description,
            properties: properties,
            required: ["name"],
            additionalProperties: true
        )
    }()

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "validate_applicant_profile" }
    var description: String {
        "Confirm the applicant's contact details with the user in the dedicated reviewer. Use this only when the coordinator indicates the data still needs review. If `meta.validation_state == \"user_validated\"`, skip this tool—the coordinator already saved the data; acknowledge and proceed."
    }
    var parameters: JSONSchema { Self.schema }
    var isStrict: Bool { false }

    func execute(_ params: JSON) async throws -> ToolResult {
        let draft = ApplicantProfileDraft(json: params)
        var sanitized = draft.toSafeJSON()
        if params["meta"] != .null {
            sanitized["meta"] = params["meta"]
        }
        let sources = params["sources"].arrayValue.compactMap { $0.string }
        let intakeChannel = params["mode"].string ?? sources.first ?? "intake"

        if sanitized["meta"]["validation_state"].stringValue.lowercased() == "user_validated" {
            let enriched = Self.attachValidationMeta(to: sanitized, via: intakeChannel)
            await service.persistApplicantProfile(enriched)
            var response = JSON()
            response["status"].string = "approved"
            response["data"] = enriched
            return .immediate(response)
        }

        let continuationId = UUID()
        await service.presentApplicantProfileRequest(
            OnboardingApplicantProfileRequest(proposedProfile: sanitized, sources: sources),
            continuationId: continuationId
        )

        let token = ContinuationToken(
            id: continuationId,
            toolName: name,
            initialPayload: JSON([
                "status": "waiting",
                "tool": name,
                "message": "Awaiting applicant profile confirmation"
            ]),
            resumeHandler: { input in
                await service.clearApplicantProfileRequest(continuationId: continuationId)

                if input["cancelled"].boolValue {
                    return .error(.userCancelled)
                }

                guard let status = input["status"].string, !status.isEmpty else {
                    return .error(.invalidParameters("Validation response requires a status value."))
                }

                var response = JSON()
                response["status"].string = status

                if input["data"] != .null {
                    let cleaned = ApplicantProfileDraft.removeHiddenEmailOptions(from: input["data"])
                    response["data"] = Self.attachValidationMeta(to: cleaned, via: "validation_card")
                }

                if let notes = input["userNotes"].string, !notes.isEmpty {
                    response["userNotes"].string = notes
                }

                response["timestamp"].string = ISO8601DateFormatter().string(from: Date())
                return .immediate(response)
            }
        )

        return .waiting(message: "Awaiting applicant profile review", continuation: token)
    }
}

private extension ValidateApplicantProfileTool {
    static func attachValidationMeta(to json: JSON, via channel: String) -> JSON {
        var enriched = json
        let formatter = ISO8601DateFormatter()
        if enriched["meta"] == .null {
            enriched["meta"] = JSON()
        }
        enriched["meta"]["validation_state"].string = "user_validated"
        if !channel.isEmpty {
            enriched["meta"]["validated_via"].string = channel
        }
        if enriched["meta"]["validated_at"].stringValue.isEmpty {
            enriched["meta"]["validated_at"].string = formatter.string(from: Date())
        }
        return enriched
    }
}
