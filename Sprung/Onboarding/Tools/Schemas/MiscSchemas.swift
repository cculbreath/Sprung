//
//  MiscSchemas.swift
//  Sprung
//
//  Shared JSON schema definitions for miscellaneous onboarding tools.
//  DRY: Common schemas extracted from multiple tool implementations.
//
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Shared schema definitions for resume sections and other common structures
enum MiscSchemas {
    // MARK: - Resume Section Schemas

    /// Work experience entry schema
    static func workItemSchema() -> JSONSchema {
        JSONSchema(
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
    }

    /// Education entry schema
    static func educationItemSchema() -> JSONSchema {
        JSONSchema(
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
    }

    /// Project entry schema
    static func projectItemSchema() -> JSONSchema {
        JSONSchema(
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
    }

    /// Skills category schema
    static func skillItemSchema() -> JSONSchema {
        JSONSchema(
            type: .object,
            description: "A skill category",
            properties: [
                "name": JSONSchema(type: .string, description: "Skill category name (e.g., 'Software Development')"),
                "level": JSONSchema(type: .string, description: "Proficiency level (Expert/Advanced/Intermediate)"),
                "keywords": JSONSchema(type: .array, description: "Specific technologies/skills", items: JSONSchema(type: .string))
            ],
            required: ["name", "keywords"]
        )
    }

    /// Language proficiency schema
    static func languageItemSchema() -> JSONSchema {
        JSONSchema(
            type: .object,
            description: "A language entry",
            properties: [
                "language": JSONSchema(type: .string, description: "Language name"),
                "fluency": JSONSchema(type: .string, description: "Fluency level (Native/Fluent/Professional/Conversational)")
            ],
            required: ["language", "fluency"]
        )
    }

    /// Volunteer experience schema
    static func volunteerItemSchema() -> JSONSchema {
        JSONSchema(
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
    }

    /// Award entry schema
    static func awardItemSchema() -> JSONSchema {
        JSONSchema(
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
    }

    /// Certificate entry schema
    static func certificateItemSchema() -> JSONSchema {
        JSONSchema(
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
    }

    /// Publication entry schema
    static func publicationItemSchema() -> JSONSchema {
        JSONSchema(
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
    }

    // MARK: - Candidate Dossier Schemas

    /// Candidate dossier field schemas
    static func candidateDossierProperties() -> [String: JSONSchema] {
        [
            "job_search_context": JSONSchema(
                type: .string,
                description: """
                    REQUIRED. Why looking, what seeking, priorities, non-negotiables, ideal role attributes.
                    Include: Push factors (leaving), pull factors (seeking), top priorities ranked,
                    compensation expectations if shared. 2-6 sentences or bullets.
                    Example: "Seeking greater technical ownership and product impact; frustrated by
                    bureaucracy at current role. Priorities: 1) High autonomy 2) Small team 3) Modern stack.
                    Compensation target $160-180k base, flexible for equity upside."
                    """
            ),
            "work_arrangement_preferences": JSONSchema(
                type: .string,
                description: """
                    Remote/hybrid/onsite preferences, relocation willingness, location constraints, travel tolerance.
                    Example: "Strong preference for remote-first. Would consider hybrid 2 days/week max.
                    Based in Austin, open to relocating to SF or Seattle for Staff+ role with strong equity."
                    """
            ),
            "availability": JSONSchema(
                type: .string,
                description: """
                    Start timing window, notice period, scheduling constraints.
                    Example: "Currently employed with 2-week notice. Could start 3 weeks from offer.
                    No major timing constraints."
                    """
            ),
            "unique_circumstances": JSONSchema(
                type: .string,
                description: """
                    Context for gaps, pivots, visa status, non-compete, sabbatical, or anything unconventional.
                    Keep factual and neutral. Frame positively where possible.
                    Example: "6-month sabbatical in 2023 for open-source work and learning Rust.
                    Intentional skill investment, not unemployment."
                    """
            ),
            "strengths_to_emphasize": JSONSchema(
                type: .string,
                description: """
                    Hidden or under-emphasized strengths not obvious from resume. How to surface these.
                    Look for: cross-domain expertise, untitled leadership, rare combinations,
                    skills from unlisted experiences. 2-4 paragraphs.
                    Example: "Bridge between deep technical expertise and product thinking—highlight
                    examples where technical decisions drove user impact. Self-directed learner with
                    demonstrated follow-through (sabbatical learning, OSS contributions)."
                    """
            ),
            "pitfalls_to_avoid": JSONSchema(
                type: .string,
                description: """
                    Potential concerns, vulnerabilities, or red flags and how to address/mitigate them.
                    Include specific, actionable recommendations. 2-4 paragraphs.
                    Example: "6-month gap may raise questions—proactively label as 'sabbatical' with
                    1-liner about OSS work. Avoid sounding negative about previous employer when
                    discussing departure reasons."
                    """
            ),
            "notes": JSONSchema(
                type: .string,
                description: """
                    Private interviewer observations, impressions, strategic recommendations.
                    Not for export without consent. Include deal-breakers, cultural fit indicators,
                    communication style observations.
                    Example: "Candidate is thoughtful and self-aware. Values substance over polish.
                    Deal-breakers: full-time office, large bureaucratic orgs, purely managerial track."
                    """
            )
        ]
    }

    // MARK: - Writing Sample Schemas

    /// Writing sample type enum values
    static var writingSampleTypes: [String] {
        ["cover_letter", "email", "essay", "proposal", "report", "blog_post", "documentation", "other"]
    }

    // MARK: - Evidence Category Schemas

    /// Evidence category enum values
    static var evidenceCategories: [String] {
        ["paper", "code", "website", "portfolio", "degree", "other"]
    }

    // MARK: - Array Schemas (for section data)

    /// Work experience array schema - used by SubmitExperienceDefaultsTool and PersistDataTool
    static let workArray = JSONSchema(
        type: .array,
        description: "Work experience entries (only if 'work' section enabled)",
        items: workItemSchema()
    )

    /// Education array schema - used by SubmitExperienceDefaultsTool and PersistDataTool
    static let educationArray = JSONSchema(
        type: .array,
        description: "Education entries (only if 'education' section enabled)",
        items: educationItemSchema()
    )

    /// Projects array schema - used by SubmitExperienceDefaultsTool and PersistDataTool
    static let projectsArray = JSONSchema(
        type: .array,
        description: "Project entries (only if 'projects' section enabled)",
        items: projectItemSchema()
    )

    /// Skills array schema - used by SubmitExperienceDefaultsTool and PersistDataTool
    static let skillsArray = JSONSchema(
        type: .array,
        description: "Skill categories (only if 'skills' section enabled)",
        items: skillItemSchema()
    )

    /// Languages array schema - used by SubmitExperienceDefaultsTool and PersistDataTool
    static let languagesArray = JSONSchema(
        type: .array,
        description: "Language proficiencies (only if 'languages' section enabled)",
        items: languageItemSchema()
    )

    /// Volunteer array schema - used by SubmitExperienceDefaultsTool and PersistDataTool
    static let volunteerArray = JSONSchema(
        type: .array,
        description: "Volunteer experiences (only if 'volunteer' section enabled)",
        items: volunteerItemSchema()
    )

    /// Awards array schema - used by SubmitExperienceDefaultsTool and PersistDataTool
    static let awardsArray = JSONSchema(
        type: .array,
        description: "Awards received (only if 'awards' section enabled)",
        items: awardItemSchema()
    )

    /// Certificates array schema - used by SubmitExperienceDefaultsTool and PersistDataTool
    static let certificatesArray = JSONSchema(
        type: .array,
        description: "Professional certificates (only if 'certificates' section enabled)",
        items: certificateItemSchema()
    )

    /// Publications array schema - used by SubmitExperienceDefaultsTool and PersistDataTool
    static let publicationsArray = JSONSchema(
        type: .array,
        description: "Publications (only if 'publications' section enabled)",
        items: publicationItemSchema()
    )

    // MARK: - Professional Summary Schema

    /// Professional summary schema - used by SubmitExperienceDefaultsTool
    static let professionalSummary = JSONSchema(
        type: .string,
        description: """
            A 2-4 sentence professional summary highlighting the candidate's key strengths,
            experience level, and career focus. This will be saved to Experience Defaults
            for use in resume headers and cover letter introductions.
            Example: "Senior software engineer with 8+ years building scalable distributed systems.
            Proven track record leading cross-functional teams and delivering high-impact products.
            Passionate about developer experience and engineering excellence."
            """
    )

    // MARK: - PersistDataTool Schemas

    /// DataType enum for PersistDataTool
    static let persistDataType = JSONSchema(
        type: .string,
        description: """
            Type of data being persisted. Each type triggers specific coordinator events and state updates.
            Valid types:
            - applicant_profile: Contact info (name, email, phone, location, URLs, social profiles)
            - skeleton_timeline: Complete timeline of positions/education entries
            - experience_defaults: Resume defaults generated from knowledge cards. REQUIRED structure:
                {
                    "work": [{ "name": "Company", "position": "Title", "location": "City, ST", "startDate": "YYYY-MM", "endDate": "YYYY-MM" or "Present", "summary": "Brief role description", "highlights": ["Achievement 1", "Achievement 2", ...] }],
                    "education": [{ "institution": "School", "area": "Field of Study", "studyType": "Degree Type", "startDate": "YYYY", "endDate": "YYYY", "score": "GPA if relevant" }],
                    "projects": [{ "name": "Project Name", "description": "What it does", "startDate": "YYYY-MM", "endDate": "YYYY-MM", "highlights": ["Key accomplishment"], "keywords": ["tech", "stack"] }],
                    "skills": [{ "name": "Skill Category", "level": "Expert/Advanced/Intermediate", "keywords": ["specific", "technologies"] }],
                    "languages": [{ "language": "English", "fluency": "Native" }]
                }
            - enabled_sections: Alternative format for enabled sections (array of section names)
            - candidate_dossier_entry: Single Q&A entry for dossier seed (requires: question, answer, asked_at)
            - knowledge_card: Deep dive expertise card from Phase 2
            - writing_sample: Writing sample (Phase 3)
            - candidate_dossier: Final compiled candidate dossier (Phase 3)
            """,
        enum: [
            "applicant_profile",
            "skeleton_timeline",
            "experience_defaults",
            "enabled_sections",
            "candidate_dossier_entry",
            "knowledge_card",
            "writing_sample",
            "candidate_dossier"
        ]
    )

    /// Data payload schema for PersistDataTool
    static let persistDataPayload = JSONSchema(
        type: .object,
        description: "JSON payload containing the data to persist. Schema varies by dataType.",
        additionalProperties: true
    )

    // MARK: - IngestWritingSampleTool Schemas

    /// Writing sample name schema
    static let writingSampleName = JSONSchema(
        type: .string,
        description: "Descriptive name for the writing sample (e.g., 'Cover letter for Google', 'Professional email to client', 'Graduate school essay')"
    )

    /// Writing sample content schema
    static let writingSampleContent = JSONSchema(
        type: .string,
        description: "The full text content of the writing sample. Include the complete text exactly as provided by the user."
    )

    /// Writing sample type schema
    static let writingSampleType = JSONSchema(
        type: .string,
        description: "Type of writing sample",
        enum: writingSampleTypes
    )

    /// Writing sample context schema
    static let writingSampleContext = JSONSchema(
        type: .string,
        description: "Optional context about the writing sample (when written, purpose, audience)"
    )

    // MARK: - ConfigureEnabledSectionsTool Schemas

    /// Proposed sections schema for ConfigureEnabledSectionsTool
    static let proposedSections = JSONSchema(
        type: .object,
        description: """
            Object mapping JSON Resume top-level section keys to boolean enabled/disabled state.
            Valid section keys (from JSON Resume schema):
            - work: Work experience entries
            - education: Educational background
            - volunteer: Volunteer experience
            - awards: Professional awards and recognitions
            - certificates: Professional certifications
            - publications: Published works
            - skills: Technical and professional skills
            - languages: Language proficiencies
            - interests: Personal interests and hobbies
            - references: Professional references
            - projects: Career projects and portfolio items
            Example: { "work": true, "education": true, "skills": true, "publications": false, "projects": true, "awards": false }
            """,
        additionalProperties: true
    )

    /// Section configuration rationale schema
    static let sectionConfigRationale = JSONSchema(
        type: .string,
        description: "Optional explanation or context for the proposed sections"
    )

}
