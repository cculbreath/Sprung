//
//  DeleteFileTool.swift
//  Sprung
//
//  Tool for deleting files.
//

import Foundation

struct DeleteFileTool: AgentTool {
    static let name = "delete_file"
    static let description = """
        Delete a file from the workspace. Use to remove source cards after merging.
        Cannot delete directories - only individual files.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "path": [
                "type": "string",
                "description": "Path to the file to delete (relative to workspace root)"
            ]
        ],
        "required": ["path"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let path: String
    }

    struct Result: Codable {
        let success: Bool
        let path: String
    }

    /// Execute the delete_file tool
    static func execute(
        parameters: Parameters,
        repoRoot: URL
    ) throws -> Result {
        // Resolve and validate path
        let filePath = try GitToolUtilities.resolveAndValidatePath(parameters.path, repoRoot: repoRoot)

        // Check file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw GitToolError.fileNotFound(parameters.path)
        }

        // Ensure it's a file, not a directory
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            throw GitToolError.notADirectory(parameters.path)
        }

        // Delete the file
        try FileManager.default.removeItem(atPath: filePath)

        return Result(
            success: true,
            path: parameters.path
        )
    }
}
