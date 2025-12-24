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
    func applyReasoning(_ reasoning: OpenRouterReasoning?, to parameters: inout ChatCompletionParameters) {
        guard let reasoning else { return }
        let hasOverride =
            reasoning.maxTokens != nil ||
            (reasoning.exclude != nil && reasoning.exclude != false)
        if hasOverride {
            parameters.reasoningEffort = nil
            // Build reasoning dictionary for OpenRouter
            var reasoningDict: [String: Any] = [:]
            if let effort = reasoning.effort {
                reasoningDict["effort"] = effort
            }
            if let exclude = reasoning.exclude {
                reasoningDict["exclude"] = exclude
            }
            if let maxTokens = reasoning.maxTokens {
                reasoningDict["max_tokens"] = maxTokens
            }
            parameters.reasoning = reasoningDict
            let effortDescription = reasoning.effort ?? "<nil>"
            let excludeDescription = String(describing: reasoning.exclude)
            let maxTokensDescription = String(describing: reasoning.maxTokens)
            Logger.debug("🧠 Configured reasoning override: effort=\(effortDescription), exclude=\(excludeDescription), max_tokens=\(maxTokensDescription)")
        } else {
            parameters.reasoning = nil
            parameters.reasoningEffort = reasoning.effort
        }
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
