//
//  ToolExecutor.swift
//  Sprung
//
//  Executes onboarding interview tools and manages continuations.
//
import Foundation
import SwiftOpenAI
import SwiftyJSON
/// A tool execution's result plus the ids it minted through the determinism seam.
/// `mintedIds` is teed to the tape (recording) so a re-executable tool can
/// reproduce those exact ids on replay; it is empty for replayed and no-mint calls.
struct ExecutedToolCall {
    let result: ToolResult
    let mintedIds: [String]
}

actor ToolExecutor {
    private let registry: ToolRegistry

    /// When set (session replay), recorded tool results drive the outcome by
    /// callId. External / IO / LLM tools are served verbatim and NEVER re-run;
    /// pure-local state-building tools (see `ReplayToolGateway.shouldReExecute`)
    /// are RE-EXECUTED for their side effects so domain state rebuilds for real.
    /// Cleared on go-live.
    private var replayGateway: ReplayToolGateway?

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    /// Install (or clear, with nil) the replay tool gateway.
    func setReplayGateway(_ gateway: ReplayToolGateway?) {
        self.replayGateway = gateway
    }

    func handleToolCall(_ call: ToolCall) async throws -> ExecutedToolCall {
        // Replay path: the recorded result for this callId decides the outcome.
        if let gateway = replayGateway, let recorded = await gateway.recordedResult(callId: call.callId) {
            if ReplayToolGateway.shouldReExecute(toolName: call.name) {
                // Re-run for side effects (rebuild domain state) with the recorded
                // id sequence, then return the recorded output verbatim below so
                // the replayed conversation history stays byte-faithful.
                await reExecuteForSideEffects(call, recorded: recorded)
            } else {
                Logger.info("⏪ Replay: serving recorded result for \(call.name) (\(call.callId.prefix(8)))", category: .ai)
            }
            let parsed = JSON(parseJSON: recorded.output)
            let result: ToolResult = .immediate(parsed.type != .null ? parsed : JSON(["output": recorded.output]))
            return ExecutedToolCall(result: result, mintedIds: [])
        }
        guard let tool = registry.tool(named: call.name) else {
            throw ToolError.invalidParameters("Unknown tool: \(call.name)")
        }
        // Normal (live / recording) path: capture minted ids through the seam so a
        // later replay can serve them back to re-executable tools.
        let context = DeterminismContext(mode: .recording)
        do {
            let result = try await DeterminismScope.$current.withValue(context) {
                try await tool.execute(call.arguments)
            }
            return ExecutedToolCall(result: normalize(result, toolName: call.name), mintedIds: context.mintedIds)
        } catch {
            return ExecutedToolCall(result: errorResult(for: call.name, error: error), mintedIds: context.mintedIds)
        }
    }

    /// Re-execute a whitelisted, pure-local, deterministic state-building tool
    /// during replay so its domain side effects (timeline / dossier / todo /
    /// artifact mutations) are rebuilt for real. The determinism seam is seeded
    /// with the recorded id sequence so re-created entities keep the exact ids that
    /// later recorded turns reference. The tool's own result is discarded — the
    /// caller returns the recorded output verbatim for history fidelity.
    private func reExecuteForSideEffects(_ call: ToolCall, recorded: TapeToolResult) async {
        guard let tool = registry.tool(named: call.name) else { return }
        Logger.info("⏪ Replay: re-executing \(call.name) (\(call.callId.prefix(8))) to rebuild domain state", category: .ai)
        let context = DeterminismContext(mode: .replaying(recorded.mintedIds ?? []))
        do {
            _ = try await DeterminismScope.$current.withValue(context) {
                try await tool.execute(call.arguments)
            }
        } catch {
            Logger.warning("⏪ Replay re-exec of \(call.name) threw (domain state may be incomplete): \(error.localizedDescription)", category: .ai)
        }
        if context.didExhaust {
            Logger.warning("📉 Replay seam exhausted re-executing \(call.name) (\(call.callId.prefix(8))) — re-exec minted more ids than recorded; domain state may diverge", category: .ai)
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
