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
