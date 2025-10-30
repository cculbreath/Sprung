//
//  PhaseOneScript.swift
//  Sprung
//
//  Phase 1: Core Facts — Collect applicant profile and skeleton timeline.
//

import Foundation

struct PhaseOneScript: PhaseScript {
    let phase: InterviewPhase = .phase1CoreFacts

    let requiredObjectives: [String] = [
        "applicant_profile",
        "skeleton_timeline",
        "enabled_sections"
    ]

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            "contact_source_selected": ObjectiveWorkflow(
                id: "contact_source_selected",
                onComplete: { context in
                    let source = context.details["source"] ?? context.details["status"] ?? "unknown"
                    let title = "Contact source selected: \(source). Continue guiding the user through the applicant profile intake card that remains on screen."
                    let details = ["source": source, "next_objective": "contact_data_collected"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "contact_data_collected": ObjectiveWorkflow(
                id: "contact_data_collected",
                dependsOn: ["contact_source_selected"],
                onComplete: { context in
                    let mode = context.details["source"] ?? context.details["status"] ?? "unspecified"
                    let title = "Applicant contact data collected via \(mode). Await validation status before re-requesting any details."
                    let details = ["source": mode, "next_objective": "contact_data_validated"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "contact_data_validated": ObjectiveWorkflow(
                id: "contact_data_validated",
                dependsOn: ["contact_data_collected"],
                onComplete: { context in
                    let details = context.details.isEmpty ? ["source": "workflow"] : context.details
                    return [.triggerPhotoFollowUp(extraDetails: details)]
                }
            ),
            "contact_photo_collected": ObjectiveWorkflow(
                id: "contact_photo_collected",
                dependsOn: ["contact_data_validated"],
                onComplete: { context in
                    let title = "Profile photo stored successfully. Resume the Phase 1 sequence without re-requesting another upload."
                    let details = ["status": context.status.rawValue, "objective": "contact_photo_collected"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "applicant_profile": ObjectiveWorkflow(
                id: "applicant_profile",
                dependsOn: ["contact_data_validated"],
                onComplete: { context in
                    let title = "Applicant profile persisted. Move on to building the skeleton timeline next."
                    let details = ["next_objective": "skeleton_timeline", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "skeleton_timeline": ObjectiveWorkflow(
                id: "skeleton_timeline",
                dependsOn: ["applicant_profile"],
                onComplete: { context in
                    let title = "Skeleton timeline captured. Prepare the user to choose enabled résumé sections."
                    let details = ["next_objective": "enabled_sections", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "enabled_sections": ObjectiveWorkflow(
                id: "enabled_sections",
                dependsOn: ["skeleton_timeline"],
                onComplete: { context in
                    let title = "Enabled sections confirmed. When all ledger entries are clear, prompt the user to advance to Phase 2."
                    let details = ["status": context.status.rawValue, "ready_for": "next_phase"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }

    var systemPromptFragment: String {
        SystemPromptTemplates.phaseOneFragment
    }
}
