//
//  ToolExecutor.swift
//  Sprung
//
//  Executes onboarding interview tools and manages continuations.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

actor ToolExecutor {
    private let registry: ToolRegistry
    private var continuations: [UUID: ContinuationToken] = [:]

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    func availableToolSchemas(allowedNames: Set<String>? = nil) async -> [Tool] {
        await registry.toolSchemas(filteredBy: allowedNames)
    }

    func handleToolCall(_ call: ToolCall) async throws -> ToolResult {
        guard let tool = registry.tool(named: call.name) else {
            throw ToolError.invalidParameters("Unknown tool: \(call.name)")
        }

        do {
            let result = try await tool.execute(call.arguments)
            return normalize(result, toolName: call.name)
        } catch {
            return errorResult(for: call.name, error: error)
        }
    }

    func resumeContinuation(id: UUID, with input: JSON) async throws -> ToolResult {
        guard let token = continuations.removeValue(forKey: id) else {
            throw ToolError.invalidParameters("Unknown continuation: \(id)")
        }
        let result = await token.resumeHandler(input)
        return normalize(result, toolName: token.toolName)
    }

    /// Get a continuation token (without removing it)
    func getContinuation(id: UUID) -> ContinuationToken? {
        continuations[id]
    }

    // MARK: - Helpers

    private func normalize(_ result: ToolResult, toolName: String) -> ToolResult {
        switch result {
        case .immediate:
            return result
        case .waiting(_, let token):
            continuations[token.id] = token
            return result
        case .error(let error):
            return errorResult(for: toolName, error: error)
        }
    }

    private func errorResult(for toolName: String, error: Error) -> ToolResult {
        let reason: String
        let message: String

        switch error {
        case let toolError as ToolError:
            switch toolError {
            case .invalidParameters(let text):
                reason = "invalid_parameters"
                message = text
            case .executionFailed(let text):
                reason = "execution_failed"
                message = text
            case .timeout(let interval):
                reason = "timeout"
                message = "Tool timed out after \(String(format: "%.2f", interval)) seconds."
            case .userCancelled:
                reason = "user_cancelled"
                message = "User cancelled the operation."
            case .permissionDenied(let text):
                reason = "permission_denied"
                message = text
            }
        default:
            reason = "unknown_error"
            message = error.localizedDescription
        }

        var payload = JSON()
        payload["status"].string = "error"
        payload["reason"].string = reason
        payload["message"].string = message
        payload["tool"].string = toolName

        Logger.warning("⚠️ Tool \(toolName) failed: \(message)", category: .ai)
        return .immediate(payload)
    }
}
