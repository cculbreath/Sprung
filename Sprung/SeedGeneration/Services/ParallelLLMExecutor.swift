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
    private var waitQueue: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []

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
    ///   - config: Execution configuration
    /// - Returns: AsyncStream of task results
    func execute(
        tasks: [GenerationTask],
        generator: SectionGenerator,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
    ) -> AsyncStream<TaskExecutionResult> {
        AsyncStream { continuation in
            Task {
                await withTaskGroup(of: TaskExecutionResult.self) { group in
                    for task in tasks {
                        // Wait if at max concurrency
                        await self.waitForSlot()

                        group.addTask {
                            let result: TaskExecutionResult
                            do {
                                let content = try await generator.execute(
                                    task: task,
                                    context: context,
                                    config: config
                                )
                                result = TaskExecutionResult(
                                    taskId: task.id,
                                    result: .success(content)
                                )
                            } catch {
                                result = TaskExecutionResult(
                                    taskId: task.id,
                                    result: .failure(error)
                                )
                            }
                            await self.releaseSlot()
                            return result
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
        config: GeneratorExecutionConfig
    ) async -> TaskExecutionResult {
        await waitForSlot()

        let result: TaskExecutionResult
        do {
            let content = try await generator.execute(
                task: task,
                context: context,
                config: config
            )
            result = TaskExecutionResult(
                taskId: task.id,
                result: .success(content)
            )
        } catch {
            result = TaskExecutionResult(
                taskId: task.id,
                result: .failure(error)
            )
        }
        await releaseSlot()
        return result
    }

    // MARK: - Concurrency Control

    private func waitForSlot() async {
        if runningCount < maxConcurrent {
            runningCount += 1
            return
        }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waitQueue.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UUID) {
        if let index = waitQueue.firstIndex(where: { $0.id == id }) {
            let entry = waitQueue.remove(at: index)
            entry.continuation.resume()
        }
    }

    private func releaseSlot() {
        if let next = waitQueue.first {
            waitQueue.removeFirst()
            next.continuation.resume()
        } else {
            guard runningCount > 0 else { return }
            runningCount -= 1
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
    ///   - config: Execution configuration
    /// - Returns: Dictionary mapping task IDs to results
    func executeAll(
        tasks: [GenerationTask],
        generator: SectionGenerator,
        context: SeedGenerationContext,
        config: GeneratorExecutionConfig
    ) async -> [UUID: Result<GeneratedContent, Error>] {
        var results: [UUID: Result<GeneratedContent, Error>] = [:]

        let stream = execute(
            tasks: tasks,
            generator: generator,
            context: context,
            config: config
        )

        for await taskResult in stream {
            results[taskResult.taskId] = taskResult.result
        }

        return results
    }
}
