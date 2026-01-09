//
//  ToolOperation.swift
//  Sprung
//
//  Lifecycle wrapper for tool execution. Tracks state and enables
//  cancellation with proper cleanup.
//
//  Usage patterns:
//  - Blocking tools: Don't register (return immediately)
//  - Async tools: Register with .running(task)
//

import Foundation

/// Lifecycle wrapper for a single tool execution
actor ToolOperation {
    let callId: String
    let name: String
    let arguments: String
    let startedAt: Date

    private var task: Task<String, Error>?

    /// Tool execution state
    enum State: Sendable {
        case pending                              // Created, not yet started
        case running                              // Task execution in progress
        case completed(output: String)            // Finished successfully
        case cancelled(reason: String)            // Interrupted
        case failed(error: String)                // Threw error
    }

    private(set) var state: State = .pending

    init(callId: String, name: String, arguments: String = "", startedAt: Date = Date()) {
        self.callId = callId
        self.name = name
        self.arguments = arguments
        self.startedAt = startedAt
    }

    // MARK: - State Queries

    /// Check if operation was cancelled (tools should check this periodically)
    var isCancelled: Bool {
        if case .cancelled = state { return true }
        return false
    }

    /// Check if operation has reached a terminal state
    var isTerminal: Bool {
        switch state {
        case .completed, .cancelled, .failed:
            return true
        case .pending, .running:
            return false
        }
    }

    // MARK: - State Transitions

    /// Set state to running with a cancellable task
    func setRunning(task: Task<String, Error>) {
        guard !isTerminal else {
            Logger.warning("ToolOperation[\(callId.prefix(8))]: Cannot set running, already terminal", category: .ai)
            return
        }
        self.task = task
        self.state = .running
        Logger.debug("ToolOperation[\(callId.prefix(8))]: State -> running", category: .ai)
    }

    /// Complete the operation successfully
    func complete(output: String) {
        guard !isTerminal else {
            Logger.warning("ToolOperation[\(callId.prefix(8))]: Cannot complete, already terminal", category: .ai)
            return
        }
        state = .completed(output: output)
        Logger.debug("ToolOperation[\(callId.prefix(8))]: State -> completed", category: .ai)
    }

    /// Cancel the operation (cancels task if any)
    func cancel(reason: String = "User interrupted") {
        guard !isTerminal else {
            Logger.debug("ToolOperation[\(callId.prefix(8))]: Already terminal, skip cancel", category: .ai)
            return
        }

        // Cancel running task if any
        if let task = task {
            task.cancel()
            Logger.debug("ToolOperation[\(callId.prefix(8))]: Cancelled task", category: .ai)
        }

        state = .cancelled(reason: reason)
        Logger.info("ToolOperation[\(callId.prefix(8))]: State -> cancelled(\(reason))", category: .ai)
    }

    /// Mark the operation as failed
    func fail(error: Error) {
        guard !isTerminal else {
            Logger.warning("ToolOperation[\(callId.prefix(8))]: Cannot fail, already terminal", category: .ai)
            return
        }
        state = .failed(error: error.localizedDescription)
        Logger.warning("ToolOperation[\(callId.prefix(8))]: State -> failed(\(error.localizedDescription))", category: .ai)
    }

    // MARK: - Result

    /// Get result (real output or synthetic based on state)
    var result: String {
        switch state {
        case .completed(let output):
            return output
        case .cancelled(let reason):
            return #"{"status":"cancelled","reason":"\#(reason)"}"#
        case .failed(let error):
            return #"{"status":"error","reason":"\#(error)"}"#
        case .pending, .running:
            return #"{"status":"error","reason":"Operation not complete"}"#
        }
    }
}
