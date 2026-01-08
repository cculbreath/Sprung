//
//  ToolOperation.swift
//  Sprung
//
//  Lifecycle wrapper for tool execution. Tracks state and enables
//  cancellation with proper cleanup (task cancellation, UI dismissal).
//
//  Usage patterns:
//  - Blocking tools: Don't register (return immediately)
//  - UI tools: Register with .awaitingUser(dismissUI:)
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
    private var uiDismissHandler: (() async -> Void)?

    /// Tool execution state
    enum State: Sendable {
        case pending                              // Created, not yet started
        case running                              // Task execution in progress
        case awaitingUser                         // Blocked on user interaction
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
        case .pending, .running, .awaitingUser:
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

    /// Set state to awaiting user (dismiss handler can be set later via setDismissHandler)
    func setAwaitingUser() {
        guard !isTerminal else {
            Logger.warning("ToolOperation[\(callId.prefix(8))]: Cannot set awaitingUser, already terminal", category: .ai)
            return
        }
        self.state = .awaitingUser
        Logger.debug("ToolOperation[\(callId.prefix(8))]: State -> awaitingUser", category: .ai)
    }

    /// Set state to awaiting user with a dismiss callback
    func setAwaitingUser(dismissUI: @escaping () async -> Void) {
        guard !isTerminal else {
            Logger.warning("ToolOperation[\(callId.prefix(8))]: Cannot set awaitingUser, already terminal", category: .ai)
            return
        }
        self.uiDismissHandler = dismissUI
        self.state = .awaitingUser
        Logger.debug("ToolOperation[\(callId.prefix(8))]: State -> awaitingUser", category: .ai)
    }

    /// Set the dismiss handler for UI cleanup (can be set after setAwaitingUser())
    func setDismissHandler(_ handler: @escaping () async -> Void) {
        self.uiDismissHandler = handler
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

    /// Cancel the operation (cancels task, dismisses UI)
    func cancel(reason: String = "User interrupted") async {
        guard !isTerminal else {
            Logger.debug("ToolOperation[\(callId.prefix(8))]: Already terminal, skip cancel", category: .ai)
            return
        }

        // Cancel running task if any
        if let task = task {
            task.cancel()
            Logger.debug("ToolOperation[\(callId.prefix(8))]: Cancelled task", category: .ai)
        }

        // Dismiss UI if any
        if let dismiss = uiDismissHandler {
            await dismiss()
            Logger.debug("ToolOperation[\(callId.prefix(8))]: Dismissed UI", category: .ai)
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
        case .pending, .running, .awaitingUser:
            return #"{"status":"error","reason":"Operation not complete"}"#
        }
    }
}
