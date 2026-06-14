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

    /// When set (session replay), recorded tool results are served verbatim by
    /// callId and the real tool NEVER executes — so PDF ingestion / git agent /
    /// network tools don't re-run during replay. Cleared on go-live.
    private var replayGateway: ReplayToolGateway?

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    /// Install (or clear, with nil) the replay tool gateway.
    func setReplayGateway(_ gateway: ReplayToolGateway?) {
        self.replayGateway = gateway
    }

    func handleToolCall(_ call: ToolCall) async throws -> ToolResult {
        // Replay short-circuit: serve the recorded result for this callId without
        // executing the real tool. The exact bytes here don't affect replay
        // ordering (recorded model streams are served by turn order, not by tool
        // output), so parsing the recorded output as JSON is safe.
        if let recorded = await replayGateway?.recordedResult(callId: call.callId) {
            Logger.info("⏪ Replay: serving recorded result for \(call.name) (\(call.callId.prefix(8)))", category: .ai)
            let parsed = JSON(parseJSON: recorded.output)
            return .immediate(parsed.type != .null ? parsed : JSON(["output": recorded.output]))
        }
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
    // MARK: - Helpers
    private func normalize(_ result: ToolResult, toolName: String) -> ToolResult {
        switch result {
        case .immediate:
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
        payload["status"].string = "completed"
        payload["error"].bool = true
        payload["reason"].string = reason
        payload["message"].string = message
        payload["tool"].string = toolName
        Logger.warning("⚠️ Tool \(toolName) failed: \(message)", category: .ai)
        return .immediate(payload)
    }
}
