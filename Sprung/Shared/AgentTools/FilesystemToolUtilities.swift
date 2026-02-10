//
//  FilesystemToolUtilities.swift
//  Sprung
//
//  Shared utilities for filesystem agent tools.
//

import Foundation

/// Shared utilities for filesystem tools
enum FilesystemToolUtilities {
    /// Directories to always skip when traversing
    static let skipDirectories = Set([
        ".git", "node_modules", "__pycache__", ".pytest_cache",
        "dist", "build", ".build", "DerivedData", "Pods",
        ".gradle", "target", "vendor", ".venv", "venv",
        ".idea", ".vscode", ".vs", "coverage", ".nyc_output",
        ".next", ".nuxt", "out", ".cache", ".parcel-cache"
    ])

    /// Resolves a user-provided path (which may be relative, ".", "/", or empty) against a repository root.
    /// Returns the resolved absolute path and validates it's within the repo root.
    /// - Parameters:
    ///   - userPath: The path provided by the LLM (could be ".", "/", "", relative, or absolute)
    ///   - repoRoot: The repository/sandbox root directory
    /// - Returns: The resolved absolute path within the repo
    /// - Throws: AgentToolError.pathOutsideRepo if the resolved path escapes the repo root
    static func resolveAndValidatePath(_ userPath: String, repoRoot: URL) throws -> String {
        // Handle empty string, ".", "/" as root of repo
        let normalizedPath: String
        if userPath.isEmpty || userPath == "." || userPath == "./" {
            normalizedPath = repoRoot.path
        } else if userPath == "/" {
            // "/" should mean the repo root, not filesystem root
            normalizedPath = repoRoot.path
        } else if userPath.hasPrefix("/") {
            // Absolute path - check if it's already under repoRoot
            normalizedPath = userPath
        } else {
            // Relative path - resolve against repoRoot
            normalizedPath = repoRoot.appendingPathComponent(userPath).path
        }

        // Resolve symlinks and normalize the path
        let resolvedURL = URL(fileURLWithPath: normalizedPath).standardized

        // Security check: ensure resolved path is within repo root
        guard resolvedURL.path.hasPrefix(repoRoot.standardized.path) else {
            throw AgentToolError.pathOutsideRepo(userPath)
        }

        return resolvedURL.path
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

    /// Format file size for display
    static func formatFileSize(_ size: Int64) -> String {
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

/// Global function for convenience
func resolveAndValidatePath(_ userPath: String, repoRoot: URL) throws -> String {
    try FilesystemToolUtilities.resolveAndValidatePath(userPath, repoRoot: repoRoot)
}
