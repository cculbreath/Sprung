//
//  SubmitDossierTool.swift
//  Sprung
//
//  Validation tool for the candidate dossier. Called after all sections are
//  completed via complete_dossier_section to validate completeness and finalize.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct SubmitDossierTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Validate and finalize the candidate dossier. Call this after completing all required
                sections via complete_dossier_section.

                PREREQUISITE: All required sections must be complete:
                - job_context (200+ chars)
                - strengths (500+ chars)
                - pitfalls (500+ chars)

                If any required sections are missing or below minimum length, this tool will
                return an error with the specific missing sections.

                On success, marks dossier_complete objective as completed and emits the
                candidateDossierPersisted artifact event.
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }()

    private let eventBus: EventCoordinator
    private let candidateDossierStore: CandidateDossierStore

    var name: String { OnboardingToolName.submitDossier.rawValue }
    var description: String {
        """
        Validate and finalize the candidate dossier. Call after all sections are complete.
        Returns error if required sections (job_context, strengths, pitfalls) are missing or too short.
        """
    }
    var parameters: JSONSchema { Self.schema }

    init(eventBus: EventCoordinator, candidateDossierStore: CandidateDossierStore) {
        self.eventBus = eventBus
        self.candidateDossierStore = candidateDossierStore
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Check if dossier exists
        guard let dossier = await MainActor.run(body: { candidateDossierStore.dossier }) else {
            return ToolResultHelpers.executionFailed(
                "No dossier found. Use complete_dossier_section to add content first."
            )
        }

        // Check for missing required sections
        let missingSections = await MainActor.run { candidateDossierStore.missingSections() }
        if !missingSections.isEmpty {
            let missing = missingSections.map { section in
                "\(section.rawValue) (min \(section.minimumLength) chars)"
            }.joined(separator: ", ")
            return ToolResultHelpers.executionFailed(
                "Dossier incomplete. Missing required sections: \(missing). " +
                "Use complete_dossier_section to add each missing section."
            )
        }

        // Validate content quality (warnings only, don't block)
        var warnings: [String] = []
        if dossier.wordCount < 500 {
            warnings.append("Dossier is brief (\(dossier.wordCount) words). Target 1,500+ words for comprehensive guidance.")
        }

        Logger.info("📋 Candidate dossier validated: \(dossier.wordCount) words", category: .ai)

        // Emit artifact event
        var eventPayload = JSON()
        eventPayload["dossierId"].string = dossier.id.uuidString
        await eventBus.publish(.artifact(.candidateDossierPersisted(dossier: eventPayload)))

        // Mark dossier_complete objective as completed
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.dossierComplete.rawValue,
            status: "completed",
            source: "tool_execution",
            notes: "Candidate dossier validated and finalized",
            details: nil
        )))

        // Send coordinator message for next step
        var devPayload = JSON()
        devPayload["title"].string = "Dossier Complete"
        var details = JSON()
        details["instruction"].string = """
            Dossier finalized! Interview is nearly complete.

            Summarize what was accomplished in the interview:
            - Voice primers extracted from writing samples
            - Knowledge cards generated from evidence
            - Strategic dossier with strengths and pitfall mitigations
            - Skeleton timeline established

            Explain next steps (Seed Generation will create resume content, then resume
            customization for job applications, cover letter generation, job tracking).

            Call next_phase to complete the onboarding interview.
            """
        devPayload["details"] = details
        await eventBus.publish(.llm(.sendCoordinatorMessage(payload: devPayload)))

        // Build response
        var response = JSON()
        response["status"].string = "validated"
        response["dossierId"].string = dossier.id.uuidString
        response["wordCount"].int = dossier.wordCount

        let completedSections = await MainActor.run { candidateDossierStore.completedSections() }
        response["sections"].arrayObject = completedSections.map { $0.rawValue }

        if !warnings.isEmpty {
            response["warnings"].arrayObject = warnings
        }

        response["message"].string = "Dossier validated and finalized. Summarize and call next_phase to complete interview."

        return .immediate(response)
    }
}
