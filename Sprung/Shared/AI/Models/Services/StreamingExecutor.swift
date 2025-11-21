//
//  StreamingExecutor.swift
//  Sprung
//
//  Wraps LLM streaming execution with DTO mapping and optional accumulation.
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
            parameters.reasoning = ChatCompletionParameters.ReasoningOverrides(
                effort: reasoning.effort,
                exclude: reasoning.exclude,
                maxTokens: reasoning.maxTokens
            )
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
