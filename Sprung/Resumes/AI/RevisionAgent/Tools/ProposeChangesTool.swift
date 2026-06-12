import Foundation

struct ProposeChangesTool: AgentTool {
    static let name = "propose_changes"
    static let description = """
        Present a structured change proposal to the user for review. Group related edits — \
        especially items in the same list (skills, keywords, bullets) — into a SINGLE call. The \
        user accepts or rejects each call as a unit; one call per list element is too granular. \
        Include a summary and the list of changes with before/after previews. Every change MUST \
        cite its supporting evidence source. Wait for the user's response before writing any files.
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
                        "evidence": [
                            "type": "string",
                            "description": "The supporting source that grounds this change. Cite the specific knowledge-card title, skill-bank entry, \"existing resume content\", or \"user-provided answer\" the new content traces to. Never cite vague sources like \"general knowledge\"."
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
                    "required": ["section", "type", "description", "evidence"]
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
        /// Required by the schema; decoded as optional so a malformed call
        /// degrades to "no evidence cited" in the UI instead of failing decode.
        let evidence: String?
        let beforePreview: String?
        let afterPreview: String?

        enum CodingKeys: String, CodingKey {
            case section, type, description, evidence
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
    /// Ground-truth verification of each change's before-preview against the
    /// ACTUAL current workspace content, parallel to `changes`. The user
    /// approves reality, not the model's claims — a mismatch is surfaced with
    /// the real content alongside the model's asserted preview.
    let verifications: [BeforeVerification]

    enum BeforeVerification {
        /// The model's before-preview matches the actual workspace content.
        case verified
        /// The model's before-preview was not found in the actual workspace
        /// content; `actualContent` carries the real values for display.
        case mismatch(actualContent: [String])
        /// No before-content to verify (e.g. an `add` change).
        case notApplicable
    }

    /// Safe indexed access (verifications is parallel to changes by construction).
    func verification(at index: Int) -> BeforeVerification {
        verifications.indices.contains(index) ? verifications[index] : .notApplicable
    }
}

/// A per-item decision when the user reviews a multi-change proposal individually.
struct ItemDecision {
    enum Kind: String { case accept, reject, feedback, edit }
    let index: Int        // position in ChangeProposal.changes
    let section: String   // human-readable reference for the LLM
    let kind: Kind
    let feedback: String? // revision note for `.feedback` (agent re-proposes)
    let editedText: String? // verbatim replacement for `.edit` (applied as written)
}

enum ProposalResponse {
    case accepted
    case rejected
    case modified(feedback: String)
    /// Per-item outcome: the user accepted some changes, rejected others, and/or
    /// attached revision feedback to specific items.
    case itemized([ItemDecision])

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
            return Self.encode(["decision": "modified", "feedback": feedback])
                ?? #"{"decision": "modified", "feedback": ""}"#
        case .itemized(let items):
            let itemPayload: [[String: Any]] = items.map { item in
                var dict: [String: Any] = [
                    "index": item.index,
                    "section": item.section,
                    "decision": item.kind.rawValue
                ]
                if let feedback = item.feedback, !feedback.isEmpty {
                    dict["feedback"] = feedback
                }
                if let editedText = item.editedText, !editedText.isEmpty {
                    dict["edited_text"] = editedText
                }
                return dict
            }
            let payload: [String: Any] = ["decision": "itemized", "items": itemPayload]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return #"{"decision": "itemized", "items": []}"#
        }
    }

    private static func encode(_ payload: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}
