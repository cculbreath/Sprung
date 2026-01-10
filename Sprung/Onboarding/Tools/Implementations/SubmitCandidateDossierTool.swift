//
//  SubmitCandidateDossierTool.swift
//  Sprung
//
//  Submit the finalized candidate dossier with explicit schema validation.
//  Auto-generates dossier_id and timestamps.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct SubmitCandidateDossierTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties = MiscSchemas.candidateDossierProperties()

        return JSONSchema(
            type: .object,
            description: """
                Submit the finalized candidate dossier capturing qualitative context behind the job search.

                The dossier complements structured facts (experience, education, skills) with:
                - Motivations, constraints, and preferences
                - Strategic positioning insights
                - Job fit assessment criteria

                The tool auto-generates dossier_id and timestamps. Only jobSearchContext is required;
                include other fields based on what was gathered during the interview.

                IMPORTANT: Keep prose concise and factual. Avoid medical/health details unless
                the candidate volunteered them. Write in professional, neutral tone.
                """,
            properties: properties,
            required: ["jobSearchContext"],
            additionalProperties: false
        )
    }()

    private let eventBus: EventCoordinator
    private let dataStore: InterviewDataStore

    var name: String { OnboardingToolName.submitCandidateDossier.rawValue }
    var description: String {
        """
        Submit the finalized candidate dossier. Only jobSearchContext is required.
        Auto-generates dossier_id and timestamps. Include strengthsToEmphasize and
        pitfallsToAvoid for strategic positioning guidance.
        """
    }
    var parameters: JSONSchema { Self.schema }

    init(eventBus: EventCoordinator, dataStore: InterviewDataStore) {
        self.eventBus = eventBus
        self.dataStore = dataStore
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Validate required field (camelCase to match schema)
        let jobSearchContext = try ToolResultHelpers.requireString(
            params["jobSearchContext"].string,
            named: "jobSearchContext"
        )

        // Build dossier with auto-generated fields
        let dossierId = "doss_\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter().string(from: Date())

        var dossier = JSON()
        dossier["dossier_id"].string = dossierId
        dossier["created_at"].string = now
        dossier["updated_at"].string = now

        // Required field (output uses snake_case for downstream consumers)
        dossier["job_search_context"].string = jobSearchContext

        // Optional fields - read camelCase from params, write snake_case to output
        if let value = params["workArrangementPreferences"].string, !value.isEmpty {
            dossier["work_arrangement_preferences"].string = value
        }
        if let value = params["availability"].string, !value.isEmpty {
            dossier["availability"].string = value
        }
        if let value = params["uniqueCircumstances"].string, !value.isEmpty {
            dossier["unique_circumstances"].string = value
        }
        if let value = params["strengthsToEmphasize"].string, !value.isEmpty {
            dossier["strengths_to_emphasize"].string = value
        }
        if let value = params["pitfallsToAvoid"].string, !value.isEmpty {
            dossier["pitfalls_to_avoid"].string = value
        }
        if let value = params["notes"].string, !value.isEmpty {
            dossier["notes"].string = value
        }

        // Persist to data store
        do {
            let identifier = try await dataStore.persist(dataType: "candidate_dossier", payload: dossier)

            // Emit event for downstream handling
            await eventBus.publish(.artifact(.candidateDossierPersisted(dossier: dossier)))
            Logger.info("📋 Candidate dossier persisted: \(dossierId)", category: .ai)

            // Mark all Phase 4 synthesis objectives as completed
            // Submitting the dossier represents completion of strategic synthesis work
            await eventBus.publish(.objective(.statusUpdateRequested(
                id: OnboardingObjectiveId.strengthsIdentified.rawValue,
                status: "completed",
                source: "tool_execution",
                notes: "Strategic synthesis complete via dossier submission",
                details: nil
            )))
            await eventBus.publish(.objective(.statusUpdateRequested(
                id: OnboardingObjectiveId.pitfallsDocumented.rawValue,
                status: "completed",
                source: "tool_execution",
                notes: "Strategic synthesis complete via dossier submission",
                details: nil
            )))
            // Mark dossier objective as completed so subphase can advance
            await eventBus.publish(.objective(.statusUpdateRequested(
                id: OnboardingObjectiveId.dossierComplete.rawValue,
                status: "completed",
                source: "tool_execution",
                notes: "Candidate dossier persisted",
                details: nil
            )))

            // Force user review via submit_for_validation
            var devPayload = JSON()
            devPayload["title"].string = "Review Candidate Dossier"
            var details = JSON()
            details["instruction"].string = """
                Next, call submit_for_validation with validation_type=\"candidate_dossier\" and a short summary. \
                If the user rejects or requests changes, revise and re-run submit_candidate_dossier before proceeding.
                """
            devPayload["details"] = details
            await eventBus.publish(.llm(.sendCoordinatorMessage(payload: devPayload)))

            // Build response
            var response = JSON()
            response["status"].string = "completed"
            response["dossier_id"].string = dossierId
            response["persisted_id"].string = identifier

            // List which fields were included (report camelCase names as sent by LLM)
            var includedFields: [String] = ["jobSearchContext"]
            if dossier["work_arrangement_preferences"].exists() { includedFields.append("workArrangementPreferences") }
            if dossier["availability"].exists() { includedFields.append("availability") }
            if dossier["unique_circumstances"].exists() { includedFields.append("uniqueCircumstances") }
            if dossier["strengths_to_emphasize"].exists() { includedFields.append("strengthsToEmphasize") }
            if dossier["pitfalls_to_avoid"].exists() { includedFields.append("pitfallsToAvoid") }
            if dossier["notes"].exists() { includedFields.append("notes") }

            response["fields_included"].arrayObject = includedFields

            return .immediate(response)
        } catch {
            return ToolResultHelpers.executionFailed("Failed to persist dossier: \(error.localizedDescription)")
        }
    }
}
