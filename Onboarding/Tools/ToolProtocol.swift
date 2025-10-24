//
//  ToolProtocol.swift
//  Sprung
//
//  Canonical tool protocol for onboarding interview feature.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

protocol InterviewTool {
    var name: String { get }
    var description: String { get }
    var parameters: JSONSchema { get }

    func execute(_ params: JSON) async throws -> ToolResult
}

enum ToolResult {
    case immediate(JSON)
    case waiting(message: String, continuation: ContinuationToken)
    case error(ToolError)
}

struct ContinuationToken {
    let id: UUID
    let toolName: String
    let resumeHandler: @Sendable (JSON) async -> ToolResult
}

enum ToolError: Error {
    case invalidParameters(String)
    case executionFailed(String)
    case timeout(TimeInterval)
    case userCancelled
    case permissionDenied(String)
}

struct ToolCall {
    let id: String
    let name: String
    let arguments: JSON
}

