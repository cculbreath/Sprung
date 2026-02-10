import Foundation

struct CompleteRevisionTool: AgentTool {
    static let name = "complete_revision"
    static let description = """
        Signal that the revision process is complete.
        Provide a summary of all changes made during the session.
        The user will see the final PDF and choose to accept or reject the revised resume.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": [
                "type": "string",
                "description": "Final summary of all changes made during the revision session"
            ]
        ],
        "required": ["summary"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let summary: String
    }
}
