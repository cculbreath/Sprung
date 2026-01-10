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
    // MARK: - Field Validation Constants

    /// Minimum character counts for substantive fields
    private enum FieldMinimums {
        static let jobSearchContext = 200
        static let strengthsToEmphasize = 500
        static let pitfallsToAvoid = 500
        static let notes = 200
    }

    private static let schema: JSONSchema = {
        let properties = MiscSchemas.candidateDossierProperties()

        return JSONSchema(
            type: .object,
            description: """
                Submit the finalized candidate dossier capturing qualitative context behind the job search.

                The dossier complements structured facts (experience, education, skills) with:
                - Motivations, constraints, and preferences
                - Strategic positioning insights (strengths with evidence, pitfalls with mitigations)
                - Job fit assessment criteria

                FIELD REQUIREMENTS:
                - jobSearchContext: REQUIRED, minimum \(FieldMinimums.jobSearchContext) chars
                - strengthsToEmphasize: Recommended, minimum \(FieldMinimums.strengthsToEmphasize) chars (2-4 paragraphs with evidence)
                - pitfallsToAvoid: Recommended, minimum \(FieldMinimums.pitfallsToAvoid) chars (2-4 pitfalls with mitigations)
                - notes: Optional, minimum \(FieldMinimums.notes) chars if provided

                IMPORTANT: This dossier will guide job fit assessment and networking. Provide substantial,
                actionable content. A useful dossier is typically 1,500+ words total.
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
        Submit the finalized candidate dossier. jobSearchContext is required (min \(FieldMinimums.jobSearchContext) chars).
        Include strengthsToEmphasize (min \(FieldMinimums.strengthsToEmphasize) chars) and pitfallsToAvoid (min \(FieldMinimums.pitfallsToAvoid) chars)
        for strategic positioning guidance. Target 1,500+ total words for a useful dossier.
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

        // Validate minimum lengths and collect errors
        var validationErrors: [String] = []
        var validationWarnings: [String] = []

        // Required field validation
        if jobSearchContext.count < FieldMinimums.jobSearchContext {
            validationErrors.append(
                "jobSearchContext is too short (\(jobSearchContext.count) chars). " +
                "Minimum \(FieldMinimums.jobSearchContext) chars required for useful job search context."
            )
        }

        // Get optional fields (accept both schema names and LLM abbreviations)
        let strengthsValue = params["strengthsToEmphasize"].string ?? params["strengths"].string
        let pitfallsValue = params["pitfallsToAvoid"].string ?? params["pitfalls"].string
        let notesValue = params["notes"].string

        // Validate optional fields if provided
        if let strengths = strengthsValue, !strengths.isEmpty {
            if strengths.count < FieldMinimums.strengthsToEmphasize {
                validationWarnings.append(
                    "strengthsToEmphasize is short (\(strengths.count) chars). " +
                    "Recommend \(FieldMinimums.strengthsToEmphasize)+ chars with evidence and positioning guidance."
                )
            }
        } else {
            validationWarnings.append(
                "strengthsToEmphasize not provided. This field helps identify hidden strengths for strategic positioning."
            )
        }

        if let pitfalls = pitfallsValue, !pitfalls.isEmpty {
            if pitfalls.count < FieldMinimums.pitfallsToAvoid {
                validationWarnings.append(
                    "pitfallsToAvoid is short (\(pitfalls.count) chars). " +
                    "Recommend \(FieldMinimums.pitfallsToAvoid)+ chars with specific mitigations for each pitfall."
                )
            }
        } else {
            validationWarnings.append(
                "pitfallsToAvoid not provided. This field helps prepare for interview questions about concerns."
            )
        }

        if let notes = notesValue, !notes.isEmpty, notes.count < FieldMinimums.notes {
            validationWarnings.append(
                "notes is short (\(notes.count) chars). Consider adding deal-breakers, cultural fit indicators, and communication style observations."
            )
        }

        // Return error if required fields don't meet minimums
        if !validationErrors.isEmpty {
            let errorMessage = "Dossier validation failed:\n" + validationErrors.joined(separator: "\n")
            Logger.warning("⚠️ Dossier rejected: \(errorMessage)", category: .ai)
            return ToolResultHelpers.executionFailed(errorMessage)
        }

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
        // Note: LLM sometimes abbreviates key names, so we accept both variants
        if let value = params["workArrangementPreferences"].string, !value.isEmpty {
            dossier["work_arrangement_preferences"].string = value
        }
        if let value = params["availability"].string, !value.isEmpty {
            dossier["availability"].string = value
        }
        if let value = params["uniqueCircumstances"].string, !value.isEmpty {
            dossier["unique_circumstances"].string = value
        }
        // Accept both "strengthsToEmphasize" (schema) and "strengths" (LLM abbreviation)
        if let value = params["strengthsToEmphasize"].string ?? params["strengths"].string, !value.isEmpty {
            dossier["strengths_to_emphasize"].string = value
        }
        // Accept both "pitfallsToAvoid" (schema) and "pitfalls" (LLM abbreviation)
        if let value = params["pitfallsToAvoid"].string ?? params["pitfalls"].string, !value.isEmpty {
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

            // Calculate total word count for quality logging
            let allContent = [
                jobSearchContext,
                strengthsValue ?? "",
                pitfallsValue ?? "",
                params["workArrangementPreferences"].string ?? "",
                params["availability"].string ?? "",
                params["uniqueCircumstances"].string ?? "",
                notesValue ?? ""
            ].joined(separator: " ")
            let wordCount = allContent.split(separator: " ").count
            Logger.info("📋 Dossier word count: \(wordCount) words", category: .ai)

            // Build response
            var response = JSON()
            response["status"].string = "completed"
            response["dossier_id"].string = dossierId
            response["persisted_id"].string = identifier
            response["word_count"].int = wordCount

            // List which fields were included (report camelCase names as sent by LLM)
            var includedFields: [String] = ["jobSearchContext"]
            if dossier["work_arrangement_preferences"].exists() { includedFields.append("workArrangementPreferences") }
            if dossier["availability"].exists() { includedFields.append("availability") }
            if dossier["unique_circumstances"].exists() { includedFields.append("uniqueCircumstances") }
            if dossier["strengths_to_emphasize"].exists() { includedFields.append("strengthsToEmphasize") }
            if dossier["pitfalls_to_avoid"].exists() { includedFields.append("pitfallsToAvoid") }
            if dossier["notes"].exists() { includedFields.append("notes") }

            response["fields_included"].arrayObject = includedFields

            // Include validation warnings if any
            if !validationWarnings.isEmpty {
                response["warnings"].arrayObject = validationWarnings
                Logger.warning("⚠️ Dossier accepted with warnings: \(validationWarnings.count) issues", category: .ai)
            }

            return .immediate(response)
        } catch {
            return ToolResultHelpers.executionFailed("Failed to persist dossier: \(error.localizedDescription)")
        }
    }
}
