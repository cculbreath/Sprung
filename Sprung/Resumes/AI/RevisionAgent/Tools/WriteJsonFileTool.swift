import Foundation

struct WriteJsonFileTool: AgentTool {
    static let name = "write_json_file"
    static let description = """
        Write modified JSON to an editable workspace file.
        Allowed paths: treenodes/*.json (resume content) and fontsizenodes.json (font sizes).
        Content must be valid JSON.
        For treenode files: array of objects with id, name, value, myIndex, isTitleNode, children.
        For fontsizenodes.json: array of objects with key and fontString (e.g. "12pt").
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "path": [
                "type": "string",
                "description": "Path to the JSON file (e.g. 'treenodes/work.json' or 'fontsizenodes.json')"
            ],
            "content": [
                "type": "string",
                "description": "Valid JSON content to write"
            ]
        ],
        "required": ["path", "content"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let path: String
        let content: String
    }

    struct Result {
        let success: Bool
        let path: String
        let itemCount: Int
    }

    static func execute(parameters: Parameters, repoRoot: URL) throws -> Result {
        let path = parameters.path

        // Resolve the path FIRST, then authorize against the resolved location.
        // A prefix check on the raw string would let "treenodes/../…" traverse
        // into read-only areas of the workspace (or out of it entirely).
        guard !path.isEmpty, !path.hasPrefix("/") else {
            throw AgentToolError.pathOutsideRepo(
                "Write paths must be workspace-relative (got '\(path)'). Allowed: treenodes/<section>.json, fontsizenodes.json"
            )
        }

        let workspaceRoot = repoRoot.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = workspaceRoot.appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        let rootComponents = workspaceRoot.pathComponents
        let fileComponents = resolved.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            throw AgentToolError.pathOutsideRepo(path)
        }

        // Authorize the RESOLVED location: either a JSON file directly inside
        // treenodes/, or exactly fontsizenodes.json at the workspace root.
        let isTreeNodeFile = fileComponents.count == rootComponents.count + 2
            && fileComponents[rootComponents.count] == "treenodes"
            && resolved.pathExtension == "json"
        let isFontSizeFile = fileComponents.count == rootComponents.count + 1
            && resolved.lastPathComponent == "fontsizenodes.json"
        guard isTreeNodeFile || isFontSizeFile else {
            throw AgentToolError.pathOutsideRepo(
                "Write not allowed for '\(path)'. Allowed: treenodes/<section>.json, fontsizenodes.json"
            )
        }

        // Validate content is valid JSON
        guard let contentData = parameters.content.data(using: .utf8) else {
            throw AgentToolError.executionFailed("Content is not valid UTF-8")
        }

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: contentData)
        } catch {
            throw AgentToolError.executionFailed("Content is not valid JSON: \(error.localizedDescription)")
        }

        // Type-specific validation, keyed off the resolved location
        let itemCount: Int
        if isTreeNodeFile {
            itemCount = try validateTreeNodes(parsed)
        } else {
            itemCount = try validateFontSizeNodes(parsed)
        }

        try FileManager.default.createDirectory(
            at: resolved.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contentData.write(to: resolved)

        return Result(success: true, path: path, itemCount: itemCount)
    }

    // MARK: - Validators

    private static func validateTreeNodes(_ parsed: Any) throws -> Int {
        guard let nodes = parsed as? [[String: Any]] else {
            throw AgentToolError.executionFailed("Treenode content must be a JSON array of node objects")
        }

        let requiredFields: Set<String> = ["id", "name", "value", "myIndex", "children"]
        for (index, node) in nodes.enumerated() {
            let keys = Set(node.keys)
            let missing = requiredFields.subtracting(keys)
            if !missing.isEmpty {
                throw AgentToolError.executionFailed(
                    "Node at index \(index) is missing required fields: \(missing.sorted().joined(separator: ", "))"
                )
            }
        }
        return nodes.count
    }

    private static func validateFontSizeNodes(_ parsed: Any) throws -> Int {
        guard let nodes = parsed as? [[String: Any]] else {
            throw AgentToolError.executionFailed("Font size content must be a JSON array of objects")
        }

        for (index, node) in nodes.enumerated() {
            guard node["key"] is String else {
                throw AgentToolError.executionFailed("Font size node at index \(index) missing 'key' (String)")
            }
            guard node["fontString"] is String else {
                throw AgentToolError.executionFailed("Font size node at index \(index) missing 'fontString' (String)")
            }
        }
        return nodes.count
    }
}
