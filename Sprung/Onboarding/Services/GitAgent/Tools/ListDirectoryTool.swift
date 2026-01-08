//
//  ListDirectoryTool.swift
//  Sprung
//
//  Tool for listing directory contents with depth traversal.
//

import Foundation

struct ListDirectoryTool: AgentTool {
    static let name = "list_directory"
    static let description = """
        List contents of a directory with optional depth traversal.
        Returns a tree-like structure showing files and subdirectories.
        Respects .gitignore and skips common noise directories.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "path": [
                "type": "string",
                "description": "Absolute path to the directory to list"
            ],
            "depth": [
                "type": "integer",
                "description": "Maximum recursion depth. Default: 2"
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum number of entries to return. Default: 100"
            ]
        ],
        "required": ["path"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let path: String
        let depth: Int?
        let limit: Int?
    }

    struct Entry: Codable {
        let name: String
        let path: String
        let type: String  // "file" | "directory" | "symlink"
        let size: Int64?
        let depth: Int
    }

    struct Result: Codable {
        let entries: [Entry]
        let totalCount: Int
        let truncated: Bool
        let formattedTree: String
    }

    /// Execute the list_directory tool
    static func execute(
        parameters: Parameters,
        repoRoot: URL,
        gitignorePatterns _: [String] = []
    ) throws -> Result {
        // Resolve and validate path (handles ".", "/", relative paths)
        let dirPath = try GitToolUtilities.resolveAndValidatePath(parameters.path, repoRoot: repoRoot)
        let maxDepth = min(5, parameters.depth ?? 2)
        let limit = min(500, parameters.limit ?? 100)

        let dirURL = URL(fileURLWithPath: dirPath)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitToolError.notADirectory(parameters.path)
        }

        var entries: [Entry] = []
        var totalCount = 0

        // BFS traversal
        var queue: [(URL, Int)] = [(dirURL, 0)]  // (url, depth)

        while !queue.isEmpty && entries.count < limit {
            let (currentURL, currentDepth) = queue.removeFirst()

            guard currentDepth <= maxDepth else { continue }

            let contents = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )

            // Sort: directories first, then alphabetically
            let sorted = contents.sorted { a, b in
                let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if aIsDir != bIsDir {
                    return aIsDir
                }
                return a.lastPathComponent.lowercased() < b.lastPathComponent.lowercased()
            }

            for itemURL in sorted {
                let name = itemURL.lastPathComponent

                // Skip noise directories
                if GitToolUtilities.skipDirectories.contains(name) {
                    continue
                }

                // Skip hidden files (that weren't caught by options)
                if name.hasPrefix(".") {
                    continue
                }

                totalCount += 1

                let resources = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
                let isSymlink = resources?.isSymbolicLink ?? false
                let isDir = resources?.isDirectory ?? false
                let size = resources?.fileSize.map { Int64($0) }

                let entryType: String
                if isSymlink {
                    entryType = "symlink"
                } else if isDir {
                    entryType = "directory"
                } else {
                    entryType = "file"
                }

                if entries.count < limit {
                    entries.append(Entry(
                        name: name,
                        path: itemURL.path,
                        type: entryType,
                        size: entryType == "file" ? size : nil,
                        depth: currentDepth
                    ))
                }

                // Queue subdirectories for traversal
                if isDir && !isSymlink && currentDepth < maxDepth {
                    queue.append((itemURL, currentDepth + 1))
                }
            }
        }

        // Format as tree
        let tree = formatTree(entries: entries, baseDepth: 0)

        return Result(
            entries: entries,
            totalCount: totalCount,
            truncated: entries.count >= limit,
            formattedTree: tree
        )
    }

    private static func formatTree(entries: [Entry], baseDepth: Int) -> String {
        var lines: [String] = []
        for entry in entries {
            let indent = String(repeating: "  ", count: entry.depth - baseDepth)
            let icon = entry.type == "directory" ? "📁" : (entry.type == "symlink" ? "🔗" : "📄")
            let sizeStr = entry.size.map { " (\(GitToolUtilities.formatFileSize($0)))" } ?? ""
            lines.append("\(indent)\(icon) \(entry.name)\(sizeStr)")
        }
        return lines.joined(separator: "\n")
    }
}
