import Foundation

struct ProposeChangesTool: AgentTool {
    static let name = "propose_changes"
    static let description = """
        Present a structured change proposal to the user for review.
        Include a summary and list of specific changes with before/after previews.
        The user will accept, reject, or provide feedback.
        You MUST wait for the user's response before writing any files.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": [
                "type": "string",
                "description": "Brief description of the proposed changes and why they improve the resume"
            ],
            "changes": [
                "type": "array",
                "description": "List of specific changes being proposed",
                "items": [
                    "type": "object",
                    "properties": [
                        "section": [
                            "type": "string",
                            "description": "Section being changed (e.g., 'work', 'skills', 'summary')"
                        ],
                        "type": [
                            "type": "string",
                            "enum": ["modify", "add", "remove", "reorder"],
                            "description": "Type of change"
                        ],
                        "description": [
                            "type": "string",
                            "description": "What changed and why"
                        ],
                        "before_preview": [
                            "type": "string",
                            "description": "Preview of the content before the change (empty for 'add')"
                        ],
                        "after_preview": [
                            "type": "string",
                            "description": "Preview of the content after the change (empty for 'remove')"
                        ]
                    ] as [String: Any],
                    "required": ["section", "type", "description"]
                ] as [String: Any]
            ]
        ] as [String: Any],
        "required": ["summary", "changes"],
        "additionalProperties": false
    ]

    struct ChangeDetail: Codable {
        let section: String
        let type: String
        let description: String
        let beforePreview: String?
        let afterPreview: String?

        enum CodingKeys: String, CodingKey {
            case section, type, description
            case beforePreview = "before_preview"
            case afterPreview = "after_preview"
        }
    }

    struct Parameters: Codable {
        let summary: String
        let changes: [ChangeDetail]
    }
}

// MARK: - Change Proposal (Domain Model)

struct ChangeProposal {
    let summary: String
    let changes: [ProposeChangesTool.ChangeDetail]
}

enum ProposalResponse {
    case accepted
    case rejected
    case modified(feedback: String)

    var toolResultJSON: String {
        switch self {
        case .accepted:
            return """
            {"decision": "accepted", "feedback": ""}
            """
        case .rejected:
            return """
            {"decision": "rejected", "feedback": ""}
            """
        case .modified(let feedback):
            let escaped = feedback
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return """
            {"decision": "modified", "feedback": "\(escaped)"}
            """
        }
    }
}
