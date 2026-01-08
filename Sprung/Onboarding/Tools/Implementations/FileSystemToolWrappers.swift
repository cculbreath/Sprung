//
//  FileSystemToolWrappers.swift
//  Sprung
//
//  Wraps GitAgent's FileSystemTools for use in the main interview LLM.
//  These tools allow the LLM to browse exported artifacts using familiar
//  filesystem operations (read_file, list_directory, glob_search, grep_search).
//
//  IMPORTANT: Tool responses are marked as ephemeral and will be pruned from
//  context after a few turns. The LLM should use timeline cards or knowledge
//  card tools to preserve important information discovered in artifacts.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

// MARK: - Artifact Filesystem Context

/// Manages the exported artifact filesystem root for tool execution.
/// Set by the coordinator when artifacts are exported.
actor ArtifactFilesystemContext {
    private var _rootURL: URL?

    var rootURL: URL? {
        _rootURL
    }

    func setRoot(_ url: URL?) {
        _rootURL = url
    }

    /// Initializer for dependency injection
    init(rootURL: URL? = nil) {
        self._rootURL = rootURL
    }
}

// MARK: - Read File Tool Wrapper

/// Wraps ReadFileTool for the interview LLM.
/// Reads artifact content with pagination (offset/limit).
struct ReadArtifactFileTool: InterviewTool {
    var name: String { "read_file" }

    private let context: ArtifactFilesystemContext

    init(context: ArtifactFilesystemContext) {
        self.context = context
    }

    var description: String {
        """
        Read content from an exported artifact file. Use offset and limit for pagination on large files.

        IMPORTANT: File content will be pruned from context after 3 turns. Use timeline cards or
        update_timeline_card to preserve important facts you discover.

        Returns file content with line numbers. Use offset to continue reading from where you left off.
        """
    }

    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Read file parameters",
            properties: [
                "path": JSONSchema(
                    type: .string,
                    description: "Path to the file (relative to artifacts root, e.g., 'resume_pdf/extracted_text.txt')"
                ),
                "offset": JSONSchema(
                    type: .integer,
                    description: "Line number to start reading from (1-indexed). Default: 1"
                ),
                "limit": JSONSchema(
                    type: .integer,
                    description: "Maximum number of lines to read. Default: 200, max: 500"
                )
            ],
            required: ["path"],
            additionalProperties: false
        )
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let rootURL = await context.rootURL else {
            return .error(.executionFailed("Artifact filesystem not initialized. No artifacts have been exported."))
        }

        let path = params["path"].stringValue
        let offset = params["offset"].int
        let limit = min(params["limit"].int ?? 200, 500)

        do {
            let fsParams = ReadFileTool.Parameters(
                path: path,
                offset: offset,
                limit: limit
            )
            let result = try ReadFileTool.execute(parameters: fsParams, repoRoot: rootURL)

            var response = JSON()
            response["status"].string = "success"
            response["content"].string = result.content
            response["total_lines"].int = result.totalLines
            response["start_line"].int = result.startLine
            response["end_line"].int = result.endLine
            response["has_more"].bool = result.hasMore
            if result.hasMore {
                response["next_offset"].int = result.endLine + 1
                response["hint"].string = "Use offset=\(result.endLine + 1) to continue reading"
            }
            response["ephemeral"].bool = true  // Mark for context pruning
            response["ephemeral_turns"].int = 3

            return .immediate(response)
        } catch {
            return .error(.executionFailed(error.localizedDescription))
        }
    }
}

// MARK: - List Directory Tool Wrapper

/// Wraps ListDirectoryTool for the interview LLM.
/// Lists exported artifact folders and files.
struct ListArtifactDirectoryTool: InterviewTool {
    var name: String { "list_directory" }

    private let context: ArtifactFilesystemContext

    init(context: ArtifactFilesystemContext) {
        self.context = context
    }

    var description: String {
        """
        List contents of the artifact directory. Shows folders (one per artifact) and their files.
        Each artifact folder contains: extracted_text.txt, summary.txt, and optionally card_inventory.json.

        Use depth=1 to see top-level artifact folders, depth=2 to see files within each.
        """
    }

    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: "List directory parameters",
            properties: [
                "path": JSONSchema(
                    type: .string,
                    description: "Directory path (use '.' or '/' for root). Default: root"
                ),
                "depth": JSONSchema(
                    type: .integer,
                    description: "Maximum recursion depth. Default: 2"
                ),
                "limit": JSONSchema(
                    type: .integer,
                    description: "Maximum entries to return. Default: 100"
                )
            ],
            additionalProperties: false
        )
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let rootURL = await context.rootURL else {
            return .error(.executionFailed("Artifact filesystem not initialized. No artifacts have been exported."))
        }

        let path = params["path"].string ?? "."
        let depth = params["depth"].int ?? 2
        let limit = params["limit"].int ?? 100

        do {
            let fsParams = ListDirectoryTool.Parameters(
                path: path,
                depth: depth,
                limit: limit
            )
            let result = try ListDirectoryTool.execute(parameters: fsParams, repoRoot: rootURL)

            var response = JSON()
            response["status"].string = "success"
            response["tree"].string = result.formattedTree
            response["total_entries"].int = result.totalCount
            response["truncated"].bool = result.truncated

            return .immediate(response)
        } catch {
            return .error(.executionFailed(error.localizedDescription))
        }
    }
}

// MARK: - Glob Search Tool Wrapper

/// Wraps GlobSearchTool for the interview LLM.
/// Find files matching glob patterns within exported artifacts.
struct GlobArtifactSearchTool: InterviewTool {
    var name: String { "glob_search" }

    private let context: ArtifactFilesystemContext

    init(context: ArtifactFilesystemContext) {
        self.context = context
    }

    var description: String {
        """
        Find files matching a glob pattern within exported artifacts.
        Examples: "**/*.txt" for all text files, "*/extracted_text.txt" for all extracted content.
        Results sorted by modification time (newest first).
        """
    }

    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Glob search parameters",
            properties: [
                "pattern": JSONSchema(
                    type: .string,
                    description: "Glob pattern (e.g., '**/*.txt', '*/summary.txt')"
                ),
                "path": JSONSchema(
                    type: .string,
                    description: "Directory to search in. Default: artifacts root"
                ),
                "limit": JSONSchema(
                    type: .integer,
                    description: "Maximum results to return. Default: 50"
                )
            ],
            required: ["pattern"],
            additionalProperties: false
        )
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let rootURL = await context.rootURL else {
            return .error(.executionFailed("Artifact filesystem not initialized. No artifacts have been exported."))
        }

        let pattern = params["pattern"].stringValue
        let path = params["path"].string
        let limit = params["limit"].int ?? 50

        do {
            let fsParams = GlobSearchTool.Parameters(
                pattern: pattern,
                path: path,
                limit: limit
            )
            let result = try GlobSearchTool.execute(parameters: fsParams, repoRoot: rootURL)

            var files = JSON([])
            for file in result.files {
                var entry = JSON()
                entry["path"].string = file.relativePath
                entry["size_bytes"].int64 = file.size
                files.arrayObject?.append(entry)
            }

            var response = JSON()
            response["status"].string = "success"
            response["files"] = files
            response["total_matches"].int = result.totalMatches
            response["truncated"].bool = result.truncated

            return .immediate(response)
        } catch {
            return .error(.executionFailed(error.localizedDescription))
        }
    }
}

// MARK: - Grep Search Tool Wrapper

/// Wraps GrepSearchTool for the interview LLM.
/// Search for patterns within artifact content.
struct GrepArtifactSearchTool: InterviewTool {
    var name: String { "grep_search" }

    private let context: ArtifactFilesystemContext

    init(context: ArtifactFilesystemContext) {
        self.context = context
    }

    var description: String {
        """
        Search for a pattern in artifact file contents. Returns matching lines with context.
        Supports regex patterns. Use to find specific information across all artifacts.

        IMPORTANT: Search results will be pruned from context after 3 turns. Use timeline cards
        to preserve important facts you discover.
        """
    }

    var parameters: JSONSchema {
        JSONSchema(
            type: .object,
            description: "Grep search parameters",
            properties: [
                "pattern": JSONSchema(
                    type: .string,
                    description: "Search pattern (regex or literal string)"
                ),
                "path": JSONSchema(
                    type: .string,
                    description: "Directory to search in. Default: artifacts root"
                ),
                "file_pattern": JSONSchema(
                    type: .string,
                    description: "Filter files by glob (e.g., '*.txt')"
                ),
                "limit": JSONSchema(
                    type: .integer,
                    description: "Maximum files to return. Default: 20"
                ),
                "context_lines": JSONSchema(
                    type: .integer,
                    description: "Lines of context before/after matches. Default: 2"
                )
            ],
            required: ["pattern"],
            additionalProperties: false
        )
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let rootURL = await context.rootURL else {
            return .error(.executionFailed("Artifact filesystem not initialized. No artifacts have been exported."))
        }

        let pattern = params["pattern"].stringValue
        let path = params["path"].string
        let filePattern = params["file_pattern"].string
        let limit = params["limit"].int ?? 20
        let contextLines = params["context_lines"].int ?? 2

        do {
            let fsParams = GrepSearchTool.Parameters(
                pattern: pattern,
                path: path,
                filePattern: filePattern,
                limit: limit,
                contextLines: contextLines
            )
            let result = try GrepSearchTool.execute(parameters: fsParams, repoRoot: rootURL)

            var response = JSON()
            response["status"].string = "success"
            response["formatted_results"].string = result.formatted
            response["total_files"].int = result.totalFiles
            response["total_matches"].int = result.totalMatches
            response["truncated"].bool = result.truncated
            response["ephemeral"].bool = true  // Mark for context pruning
            response["ephemeral_turns"].int = 3

            return .immediate(response)
        } catch {
            return .error(.executionFailed(error.localizedDescription))
        }
    }
}
