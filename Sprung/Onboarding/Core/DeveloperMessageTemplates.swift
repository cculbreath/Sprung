import Foundation
import SwiftyJSON

struct DeveloperMessageTemplates {
    struct Message {
        let title: String
        let details: [String: String]
        let payload: JSON?
    }

    static func contactIntakeCompleted(source: String, note: String, payload: JSON) -> Message {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let notePrefix = trimmedNote.isEmpty ? "" : "\(trimmedNote) "
        let title = "Applicant profile intake complete. \(notePrefix)Coordinator has already persisted the applicant profile. If you present profile validation it will auto-approve. Do not re-persist the profile. Proceed to skeleton timeline."
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
        case "cancelled":
            title = "Upload cancelled by coordinator."
        case "failed":
            title = "Upload failed."
        default:
            title = "Upload update."
        }
        if let cancelReason = payload?["cancel_reason"].string, !cancelReason.isEmpty {
            details["cancel_reason"] = cancelReason
        }

        return Message(title: title, details: details, payload: payload)
    }

    static func profilePersisted(displayName: String?, payload: JSON) -> Message {
        var details: [String: String] = ["status": "saved"]
        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            details["applicant_name"] = name
        }

        let title: String
        if let name = details["applicant_name"], !name.isEmpty {
            title = "Applicant profile persisted for \(name). Let them know their details are stored for reuse and that edits stay welcome."
        } else {
            title = "Applicant profile persisted to local store. Confirm the data is reusable for resumes and invite future tweaks."
        }

        return Message(
            title: title,
            details: details,
            payload: payload
        )
    }

    static func profileUnchanged(displayName: String?, payload: JSON) -> Message {
        var details: [String: String] = ["status": "unchanged"]
        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            details["applicant_name"] = name
        }

        let title: String
        if let name = details["applicant_name"], !name.isEmpty {
            title = "Applicant profile for \(name) already persisted. Acknowledge the stored details and offer adjustments anytime."
        } else {
            title = "Applicant profile already persisted. Coordinator retains the existing record—invite updates if anything changes."
        }

        return Message(
            title: title,
            details: details,
            payload: payload
        )
    }

    static func artifactStored(artifact: JSON) -> Message {
        var details: [String: String] = [:]
        let metadata = artifact["metadata"]

        func assign(_ key: String, value: String) {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            details[key] = value
        }

        assign("artifact_id", value: artifact["id"].stringValue)
        assign("sha256", value: artifact["sha256"].stringValue)
        assign("filename", value: artifact["filename"].stringValue)
        assign("content_type", value: artifact["content_type"].stringValue)
        if let size = artifact["size_bytes"].int {
            details["size_bytes"] = "\(size)"
        }
        assign("purpose", value: metadata["purpose"].stringValue)
        assign("source", value: metadata["source"].stringValue)
        assign("source_file_url", value: metadata["source_file_url"].stringValue)
        assign("source_filename", value: metadata["source_filename"].stringValue)
        if metadata["inline_base64"].string != nil {
            details["inline_payload"] = "base64"
        }

        let title = "Artifact captured. Use list_artifacts to review stored items, get_artifact for full metadata, and request_raw_file with the recorded artifact_id when you need the native file."
        return Message(title: title, details: details, payload: artifact)
    }

    static func timelineUserEdited(diff: TimelineDiff, payload: JSON) -> Message {
        var details: [String: String] = [
            "added_count": "\(diff.added.count)",
            "removed_count": "\(diff.removed.count)",
            "updated_count": "\(diff.updated.count)",
            "reordered": diff.reordered ? "true" : "false"
        ]

        if diff.added.isEmpty == false {
            details["added_cards"] = diff.added.map(timelineCardLabel).joined(separator: " | ")
        }
        if diff.removed.isEmpty == false {
            details["removed_cards"] = diff.removed.map(timelineCardLabel).joined(separator: " | ")
        }
        if diff.updated.isEmpty == false {
            let summary = diff.updated.map { change in
                var tokens: [String] = []
                if change.fieldChanges.isEmpty == false {
                    let fieldNames = change.fieldChanges.map { $0.field }
                    tokens.append(fieldNames.joined(separator: ", "))
                }
                if let highlight = change.highlightChange, highlight.isEmpty == false {
                    tokens.append("highlights")
                }
                let descriptor = tokens.isEmpty ? "changed" : tokens.joined(separator: ", ")
                return "\(change.title) (\(descriptor))"
            }
            details["updated_cards"] = summary.joined(separator: " | ")
        }

        let title = "Timeline cards updated by the user. Treat the attached payload as user_validated; proceed to enabled_sections. Do not call submit_for_validation unless introducing new, unreviewed facts."

        if let validationState = payload["meta"]["validation_state"].string, !validationState.isEmpty {
            details["validation_state"] = validationState
        }
        if let validatedVia = payload["meta"]["validated_via"].string, !validatedVia.isEmpty {
            details["validated_via"] = validatedVia
        }

        return Message(title: title, details: details, payload: payload)
    }

    static func dossierSeedReady(payload: JSON?) -> Message {
        let title = "Enabled sections set. Seed the candidate dossier with 2–3 quick prompts about goals, motivations, and strengths. For each answer, call persist_data(dataType: 'candidate_dossier_entry', payload: {question, answer, asked_at}). Mark dossier_seed complete after at least two entries."
        let details: [String: String] = [
            "next_objective": "dossier_seed",
            "required": "false",
            "min_entries": "2"
        ]
        return Message(title: title, details: details, payload: payload)
    }

    /// Format objective status as checkbox tree for developer messages with visual hierarchy
    /// Example output:
    /// ```
    /// Phase 1 Progress:
    /// ✅ P1.1 applicant_profile
    ///   ✅ P1.1.A Contact Information
    ///     ✅ P1.1.A.1 Activate applicant profile card
    ///     ✅ P1.1.A.2 ApplicantProfile updated
    ///   ◻ P1.1.B Optional Profile Photo
    /// ◻ P1.2 skeleton_timeline
    /// ```
    static func formatObjectiveStatus(
        phase: InterviewPhase,
        objectives: [StateCoordinator.ObjectiveEntry]
    ) -> String {
        guard !objectives.isEmpty else {
            return "\(phase.description) - No objectives defined"
        }

        var lines: [String] = ["\(phase.description) Progress:"]

        for objective in objectives.sorted(by: { $0.id < $1.id }) {
            let checkbox: String
            switch objective.status {
            case .completed, .skipped:
                checkbox = "✅"
            case .inProgress:
                checkbox = "⏳"
            case .pending:
                checkbox = "◻"
            }

            // Add indentation based on hierarchy level
            let indent = String(repeating: "  ", count: objective.level)
            lines.append("\(indent)\(checkbox) \(objective.id)")
        }

        return lines.joined(separator: "\n")
    }
}

private extension DeveloperMessageTemplates {
    static func timelineCardLabel(_ card: TimelineCard) -> String {
        let trimmedTitle = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }

        let trimmedOrg = card.organization.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOrg.isEmpty { return trimmedOrg }

        return "Card \(card.id)"
    }
}
