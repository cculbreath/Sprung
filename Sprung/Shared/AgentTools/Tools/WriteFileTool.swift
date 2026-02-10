//
//  WriteFileTool.swift
//  Sprung
//
//  Tool for writing content to files.
//

import Foundation

struct WriteFileTool: AgentTool {
    static let name = "write_file"
    static let description = """
        Write content to a file. Creates the file if it doesn't exist, overwrites if it does.
        Use for creating merged cards or updating existing files.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "path": [
                "type": "string",
                "description": "Path to the file to write (relative to workspace root)"
            ],
            "content": [
                "type": "string",
                "description": "Content to write to the file"
            ]
        ],
        "required": ["path", "content"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let path: String
        let content: String
    }

    struct Result: Codable {
        let success: Bool
        let path: String
        let bytesWritten: Int
    }

    /// Execute the write_file tool
    static func execute(
        parameters: Parameters,
        repoRoot: URL
    ) throws -> Result {
        // Resolve and validate path
        let filePath = try FilesystemToolUtilities.resolveAndValidatePath(parameters.path, repoRoot: repoRoot)
        let fileURL = URL(fileURLWithPath: filePath)

        // Create parent directories if needed
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Write content
        let data = parameters.content.data(using: .utf8) ?? Data()
        try data.write(to: fileURL)

        return Result(
            success: true,
            path: parameters.path,
            bytesWritten: data.count
        )
    }
}
