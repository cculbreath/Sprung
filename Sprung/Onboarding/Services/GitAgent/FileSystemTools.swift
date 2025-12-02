//
//  FileSystemTools.swift
//  Sprung
//
//  Filesystem tools for the git analysis agent.
//  Provides read_file, list_directory, glob_search, grep_search, and complete_analysis.
//

import Foundation
import SwiftyJSON

// MARK: - Tool Protocols

/// Protocol for all agent tools
protocol AgentTool {
    /// Tool name (used in function calling)
    static var name: String { get }
    /// Tool description for LLM
    static var description: String { get }
    /// JSON Schema for parameters
    static var parametersSchema: [String: Any] { get }
}

// MARK: - Read File Tool

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
        let filePath = parameters.path
        let offset = max(1, parameters.offset ?? 1)
        let limit = min(2000, parameters.limit ?? 500)

        // Security: Validate path is within repo root
        let fileURL = URL(fileURLWithPath: filePath)
        guard fileURL.standardized.path.hasPrefix(repoRoot.standardized.path) else {
            throw GitToolError.pathOutsideRepo(filePath)
        }

        // Check file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw GitToolError.fileNotFound(filePath)
        }

        // Check if binary
        if isBinaryFile(at: fileURL) {
            throw GitToolError.binaryFile(filePath)
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

    /// Check if file is binary using magic bytes and extension
    static func isBinaryFile(at url: URL) -> Bool {
        // Check extension first
        let binaryExtensions = Set([
            "png", "jpg", "jpeg", "gif", "ico", "webp", "bmp", "tiff",
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "zip", "tar", "gz", "rar", "7z",
            "exe", "dll", "so", "dylib", "o", "a",
            "mp3", "mp4", "wav", "avi", "mov", "mkv",
            "ttf", "otf", "woff", "woff2", "eot",
            "sqlite", "db",
            "pyc", "class"
        ])

        let ext = url.pathExtension.lowercased()
        if binaryExtensions.contains(ext) {
            return true
        }

        // Check magic bytes for common binary formats
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 8192) else {
            return false
        }

        // Check for null bytes (common in binary files)
        let bytes = [UInt8](data)
        let nullCount = bytes.prefix(1024).filter { $0 == 0 }.count
        if nullCount > 5 {
            return true
        }

        // Check for high proportion of non-printable characters
        let nonPrintable = bytes.prefix(1024).filter { byte in
            byte < 9 || (byte > 13 && byte < 32 && byte != 27)
        }.count

        return Double(nonPrintable) / Double(min(bytes.count, 1024)) > 0.1
    }
}

// MARK: - List Directory Tool

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

    /// Directories to always skip
    static let skipDirectories = Set([
        ".git", "node_modules", "__pycache__", ".pytest_cache",
        "dist", "build", ".build", "DerivedData", "Pods",
        ".gradle", "target", "vendor", ".venv", "venv",
        ".idea", ".vscode", ".vs", "coverage", ".nyc_output",
        ".next", ".nuxt", "out", ".cache", ".parcel-cache"
    ])

    /// Execute the list_directory tool
    static func execute(
        parameters: Parameters,
        repoRoot: URL,
        gitignorePatterns: [String] = []
    ) throws -> Result {
        let dirPath = parameters.path
        let maxDepth = min(5, parameters.depth ?? 2)
        let limit = min(500, parameters.limit ?? 100)

        // Security: Validate path is within repo root
        let dirURL = URL(fileURLWithPath: dirPath)
        guard dirURL.standardized.path.hasPrefix(repoRoot.standardized.path) else {
            throw GitToolError.pathOutsideRepo(dirPath)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitToolError.notADirectory(dirPath)
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
                if skipDirectories.contains(name) {
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
            let sizeStr = entry.size.map { " (\(formatFileSize($0)))" } ?? ""
            lines.append("\(indent)\(icon) \(entry.name)\(sizeStr)")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatFileSize(_ size: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var size = Double(size)
        var unitIndex = 0
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(size)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", size, units[unitIndex])
    }
}

// MARK: - Glob Search Tool

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
        let searchPath = parameters.path ?? repoRoot.path
        let limit = min(200, parameters.limit ?? 50)

        // Security: Validate path is within repo root
        let searchURL = URL(fileURLWithPath: searchPath)
        guard searchURL.standardized.path.hasPrefix(repoRoot.standardized.path) else {
            throw GitToolError.pathOutsideRepo(searchPath)
        }

        // Parse the glob pattern
        let regex = try globToRegex(pattern)

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
            if ListDirectoryTool.skipDirectories.contains(itemURL.lastPathComponent) {
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

    /// Convert glob pattern to regex
    static func globToRegex(_ pattern: String) throws -> NSRegularExpression {
        var regex = "^"
        var i = pattern.startIndex

        while i < pattern.endIndex {
            let char = pattern[i]

            switch char {
            case "*":
                // Check for **
                let next = pattern.index(after: i)
                if next < pattern.endIndex && pattern[next] == "*" {
                    // ** matches any path
                    regex += ".*"
                    i = pattern.index(after: next)
                    // Skip following /
                    if i < pattern.endIndex && pattern[i] == "/" {
                        i = pattern.index(after: i)
                    }
                    continue
                } else {
                    // * matches anything except /
                    regex += "[^/]*"
                }
            case "?":
                regex += "[^/]"
            case ".":
                regex += "\\."
            case "/":
                regex += "/"
            case "[":
                regex += "["
            case "]":
                regex += "]"
            case "{":
                regex += "("
            case "}":
                regex += ")"
            case ",":
                regex += "|"
            default:
                // Escape special regex characters
                if "\\^$.|+()".contains(char) {
                    regex += "\\"
                }
                regex += String(char)
            }

            i = pattern.index(after: i)
        }

        regex += "$"
        return try NSRegularExpression(pattern: regex, options: [.caseInsensitive])
    }
}

// MARK: - Grep Search Tool

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
            "file_pattern": [
                "type": "string",
                "description": "Filter files by glob pattern (e.g., '*.swift', '*.ts')"
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum number of matching files to return. Default: 20"
            ],
            "context_lines": [
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

        enum CodingKeys: String, CodingKey {
            case pattern
            case path
            case filePattern = "file_pattern"
            case limit
            case contextLines = "context_lines"
        }
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
        let searchPath = parameters.path ?? repoRoot.path
        let limit = min(50, parameters.limit ?? 20)
        let contextLines = min(5, parameters.contextLines ?? 2)

        // Security: Validate path is within repo root
        let searchURL = URL(fileURLWithPath: searchPath)
        guard searchURL.standardized.path.hasPrefix(repoRoot.standardized.path) else {
            throw GitToolError.pathOutsideRepo(searchPath)
        }

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
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
        contextLines: Int
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
            if ListDirectoryTool.skipDirectories.contains(itemURL.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }

            let resources = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            if resources?.isDirectory == true { continue }

            // Check file pattern
            if let filePattern = filePattern {
                let globRegex = try GlobSearchTool.globToRegex(filePattern)
                let name = itemURL.lastPathComponent
                if globRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil {
                    continue
                }
            }

            // Skip binary files
            if ReadFileTool.isBinaryFile(at: itemURL) {
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

// MARK: - Complete Analysis Tool

struct CompleteAnalysisTool: AgentTool {
    static let name = "complete_analysis"
    static let description = """
        Call this tool when you have finished analyzing the repository and are ready to submit your findings.
        Provide a comprehensive assessment of the developer's skills based on the code you examined.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": [
                "type": "string",
                "description": "2-3 sentence overview of the developer's work and primary skills"
            ],
            "languages": [
                "type": "array",
                "description": "Programming languages identified with proficiency assessment",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "proficiency": ["type": "string", "enum": ["beginner", "intermediate", "advanced", "expert"]],
                        "evidence": ["type": "string", "description": "Specific files or patterns that demonstrate this skill"]
                    ],
                    "required": ["name", "proficiency", "evidence"]
                ]
            ],
            "technologies": [
                "type": "array",
                "description": "Frameworks, libraries, and tools identified",
                "items": ["type": "string"]
            ],
            "skills": [
                "type": "array",
                "description": "Technical skills demonstrated with evidence",
                "items": [
                    "type": "object",
                    "properties": [
                        "skill": ["type": "string"],
                        "evidence": ["type": "string"]
                    ],
                    "required": ["skill", "evidence"]
                ]
            ],
            "development_patterns": [
                "type": "object",
                "properties": [
                    "code_quality": ["type": "string"],
                    "testing_practices": ["type": "string"],
                    "documentation_quality": ["type": "string"],
                    "architecture_style": ["type": "string"]
                ]
            ],
            "highlights": [
                "type": "array",
                "description": "Notable achievements or impressive code patterns",
                "items": ["type": "string"]
            ],
            "evidence_files": [
                "type": "array",
                "description": "Key files that were examined to support this analysis",
                "items": ["type": "string"]
            ]
        ],
        "required": ["summary", "languages", "technologies", "skills", "highlights", "evidence_files"],
        "additionalProperties": false
    ]

    struct LanguageSkill: Codable {
        let name: String
        let proficiency: String
        let evidence: String
    }

    struct SkillAssessment: Codable {
        let skill: String
        let evidence: String
    }

    struct DevelopmentPatterns: Codable {
        let codeQuality: String?
        let testingPractices: String?
        let documentationQuality: String?
        let architectureStyle: String?

        enum CodingKeys: String, CodingKey {
            case codeQuality = "code_quality"
            case testingPractices = "testing_practices"
            case documentationQuality = "documentation_quality"
            case architectureStyle = "architecture_style"
        }
    }

    struct Parameters: Codable {
        let summary: String
        let languages: [LanguageSkill]
        let technologies: [String]
        let skills: [SkillAssessment]
        let developmentPatterns: DevelopmentPatterns?
        let highlights: [String]
        let evidenceFiles: [String]

        enum CodingKeys: String, CodingKey {
            case summary
            case languages
            case technologies
            case skills
            case developmentPatterns = "development_patterns"
            case highlights
            case evidenceFiles = "evidence_files"
        }
    }
}

// MARK: - Git Tool Errors

enum GitToolError: LocalizedError {
    case pathOutsideRepo(String)
    case fileNotFound(String)
    case notADirectory(String)
    case binaryFile(String)
    case ripgrepNotFound
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .pathOutsideRepo(let path):
            return "Path is outside the repository: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .notADirectory(let path):
            return "Not a directory: \(path)"
        case .binaryFile(let path):
            return "Cannot read binary file: \(path)"
        case .ripgrepNotFound:
            return "ripgrep (rg) not found"
        case .executionFailed(let message):
            return "Tool execution failed: \(message)"
        }
    }
}

// MARK: - Git Tool Registry

/// Registry of all available tools for the git analysis agent
struct GitToolRegistry {
    /// Get all tool definitions for LLM function calling
    static func allToolDefinitions() -> [[String: Any]] {
        [
            toolDefinition(for: ReadFileTool.self),
            toolDefinition(for: ListDirectoryTool.self),
            toolDefinition(for: GlobSearchTool.self),
            toolDefinition(for: GrepSearchTool.self),
            toolDefinition(for: CompleteAnalysisTool.self)
        ]
    }

    /// Create tool definition for LLM
    private static func toolDefinition<T: AgentTool>(for tool: T.Type) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.parametersSchema
            ]
        ]
    }
}
