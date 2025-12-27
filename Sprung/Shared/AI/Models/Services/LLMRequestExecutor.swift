//
//  LLMRequestExecutor.swift
//  Sprung
//
//
import Foundation
import SwiftOpenAI
/// Network layer for executing LLM requests with retry logic.
///
/// - Important: This is an internal implementation type. Use `LLMFacade` as the
///   public entry point for LLM operations. Do not instantiate directly outside
///   of `LLMFacadeFactory`.
actor LLMRequestExecutor {
    // OpenRouter client
    private var openRouterClient: OpenAIService?
    // Request management
    private var currentRequestIDs: Set<UUID> = []
    // Configuration
    private let defaultMaxRetries: Int = 3
    private let baseRetryDelay: TimeInterval = 1.0
    init() {}
    // MARK: - Client Configuration
    /// Configure the OpenRouter client with the current API key from Keychain
    func configureClient() {
        let apiKey = APIKeyManager.get(.openRouter) ?? ""
        Logger.debug("🔑 LLMRequestExecutor API key length: \(apiKey.count) chars", category: .diagnostics)
        if !apiKey.isEmpty {
            // Log first/last 4 chars for debugging (same as SettingsView does)
            let maskedKey = apiKey.count > 8 ?
                "\(apiKey.prefix(4))...\(apiKey.suffix(4))" :
                "***masked***"
            Logger.debug("🔑 Using API key: \(maskedKey)", category: .diagnostics)
            Logger.debug("🔧 Creating OpenRouter client with baseURL: \(AppConfig.openRouterBaseURL)", category: .networking)
            // Only enable verbose SwiftOpenAI debug logging when user has set debug level to Verbose (2)
            let enableSwiftOpenAIDebug = Logger.isVerboseEnabled
            Logger.debug(
                "🔧 SwiftOpenAI debug logging: \(enableSwiftOpenAIDebug ? "enabled" : "disabled")",
                category: .diagnostics
            )
            self.openRouterClient = OpenAIServiceFactory.service(
                apiKey: apiKey,
                overrideBaseURL: AppConfig.openRouterBaseURL,
                proxyPath: AppConfig.openRouterAPIPath,
                overrideVersion: AppConfig.openRouterVersion,
                extraHeaders: AppConfig.openRouterHeaders,
                debugEnabled: enableSwiftOpenAIDebug
            )
            Logger.info("🔄 LLMRequestExecutor configured OpenRouter client with key", category: .networking)
            Logger.debug(
                "🌐 Expected URL: \(AppConfig.openRouterBaseURL)/\(AppConfig.openRouterAPIPath)/\(AppConfig.openRouterVersion)/chat/completions",
                category: .networking
            )
            // Debug the actual client configuration
            if let client = self.openRouterClient {
                Logger.info("✅ OpenRouter client created: \(type(of: client))", category: .networking)
            }
        } else {
            self.openRouterClient = nil
            Logger.info("🔴 No OpenRouter API key available, client cleared", category: .networking)
        }
    }
    /// Check if client is properly configured
    func isConfigured() -> Bool {
        return openRouterClient != nil
    }
    // MARK: - Request Execution
    /// Execute a request with retry logic and exponential backoff
    func execute(parameters: ChatCompletionParameters, maxRetries: Int? = nil) async throws -> LLMResponse {
        guard let client = openRouterClient else {
            throw LLMError.clientError("OpenRouter client not configured")
        }
        let requestId = UUID()
        currentRequestIDs.insert(requestId)
        defer { currentRequestIDs.remove(requestId) }
        let retries = maxRetries ?? defaultMaxRetries
        var lastError: Error?
        for attempt in 0...retries {
            // Check if request was cancelled
            guard currentRequestIDs.contains(requestId) else {
                throw LLMError.clientError("Request was cancelled")
            }
            do {
                let availableTools = parameters.tools?.compactMap { $0.function.name }.joined(separator: ", ") ?? ""
                let toolInfo = availableTools.isEmpty ? "" : " (tools: \(availableTools))"
                Logger.info("🌐 Making request with model: \(parameters.model)\(toolInfo)", category: .networking)
                let response = try await client.startChat(parameters: parameters)
                let calledTools = response.choices?.first?.message?.toolCalls?.compactMap { $0.function.name } ?? []
                let calledInfo = calledTools.isEmpty ? "" : " called: [\(calledTools.joined(separator: ", "))]"
                Logger.info("✅ Request completed for model: \(parameters.model)\(calledInfo)", category: .networking)
                return response
            } catch {
                lastError = error
                Logger.debug("❌ Request failed with error: \(error)", category: .networking)
                // Handle SwiftOpenAI APIErrors with enhanced error detection
                if let apiError = error as? SwiftOpenAI.APIError {
                    Logger.debug("🔍 SwiftOpenAI APIError details: \(apiError.displayDescription)", category: .networking)
                    // Check for 402 Insufficient Credits
                    if apiError.displayDescription.contains("status code 402") {
                        let (requested, available) = parseCreditsError(apiError.displayDescription)
                        Logger.warning("💳 402 Insufficient credits: requested \(requested), available \(available)", category: .networking)
                        throw LLMError.insufficientCredits(requested: requested, available: available)
                    }
                    // Check for 403 Unauthorized specifically
                    if apiError.displayDescription.contains("status code 403") {
                        let modelId = extractModelId(from: parameters)
                        Logger.debug("🚫 403 Unauthorized detected for model: \(modelId)", category: .networking)
                        throw LLMError.unauthorized(modelId)
                    }
                    if apiError.displayDescription.lowercased().contains("not a valid model id") {
                        let modelId = extractModelId(from: parameters)
                        Logger.debug("🚫 Invalid model ID detected: \(modelId)", category: .networking)
                        throw LLMError.invalidModelId(modelId)
                    }
                }
                // Don't retry on certain errors
                if let appError = error as? LLMError {
                    switch appError {
                    case .decodingFailed, .unexpectedResponseFormat, .clientError, .unauthorized, .invalidModelId, .insufficientCredits:
                        throw appError
                    case .rateLimited(let retryAfter):
                        if let delay = retryAfter, attempt < retries {
                            Logger.debug("🔄 Rate limited, waiting \(delay)s before retry", category: .networking)
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            continue
                        } else {
                            throw appError
                        }
                    case .timeout:
                        if attempt < retries {
                            let delay = baseRetryDelay * pow(2.0, Double(attempt))
                            Logger.debug(
                                "🔄 Request timeout, retrying in \(delay)s (attempt \(attempt + 1)/\(retries + 1))",
                                category: .networking
                            )
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            continue
                        } else {
                            throw appError
                        }
                    }
                }
                // Retry for network errors
                if attempt < retries {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    Logger.debug(
                        "🔄 Network error, retrying in \(delay)s (attempt \(attempt + 1)/\(retries + 1))",
                        category: .networking
                    )
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
        }
        // All retries exhausted
        throw lastError ?? LLMError.clientError("Maximum retries exceeded")
    }
    /// Execute a streaming request with retry logic
    func executeStreaming(parameters: ChatCompletionParameters, maxRetries: Int? = nil) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        guard let client = openRouterClient else {
            throw LLMError.clientError("OpenRouter client not configured")
        }
        let requestId = UUID()
        currentRequestIDs.insert(requestId)
        defer { currentRequestIDs.remove(requestId) }
        let retries = maxRetries ?? defaultMaxRetries
        var lastError: Error?
        for attempt in 0...retries {
            // Check if request was cancelled
            guard currentRequestIDs.contains(requestId) else {
                throw LLMError.clientError("Request was cancelled")
            }
            do {
                Logger.info("🌐 Starting streaming request with model: \(parameters.model)", category: .networking)
                let stream = try await client.startStreamedChat(parameters: parameters)
                Logger.info("✅ Streaming started successfully for model: \(parameters.model)", category: .networking)
                return stream
            } catch {
                lastError = error
                Logger.debug("❌ Streaming request failed with error: \(error)", category: .networking)
                // Handle SwiftOpenAI APIErrors with enhanced error detection
                if let apiError = error as? SwiftOpenAI.APIError {
                    Logger.debug("🔍 SwiftOpenAI APIError details: \(apiError.displayDescription)", category: .networking)
                    // Check for 402 Insufficient Credits
                    if apiError.displayDescription.contains("status code 402") {
                        let (requested, available) = parseCreditsError(apiError.displayDescription)
                        Logger.warning("💳 402 Insufficient credits: requested \(requested), available \(available)", category: .networking)
                        throw LLMError.insufficientCredits(requested: requested, available: available)
                    }
                    // Check for 403 Unauthorized specifically
                    if apiError.displayDescription.contains("status code 403") {
                        let modelId = extractModelId(from: parameters)
                        Logger.debug("🚫 403 Unauthorized detected for model: \(modelId)", category: .networking)
                        throw LLMError.unauthorized(modelId)
                    }
                    if apiError.displayDescription.lowercased().contains("not a valid model id") {
                        let modelId = extractModelId(from: parameters)
                        Logger.debug("🚫 Invalid model ID detected: \(modelId)", category: .networking)
                        throw LLMError.invalidModelId(modelId)
                    }
                }
                // Don't retry on certain errors
                if let appError = error as? LLMError {
                    switch appError {
                    case .decodingFailed, .unexpectedResponseFormat, .clientError, .unauthorized, .invalidModelId, .insufficientCredits:
                        throw appError
                    case .rateLimited(let retryAfter):
                        if let delay = retryAfter, attempt < retries {
                            Logger.debug("🔄 Rate limited, waiting \(delay)s before retry", category: .networking)
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            continue
                        } else {
                            throw appError
                        }
                    case .timeout:
                        if attempt < retries {
                            let delay = baseRetryDelay * pow(2.0, Double(attempt))
                            Logger.debug(
                                "🔄 Request timeout, retrying in \(delay)s (attempt \(attempt + 1)/\(retries + 1))",
                                category: .networking
                            )
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            continue
                        } else {
                            throw appError
                        }
                    }
                }
                // Retry for network errors
                if attempt < retries {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    Logger.debug(
                        "🔄 Network error, retrying in \(delay)s (attempt \(attempt + 1)/\(retries + 1))",
                        category: .networking
                    )
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
        }
        // All retries exhausted
        throw lastError ?? LLMError.clientError("Maximum retries exceeded")
    }
    /// Cancel all current requests
    func cancelAllRequests() {
        currentRequestIDs.removeAll()
        Logger.info("🛑 Cancelled all LLM requests", category: .networking)
    }
    // MARK: - Private Helpers
    /// Extract model ID from chat completion parameters for error reporting
    private func extractModelId(from parameters: ChatCompletionParameters) -> String {
        return parameters.model
    }

    /// Parse token counts from 402 insufficient credits error message
    /// Example: "You requested up to 64000 tokens, but can only afford 14924"
    private func parseCreditsError(_ description: String) -> (requested: Int, available: Int) {
        // Try to extract "requested X tokens" and "afford Y"
        var requested = 0
        var available = 0

        // Pattern: "requested up to X tokens"
        if let requestedRange = description.range(of: "requested up to "),
           let tokensRange = description.range(of: " tokens", range: requestedRange.upperBound..<description.endIndex) {
            let numberStr = description[requestedRange.upperBound..<tokensRange.lowerBound]
            requested = Int(numberStr) ?? 0
        }

        // Pattern: "can only afford X"
        if let affordRange = description.range(of: "can only afford ") {
            // Find the end of the number (next non-digit or end of string)
            let startIndex = affordRange.upperBound
            var endIndex = startIndex
            while endIndex < description.endIndex && description[endIndex].isNumber {
                endIndex = description.index(after: endIndex)
            }
            if startIndex < endIndex {
                let numberStr = description[startIndex..<endIndex]
                available = Int(numberStr) ?? 0
            }
        }

        return (requested, available)
    }
}
