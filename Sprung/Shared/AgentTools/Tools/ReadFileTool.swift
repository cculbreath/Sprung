//
//  ReadFileTool.swift
//  Sprung
//
//  Tool for reading file contents with pagination.
//

import Foundation

struct ReadFileTool: AgentTool {
    static let name = "read_file"
    static let description = """
        Read the contents of a file. Returns the file content with line numbers.
        Use offset and limit for pagination on large files.
        Skips binary files automatically.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "path": [
                "type": "string",
                "description": "Absolute path to the file to read"
            ],
            "offset": [
                "type": "integer",
                "description": "Line number to start reading from (1-indexed). Default: 1"
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum number of lines to read. Default: 500"
            ]
        ],
        "required": ["path"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let path: String
        let offset: Int?
        let limit: Int?
    }

    struct Result: Codable {
        let content: String
        let totalLines: Int
        let startLine: Int
        let endLine: Int
        let hasMore: Bool
        let truncatedLines: Int  // Number of lines that were truncated at max chars
    }

    /// Execute the read_file tool
    static func execute(
        parameters: Parameters,
        repoRoot: URL
    ) throws -> Result {
        // Resolve and validate path (handles ".", "/", relative paths)
        let filePath = try FilesystemToolUtilities.resolveAndValidatePath(parameters.path, repoRoot: repoRoot)
        let offset = max(1, parameters.offset ?? 1)
        let limit = min(2000, parameters.limit ?? 500)

        // Check file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw AgentToolError.fileNotFound(parameters.path)
        }

        // Check if binary
        let fileURL = URL(fileURLWithPath: filePath)
        if FilesystemToolUtilities.isBinaryFile(at: fileURL) {
            throw AgentToolError.binaryFile(parameters.path)
        }

        // Read file
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let allLines = content.components(separatedBy: .newlines)
        let totalLines = allLines.count

        // Calculate range
        let startIndex = offset - 1  // Convert to 0-indexed
        let endIndex = min(startIndex + limit, totalLines)

        guard startIndex < totalLines else {
            return Result(
                content: "",
                totalLines: totalLines,
                startLine: offset,
                endLine: offset,
                hasMore: false,
                truncatedLines: 0
            )
        }

        // Extract and format lines
        let selectedLines = Array(allLines[startIndex..<endIndex])
        var truncatedCount = 0
        let maxLineLength = 500

        let formattedLines = selectedLines.enumerated().map { index, line in
            let lineNumber = startIndex + index + 1  // 1-indexed
            var displayLine = line
            if line.count > maxLineLength {
                displayLine = String(line.prefix(maxLineLength)) + "... [truncated]"
                truncatedCount += 1
            }
            return String(format: "%4d: %@", lineNumber, displayLine)
        }

        return Result(
            content: formattedLines.joined(separator: "\n"),
            totalLines: totalLines,
            startLine: offset,
            endLine: startIndex + selectedLines.count,
            hasMore: endIndex < totalLines,
            truncatedLines: truncatedCount
        )
    }
}
