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
    private static let schema: JSONSchema = {
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
                """,
            properties: properties,
            required: [],  // All sections optional - tool validates against enabled sections
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator
    private let eventBus: EventCoordinator

    var name: String { OnboardingToolName.submitExperienceDefaults.rawValue }
    var description: String {
        """
        Submit resume defaults for the Experience Editor. Only include sections enabled in Phase 1.
        The tool validates against user's section choices and filters accordingly.
        Required BEFORE calling next_phase to complete the interview.
        """
    }
    var parameters: JSONSchema { Self.schema }

    init(coordinator: OnboardingInterviewCoordinator, eventBus: EventCoordinator) {
        self.coordinator = coordinator
        self.eventBus = eventBus
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Get user's enabled sections from Phase 1
        let enabledSections = await coordinator.state.getEnabledSections()

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

        // Check if we have any data to persist
        guard !includedSections.isEmpty || summarySaved else {
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

        // Build response
        var response = JSON()
        response["status"].string = "completed"
        response["sections_saved"].arrayObject = includedSections
        response["professional_summary_saved"].bool = summarySaved
        if !skippedSections.isEmpty {
            response["sections_skipped"].arrayObject = skippedSections
            response["skipped_reason"].string = "Not in user's enabled sections from Phase 1"
        }

        return .immediate(response)
    }
}
