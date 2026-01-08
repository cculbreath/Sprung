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
        let callId = await operation.callId
        operations[callId] = operation
        Logger.debug("OperationTracker: Registered operation \(callId.prefix(8))", category: .ai)
    }

    /// Check if an operation is registered
    func hasOperation(callId: String) -> Bool {
        operations[callId] != nil
    }

    // MARK: - Lifecycle

    /// Complete an operation with output
    func complete(callId: String, output: String) async {
        guard let op = operations[callId] else {
            Logger.warning("OperationTracker: Cannot complete unknown operation \(callId.prefix(8))", category: .ai)
            return
        }
        await op.complete(output: output)
    }

    /// Cancel a specific operation
    func cancel(callId: String, reason: String = "User interrupted") async {
        guard let op = operations[callId] else {
            Logger.debug("OperationTracker: Cannot cancel unknown operation \(callId.prefix(8))", category: .ai)
            return
        }
        await op.cancel(reason: reason)
    }

    /// Cancel all active operations
    func cancelAll(reason: String = "User interrupted") async {
        for op in operations.values {
            await op.cancel(reason: reason)
        }
        Logger.info("OperationTracker: Cancelled all \(operations.count) operations", category: .ai)
    }

    /// Mark an operation as failed
    func fail(callId: String, error: Error) async {
        guard let op = operations[callId] else {
            Logger.warning("OperationTracker: Cannot fail unknown operation \(callId.prefix(8))", category: .ai)
            return
        }
        await op.fail(error: error)
    }

    // MARK: - Result Retrieval

    /// Get the result for an operation (real or synthetic)
    func getResult(callId: String) async -> String? {
        guard let op = operations[callId] else {
            return nil
        }
        return await op.result
    }

    /// Check if an operation has reached terminal state
    func isTerminal(callId: String) async -> Bool {
        guard let op = operations[callId] else {
            return true  // Unknown operations are effectively terminal
        }
        return await op.isTerminal
    }

    // MARK: - Cleanup

    /// Remove completed/cancelled/failed operations from tracking
    func cleanup(callIds: [String]) {
        for callId in callIds {
            operations.removeValue(forKey: callId)
        }
        if !callIds.isEmpty {
            Logger.debug("OperationTracker: Cleaned up \(callIds.count) operations", category: .ai)
        }
    }

    /// Remove all operations (for reset)
    func reset() {
        let count = operations.count
        operations.removeAll()
        Logger.info("OperationTracker: Reset, removed \(count) operations", category: .ai)
    }

    // MARK: - Queries

    /// Get all active (non-terminal) operation IDs
    func activeOperationIds() async -> [String] {
        var active: [String] = []
        for (callId, op) in operations {
            if await !op.isTerminal {
                active.append(callId)
            }
        }
        return active
    }

    /// Get count of active operations
    var activeCount: Int {
        get async {
            var count = 0
            for op in operations.values {
                if await !op.isTerminal {
                    count += 1
                }
            }
            return count
        }
    }
}
