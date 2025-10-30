import Foundation
import SwiftyJSON

struct DeveloperMessageTemplates {
    struct Message {
        let title: String
        let details: [String: String]
        let payload: JSON?
    }

    static func contactIntakeCompleted(source: String, note: String, payload: JSON) -> Message {
        let title = "Applicant profile intake complete. \(note) Coordinator has already persisted these details; skip submit_for_validation/persist_data and avoid re-asking unless new info arrives. Move to the next objective."
        let details: [String: String] = [
            "source": source,
            "validation_state": payload["meta"]["validation_state"].stringValue,
            "validated_via": payload["meta"]["validated_via"].stringValue
        ]
        return Message(title: title, details: details, payload: payload)
    }

    static func contactURLSubmitted(mode: String, status: String, url: String, payload: JSON) -> Message {
        let title = "Applicant profile intake: user supplied profile URL. Data still requires parsing and validation."
        let details: [String: String] = [
            "mode": mode,
            "status": status,
            "url": url
        ]
        return Message(title: title, details: details, payload: payload)
    }

    static func contactValidation(status: String, extraDetails: [String: String], payload: JSON?) -> Message {
        var details = extraDetails
        details["status"] = status
        if let payload = payload {
            if let validationState = payload["meta"]["validation_state"].string {
                details["validation_state"] = validationState
            }
            if let validatedVia = payload["meta"]["validated_via"].string {
                details["validated_via"] = validatedVia
            }
        }
        var title = "Applicant profile validation update."
        if let validationState = payload?["meta"]["validation_state"].string,
           validationState.lowercased() == "user_validated" {
            title += " Data already confirmed by the user; do not prompt for additional approval unless new information is introduced."
        }
        return Message(title: title, details: details, payload: payload)
    }

    static func uploadStatus(status: String, kind: String?, targetKey: String?, payload: JSON?) -> Message {
        var details: [String: String] = ["status": status]
        if let kind {
            details["kind"] = kind
        }
        if let targetKey {
            details["target_key"] = targetKey
        }
        if let error = payload?["error"].string {
            details["error"] = error
        }

        let title: String
        switch status {
        case "uploaded":
            title = "Upload completed. Await downstream processing before validation."
        case "skipped":
            title = "Upload skipped by user."
        case "failed":
            title = "Upload failed."
        default:
            title = "Upload update."
        }

        return Message(title: title, details: details, payload: payload)
    }

    static func profilePersisted(payload: JSON) -> Message {
        Message(
            title: "Applicant profile persisted to local store.",
            details: ["status": "saved"],
            payload: payload
        )
    }

    static func profileUnchanged(payload: JSON) -> Message {
        Message(
            title: "Applicant profile already persisted. Coordinator retains the existing record.",
            details: ["status": "unchanged"],
            payload: payload
        )
    }
}
