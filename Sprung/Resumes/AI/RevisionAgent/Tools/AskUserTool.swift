import Foundation

struct AskUserTool: AgentTool {
    static let name = "ask_user"
    static let description = """
        Ask the user a clarifying question about their resume preferences, \
        target role, or feedback on proposed changes. \
        The user will type a free-form response.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "question": [
                "type": "string",
                "description": "The question to ask the user"
            ]
        ],
        "required": ["question"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let question: String
    }
}
