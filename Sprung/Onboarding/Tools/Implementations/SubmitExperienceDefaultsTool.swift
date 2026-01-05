//
//  SubmitExperienceDefaultsTool.swift
//  Sprung
//
//  Submit structured resume defaults based on user's enabled sections.
//  Only processes sections that were enabled in Phase 1.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct SubmitExperienceDefaultsTool: InterviewTool {
    private static let baseSchema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "professional_summary": MiscSchemas.professionalSummary,
            "work": MiscSchemas.workArray,
            "education": MiscSchemas.educationArray,
            "projects": MiscSchemas.projectsArray,
            "skills": MiscSchemas.skillsArray,
            "languages": MiscSchemas.languagesArray,
            "volunteer": MiscSchemas.volunteerArray,
            "awards": MiscSchemas.awardsArray,
            "certificates": MiscSchemas.certificatesArray,
            "publications": MiscSchemas.publicationsArray
        ]

        return JSONSchema(
            type: .object,
            description: """
                Submit structured resume defaults to populate the Experience Editor.

                IMPORTANT: Only include sections that were enabled by the user in Phase 1 (via configure_enabled_sections).
                The tool will automatically filter out any sections that weren't enabled.

                Base entries on the skeleton timeline from Phase 1, enriched with details from Phase 2 knowledge cards.
                Include quantified achievements and specific technologies where available.

                Custom fields: If the user defined custom fields during section configuration, include them as
                additional properties with keys matching the field key (e.g., "custom.objective"). Generate content
                based on the field's description. Custom field descriptions will be provided in the tool response
                after the first call attempt, or check enabled sections configuration.
                """,
            properties: properties,
            required: [],  // All sections optional - tool validates against enabled sections
            additionalProperties: true  // Allow custom.* fields
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator
    private let eventBus: EventCoordinator
    private let dataStore: InterviewDataStore

    var name: String { OnboardingToolName.submitExperienceDefaults.rawValue }
    var description: String {
        """
        Submit resume defaults for the Experience Editor. Only include sections enabled in Phase 1.
        The tool validates against user's section choices and filters accordingly.
        Custom fields (e.g., custom.objective) can be included if defined during section configuration.
        Required BEFORE calling next_phase to complete the interview.
        """
    }
    var parameters: JSONSchema { Self.baseSchema }

    init(coordinator: OnboardingInterviewCoordinator, eventBus: EventCoordinator, dataStore: InterviewDataStore) {
        self.coordinator = coordinator
        self.eventBus = eventBus
        self.dataStore = dataStore
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Get user's enabled sections from Phase 1
        let enabledSections = await coordinator.state.getEnabledSections()
        // Get custom field definitions
        let customFieldDefinitions = await coordinator.state.getCustomFieldDefinitions()

        if enabledSections.isEmpty {
            Logger.warning("⚠️ No enabled sections found - using all submitted sections", category: .ai)
        }

        // Build filtered payload with only enabled sections
        var filteredPayload = JSON()
        var includedSections: [String] = []
        var skippedSections: [String] = []

        // Map of JSON keys to section keys
        let sectionMapping: [(jsonKey: String, sectionKey: String)] = [
            ("work", "work"),
            ("education", "education"),
            ("projects", "projects"),
            ("skills", "skills"),
            ("languages", "languages"),
            ("volunteer", "volunteer"),
            ("awards", "awards"),
            ("certificates", "certificates"),
            ("publications", "publications")
        ]

        for (jsonKey, sectionKey) in sectionMapping {
            if let array = params[jsonKey].array, !array.isEmpty {
                // Include if enabled or if no sections were configured (fallback)
                if enabledSections.isEmpty || enabledSections.contains(sectionKey) {
                    filteredPayload[jsonKey] = params[jsonKey]
                    includedSections.append(sectionKey)
                } else {
                    skippedSections.append(sectionKey)
                }
            }
        }

        // Handle professional_summary - include in filteredPayload for ExperienceDefaults
        var summarySaved = false
        if let professionalSummary = params["professional_summary"].string,
           !professionalSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filteredPayload["professional_summary"].string = professionalSummary
            summarySaved = true
            Logger.info("📝 Professional summary included in experience defaults", category: .ai)
        }

        // Handle custom fields (keys starting with "custom.")
        var customFieldsSaved: [String] = []
        var missingCustomFields: [CustomFieldDefinition] = []

        for definition in customFieldDefinitions {
            if let value = params[definition.key].string, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                filteredPayload[definition.key].string = value
                customFieldsSaved.append(definition.key)
                Logger.info("📝 Custom field '\(definition.key)' included in experience defaults", category: .ai)
            } else {
                missingCustomFields.append(definition)
            }
        }

        // Check if we have any data to persist
        guard !includedSections.isEmpty || summarySaved || !customFieldsSaved.isEmpty else {
            // If custom fields are defined but missing, guide the LLM to include them
            if !customFieldDefinitions.isEmpty {
                var response = JSON()
                response["status"].string = "incomplete"
                response["error"].string = "No section data provided and custom fields are missing"
                response["required_custom_fields"] = JSON(customFieldDefinitions.map { definition in
                    ["key": definition.key, "description": definition.description]
                })
                response["hint"].string = "Include the required custom fields with content based on their descriptions"
                return .immediate(response)
            }
            return .error(.executionFailed(
                "No valid section data provided. Include at least one enabled section: \(enabledSections.sorted().joined(separator: ", "))"
            ))
        }

        // Log what was included/skipped
        Logger.info("📋 Experience defaults - included: \(includedSections.joined(separator: ", "))", category: .ai)
        if !skippedSections.isEmpty {
            Logger.info("📋 Experience defaults - skipped (not enabled): \(skippedSections.joined(separator: ", "))", category: .ai)
        }

        // Emit event to populate ExperienceDefaultsStore
        await eventBus.publish(.experienceDefaultsGenerated(defaults: filteredPayload))

        // Persist for phase completion gating (NextPhaseTool checks InterviewDataStore)
        // Keep the persisted payload small: enabled sections only + professional_summary.
        do {
            let persistedId = try await dataStore.persist(dataType: "experience_defaults", payload: filteredPayload)
            Logger.info("💾 Persisted experience_defaults for phase completion (\(persistedId))", category: .ai)

            // Mark objective as completed so subphase can advance to p4_completion
            await eventBus.publish(.objectiveStatusUpdateRequested(
                id: OnboardingObjectiveId.experienceDefaultsSet.rawValue,
                status: "completed",
                source: "tool_execution",
                notes: "Experience defaults persisted",
                details: nil
            ))
        } catch {
            Logger.error("❌ Failed to persist experience_defaults: \(error.localizedDescription)", category: .ai)
            return .error(.executionFailed("Failed to persist experience_defaults required for completion: \(error.localizedDescription)"))
        }

        // Mandate an explicit user review of experience defaults via submit_for_validation.
        // We force the next continuation (tool_response) to call submit_for_validation.
        // submit_for_validation will auto-fetch current experience defaults from the store.
        var devPayload = JSON()
        devPayload["title"].string = "Review Experience Defaults"
        devPayload["toolChoice"].string = OnboardingToolName.submitForValidation.rawValue
        var details = JSON()
        details["instruction"].string = """
            Next, call submit_for_validation with validation_type=\"experience_defaults\" and a short summary. \
            You may pass an empty data object; the tool will auto-fetch current experience defaults. \
            If the user rejects or requests changes, revise and re-run submit_experience_defaults before proceeding.
            """
        devPayload["details"] = details
        await coordinator.eventBus.publish(.llmSendDeveloperMessage(payload: devPayload))

        // Build response
        var response = JSON()
        response["status"].string = "completed"
        response["sections_saved"].arrayObject = includedSections
        response["professional_summary_saved"].bool = summarySaved
        if !skippedSections.isEmpty {
            response["sections_skipped"].arrayObject = skippedSections
            response["skipped_reason"].string = "Not in user's enabled sections from Phase 1"
        }

        // Include custom field status
        if !customFieldsSaved.isEmpty {
            response["custom_fields_saved"].arrayObject = customFieldsSaved
        }
        if !missingCustomFields.isEmpty {
            response["custom_fields_missing"] = JSON(missingCustomFields.map { definition in
                ["key": definition.key, "description": definition.description]
            })
            response["custom_fields_hint"].string = "Consider re-submitting with the missing custom fields included"
        }

        return .immediate(response)
    }
}
