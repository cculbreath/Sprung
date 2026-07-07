import Foundation

/// On-demand page-count check for the revision agent's page-overflow skill.
///
/// Execution (in `ResumeRevisionAgent.executeTool`) applies the CURRENT
/// workspace state to a scratch copy of the resume via
/// `RevisionPDFRenderer.autoRenderResume` — the real resume is never mutated —
/// renders it, and reports the resulting page count alongside the count from
/// the previous render so the agent can iterate until the content fits.
struct CheckPageCountTool: AgentTool {
    static let name = "check_page_count"
    static let description = """
        Render the resume from the current workspace state and return its page count.
        The render applies your workspace edits to a scratch copy — the real resume is never modified.
        Returns {"pageCount": <current count>, "previousPageCount": <count from the previous render, or null>}.
        Use this to verify the resume fits the target length after a round of edits or cuts.
        Takes no parameters.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [:] as [String: Any],
        "required": [] as [String],
        "additionalProperties": false
    ]

    struct Parameters: Codable {}

    /// Pure half: the tool-result JSON. Keys we control are camelCase;
    /// a missing previous count is an explicit JSON null, never a fake number.
    static func resultJSON(pageCount: Int, previousPageCount: Int?) -> String {
        let previous = previousPageCount.map(String.init) ?? "null"
        return "{\"pageCount\": \(pageCount), \"previousPageCount\": \(previous)}"
    }
}
