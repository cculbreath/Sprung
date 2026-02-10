//
//  AgentToolError.swift
//  Sprung
//
//  Error types for agent filesystem tools.
//

import Foundation

/// Errors from agent filesystem tools
enum AgentToolError: LocalizedError {
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
