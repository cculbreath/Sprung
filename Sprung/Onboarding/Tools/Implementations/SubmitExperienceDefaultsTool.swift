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
        // Work experience schema
        let workItemSchema = JSONSchema(
            type: .object,
            description: "A work experience entry",
            properties: [
                "name": JSONSchema(type: .string, description: "Company/organization name"),
                "position": JSONSchema(type: .string, description: "Job title"),
                "location": JSONSchema(type: .string, description: "City, State"),
                "url": JSONSchema(type: .string, description: "Company website (optional)"),
                "startDate": JSONSchema(type: .string, description: "Start date (YYYY-MM format)"),
                "endDate": JSONSchema(type: .string, description: "End date (YYYY-MM or 'Present')"),
                "summary": JSONSchema(type: .string, description: "Brief role description"),
                "highlights": JSONSchema(type: .array, description: "Achievement bullets (3-5 recommended)", items: JSONSchema(type: .string))
            ],
            required: ["name", "position", "startDate", "endDate"]
        )

        // Education schema
        let educationItemSchema = JSONSchema(
            type: .object,
            description: "An education entry",
            properties: [
                "institution": JSONSchema(type: .string, description: "School/university name"),
                "area": JSONSchema(type: .string, description: "Field of study"),
                "studyType": JSONSchema(type: .string, description: "Degree type (e.g., 'Ph.D.', 'Bachelor of Science')"),
                "startDate": JSONSchema(type: .string, description: "Start year (YYYY)"),
                "endDate": JSONSchema(type: .string, description: "End year (YYYY)"),
                "score": JSONSchema(type: .string, description: "GPA if relevant (optional)"),
                "courses": JSONSchema(type: .array, description: "Notable courses (optional)", items: JSONSchema(type: .string))
            ],
            required: ["institution", "area", "studyType", "startDate", "endDate"]
        )

        // Project schema
        let projectItemSchema = JSONSchema(
            type: .object,
            description: "A project entry",
            properties: [
                "name": JSONSchema(type: .string, description: "Project name"),
                "description": JSONSchema(type: .string, description: "What the project does"),
                "startDate": JSONSchema(type: .string, description: "Start date (YYYY-MM)"),
                "endDate": JSONSchema(type: .string, description: "End date (YYYY-MM or 'Present')"),
                "url": JSONSchema(type: .string, description: "Project URL (optional)"),
                "organization": JSONSchema(type: .string, description: "Associated organization (optional)"),
                "highlights": JSONSchema(type: .array, description: "Key accomplishments", items: JSONSchema(type: .string)),
                "keywords": JSONSchema(type: .array, description: "Technologies used", items: JSONSchema(type: .string))
            ],
            required: ["name", "description"]
        )

        // Skills schema
        let skillItemSchema = JSONSchema(
            type: .object,
            description: "A skill category",
            properties: [
                "name": JSONSchema(type: .string, description: "Skill category name (e.g., 'Software Development')"),
                "level": JSONSchema(type: .string, description: "Proficiency level (Expert/Advanced/Intermediate)"),
                "keywords": JSONSchema(type: .array, description: "Specific technologies/skills", items: JSONSchema(type: .string))
            ],
            required: ["name", "keywords"]
        )

        // Languages schema
        let languageItemSchema = JSONSchema(
            type: .object,
            description: "A language entry",
            properties: [
                "language": JSONSchema(type: .string, description: "Language name"),
                "fluency": JSONSchema(type: .string, description: "Fluency level (Native/Fluent/Professional/Conversational)")
            ],
            required: ["language", "fluency"]
        )

        // Volunteer schema
        let volunteerItemSchema = JSONSchema(
            type: .object,
            description: "A volunteer experience entry",
            properties: [
                "organization": JSONSchema(type: .string, description: "Organization name"),
                "position": JSONSchema(type: .string, description: "Role/title"),
                "url": JSONSchema(type: .string, description: "Organization website (optional)"),
                "startDate": JSONSchema(type: .string, description: "Start date"),
                "endDate": JSONSchema(type: .string, description: "End date"),
                "summary": JSONSchema(type: .string, description: "Brief description"),
                "highlights": JSONSchema(type: .array, description: "Key contributions", items: JSONSchema(type: .string))
            ],
            required: ["organization", "position"]
        )

        // Awards schema
        let awardItemSchema = JSONSchema(
            type: .object,
            description: "An award entry",
            properties: [
                "title": JSONSchema(type: .string, description: "Award name"),
                "date": JSONSchema(type: .string, description: "Date received"),
                "awarder": JSONSchema(type: .string, description: "Awarding organization"),
                "summary": JSONSchema(type: .string, description: "Brief description (optional)")
            ],
            required: ["title", "awarder"]
        )

        // Certificates schema
        let certificateItemSchema = JSONSchema(
            type: .object,
            description: "A certificate entry",
            properties: [
                "name": JSONSchema(type: .string, description: "Certificate name"),
                "date": JSONSchema(type: .string, description: "Date earned"),
                "issuer": JSONSchema(type: .string, description: "Issuing organization"),
                "url": JSONSchema(type: .string, description: "Verification URL (optional)")
            ],
            required: ["name", "issuer"]
        )

        // Publications schema
        let publicationItemSchema = JSONSchema(
            type: .object,
            description: "A publication entry",
            properties: [
                "name": JSONSchema(type: .string, description: "Publication title"),
                "publisher": JSONSchema(type: .string, description: "Publisher/journal name"),
                "releaseDate": JSONSchema(type: .string, description: "Publication date"),
                "url": JSONSchema(type: .string, description: "URL to publication (optional)"),
                "summary": JSONSchema(type: .string, description: "Brief description (optional)")
            ],
            required: ["name", "publisher"]
        )

        let properties: [String: JSONSchema] = [
            "professional_summary": JSONSchema(
                type: .string,
                description: """
                    A 2-4 sentence professional summary highlighting the candidate's key strengths,
                    experience level, and career focus. This will be saved to Experience Defaults
                    for use in resume headers and cover letter introductions.
                    Example: "Senior software engineer with 8+ years building scalable distributed systems.
                    Proven track record leading cross-functional teams and delivering high-impact products.
                    Passionate about developer experience and engineering excellence."
                    """
            ),
            "work": JSONSchema(type: .array, description: "Work experience entries (only if 'work' section enabled)", items: workItemSchema),
            "education": JSONSchema(type: .array, description: "Education entries (only if 'education' section enabled)", items: educationItemSchema),
            "projects": JSONSchema(type: .array, description: "Project entries (only if 'projects' section enabled)", items: projectItemSchema),
            "skills": JSONSchema(type: .array, description: "Skill categories (only if 'skills' section enabled)", items: skillItemSchema),
            "languages": JSONSchema(type: .array, description: "Language proficiencies (only if 'languages' section enabled)", items: languageItemSchema),
            "volunteer": JSONSchema(type: .array, description: "Volunteer experiences (only if 'volunteer' section enabled)", items: volunteerItemSchema),
            "awards": JSONSchema(type: .array, description: "Awards received (only if 'awards' section enabled)", items: awardItemSchema),
            "certificates": JSONSchema(type: .array, description: "Professional certificates (only if 'certificates' section enabled)", items: certificateItemSchema),
            "publications": JSONSchema(type: .array, description: "Publications (only if 'publications' section enabled)", items: publicationItemSchema)
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
