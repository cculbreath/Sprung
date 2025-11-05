import Foundation
import SwiftyJSON

/// Manages tool continuation tracking and resumption.
/// Extracted from OnboardingInterviewCoordinator to improve maintainability.
@MainActor
final class ContinuationTracker {
    // MARK: - Dependencies

    private let toolExecutionCoordinator: ToolExecutionCoordinator

    // MARK: - State

    private var toolQueueEntries: [UUID: ToolQueueEntry] = [:]
    private var phaseAdvanceContinuationId: UUID?

    // MARK: - Types

    private struct ToolQueueEntry {
        let tokenId: UUID
        let callId: String
        let toolName: String
        let status: String
        let requestedInput: String
        let enqueuedAt: Date
    }

    // MARK: - Initialization

    init(toolExecutionCoordinator: ToolExecutionCoordinator) {
        self.toolExecutionCoordinator = toolExecutionCoordinator
    }

    // MARK: - Continuation Tracking

    func trackContinuation(id: UUID, toolName: String) {
        toolQueueEntries[id] = ToolQueueEntry(
            tokenId: id,
            callId: "", // CallId managed by ToolExecutionCoordinator
            toolName: toolName,
            status: "waiting",
            requestedInput: "{}",
            enqueuedAt: Date()
        )
        Logger.debug("⏸️ Queued continuation for \(toolName) (\(id))", category: .ai)
    }

    func trackPhaseAdvanceContinuation(id: UUID) {
        phaseAdvanceContinuationId = id
    }

    func clearPhaseAdvanceContinuation() {
        phaseAdvanceContinuationId = nil
    }

    func getPhaseAdvanceContinuationId() -> UUID? {
        phaseAdvanceContinuationId
    }

    // MARK: - Continuation Resumption

    func resumeToolContinuation(from result: (UUID, JSON)?) async {
        guard let (id, payload) = result else { return }
        await resumeToolContinuation(id: id, payload: payload)
    }

    func resumeToolContinuation(id: UUID, payload: JSON) async {
        let entry = toolQueueEntries.removeValue(forKey: id)
        let label = entry?.toolName ?? "unknown_tool"
        Logger.info("✅ Resuming tool continuation \(label) (\(id))", category: .ai)

        do {
            try await toolExecutionCoordinator.resumeToolContinuation(
                id: id,
                userInput: payload
            )
        } catch {
            Logger.error("Failed to resume tool: \(error)", category: .ai)
        }
    }
}
