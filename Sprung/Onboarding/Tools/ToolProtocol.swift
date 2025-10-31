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
    var isStrict: Bool { get }
    func isAvailable() async -> Bool

    func execute(_ params: JSON) async throws -> ToolResult
}

extension InterviewTool {
    var isStrict: Bool { false }
    func isAvailable() async -> Bool { true }
}

enum ToolResult {
    case immediate(JSON)
    case waiting(message: String, continuation: ContinuationToken)
    case error(ToolError)
}

struct ContinuationToken {
    let id: UUID
    let toolName: String
    let initialPayload: JSON?
    let resumeHandler: @Sendable (JSON) async -> ToolResult

    init(
        id: UUID,
        toolName: String,
        initialPayload: JSON? = nil,
        resumeHandler: @Sendable @escaping (JSON) async -> ToolResult
    ) {
        self.id = id
        self.toolName = toolName
        self.initialPayload = initialPayload
        self.resumeHandler = resumeHandler
    }
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
    let callId: String
}
