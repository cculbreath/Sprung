//
//  ParallelLLMExecutor.swift
//  Sprung
//
//  Manages concurrent execution of LLM generation tasks.
//  Limits concurrency to avoid overwhelming the API and provides
//  streaming results as tasks complete.
//

import Foundation

/// Result of a task execution
struct TaskExecutionResult: Sendable {
    let taskId: UUID
    let result: Result<GeneratedContent, Error>
}

/// Actor that manages parallel execution of generation tasks.
/// Limits concurrency and streams results as they complete.
actor ParallelLLMExecutor {
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

    /// Execute multiple tasks in parallel with concurrency limiting.
    /// Returns an AsyncStream that yields results as tasks complete.
    /// - Parameters:
    ///   - tasks: The tasks to execute
    ///   - generator: The generator to use for execution
    ///   - context: The generation context
    ///   - preamble: Cached preamble for prompts
    ///   - llmFacade: The LLM facade to use
    ///   - modelId: The model ID to use
    /// - Returns: AsyncStream of task results
    func execute(
        tasks: [GenerationTask],
        generator: SectionGenerator,
        context: SeedGenerationContext,
        preamble: String,
        llmFacade: LLMFacade,
        modelId: String
    ) -> AsyncStream<TaskExecutionResult> {
        AsyncStream { continuation in
            Task {
                await withTaskGroup(of: TaskExecutionResult.self) { group in
                    for task in tasks {
                        // Wait if at max concurrency
                        await self.waitForSlot()

                        group.addTask {
                            defer {
                                Task { await self.releaseSlot() }
                            }

                            do {
                                let content = try await generator.execute(
                                    task: task,
                                    context: context,
                                    preamble: preamble,
                                    llmFacade: llmFacade,
                                    modelId: modelId
                                )
                                return TaskExecutionResult(
                                    taskId: task.id,
                                    result: .success(content)
                                )
                            } catch {
                                return TaskExecutionResult(
                                    taskId: task.id,
                                    result: .failure(error)
                                )
                            }
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

    /// Execute a single task (convenience method)
    func executeSingle(
        task: GenerationTask,
        generator: SectionGenerator,
        context: SeedGenerationContext,
        preamble: String,
        llmFacade: LLMFacade,
        modelId: String
    ) async -> TaskExecutionResult {
        await waitForSlot()
        defer {
            Task { await self.releaseSlot() }
        }

        do {
            let content = try await generator.execute(
                task: task,
                context: context,
                preamble: preamble,
                llmFacade: llmFacade,
                modelId: modelId
            )
            return TaskExecutionResult(
                taskId: task.id,
                result: .success(content)
            )
        } catch {
            return TaskExecutionResult(
                taskId: task.id,
                result: .failure(error)
            )
        }
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

extension ParallelLLMExecutor {
    /// Execute all tasks and collect results.
    /// Useful when you need all results before proceeding.
    /// - Parameters:
    ///   - tasks: The tasks to execute
    ///   - generator: The generator to use
    ///   - context: The generation context
    ///   - preamble: Cached preamble
    ///   - llmFacade: LLM facade to use
    ///   - modelId: Model ID to use
    /// - Returns: Dictionary mapping task IDs to results
    func executeAll(
        tasks: [GenerationTask],
        generator: SectionGenerator,
        context: SeedGenerationContext,
        preamble: String,
        llmFacade: LLMFacade,
        modelId: String
    ) async -> [UUID: Result<GeneratedContent, Error>] {
        var results: [UUID: Result<GeneratedContent, Error>] = [:]

        let stream = execute(
            tasks: tasks,
            generator: generator,
            context: context,
            preamble: preamble,
            llmFacade: llmFacade,
            modelId: modelId
        )

        for await taskResult in stream {
            results[taskResult.taskId] = taskResult.result
        }

        return results
    }
}
