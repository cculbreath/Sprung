import Foundation

struct RenderResumeTool: AgentTool {
    static let name = "render_resume"
    static let description = """
        Re-render the resume PDF from the current workspace treenode state.
        Merges modified treenodes with locked originals, renders via the template, \
        and writes the updated PDF to the workspace.
        Returns the page count so you can check against the target.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [:] as [String: Any],
        "required": [] as [String],
        "additionalProperties": false
    ]

    struct Parameters: Codable {}

    struct Result {
        let success: Bool
        let pageCount: Int
        let pdfPath: String
    }
}
