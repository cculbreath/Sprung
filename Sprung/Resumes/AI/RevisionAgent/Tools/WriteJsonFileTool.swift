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

    /// Paths the agent is allowed to write to.
    private static let allowedPrefixes = ["treenodes/"]
    private static let allowedExactPaths: Set<String> = ["fontsizenodes.json"]

    static func execute(parameters: Parameters, repoRoot: URL) throws -> Result {
        let path = parameters.path

        // Validate path is within allowed write targets
        let isAllowed = allowedPrefixes.contains(where: { path.hasPrefix($0) })
            || allowedExactPaths.contains(path)
        guard isAllowed else {
            throw AgentToolError.pathOutsideRepo(
                "Write not allowed for '\(path)'. Allowed: treenodes/*.json, fontsizenodes.json"
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

        // Type-specific validation
        let itemCount: Int
        if path.hasPrefix("treenodes/") {
            itemCount = try validateTreeNodes(parsed)
        } else if path == "fontsizenodes.json" {
            itemCount = try validateFontSizeNodes(parsed)
        } else {
            guard let array = parsed as? [Any] else {
                throw AgentToolError.executionFailed("Content must be a JSON array")
            }
            itemCount = array.count
        }

        // Resolve path and write
        let filePath = try FilesystemToolUtilities.resolveAndValidatePath(path, repoRoot: repoRoot)
        let fileURL = URL(fileURLWithPath: filePath)

        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        try contentData.write(to: fileURL)

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
