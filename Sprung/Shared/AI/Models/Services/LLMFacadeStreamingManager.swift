//
//  LLMFacadeStreamingManager.swift
//  Sprung
//
//  Manages streaming task lifecycle for LLM operations.
//  Extracted from LLMFacade for single responsibility.
//

import Foundation

/// Manages streaming task lifecycle for LLM operations
@MainActor
final class LLMFacadeStreamingManager {
    private var activeStreamingTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Task Management

    func registerStreamingTask(_ task: Task<Void, Never>, for handleId: UUID) {
        activeStreamingTasks[handleId]?.cancel()
        activeStreamingTasks[handleId] = task
    }

    func cancelStreaming(handleId: UUID) {
        if let task = activeStreamingTasks.removeValue(forKey: handleId) {
            task.cancel()
        }
    }

    func removeTask(for handleId: UUID) {
        activeStreamingTasks.removeValue(forKey: handleId)
    }

    func cancelAllTasks() {
        for task in activeStreamingTasks.values {
            task.cancel()
        }
        activeStreamingTasks.removeAll()
    }

    // MARK: - Handle Creation

    func makeStreamingHandle(
        conversationId: UUID?,
        sourceStream: AsyncThrowingStream<LLMStreamChunkDTO, Error>
    ) -> LLMStreamingHandle {
        let handleId = UUID()
        let stream = AsyncThrowingStream<LLMStreamChunkDTO, Error> { [weak self] continuation in
            let task = Task {
                defer {
                    Task { @MainActor in
                        self?.removeTask(for: handleId)
                    }
                }
                do {
                    for try await chunk in sourceStream {
                        if Task.isCancelled { break }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self?.registerStreamingTask(task, for: handleId)
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.cancelStreaming(handleId: handleId)
                }
            }
        }
        let cancelClosure: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.cancelStreaming(handleId: handleId)
            }
        }
        return LLMStreamingHandle(conversationId: conversationId, stream: stream, cancel: cancelClosure)
    }
}
