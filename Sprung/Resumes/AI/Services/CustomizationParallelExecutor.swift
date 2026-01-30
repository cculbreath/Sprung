//
//  CustomizationParallelExecutor.swift
//  Sprung
//
//  Manages concurrent execution of resume customization revision tasks.
//  Limits concurrency to avoid overwhelming the API and provides
//  streaming results as tasks complete.
//

import Foundation

// MARK: - Supporting Types

/// Type of revision for node-specific behavior
enum RevisionNodeType: String, Sendable {
    case skills          // Skills section (categories from LLM, skills from bank)
    case skillKeywords   // Individual skill category keywords
    case titles          // Title node (select from title set library)
    case generic         // Standard revision
}

/// A revision task to execute
struct RevisionTask: Identifiable, Sendable, Equatable {
    let id: UUID
    let revNode: ExportedReviewNode  // The node being revised
    let taskPrompt: String           // Task-specific prompt
    let nodeType: RevisionNodeType   // Type of revision
    let phase: Int                   // Phase number (1 or 2)

    init(
        id: UUID = UUID(),
        revNode: ExportedReviewNode,
        taskPrompt: String,
        nodeType: RevisionNodeType = .generic,
        phase: Int = 1
    ) {
        self.id = id
        self.revNode = revNode
        self.taskPrompt = taskPrompt
        self.nodeType = nodeType
        self.phase = phase
    }
}

/// Result of task execution
struct RevisionTaskResult: Sendable {
    let taskId: UUID
    let result: Result<ProposedRevisionNode, Error>
}

// MARK: - Parallel Execution Context

/// Lightweight context for parallel execution operations.
/// Contains serializable strings for use in concurrent tasks.
struct ParallelExecutionContext: Sendable {
    let jobPosting: String
    let resumeSnapshot: String
    let applicantProfile: String
    let additionalContext: String

    init(
        jobPosting: String = "",
        resumeSnapshot: String = "",
        applicantProfile: String = "",
        additionalContext: String = ""
    ) {
        self.jobPosting = jobPosting
        self.resumeSnapshot = resumeSnapshot
        self.applicantProfile = applicantProfile
        self.additionalContext = additionalContext
    }
}

// MARK: - Parallel Executor

/// Actor that manages parallel execution of resume revision tasks.
/// Limits concurrency and streams results as they complete.
actor CustomizationParallelExecutor {
    // MARK: - Configuration

    private let maxConcurrent: Int

    // MARK: - State

    private var runningCount = 0
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    // MARK: - Init

    init(maxConcurrent: Int = 5) {
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Public API

    /// Execute multiple revision tasks in parallel with concurrency limiting.
    /// Returns an AsyncStream that yields results as tasks complete.
    /// - Parameters:
    ///   - tasks: The revision tasks to execute
    ///   - context: The customization context
    ///   - llmFacade: The LLM facade for API calls
    ///   - modelId: The model ID to use
    ///   - preamble: The preamble to prepend to each task prompt
    /// - Returns: AsyncStream of task results
    func execute(
        tasks: [RevisionTask],
        context: ParallelExecutionContext,
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String
    ) -> AsyncStream<RevisionTaskResult> {
        AsyncStream { continuation in
            Task {
                await withTaskGroup(of: RevisionTaskResult.self) { group in
                    for task in tasks {
                        // Wait if at max concurrency
                        await self.waitForSlot()

                        group.addTask {
                            defer {
                                Task { await self.releaseSlot() }
                            }

                            return await self.executeTaskInternal(
                                task: task,
                                context: context,
                                llmFacade: llmFacade,
                                modelId: modelId,
                                preamble: preamble
                            )
                        }
                    }

                    // Yield results as they complete
                    for await result in group {
                        continuation.yield(result)
                    }
                }

                continuation.finish()
            }
        }
    }

    /// Execute a single revision task (convenience method)
    func executeSingle(
        task: RevisionTask,
        context: ParallelExecutionContext,
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String
    ) async -> RevisionTaskResult {
        await waitForSlot()
        defer {
            Task { await self.releaseSlot() }
        }

        return await executeTaskInternal(
            task: task,
            context: context,
            llmFacade: llmFacade,
            modelId: modelId,
            preamble: preamble
        )
    }

    // MARK: - Internal Execution

    private func executeTaskInternal(
        task: RevisionTask,
        context: ParallelExecutionContext,
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String
    ) async -> RevisionTaskResult {
        do {
            let fullPrompt = buildFullPrompt(preamble: preamble, task: task, context: context)

            let response = try await llmFacade.executeFlexibleJSON(
                prompt: fullPrompt,
                modelId: modelId,
                as: ProposedRevisionNode.self,
                temperature: 0.3
            )

            return RevisionTaskResult(
                taskId: task.id,
                result: .success(response)
            )
        } catch {
            return RevisionTaskResult(
                taskId: task.id,
                result: .failure(error)
            )
        }
    }

    private func buildFullPrompt(
        preamble: String,
        task: RevisionTask,
        context: ParallelExecutionContext
    ) -> String {
        var prompt = preamble

        // Add context sections if available
        if !context.jobPosting.isEmpty {
            prompt += "\n\n## Job Posting\n\(context.jobPosting)"
        }

        if !context.resumeSnapshot.isEmpty {
            prompt += "\n\n## Current Resume\n\(context.resumeSnapshot)"
        }

        if !context.applicantProfile.isEmpty {
            prompt += "\n\n## Applicant Profile\n\(context.applicantProfile)"
        }

        if !context.additionalContext.isEmpty {
            prompt += "\n\n## Additional Context\n\(context.additionalContext)"
        }

        // Add task-specific prompt
        prompt += "\n\n## Task\n\(task.taskPrompt)"

        // Add node information
        prompt += "\n\n## Node to Revise\n"
        prompt += "ID: \(task.revNode.id)\n"
        prompt += "Path: \(task.revNode.path)\n"
        prompt += "Display Name: \(task.revNode.displayName)\n"
        prompt += "Current Value: \(task.revNode.value)\n"

        if let childValues = task.revNode.childValues, !childValues.isEmpty {
            prompt += "Child Values: \(childValues.joined(separator: ", "))\n"
        }

        return prompt
    }

    // MARK: - Concurrency Control

    private func waitForSlot() async {
        if runningCount >= maxConcurrent {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let id = UUID()
                continuations[id] = continuation
            }
        }
        runningCount += 1
    }

    private func releaseSlot() {
        guard runningCount > 0 else {
            Logger.warning("releaseSlot called with runningCount at 0", category: .ai)
            return
        }
        runningCount -= 1

        // Resume a waiting task if any
        if let (id, continuation) = continuations.first {
            continuations.removeValue(forKey: id)
            continuation.resume()
        }
    }

    /// Current number of running tasks
    var currentRunningCount: Int {
        runningCount
    }

    /// Whether any tasks are running
    var isRunning: Bool {
        runningCount > 0
    }
}

// MARK: - Batch Execution Helper

extension CustomizationParallelExecutor {
    /// Execute all tasks and collect results.
    /// Useful when you need all results before proceeding.
    /// - Parameters:
    ///   - tasks: The revision tasks to execute
    ///   - context: The customization context
    ///   - llmFacade: The LLM facade for API calls
    ///   - modelId: The model ID to use
    ///   - preamble: The preamble to prepend to each task prompt
    /// - Returns: Dictionary mapping task IDs to results
    func executeAll(
        tasks: [RevisionTask],
        context: ParallelExecutionContext,
        llmFacade: LLMFacade,
        modelId: String,
        preamble: String
    ) async -> [UUID: Result<ProposedRevisionNode, Error>] {
        var results: [UUID: Result<ProposedRevisionNode, Error>] = [:]

        let stream = execute(
            tasks: tasks,
            context: context,
            llmFacade: llmFacade,
            modelId: modelId,
            preamble: preamble
        )

        for await taskResult in stream {
            results[taskResult.taskId] = taskResult.result
        }

        return results
    }
}
