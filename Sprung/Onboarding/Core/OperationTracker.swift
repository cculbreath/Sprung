//
//  OperationTracker.swift
//  Sprung
//
//  Manages active tool operations. Provides registration, cancellation,
//  and result retrieval. Works with ConversationLog for interrupt handling.
//

import Foundation

/// Manages the collection of active tool operations
actor OperationTracker {

    private var operations: [String: ToolOperation] = [:]

    // MARK: - Registration

    /// Register a new tool operation
    func register(_ operation: ToolOperation) async {
        let callId = operation.callId
        operations[callId] = operation
        Logger.debug("OperationTracker: Registered operation \(callId.prefix(8))", category: .ai)
    }

    // MARK: - Lifecycle

    /// Cancel a specific operation
    func cancel(callId: String, reason: String = "User interrupted") async {
        guard let op = operations[callId] else {
            Logger.debug("OperationTracker: Cannot cancel unknown operation \(callId.prefix(8))", category: .ai)
            return
        }
        await op.cancel(reason: reason)
    }

    // MARK: - Result Retrieval

    /// Get the result for an operation (real or synthetic)
    func getResult(callId: String) async -> String? {
        guard let op = operations[callId] else {
            return nil
        }
        return await op.result
    }

    // MARK: - Cleanup

    /// Remove all operations (for reset)
    func reset() {
        let count = operations.count
        operations.removeAll()
        Logger.info("OperationTracker: Reset, removed \(count) operations", category: .ai)
    }

}
