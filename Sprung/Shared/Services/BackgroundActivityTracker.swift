//
//  BackgroundActivityTracker.swift
//  Sprung
//
//  Tracks background LLM operations with real-time transcript entries.
//  Similar to onboarding's AgentActivityTracker but for any background operation.
//

import Foundation

/// Type of background operation being tracked
enum BackgroundOperationType: String, Codable, CaseIterable {
    case preprocessing = "preprocessing"
    // Future: coverLetterGeneration, resumeOptimization, etc.

    var displayName: String {
        switch self {
        case .preprocessing: return "Preprocessing"
        }
    }

    var icon: String {
        switch self {
        case .preprocessing: return "doc.text.magnifyingglass"
        }
    }
}

/// Status of a tracked operation
enum BackgroundOperationStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
}

/// A single transcript entry in an operation
struct BackgroundTranscriptEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let entryType: EntryType
    let content: String
    let details: String?

    enum EntryType: String, Codable {
        case system
        case llmRequest
        case llmResponse
        case error
        case phase
    }

    init(id: UUID = UUID(), timestamp: Date = Date(), entryType: EntryType, content: String, details: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.entryType = entryType
        self.content = content
        self.details = details
    }
}

/// A tracked background operation with transcript
struct TrackedOperation: Identifiable, Codable {
    let id: String
    let operationType: BackgroundOperationType
    let name: String
    var status: BackgroundOperationStatus
    let startTime: Date
    var endTime: Date?
    var transcript: [BackgroundTranscriptEntry]
    var error: String?
    var currentPhase: String?

    // Metrics
    var inputTokens: Int
    var outputTokens: Int

    init(
        id: String,
        operationType: BackgroundOperationType,
        name: String,
        status: BackgroundOperationStatus = .pending,
        startTime: Date = Date(),
        endTime: Date? = nil,
        transcript: [BackgroundTranscriptEntry] = [],
        error: String? = nil,
        currentPhase: String? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.id = id
        self.operationType = operationType
        self.name = name
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
        self.transcript = transcript
        self.error = error
        self.currentPhase = currentPhase
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    var duration: TimeInterval? {
        guard let end = endTime else {
            return status == .running ? Date().timeIntervalSince(startTime) : nil
        }
        return end.timeIntervalSince(startTime)
    }
}

/// Tracks multiple background operations with real-time updates
@Observable
@MainActor
final class BackgroundActivityTracker {
    private(set) var operations: [TrackedOperation] = []
    var selectedOperationId: String?

    // MARK: - Lifecycle

    /// Start tracking a new operation
    /// - Returns: The operation ID for subsequent updates
    @discardableResult
    func trackOperation(id: String, type: BackgroundOperationType, name: String) -> String {
        let operation = TrackedOperation(
            id: id,
            operationType: type,
            name: name,
            status: .running
        )
        operations.insert(operation, at: 0)

        // Auto-select if this is the first or only running operation
        if selectedOperationId == nil || operations.filter({ $0.status == .running }).count == 1 {
            selectedOperationId = id
        }

        return id
    }

    /// Append a transcript entry to an operation
    func appendTranscript(
        operationId: String,
        entryType: BackgroundTranscriptEntry.EntryType,
        content: String,
        details: String? = nil
    ) {
        guard let index = operations.firstIndex(where: { $0.id == operationId }) else { return }
        let entry = BackgroundTranscriptEntry(
            entryType: entryType,
            content: content,
            details: details
        )
        operations[index].transcript.append(entry)
    }

    /// Update the current phase of an operation
    func updatePhase(operationId: String, phase: String) {
        guard let index = operations.firstIndex(where: { $0.id == operationId }) else { return }
        operations[index].currentPhase = phase

        // Also add a phase entry to transcript
        let entry = BackgroundTranscriptEntry(
            entryType: .phase,
            content: phase
        )
        operations[index].transcript.append(entry)
    }

    /// Mark an operation as completed
    func markCompleted(operationId: String) {
        guard let index = operations.firstIndex(where: { $0.id == operationId }) else { return }
        operations[index].status = .completed
        operations[index].endTime = Date()
        operations[index].currentPhase = nil
    }

    /// Mark an operation as failed
    func markFailed(operationId: String, error: String) {
        guard let index = operations.firstIndex(where: { $0.id == operationId }) else { return }
        operations[index].status = .failed
        operations[index].endTime = Date()
        operations[index].error = error
        operations[index].currentPhase = nil

        // Add error to transcript
        let entry = BackgroundTranscriptEntry(
            entryType: .error,
            content: error
        )
        operations[index].transcript.append(entry)
    }

    /// Add token usage to an operation
    func addTokenUsage(operationId: String, input: Int, output: Int) {
        guard let index = operations.firstIndex(where: { $0.id == operationId }) else { return }
        operations[index].inputTokens += input
        operations[index].outputTokens += output
    }

    // MARK: - Queries

    var runningCount: Int {
        operations.filter { $0.status == .running }.count
    }

    var hasRunningOperations: Bool {
        runningCount > 0
    }

    func getOperation(id: String) -> TrackedOperation? {
        operations.first { $0.id == id }
    }

    // MARK: - Cleanup

    /// Clear completed and failed operations
    func clearCompleted() {
        operations.removeAll { $0.status == .completed || $0.status == .failed }
        // Reset selection if cleared
        if let selectedId = selectedOperationId, getOperation(id: selectedId) == nil {
            selectedOperationId = operations.first?.id
        }
    }
}
