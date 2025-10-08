//
//  LLMRequestExecutor.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/10/25.
//

import Foundation
import SwiftOpenAI

/// Network layer for executing LLM requests with retry logic
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
                Logger.info("🌐 Making request with model: \(parameters.model)", category: .networking)
                let response = try await client.startChat(parameters: parameters)
                Logger.info("✅ Request completed successfully for model: \(parameters.model)", category: .networking)
                return response
            } catch {
                lastError = error
                Logger.debug("❌ Request failed with error: \(error)", category: .networking)
                
                // Handle SwiftOpenAI APIErrors with enhanced 403 detection
                if let apiError = error as? SwiftOpenAI.APIError {
                    Logger.debug("🔍 SwiftOpenAI APIError details: \(apiError.displayDescription)", category: .networking)
                    
                    // Check for 403 Unauthorized specifically
                    if apiError.displayDescription.contains("status code 403") {
                        let modelId = extractModelId(from: parameters)
                        Logger.debug("🚫 403 Unauthorized detected for model: \(modelId)", category: .networking)
                        throw LLMError.unauthorized(modelId)
                    }
                }
                
                // Don't retry on certain errors
                if let appError = error as? LLMError {
                    switch appError {
                    case .decodingFailed, .unexpectedResponseFormat, .clientError, .unauthorized:
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
                
                // Handle SwiftOpenAI APIErrors with enhanced 403 detection
                if let apiError = error as? SwiftOpenAI.APIError {
                    Logger.debug("🔍 SwiftOpenAI APIError details: \(apiError.displayDescription)", category: .networking)
                    
                    // Check for 403 Unauthorized specifically
                    if apiError.displayDescription.contains("status code 403") {
                        let modelId = extractModelId(from: parameters)
                        Logger.debug("🚫 403 Unauthorized detected for model: \(modelId)", category: .networking)
                        throw LLMError.unauthorized(modelId)
                    }
                }
                
                // Don't retry on certain errors
                if let appError = error as? LLMError {
                    switch appError {
                    case .decodingFailed, .unexpectedResponseFormat, .clientError, .unauthorized:
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
}
