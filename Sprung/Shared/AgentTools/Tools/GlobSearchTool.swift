//
//  GlobSearchTool.swift
//  Sprung
//
//  Tool for finding files matching glob patterns.
//

import Foundation

struct GlobSearchTool: AgentTool {
    static let name = "glob_search"
    static let description = """
        Find files matching a glob pattern (e.g., "**/*.swift", "src/**/*.ts").
        Results are sorted by modification time (newest first).
        Respects .gitignore and skips common noise directories.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "pattern": [
                "type": "string",
                "description": "Glob pattern to match files against (e.g., '**/*.swift', 'src/**/*.ts')"
            ],
            "path": [
                "type": "string",
                "description": "Directory to search in. Defaults to repository root."
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum number of results to return. Default: 50"
            ]
        ],
        "required": ["pattern"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let pattern: String
        let path: String?
        let limit: Int?
    }

    struct FileMatch: Codable {
        let path: String
        let relativePath: String
        let size: Int64
        let modifiedAt: Date
    }

    struct Result: Codable {
        let files: [FileMatch]
        let totalMatches: Int
        let truncated: Bool
    }

    /// Execute the glob_search tool
    static func execute(
        parameters: Parameters,
        repoRoot: URL
    ) throws -> Result {
        let pattern = parameters.pattern
        // Resolve and validate path (handles ".", "/", relative paths, nil defaults to repoRoot)
        let searchPath = try FilesystemToolUtilities.resolveAndValidatePath(parameters.path ?? ".", repoRoot: repoRoot)
        let limit = min(200, parameters.limit ?? 50)

        let searchURL = URL(fileURLWithPath: searchPath)

        // Parse the glob pattern
        let regex = try FilesystemToolUtilities.globToRegex(pattern)

        // Collect matching files
        var matches: [FileMatch] = []
        var totalCount = 0

        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: searchURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        while let itemURL = enumerator?.nextObject() as? URL {
            // Skip noise directories
            if FilesystemToolUtilities.skipDirectories.contains(itemURL.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }

            let resources = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDir = resources?.isDirectory ?? false

            if isDir { continue }

            // Get relative path for matching
            let relativePath = String(itemURL.path.dropFirst(repoRoot.path.count + 1))

            // Check if matches pattern
            if regex.firstMatch(in: relativePath, range: NSRange(relativePath.startIndex..., in: relativePath)) != nil {
                totalCount += 1

                let size = Int64(resources?.fileSize ?? 0)
                let modDate = resources?.contentModificationDate ?? Date.distantPast

                matches.append(FileMatch(
                    path: itemURL.path,
                    relativePath: relativePath,
                    size: size,
                    modifiedAt: modDate
                ))
            }
        }

        // Sort by modification date (newest first)
        matches.sort { $0.modifiedAt > $1.modifiedAt }

        // Limit results
        let truncated = matches.count > limit
        if truncated {
            matches = Array(matches.prefix(limit))
        }

        return Result(
            files: matches,
            totalMatches: totalCount,
            truncated: truncated
        )
    }
}
