//
//  StreamingExecutor.swift
//  Sprung
//
//  Wraps LLM streaming execution with DTO mapping and optional accumulation.
//
//  - Important: This is an internal implementation type. Use `LLMFacade` as the
//    public entry point for LLM operations.
//
import Foundation
final class StreamingExecutor {
    private let requestExecutor: LLMRequestExecutor
    init(requestExecutor: LLMRequestExecutor) {
        self.requestExecutor = requestExecutor
    }
    /// Map effort level to a reasoning token budget.
    /// Opus 4.6 ignores the `effort` field and uses unconstrained adaptive thinking
    /// unless `max_tokens` is set. Providing a budget keeps thinking bounded while
    /// still letting the model allocate tokens adaptively within the cap.
    private static let effortBudgets: [String: Int] = [
        "minimal": 1024,
        "low": 4096,
        "medium": 10000,
        "high": 25000,
    ]

    func applyReasoning(_ reasoning: OpenRouterReasoning?, to parameters: inout ChatCompletionParameters) {
        guard let reasoning else { return }
        // Always use the reasoning dict format with enabled: true.
        // The simple reasoningEffort param doesn't work for Opus 4.6 (which
        // requires the reasoning object with enabled: true for adaptive thinking).
        parameters.reasoningEffort = nil
        var reasoningDict: [String: Any] = ["enabled": true]
        if let exclude = reasoning.exclude {
            reasoningDict["exclude"] = exclude
        }
        // API only accepts ONE of effort or max_tokens — never both.
        // Prefer max_tokens (derived from effort budget) because Opus 4.6
        // ignores the effort field and needs an explicit token cap.
        let resolvedBudget = reasoning.maxTokens
            ?? reasoning.effort.flatMap { Self.effortBudgets[$0] }
        if let budget = resolvedBudget {
            reasoningDict["max_tokens"] = budget
        } else if let effort = reasoning.effort {
            reasoningDict["effort"] = effort
        }
        parameters.reasoning = reasoningDict
        let effortDescription = reasoning.effort ?? "<nil>"
        let excludeDescription = String(describing: reasoning.exclude)
        let budgetDescription = resolvedBudget.map(String.init) ?? "adaptive (unbounded)"
        Logger.debug("🧠 Configured reasoning: enabled=true, effort=\(effortDescription), exclude=\(excludeDescription), max_tokens=\(budgetDescription)")
    }
    func stream(
        parameters: ChatCompletionParameters,
        accumulateContent: Bool,
        onCompletion: @escaping @Sendable (Result<String?, Error>) -> Void
    ) -> AsyncThrowingStream<LLMStreamChunkDTO, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var accumulated = accumulateContent ? "" : nil
                var cancelled = false
                do {
                    let rawStream = try await self.requestExecutor.executeStreaming(parameters: parameters)
                    for try await chunk in rawStream {
                        if Task.isCancelled {
                            cancelled = true
                            break
                        }
                        let dto = LLMVendorMapper.streamChunkDTO(from: chunk)
                        if accumulateContent, let content = dto.content {
                            accumulated? += content
                        }
                        continuation.yield(dto)
                    }
                    if cancelled {
                        onCompletion(.failure(CancellationError()))
                        continuation.finish()
                        return
                    }
                    onCompletion(.success(accumulated))
                    continuation.finish()
                } catch {
                    onCompletion(.failure(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
