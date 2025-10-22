import Foundation
import SwiftOpenAI

enum OnboardingToolCatalog {
    static let all: [ToolDefinition] = {
        let interactionTools: [ToolDefinition] = [
            ToolDefinition(
                name: "ask_user_options",
                description: """
                Present a multiple-choice or checkbox form so the user can select how to proceed. Use this when human input must choose between options.

                When the tool returns {"status":"waiting_for_user"}:
                - Tell the user: "Please make your selection in the form to the left. We'll continue once you've chosen an option."
                - Do not continue reasoning or call other tools until input is provided.
                """,
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "prompt": ToolProperty(type: "string", description: "Primary prompt shown above the options."),
                        "question": ToolProperty(type: "string", description: "Alternate field for the user-facing question."),
                        "options": ToolProperty(
                            type: "array",
                            description: "Array of option objects. Each option should include id/title/description fields.",
                            items: ToolArrayItems(
                                type: "object",
                                description: "Option payload presented to the user.",
                                properties: [
                                    "id": ToolProperty(type: "string", description: "Unique identifier for the option."),
                                    "title": ToolProperty(type: "string", description: "Primary label shown to the user."),
                                    "description": ToolProperty(type: "string", description: "Supporting detail for the option.")
                                ],
                                required: ["id", "title", "description"],
                                allowAdditionalProperties: false
                            )
                        ),
                        "selection_style": ToolProperty(type: "string", description: "Selection style such as 'single', 'multiple', or 'button'."),
                        "multiple": ToolProperty(type: "boolean", description: "Whether multiple selections are allowed."),
                        "allow_cancel": ToolProperty(type: "boolean", description: "Whether the user can cancel the prompt."),
                        "context": ToolProperty(type: "string", description: "Optional reasoning or next-step guidance for the user.")
                    ],
                    required: ["prompt", "question", "options", "selection_style", "multiple", "allow_cancel", "context"]
                ),
                displayMessage: "💬 Presenting options for you to choose from..."
            ),
            ToolDefinition(
                name: "validate_applicant_profile",
                description: """
                Present an editable ApplicantProfile form for confirmation or correction. Call when the model has low confidence or needs human review.

                When the tool returns {"status":"waiting_for_user"}:
                - Tell the user: "Please review or complete your profile in the form to the left. We'll resume once you've submitted your changes."
                - Pause additional reasoning until the user responds.
                """,
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "profile": ToolProperty(
                            type: "object",
                            description: "Partial or complete ApplicantProfile data to review.",
                            properties: [
                                "name": ToolProperty(type: "string", description: "Full name of the applicant."),
                                "label": ToolProperty(type: "string", description: "Professional headline or title."),
                                "summary": ToolProperty(type: "string", description: "Short professional summary."),
                                "website": ToolProperty(type: "string", description: "Primary personal website or portfolio link."),
                                "email": ToolProperty(type: "string", description: "Primary email address."),
                                "phone": ToolProperty(type: "string", description: "Primary phone number."),
                                "location": ToolProperty(
                                    type: "object",
                                    description: "Structured location fields for the applicant.",
                                    properties: [
                                        "address": ToolProperty(type: "string", description: "Street address or mailing address."),
                                        "city": ToolProperty(type: "string", description: "City of residence."),
                                        "region": ToolProperty(type: "string", description: "State or region of residence."),
                                        "postalCode": ToolProperty(type: "string", description: "Postal or ZIP code."),
                                        "countryCode": ToolProperty(type: "string", description: "ISO country code.")
                                    ],
                                    required: ["address", "city", "region", "postalCode", "countryCode"],
                                    allowAdditionalProperties: false
                                ),
                                "socialProfiles": ToolProperty(
                                    type: "array",
                                    description: "Social profile entries for the applicant.",
                                    items: ToolArrayItems(
                                        type: "object",
                                        description: "Social profile entry.",
                                        properties: [
                                            "id": ToolProperty(type: "string", description: "Stable identifier for the social profile."),
                                            "network": ToolProperty(type: "string", description: "Social network name (e.g., LinkedIn)."),
                                            "username": ToolProperty(type: "string", description: "Username or handle on the network."),
                                            "url": ToolProperty(type: "string", description: "Profile URL.")
                                        ],
                                        required: ["id", "network", "username", "url"],
                                        allowAdditionalProperties: false
                                    )
                                )
                            ],
                            required: [
                                "name",
                                "label",
                                "summary",
                                "website",
                                "email",
                                "phone",
                                "location",
                                "socialProfiles"
                            ],
                            allowAdditionalProperties: false
                        ),
                        "sources": ToolProperty(
                            type: "array",
                            description: "Array of strings describing where data was sourced from.",
                            items: ToolArrayItems(type: "string", description: "Origin identifier for captured data.")
                        ),
                        "section": ToolProperty(type: "string", description: "Specific profile section to focus on (e.g., contact, summary)."),
                        "context": ToolProperty(type: "string", description: "Optional instructions or notes for the reviewer.")
                    ],
                    required: ["profile", "sources", "section", "context"]
                ),
                displayMessage: "📝 Preparing profile form for your review..."
            ),
            ToolDefinition(
                name: "fetch_from_system_contacts",
                description: """
                Retrieve ApplicantProfile fields from the user's macOS Contacts ("Me") card. Only call after explicit consent.

                When the tool returns {"status":"waiting_for_user"}:
                - Say: "I'll continue once you've granted or declined permission to access your Contacts card."
                - Do not continue reasoning until the user acts.
                """,
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "fields": ToolProperty(
                            type: "array",
                            description: "Array of ApplicantProfile fields to request.",
                            items: ToolArrayItems(type: "string", description: "ApplicantProfile field name to fetch.")
                        )
                    ],
                    required: ["fields"]
                ),
                displayMessage: "📇 Fetching from your macOS Contacts..."
            ),
            ToolDefinition(
                name: "validate_enabled_resume_sections",
                description: """
                Present a checklist for the user to confirm which resume sections are enabled before collecting entries.

                When the tool returns {"status":"waiting_for_user"}:
                - Say: "Please select the sections you want to include in your resume. We'll continue when you've confirmed your choices."
                - Do not continue until the user completes the form.
                """,
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "sections": ToolProperty(
                            type: "array",
                            description: "Array of section identifiers to toggle.",
                            items: ToolArrayItems(type: "string", description: "Section identifier to enable or disable.")
                        ),
                        "enabledSections": ToolProperty(
                            type: "array",
                            description: "Optional synonym for sections; use when emphasising enabled set.",
                            items: ToolArrayItems(type: "string", description: "Section identifier included in the enabled list.")
                        ),
                        "context": ToolProperty(type: "string", description: "Optional rationale or instructions for the selection.")
                    ],
                    required: ["sections", "enabledSections", "context"]
                ),
                displayMessage: "✅ Preparing section checklist for your review..."
            ),
            ToolDefinition(
                name: "validate_section_entries",
                description: """
                Present all entries for a given resume section for human confirmation or edits. Provide the full array each time.

                When the tool returns {"status":"waiting_for_user"}:
                - Say: "Please review and confirm the entries for this resume section. We'll continue after you submit your edits."
                - Stop reasoning until the user finishes.
                """,
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "section": ToolProperty(type: "string", description: "Resume section key, e.g., work, education, projects."),
                        "entries": ToolProperty(
                            type: "array",
                            description: "Full array of proposed entries for the section.",
                            items: ToolArrayItems(
                                type: "object",
                                description: "Resume section entry payload.",
                                properties: [
                                    "title": ToolProperty(type: "string", description: "Entry identifier or heading."),
                                    "value": ToolProperty(
                                        type: "array",
                                        description: "Ordered values for this entry.",
                                        items: ToolArrayItems(
                                            type: "string",
                                            description: "Value component string."
                                        )
                                    )
                                ],
                                required: ["title", "value"],
                                allowAdditionalProperties: false
                            )
                        ),
                        "mode": ToolProperty(type: "string", description: "Optional hint such as 'create' or 'update'."),
                        "context": ToolProperty(type: "string", description: "Optional narrative for the reviewer.")
                    ],
                    required: ["section", "entries", "mode", "context"]
                ),
                displayMessage: "📋 Loading entries for your review..."
            ),
            ToolDefinition(
                name: "prompt_user_for_upload",
                description: """
                Ask the user to upload supporting documents such as resumes, transcripts, or work samples. Triggers a file picker in the UI.

                When the tool returns {"status":"waiting_for_user"}:
                - Say: "Please upload the requested document in the file picker to the left. We'll continue once the upload is complete."
                - Avoid further reasoning until the upload completes.
                """,
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "kind": ToolProperty(type: "string", description: "Categorises the upload (resume, artifact, writingSample, linkedIn, generic)."),
                        "prompt": ToolProperty(type: "string", description: "Primary message explaining what to upload."),
                        "instructions": ToolProperty(type: "string", description: "Detailed guidance for the user."),
                        "title": ToolProperty(type: "string", description: "Form title for the upload request."),
                        "accepts": ToolProperty(
                            type: "array",
                            description: "Array of allowed file extensions.",
                            items: ToolArrayItems(type: "string", description: "Accepted file extension (e.g., pdf).")
                        ),
                        "acceptedFileTypes": ToolProperty(
                            type: "array",
                            description: "Synonym for accepts.",
                            items: ToolArrayItems(type: "string", description: "Accepted file extension (e.g., pdf).")
                        ),
                        "allow_multiple": ToolProperty(type: "boolean", description: "Whether multiple files can be uploaded."),
                        "followup_tool": ToolProperty(type: "string", description: "Optional tool to automatically call after upload."),
                        "followup_args": ToolProperty(
                            type: "object",
                            description: "Arguments to forward to the follow-up tool.",
                            properties: [:],
                            allowAdditionalProperties: false
                        ),
                        "context": ToolProperty(type: "string", description: "Optional rationale for the upload.")
                    ],
                    required: [
                        "kind",
                        "prompt",
                        "instructions",
                        "title",
                        "accepts",
                        "acceptedFileTypes",
                        "allow_multiple",
                        "followup_tool",
                        "followup_args",
                        "context"
                    ]
                ),
                displayMessage: "📤 Requesting file upload..."
            )
        ]

        let intakeTools: [ToolDefinition] = [
            ToolDefinition(
                name: "parse_resume",
                description: "Parse an uploaded resume file into structured applicant fields for confirmation.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "fileId": ToolProperty(type: "string", description: "Identifier of the uploaded resume file.")
                    ],
                    required: ["fileId"]
                ),
                displayMessage: "📄 Parsing your resume..."
            ),
            ToolDefinition(
                name: "parse_linkedin",
                description: "Extract structured data from a LinkedIn profile URL or uploaded HTML export.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "url": ToolProperty(type: "string", description: "LinkedIn profile URL to fetch."),
                        "fileId": ToolProperty(type: "string", description: "Optional ID of an uploaded LinkedIn HTML file.", nullable: true)
                    ],
                    required: ["url", "fileId"]
                ),
                displayMessage: "💼 Extracting LinkedIn profile data..."
            ),
            ToolDefinition(
                name: "summarize_artifact",
                description: "Summarize supporting materials such as projects, papers, or presentations into a knowledge card.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "fileId": ToolProperty(type: "string", description: "Identifier of the uploaded artifact."),
                        "context": ToolProperty(type: "string", description: "Optional context to influence the summary.")
                    ],
                    required: ["fileId", "context"]
                )
            ),
            ToolDefinition(
                name: "summarize_writing",
                description: "Analyze a writing sample to derive a style vector and salient phrases.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "fileId": ToolProperty(type: "string", description: "Identifier of the uploaded writing sample."),
                        "context": ToolProperty(type: "string", description: "Optional context or instructions for tone.")
                    ],
                    required: ["fileId", "context"]
                )
            ),
            ToolDefinition(
                name: "web_lookup",
                description: "Perform a vetted external lookup to confirm details or gather context, only when user consent permits.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "query": ToolProperty(type: "string", description: "Search query string to execute."),
                        "context": ToolProperty(type: "string", description: "Purpose or justification for the lookup.")
                    ],
                    required: ["query", "context"]
                )
            )
        ]

        let persistenceTools: [ToolDefinition] = [
            ToolDefinition(
                name: "persist_delta",
                description: "Persist verified schema updates to the ApplicantProfile, defaults, or related artifacts.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "target": ToolProperty(type: "string", description: "Target schema element to update."),
                        "delta": ToolProperty(type: "object", description: "JSON patch to apply to the target."),
                        "value": ToolProperty(type: "object", description: "Synonym for delta; use when providing the final value."),
                        "context": ToolProperty(type: "string", description: "Optional note for auditing or communication.")
                    ],
                    required: ["target", "delta", "value", "context"]
                ),
                strict: false
            ),
            ToolDefinition(
                name: "persist_card",
                description: "Persist a knowledge card generated from artifacts or writing samples.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "card": ToolProperty(type: "object", description: "Knowledge card payload to store.")
                    ],
                    required: ["card"]
                ),
                strict: false
            ),
            ToolDefinition(
                name: "persist_skill_map",
                description: "Merge updates into the skill map or skills index.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "skillMapDelta": ToolProperty(type: "object", description: "JSON delta describing skill updates."),
                        "context": ToolProperty(type: "string", description: "Optional explanation of the change.")
                    ],
                    required: ["skillMapDelta", "context"]
                ),
                strict: false
            ),
            ToolDefinition(
                name: "persist_facts_from_card",
                description: "Append fact ledger entries derived from a knowledge card or other extraction.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "facts": ToolProperty(
                            type: "array",
                            description: "Array of fact ledger entries to append.",
                            items: ToolArrayItems(
                                type: "object",
                                description: "Fact ledger entry payload.",
                                allowAdditionalProperties: true
                            )
                        ),
                        "entries": ToolProperty(
                            type: "array",
                            description: "Synonym for facts; used when referencing entry arrays.",
                            items: ToolArrayItems(
                                type: "object",
                                description: "Fact ledger entry payload.",
                                allowAdditionalProperties: true
                            )
                        ),
                        "fact_ledger": ToolProperty(
                            type: "array",
                            description: "Alternate payload name containing fact ledger entries.",
                            items: ToolArrayItems(
                                type: "object",
                                description: "Fact ledger entry payload.",
                                allowAdditionalProperties: true
                            )
                        )
                    ],
                    required: ["facts", "entries", "fact_ledger"]
                ),
                strict: false
            ),
            ToolDefinition(
                name: "persist_style_profile",
                description: "Save a writing style profile derived from collected samples.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "style_vector": ToolProperty(type: "object", description: "Computed style vector payload."),
                        "samples": ToolProperty(
                            type: "array",
                            description: "Array of writing sample summaries supporting the style vector.",
                            items: ToolArrayItems(
                                type: "object",
                                description: "Writing sample summary payload.",
                                allowAdditionalProperties: true
                            )
                        ),
                        "context": ToolProperty(type: "string", description: "Optional metadata about the style analysis.")
                    ],
                    required: ["style_vector", "samples", "context"]
                ),
                strict: false
            ),
            ToolDefinition(
                name: "verify_conflicts",
                description: "Run timeline and artifact consistency checks, returning any conflicts for review.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [:],
                    required: []
                )
            )
        ]

        return interactionTools + intakeTools + persistenceTools
    }()

    static let functionTools: [Tool] = all.map(\.asFunctionTool)

    static func displayMessage(for toolName: String) -> String? {
        all.first(where: { $0.name == toolName })?.displayMessage
    }
}
