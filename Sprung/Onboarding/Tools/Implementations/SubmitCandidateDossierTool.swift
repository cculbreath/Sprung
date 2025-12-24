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

                The tool auto-generates dossier_id and timestamps. Only job_search_context is required;
                include other fields based on what was gathered during the interview.

                IMPORTANT: Keep prose concise and factual. Avoid medical/health details unless
                the candidate volunteered them. Write in professional, neutral tone.
                """,
            properties: properties,
            required: ["job_search_context"],
            additionalProperties: false
        )
    }()

    private let eventBus: EventCoordinator
    private let dataStore: InterviewDataStore

    var name: String { OnboardingToolName.submitCandidateDossier.rawValue }
    var description: String {
        """
        Submit the finalized candidate dossier. Only job_search_context is required.
        Auto-generates dossier_id and timestamps. Include strengths_to_emphasize and
        pitfalls_to_avoid for strategic positioning guidance.
        """
    }
    var parameters: JSONSchema { Self.schema }

    init(eventBus: EventCoordinator, dataStore: InterviewDataStore) {
        self.eventBus = eventBus
        self.dataStore = dataStore
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Validate required field
        let jobSearchContext = try ToolResultHelpers.requireString(
            params["job_search_context"].string,
            named: "job_search_context"
        )

        // Build dossier with auto-generated fields
        let dossierId = "doss_\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter().string(from: Date())

        var dossier = JSON()
        dossier["dossier_id"].string = dossierId
        dossier["created_at"].string = now
        dossier["updated_at"].string = now

        // Required field
        dossier["job_search_context"].string = jobSearchContext

        // Optional fields - only include if provided
        if let value = params["work_arrangement_preferences"].string, !value.isEmpty {
            dossier["work_arrangement_preferences"].string = value
        }
        if let value = params["availability"].string, !value.isEmpty {
            dossier["availability"].string = value
        }
        if let value = params["unique_circumstances"].string, !value.isEmpty {
            dossier["unique_circumstances"].string = value
        }
        if let value = params["strengths_to_emphasize"].string, !value.isEmpty {
            dossier["strengths_to_emphasize"].string = value
        }
        if let value = params["pitfalls_to_avoid"].string, !value.isEmpty {
            dossier["pitfalls_to_avoid"].string = value
        }
        if let value = params["notes"].string, !value.isEmpty {
            dossier["notes"].string = value
        }

        // Persist to data store
        do {
            let identifier = try await dataStore.persist(dataType: "candidate_dossier", payload: dossier)

            // Emit event for downstream handling
            await eventBus.publish(.candidateDossierPersisted(dossier: dossier))
            Logger.info("📋 Candidate dossier persisted: \(dossierId)", category: .ai)

            // Build response
            var response = JSON()
            response["status"].string = "completed"
            response["dossier_id"].string = dossierId
            response["persisted_id"].string = identifier

            // List which fields were included
            var includedFields: [String] = ["job_search_context"]
            if dossier["work_arrangement_preferences"].exists() { includedFields.append("work_arrangement_preferences") }
            if dossier["availability"].exists() { includedFields.append("availability") }
            if dossier["unique_circumstances"].exists() { includedFields.append("unique_circumstances") }
            if dossier["strengths_to_emphasize"].exists() { includedFields.append("strengths_to_emphasize") }
            if dossier["pitfalls_to_avoid"].exists() { includedFields.append("pitfalls_to_avoid") }
            if dossier["notes"].exists() { includedFields.append("notes") }

            response["fields_included"].arrayObject = includedFields

            return .immediate(response)
        } catch {
            return ToolResultHelpers.executionFailed("Failed to persist dossier: \(error.localizedDescription)")
        }
    }
}
