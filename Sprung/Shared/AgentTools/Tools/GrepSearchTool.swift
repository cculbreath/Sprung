//
//  GrepSearchTool.swift
//  Sprung
//
//  Tool for searching file contents using ripgrep or native Swift.
//

import Foundation
import SwiftyJSON

struct GrepSearchTool: AgentTool {
    static let name = "grep_search"
    static let description = """
        Search for a pattern in file contents using ripgrep.
        Returns matching lines with file paths and line numbers.
        Supports regex patterns and file type filtering.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "pattern": [
                "type": "string",
                "description": "Search pattern (regex or literal string)"
            ],
            "path": [
                "type": "string",
                "description": "Directory to search in. Defaults to repository root."
            ],
            "filePattern": [
                "type": "string",
                "description": "Filter files by glob pattern (e.g., '*.swift', '*.ts')"
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum number of matching files to return. Default: 20"
            ],
            "contextLines": [
                "type": "integer",
                "description": "Number of context lines before and after matches. Default: 2"
            ]
        ],
        "required": ["pattern"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let pattern: String
        let path: String?
        let filePattern: String?
        let limit: Int?
        let contextLines: Int?
    }

    struct Match: Codable {
        let filePath: String
        let relativePath: String
        let lineNumber: Int
        let lineContent: String
        let contextBefore: [String]
        let contextAfter: [String]
    }

    struct FileMatches: Codable {
        let filePath: String
        let relativePath: String
        let matches: [Match]
    }

    struct Result: Codable {
        let files: [FileMatches]
        let totalFiles: Int
        let totalMatches: Int
        let truncated: Bool
        let formatted: String
    }

    /// Execute the grep_search tool
    static func execute(
        parameters: Parameters,
        repoRoot: URL,
        ripgrepPath: URL? = nil
    ) throws -> Result {
        // Resolve and validate path (handles ".", "/", relative paths, nil defaults to repoRoot)
        let searchPath = try FilesystemToolUtilities.resolveAndValidatePath(parameters.path ?? ".", repoRoot: repoRoot)
        let limit = min(50, parameters.limit ?? 20)
        let contextLines = min(5, parameters.contextLines ?? 2)

        // Try ripgrep first, fall back to native
        if let rgPath = ripgrepPath ?? findRipgrep() {
            return try executeWithRipgrep(
                pattern: parameters.pattern,
                searchPath: searchPath,
                repoRoot: repoRoot,
                filePattern: parameters.filePattern,
                limit: limit,
                contextLines: contextLines,
                ripgrepPath: rgPath
            )
        } else {
            return try executeNative(
                pattern: parameters.pattern,
                searchPath: searchPath,
                repoRoot: repoRoot,
                filePattern: parameters.filePattern,
                limit: limit,
                contextLines: contextLines
            )
        }
    }

    /// Find ripgrep binary
    private static func findRipgrep() -> URL? {
        // Check bundle first
        if let bundled = Bundle.main.url(forResource: "rg", withExtension: nil) {
            return bundled
        }

        // Check common paths
        let paths = [
            "/opt/homebrew/bin/rg",
            "/usr/local/bin/rg",
            "/usr/bin/rg"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    /// Execute using ripgrep
    private static func executeWithRipgrep(
        pattern: String,
        searchPath: String,
        repoRoot: URL,
        filePattern: String?,
        limit: Int,
        contextLines: Int,
        ripgrepPath: URL
    ) throws -> Result {
        var args = [
            "--json",
            "-C", String(contextLines),
            "--max-count", "10",  // Max matches per file
            "--max-filesize", "1M"
        ]

        if let filePattern = filePattern {
            args.append(contentsOf: ["-g", filePattern])
        }

        args.append(pattern)
        args.append(searchPath)

        let process = Process()
        process.executableURL = ripgrepPath
        process.arguments = args
        process.currentDirectoryURL = repoRoot

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Read output BEFORE waitUntilExit to avoid pipe buffer deadlock
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""

        return parseRipgrepOutput(
            output: output,
            repoRoot: repoRoot,
            limit: limit
        )
    }

    /// Parse ripgrep JSON output
    private static func parseRipgrepOutput(
        output: String,
        repoRoot: URL,
        limit: Int
    ) -> Result {
        var fileMatchesMap: [String: [Match]] = [:]
        var totalMatches = 0

        for line in output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSON(data: data) else {
                continue
            }

            if json["type"].stringValue == "match" {
                let matchData = json["data"]
                let path = matchData["path"]["text"].stringValue
                let lineNum = matchData["line_number"].intValue
                let lineText = matchData["lines"]["text"].stringValue.trimmingCharacters(in: .newlines)

                let relativePath = path.hasPrefix(repoRoot.path) ?
                    String(path.dropFirst(repoRoot.path.count + 1)) : path

                let match = Match(
                    filePath: path,
                    relativePath: relativePath,
                    lineNumber: lineNum,
                    lineContent: lineText,
                    contextBefore: [],
                    contextAfter: []
                )

                fileMatchesMap[path, default: []].append(match)
                totalMatches += 1
            }
        }

        // Convert to array and limit
        var files: [FileMatches] = fileMatchesMap.map { path, matches in
            let relativePath = path.hasPrefix(repoRoot.path) ?
                String(path.dropFirst(repoRoot.path.count + 1)) : path
            return FileMatches(filePath: path, relativePath: relativePath, matches: matches)
        }

        // Sort by number of matches
        files.sort { $0.matches.count > $1.matches.count }

        let truncated = files.count > limit
        if truncated {
            files = Array(files.prefix(limit))
        }

        let formatted = formatResults(files: files)

        return Result(
            files: files,
            totalFiles: files.count,
            totalMatches: totalMatches,
            truncated: truncated,
            formatted: formatted
        )
    }

    /// Native Swift fallback implementation
    private static func executeNative(
        pattern: String,
        searchPath: String,
        repoRoot: URL,
        filePattern: String?,
        limit: Int,
        contextLines _: Int
    ) throws -> Result {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let searchURL = URL(fileURLWithPath: searchPath)

        var fileMatchesMap: [String: [Match]] = [:]
        var totalMatches = 0
        var filesProcessed = 0

        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: searchURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let itemURL = enumerator?.nextObject() as? URL {
            // Skip noise directories
            if FilesystemToolUtilities.skipDirectories.contains(itemURL.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }

            let resources = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            if resources?.isDirectory == true { continue }

            // Check file pattern
            if let filePattern = filePattern {
                let globRegex = try FilesystemToolUtilities.globToRegex(filePattern)
                let name = itemURL.lastPathComponent
                if globRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil {
                    continue
                }
            }

            // Skip binary files
            if FilesystemToolUtilities.isBinaryFile(at: itemURL) {
                continue
            }

            // Read and search file
            guard let content = try? String(contentsOf: itemURL, encoding: .utf8) else {
                continue
            }

            let lines = content.components(separatedBy: .newlines)
            var matches: [Match] = []

            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    let relativePath = String(itemURL.path.dropFirst(repoRoot.path.count + 1))
                    matches.append(Match(
                        filePath: itemURL.path,
                        relativePath: relativePath,
                        lineNumber: index + 1,
                        lineContent: line,
                        contextBefore: [],
                        contextAfter: []
                    ))
                    totalMatches += 1
                }
            }

            if !matches.isEmpty {
                fileMatchesMap[itemURL.path] = matches
                filesProcessed += 1
            }

            // Stop early if we have enough files
            if filesProcessed >= limit * 2 {
                break
            }
        }

        // Convert to array and limit
        var files: [FileMatches] = fileMatchesMap.map { path, matches in
            let relativePath = path.hasPrefix(repoRoot.path) ?
                String(path.dropFirst(repoRoot.path.count + 1)) : path
            return FileMatches(filePath: path, relativePath: relativePath, matches: matches)
        }

        files.sort { $0.matches.count > $1.matches.count }

        let truncated = files.count > limit
        if truncated {
            files = Array(files.prefix(limit))
        }

        let formatted = formatResults(files: files)

        return Result(
            files: files,
            totalFiles: files.count,
            totalMatches: totalMatches,
            truncated: truncated,
            formatted: formatted
        )
    }

    /// Format results for display
    private static func formatResults(files: [FileMatches]) -> String {
        var lines: [String] = []

        for fileMatch in files {
            lines.append("📄 \(fileMatch.relativePath) (\(fileMatch.matches.count) matches)")
            for match in fileMatch.matches.prefix(5) {
                lines.append("   L\(match.lineNumber): \(match.lineContent.prefix(100))")
            }
            if fileMatch.matches.count > 5 {
                lines.append("   ... and \(fileMatch.matches.count - 5) more matches")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
