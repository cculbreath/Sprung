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
    /// Default to strict mode for guaranteed schema validation.
    /// Per Anthropic best practices: "Add strict: true to your tool definitions to ensure
    /// Claude's tool calls always match your schema exactly—no more type mismatches or missing fields."
    var isStrict: Bool { true }
    func isAvailable() async -> Bool { true }
}
enum ToolResult {
    case immediate(JSON)
    case error(ToolError)
}
enum ToolError: Error {
    case invalidParameters(String)
    case executionFailed(String)
    case timeout(TimeInterval)
    case userCancelled
    case permissionDenied(String)
}
struct ToolCall {
    let name: String
    let arguments: JSON
    let callId: String
}
