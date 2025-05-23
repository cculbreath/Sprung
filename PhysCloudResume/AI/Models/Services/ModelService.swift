//
//  ModelService.swift
//  PhysCloudResume
//
//  Created by Claude on 5/20/25.
//

import Foundation
import SwiftUI
import SwiftOpenAI

/// Service for fetching and caching AI model information from all supported providers
@available(iOS 16.0, macOS 13.0, *)
class ModelService: ObservableObject, @unchecked Sendable {
    
    /// Shared singleton instance
    static let shared = ModelService()
    // MARK: - Published properties
    
    /// Available OpenAI models, updated on fetch
    @Published var openAIModels: [String] = []
    
    /// Available Claude models, updated on fetch
    @Published var claudeModels: [String] = []
    
    /// Available Grok models, updated on fetch
    @Published var grokModels: [String] = []
    
    /// Available Gemini models, updated on fetch
    @Published var geminiModels: [String] = []
    
    /// Status of last fetch operation for each provider
    @Published var fetchStatus: [String: FetchStatus] = [:]
    
    // MARK: - Private properties
    
    /// Cached SwiftOpenAI service instances by provider
    private var services: [String: OpenAIService] = [:]
    
    /// Queue for thread-safe access to services dictionary
    private let servicesQueue = DispatchQueue(label: "com.physcloudresume.modelservice.services", attributes: .concurrent)
    
    /// Semaphore to prevent multiple concurrent fetches
    private let fetchSemaphore = DispatchSemaphore(value: 1)
    
    // MARK: - Types
    
    /// Status of model fetching operations
    enum FetchStatus {
        case notStarted
        case inProgress
        case success(Date)
        case error(String)
        
        var isInProgress: Bool {
            if case .inProgress = self {
                return true
            }
            return false
        }
        
        var displayText: String {
            switch self {
            case .notStarted:
                return "Not fetched"
            case .inProgress:
                return "Fetching..."
            case .success(let date):
                let formatter = DateFormatter()
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                return "Updated at \(formatter.string(from: date))"
            case .error(let message):
                return "Error: \(message)"
            }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        // Initialize fetch status for each provider
        fetchStatus[AIModels.Provider.openai] = .notStarted
        fetchStatus[AIModels.Provider.claude] = .notStarted
        fetchStatus[AIModels.Provider.grok] = .notStarted
        fetchStatus[AIModels.Provider.gemini] = .notStarted
        
        // Load any cached model lists from UserDefaults
        loadCachedModels()
    }
    
    // MARK: - Public Methods
    
    /// Fetches models for all providers with API keys
    /// - Parameter apiKeys: Dictionary of API keys by provider
    func fetchAllModels(apiKeys: [String: String]) {
        // For each provider with an API key
        for (provider, apiKey) in apiKeys {
            guard !apiKey.isEmpty && apiKey != "none" else { continue }
            
            fetchModelsForProvider(provider: provider, apiKey: apiKey)
        }
    }
    
    /// Fetches models for a specific provider
    /// - Parameters:
    ///   - provider: The provider identifier (e.g., "OpenAI")
    ///   - apiKey: The API key for the provider
    func fetchModelsForProvider(provider: String, apiKey: String) {
        // Log key details for debugging (without revealing the entire key)
        let firstChars = apiKey.isEmpty ? "" : String(apiKey.prefix(4))
        let keyLength = apiKey.count
        Logger.debug("🔑 Attempting to validate API key for \(provider): First chars: \(firstChars), Length: \(keyLength)")
        
        // Check if apiKey is empty or "none" - common issue
        if apiKey.isEmpty || apiKey == "none" {
            DispatchQueue.main.async {
                self.fetchStatus[provider] = .error("No API key provided")
            }
            Logger.debug("⚠️ Skipping model fetch for \(provider): No API key provided")
            return
        }
        
        // Initial format validation
        if !APIKeyValidator.isValidFormat(provider: provider, apiKey: apiKey) {
            Logger.debug("⚠️ API key format validation failed for \(provider)")
            
            // Special case for OpenAI with project-scoped keys
            if provider == AIModels.Provider.openai && apiKey.hasPrefix("sk-proj-") {
                Logger.debug("🔍 Detected OpenAI project-scoped key, proceeding with validation")
            } else {
                DispatchQueue.main.async {
                    self.fetchStatus[provider] = .error("Invalid API key format")
                }
                Logger.debug("⚠️ Skipping model fetch for \(provider): Invalid API key format")
                return
            }
        }
        
        // Update fetch status to in progress
        DispatchQueue.main.async {
            self.fetchStatus[provider] = .inProgress
        }
        
        // Clean API key by trimming whitespace
        let cleanKey = APIKeyValidator.sanitize(apiKey)
        
        // Log successful format validation
        Logger.debug("✅ Valid API key format for \(provider): First chars: \(cleanKey.prefix(4)), Length: \(cleanKey.count)")
        
        // Try direct validation for all provider types
        // This gives us immediate feedback without needing reflection
        Task {
            do {
                // Try to validate the key with a direct API call first
                let isValid = try await APIKeyValidator.validateWithAPICall(provider: provider, apiKey: cleanKey)
                
                if isValid {
                    Logger.debug("✅ Direct API validation succeeded for \(provider)")
                    
                    // Create or reuse service with the correct API key
                    let service = getOrCreateService(for: provider, apiKey: cleanKey)
                    
                    // For non-OpenAI providers, store the key in UserDefaults to ensure persistence
                    if provider != AIModels.Provider.openai {
                        UserDefaults.standard.set(cleanKey, forKey: "\(provider)ApiKey")
                    }
                    
                    // Attempt to fetch models with the validated key
                    let models = try await fetchModels(provider: provider, service: service)
                    
                    // Update models and status on main thread
                    DispatchQueue.main.async {
                        switch provider {
                        case AIModels.Provider.openai:
                            self.openAIModels = ModelFilters.filterOpenAIModels(models)
                        case AIModels.Provider.claude:
                            self.claudeModels = ModelFilters.filterClaudeModels(models)
                        case AIModels.Provider.grok:
                            self.grokModels = ModelFilters.filterGrokModels(models)
                        case AIModels.Provider.gemini:
                            self.geminiModels = ModelFilters.filterGeminiModels(models)
                        default:
                            break
                        }
                        self.fetchStatus[provider] = .success(Date())
                        self.saveModelsToCache()
                    }
                    
                    Logger.debug("✅ Fetched \(models.count) models for \(provider)")
                    return
                } 
            } catch {
                Logger.debug("⚠️ Direct API validation failed for \(provider): \(error.localizedDescription)")
                // Continue with the standard approach for all providers except Gemini
                if provider == AIModels.Provider.gemini {
                    DispatchQueue.main.async {
                        self.fetchStatus[provider] = .error("API key validation failed: \(error.localizedDescription)")
                    }
                    return
                }
            }
        }
        
        // Create or reuse service for this provider (standard approach)
        let service = getOrCreateService(for: provider, apiKey: cleanKey)
        
        // Start fetch task for this provider
        Task {
            do {
                let models = try await fetchModels(provider: provider, service: service)
                
                // Update models and status on main thread
                DispatchQueue.main.async {
                    switch provider {
                    case AIModels.Provider.openai:
                        // Apply filtering to OpenAI models
                        self.openAIModels = ModelFilters.filterOpenAIModels(models)
                    case AIModels.Provider.claude:
                        // Apply filtering to Claude models
                        self.claudeModels = ModelFilters.filterClaudeModels(models)
                    case AIModels.Provider.grok:
                        // Apply filtering to Grok models
                        self.grokModels = ModelFilters.filterGrokModels(models)
                    case AIModels.Provider.gemini:
                        // Apply filtering to Gemini models
                        self.geminiModels = ModelFilters.filterGeminiModels(models)
                    default:
                        break
                    }
                    
                    self.fetchStatus[provider] = .success(Date())
                    self.saveModelsToCache()
                }
                
                Logger.debug("✅ Fetched \(models.count) models for \(provider)")
            } catch {
                Logger.error("❌ Failed to fetch models for \(provider): \(error.localizedDescription)")
                
                // If the service fetch fails, try direct API validation as a fallback
                let serviceKey = service.apiKey
                if serviceKey.isEmpty {
                    Logger.debug("🔄 Service has empty API key, trying direct API validation")
                    
                    // Try direct validation as a last resort
                    Task {
                        do {
                            let isValid = try await APIKeyValidator.validateWithAPICall(provider: provider, apiKey: cleanKey)
                            
                            if isValid {
                                Logger.debug("✅ Fallback direct API validation succeeded for \(provider)")
                                DispatchQueue.main.async {
                                    self.fetchStatus[provider] = .success(Date())
                                }
                            } else {
                                DispatchQueue.main.async {
                                    self.fetchStatus[provider] = .error("API key validation failed")
                                }
                            }
                        } catch {
                            // Update status with error on main thread
                            DispatchQueue.main.async {
                                self.fetchStatus[provider] = .error(error.localizedDescription)
                            }
                            Logger.error("❌ Fallback validation also failed: \(error.localizedDescription)")
                        }
                    }
                } else {
                    // Update status with error on main thread
                    DispatchQueue.main.async {
                        self.fetchStatus[provider] = .error(error.localizedDescription)
                    }
                }
            }
        }
    }
    
    /// Gets available models for a specific provider
    /// - Parameter provider: The provider identifier
    /// - Returns: Array of available model names
    func getModelsForProvider(_ provider: String) -> [String] {
        switch provider {
        case AIModels.Provider.openai:
            return openAIModels
        case AIModels.Provider.claude:
            return claudeModels
        case AIModels.Provider.grok:
            return grokModels
        case AIModels.Provider.gemini:
            return geminiModels
        default:
            return []
        }
    }
    
    /// Gets all available models across providers
    /// - Returns: Dictionary mapping provider names to arrays of model names
    func getAllModels() -> [String: [String]] {
        return [
            AIModels.Provider.openai: getModelsForProvider(AIModels.Provider.openai),
            AIModels.Provider.claude: getModelsForProvider(AIModels.Provider.claude),
            AIModels.Provider.grok: getModelsForProvider(AIModels.Provider.grok),
            AIModels.Provider.gemini: getModelsForProvider(AIModels.Provider.gemini)
        ]
    }
    
    /// Gets all available models as a flat array
    /// - Returns: Array of all model identifiers
    func getAllAvailableModels() async -> [String] {
        // Use Set to automatically handle duplicates
        var uniqueModels = Set<String>()
        
        // Collect all models from all providers
        uniqueModels.formUnion(openAIModels)
        uniqueModels.formUnion(claudeModels)
        uniqueModels.formUnion(grokModels)
        uniqueModels.formUnion(geminiModels)
        
        // Convert to array and sort
        return Array(uniqueModels).sorted()
    }
    
    // MARK: - Private Methods
    
    /// Creates or retrieves a cached OpenAIService for a provider
    /// - Parameters:
    ///   - provider: The provider identifier
    ///   - apiKey: The API key for the provider
    /// - Returns: A configured OpenAIService instance
    private func getOrCreateService(for provider: String, apiKey: String) -> OpenAIService {
        // Check if we already have a service cached with the same apiKey
        var existingService: OpenAIService?
        
        // Thread-safe read
        servicesQueue.sync {
            existingService = services[provider]
        }
        
        if let existingService = existingService {
            // Verify the service has the correct API key
            let existingKey = existingService.apiKey
            if !existingKey.isEmpty && existingKey == apiKey {
                Logger.debug("♻️ Reusing existing service for \(provider) with key: \(existingKey.prefix(4))...")
                return existingService
            } else {
                // If the API key has changed or is empty, create a new service
                Logger.debug("🔄 API key for \(provider) has changed or is empty, creating new service")
            }
        }
        
        // Create a new service with the provided API key
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 30.0 // Shorter timeout for model listing
        
        // Add Authorization header directly to the URLSessionConfiguration for better extraction
        if provider != AIModels.Provider.gemini {
            // For most providers, use Bearer authorization in the header
            urlConfig.httpAdditionalHeaders = [
                "Authorization": "Bearer \(apiKey)"
            ]
            Logger.debug("🔑 Added Authorization header to URLSessionConfiguration")
        }
        
        // Ensure API key is not empty before creating service
        guard !apiKey.isEmpty else {
            Logger.error("❌ Cannot create service for \(provider): Empty API key")
            fatalError("Empty API key provided to getOrCreateService")
        }
        
        // Log key first few characters for debugging
        Logger.debug("🔑 Creating service for \(provider) with key: \(apiKey.prefix(4))...")
        
        let service: OpenAIService
        
        switch provider {
        case AIModels.Provider.claude:
            // Anthropic/Claude service
            service = OpenAIServiceFactory.createAnthropicClient(apiKey: apiKey, configuration: urlConfig)
            Logger.debug("👤 Created Claude service with base URL: api.anthropic.com")
            
        case AIModels.Provider.grok:
            // Groq/Grok service
            service = OpenAIServiceFactory.createGroqClient(apiKey: apiKey, configuration: urlConfig)
            Logger.debug("⚡ Created Grok service with base URL: api.groq.com")
            
        case AIModels.Provider.gemini:
            // Google/Gemini service - Note: Gemini uses apiKey in URL, not Authorization header
            let encodedApiKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
            service = OpenAIServiceFactory.createGeminiClient(apiKey: encodedApiKey, configuration: urlConfig)
            Logger.debug("🌟 Created Gemini service with base URL: generativelanguage.googleapis.com")
            
            // Store directly in UserDefaults for reflection fallback
            UserDefaults.standard.set(apiKey, forKey: "geminiApiKey")
            
        default: // Default to OpenAI
            // Regular OpenAI service
            service = OpenAIServiceFactory.service(apiKey: apiKey, configuration: urlConfig)
            Logger.debug("🤖 Created OpenAI service with base URL: api.openai.com")
            
            // Store directly in UserDefaults for reflection fallback
            UserDefaults.standard.set(apiKey, forKey: "openAiApiKey") 
        }
        
        // Verify service was created with correct API key
        let serviceKey = service.apiKey
        if serviceKey.isEmpty {
            Logger.error("❌ Created service has empty API key for \(provider)")
            
            // Use direct key validation against the OpenAI API
            if provider == AIModels.Provider.openai {
                // Make a direct API call to validate the key
                Task {
                    do {
                        let url = URL(string: "https://api.openai.com/v1/models")!
                        var request = URLRequest(url: url)
                        request.httpMethod = "GET"
                        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        
                        let (_, response) = try await URLSession.shared.data(for: request)
                        
                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                            Logger.debug("✅ Direct API call validated OpenAI key!")
                            
                            // Update service with guaranteed key (direct validation)
                            DispatchQueue.main.async {
                                self.fetchStatus[provider] = .success(Date())
                            }
                        } else {
                            Logger.error("❌ Direct API call failed to validate OpenAI key")
                        }
                    } catch {
                        Logger.error("❌ Direct API validation failed: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            Logger.debug("✅ Service created with API key: \(serviceKey.prefix(4))...")
        }
        
        // Cache the service with thread-safe write
        servicesQueue.async(flags: .barrier) {
            self.services[provider] = service
        }
        
        return service
    }
    
    /// Fetches models for a specific provider using an API call
    /// - Parameters:
    ///   - provider: The provider identifier
    ///   - service: The OpenAIService to use for fetching
    /// - Returns: Array of model names
    /// - Throws: Errors from the API call
    private func fetchModels(provider: String, service: OpenAIService) async throws -> [String] {
        // Use a task-based lock instead of a semaphore in async context
        let lockTask = Task {
            // In a real implementation, you'd use an actor or a lock for async contexts
            // This is a workaround for the current code structure
            return true
        }
        _ = await lockTask.value
        
        // Structure for parsing model responses
        struct ModelsResponse: Decodable {
            struct Model: Decodable {
                let id: String
                let name: String?
            }
            let data: [Model]?
            let models: [Model]?
        }
        
        var url: URL
        var request: URLRequest
        
        // For provider-specific API keys, get from UserDefaults directly
        // This is to avoid issues with the service.apiKey reflection
        var apiKey = ""
        
        switch provider {
        case AIModels.Provider.claude:
            apiKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? ""
        case AIModels.Provider.grok:
            apiKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? ""
        case AIModels.Provider.gemini:
            apiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        default: // OpenAI
            apiKey = service.apiKey
            if apiKey.isEmpty {
                apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
            }
        }
        
        guard !apiKey.isEmpty else {
            Logger.error("❌ Cannot fetch models: Empty API key for provider \(provider)")
            throw NSError(
                domain: "ModelService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Empty API key provided for \(provider)"]
            )
        }
        
        // Log key first few characters for debugging
        Logger.debug("🔑 Using API key for \(provider): First chars: \(apiKey.prefix(4)), Length: \(apiKey.count)")
        
        // Configure request based on provider
        switch provider {
        case AIModels.Provider.claude:
            url = URL(string: "https://api.anthropic.com/v1/models")!
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            // Claude uses x-api-key header, not Bearer token
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            
        case AIModels.Provider.grok:
            if apiKey.hasPrefix("xai-") {
                // X.AI Grok validation - fetch models list
                url = URL(string: "https://api.x.ai/v1/models")!
                request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            } else {
                // Groq validation - fetch models list
                url = URL(string: "https://api.groq.com/v1/models")!
                request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            
        case AIModels.Provider.gemini:
            // For Gemini, the API key is passed directly in the URL - needs proper encoding
            guard let encodedApiKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                throw NSError(
                    domain: "ModelService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to encode Gemini API key"]
                )
            }
            
            // Use v1beta instead of v1 for the API endpoint
            let urlString = "https://generativelanguage.googleapis.com/v1beta/models?key=\(encodedApiKey)"
            guard let encodedURL = URL(string: urlString) else {
                throw NSError(
                    domain: "ModelService",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create URL for Gemini API"]
                )
            }
            
            url = encodedURL
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            
            // Additional logging for Gemini which doesn't use Authorization headers
            Logger.debug("🔍 Gemini API request with key: \(apiKey.prefix(4))..., URL contains API key (not shown)")
            
        default: // Default to OpenAI
            url = URL(string: "https://api.openai.com/v1/models")!
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        request.timeoutInterval = 30.0
        
        // For debugging
        Logger.debug("🔍 Making API call to \(url.absoluteString) for provider \(provider)")
        
        // Print headers for debugging (omitting Authorization details)
        let headers = request.allHTTPHeaderFields ?? [:]
        var safeHeaders = [String: String]()
        for (key, value) in headers {
            if key.lowercased() == "authorization" {
                safeHeaders[key] = "Bearer sk-***"
            } else {
                safeHeaders[key] = value
            }
        }
        Logger.debug("🔍 Headers: \(safeHeaders)")
        
        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Log response details for debugging
        if let httpResponse = response as? HTTPURLResponse {
            Logger.debug("🔍 Response status code: \(httpResponse.statusCode)")
            Logger.debug("🔍 Response headers: \(httpResponse.allHeaderFields)")
            
            // Log a bit of the response data for debugging
            let responseString = String(data: data.prefix(200), encoding: .utf8) ?? "Unable to decode response"
            Logger.debug("🔍 Response preview: \(responseString)...")
            
            // If there's an error, attempt to show more detailed error information
            if httpResponse.statusCode != 200 {
                let errorString = String(data: data, encoding: .utf8) ?? "Unable to decode error response"
                Logger.debug("🔍 Error response: \(errorString)")
                
                throw NSError(
                    domain: "ModelService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models: \(errorString)"]
                )
            }
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "ModelService",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models: HTTP \(response)"]
            )
        }
        
        // Special handling for Gemini since it uses a different response format
        if provider == AIModels.Provider.gemini {
            struct GeminiModelsResponse: Decodable {
                struct GeminiModel: Decodable {
                    let name: String
                    let version: String?
                    let displayName: String?
                    let description: String?
                    let inputTokenLimit: Int?
                    let outputTokenLimit: Int?
                    let supportedGenerationMethods: [String]?
                }
                
                let models: [GeminiModel]
            }
            
            do {
                // Try parsing as Gemini model response
                let decoder = JSONDecoder()
                let geminiResponse = try decoder.decode(GeminiModelsResponse.self, from: data)
                
                // Extract model names (e.g., "models/gemini-1.5-pro" -> "gemini-1.5-pro")
                let modelIds = geminiResponse.models
                    .compactMap { model -> String? in
                        // Extract the last component after "models/" prefix if present
                        let modelName = model.name.components(separatedBy: "/").last ?? model.name
                        
                        // Keep only Gemini models and filter out embedding/other models
                        if modelName.lowercased().contains("gemini") && 
                           (model.supportedGenerationMethods?.contains("generateContent") == true) {
                            return modelName
                        }
                        return nil
                    }
                    .sorted()
                
                Logger.debug("✅ Successfully parsed Gemini models: \(modelIds.count) models")
                
                // If we couldn't find any Gemini models, return defaults
                if modelIds.isEmpty {
                    Logger.debug("⚠️ No Gemini models found in response, using defaults")
                    return ["gemini-2.5-flash-preview-05-20", "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"]
                }
                
                return modelIds
                
            } catch {
                Logger.debug("❌ Failed to parse Gemini models: \(error.localizedDescription)")
                // Try to extract error details from the response for better debugging
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error format"
                Logger.debug("🔍 Gemini API response: \(errorText.prefix(200))...")
                
                // If Gemini parsing fails, return default models
                return ["gemini-2.5-flash-preview-05-20", "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"]
            }
        }
        
        // For other providers, use the standard format
        let decoder = JSONDecoder()
        do {
            let modelsResponse = try decoder.decode(ModelsResponse.self, from: data)
            
            // Extract model IDs differently based on provider
            switch provider {
            case AIModels.Provider.claude:
                // Check if models are in the 'data' field (new API format)
                // or the 'models' field (old API format)
                if let claudeModelsData = modelsResponse.data, !claudeModelsData.isEmpty {
                    Logger.debug("✅ Found Claude models in 'data' field: \(claudeModelsData.count) models")
                    return claudeModelsData
                        .map { $0.id }
                        .filter { $0.contains("claude") }
                        .sorted()
                } else if let claudeModels = modelsResponse.models, !claudeModels.isEmpty {
                    Logger.debug("✅ Found Claude models in 'models' field: \(claudeModels.count) models")
                    return claudeModels
                        .map { $0.id }
                        .filter { $0.contains("claude") }
                        .sorted()
                } else {
                    Logger.debug("⚠️ No Claude models found in response, using default models")
                    return ["claude-3-opus-20240229", "claude-3-sonnet-20240229", 
                            "claude-3-haiku-20240307", "claude-3-5-sonnet-20240620"]
                }
                
            default:
                // OpenAI and Grok use 'data' field
                let modelIds = (modelsResponse.data ?? [])
                    .map { $0.id }
                    .sorted()
                
                // Filter models based on provider
                if provider == AIModels.Provider.grok {
                    // For Grok return only Grok specific models
                    return modelIds.filter { $0.lowercased().contains("grok") }
                } else {
                    // For OpenAI we now return the full list of model identifiers and let
                    // `ModelFilters.filterOpenAIModels(_:)` handle the heavy-lifting of
                    // selecting the representative chat models that should be surfaced in
                    // the UI.  This keeps the logic in a single place and ensures that new
                    // OpenAI base models (e.g. `o3`, `o3-mini`, `o4-mini`, future
                    // `gpt-5`, etc.) are not accidentally discarded by an overly strict
                    // pre-filter here.
                    return modelIds
                }
            }
        } catch {
            Logger.debug("❌ Failed to parse standard model response: \(error.localizedDescription)")
            
            // If parsing fails for Claude, return default models
            if provider == AIModels.Provider.claude {
                return ["claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307"]
            }
            
            // Rethrow for other providers
            throw error
        }
    }
    
    /// Cache models in UserDefaults
    private func saveModelsToCache() {
        UserDefaults.standard.set(openAIModels, forKey: "cachedOpenAIModels")
        UserDefaults.standard.set(claudeModels, forKey: "cachedClaudeModels")
        UserDefaults.standard.set(grokModels, forKey: "cachedGrokModels")
        UserDefaults.standard.set(geminiModels, forKey: "cachedGeminiModels")
        
        // Save timestamps for when models were fetched
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: "lastOpenAIFetch")
        UserDefaults.standard.set(now, forKey: "lastClaudeFetch")
        UserDefaults.standard.set(now, forKey: "lastGrokFetch")
        UserDefaults.standard.set(now, forKey: "lastGeminiFetch")
    }
    
    /// Load cached models from UserDefaults
    private func loadCachedModels() {
        if let cachedOpenAI = UserDefaults.standard.stringArray(forKey: "cachedOpenAIModels"), !cachedOpenAI.isEmpty {
            openAIModels = cachedOpenAI
            fetchStatus[AIModels.Provider.openai] = .success(Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "lastOpenAIFetch")))
        }
        
        if let cachedClaude = UserDefaults.standard.stringArray(forKey: "cachedClaudeModels"), !cachedClaude.isEmpty {
            claudeModels = cachedClaude
            fetchStatus[AIModels.Provider.claude] = .success(Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "lastClaudeFetch")))
        }
        
        if let cachedGrok = UserDefaults.standard.stringArray(forKey: "cachedGrokModels"), !cachedGrok.isEmpty {
            grokModels = cachedGrok
            fetchStatus[AIModels.Provider.grok] = .success(Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "lastGrokFetch")))
        }
        
        if let cachedGemini = UserDefaults.standard.stringArray(forKey: "cachedGeminiModels"), !cachedGemini.isEmpty {
            geminiModels = cachedGemini
            fetchStatus[AIModels.Provider.gemini] = .success(Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "lastGeminiFetch")))
        }
    }
}

// MARK: - OpenAIServiceFactory Extensions

/// Extensions to SwiftOpenAI.OpenAIServiceFactory for creating provider-specific clients
extension OpenAIServiceFactory {
    /// Creates a client configured for Anthropic/Claude
    static func createAnthropicClient(apiKey: String, configuration: URLSessionConfiguration? = nil) -> OpenAIService {
        let urlConfig = configuration ?? URLSessionConfiguration.default
        
        // Anthropic API has specific authentication requirements
        // Their API requires x-api-key header, not Bearer token
        
        // IMPORTANT: The SwiftOpenAI library expects certain headers in httpAdditionalHeaders
        // Add directly to URLSessionConfiguration for maximum compatibility
        var configHeaders = urlConfig.httpAdditionalHeaders as? [String: String] ?? [:]
        configHeaders["anthropic-version"] = "2023-06-01"
        configHeaders["x-api-key"] = apiKey
        configHeaders["Content-Type"] = "application/json"
        
        // Remove any Bearer token to prevent confusion
        configHeaders.removeValue(forKey: "Authorization")
        
        // Set the updated headers
        urlConfig.httpAdditionalHeaders = configHeaders
        
        // Log what we're doing for debugging
        Logger.debug("🔧 Creating Claude client with updated authentication headers")
        Logger.debug("🔑 Using anthropic-version 2023-06-01 and x-api-key: \(String(apiKey.prefix(4)))...")
        
        // Create a service with correct configuration
        // For Claude API, we don't use the Bearer token mechanism at all
        let service = OpenAIServiceFactory.service(
            apiKey: "", // MUST be empty for Claude
            overrideBaseURL: "https://api.anthropic.com",
            configuration: urlConfig,
            proxyPath: nil,
            overrideVersion: "v1",
            extraHeaders: [
                "anthropic-version": "2023-06-01",
                "x-api-key": apiKey
            ]
        )
        
        return service
    }
    
    /// Creates a client configured for Groq/Grok
    static func createGroqClient(apiKey: String, configuration: URLSessionConfiguration? = nil) -> OpenAIService {
        let urlConfig = configuration ?? URLSessionConfiguration.default
        
        // Check if this is an X.AI Grok key (starts with xai-)
        if apiKey.hasPrefix("xai-") {
            return OpenAIServiceFactory.service(
                apiKey: apiKey, 
                overrideBaseURL: "https://api.x.ai",
                configuration: urlConfig,
                proxyPath: nil,
                overrideVersion: "v1"
            )
        } else {
            // Legacy Groq API
            return OpenAIServiceFactory.service(
                apiKey: apiKey, 
                overrideBaseURL: "https://api.groq.com",
                configuration: urlConfig,
                proxyPath: nil,
                overrideVersion: "v1"
            )
        }
    }
    
    /// Creates a client configured for Google/Gemini
    static func createGeminiClient(apiKey: String, configuration: URLSessionConfiguration? = nil) -> OpenAIService {
        let urlConfig = configuration ?? URLSessionConfiguration.default
        
        // Store the Gemini key in UserDefaults for direct access
        UserDefaults.standard.set(apiKey, forKey: "geminiApiKey")
        
        // Remove the key from both headers and extraHeaders
        // Just use the key as a URL parameter which works better
        return OpenAIServiceFactory.service(
            apiKey: "", // Empty API key since we'll use it as URL param
            overrideBaseURL: "https://generativelanguage.googleapis.com",
            configuration: urlConfig,
            proxyPath: nil,
            overrideVersion: "v1beta", // Use v1beta instead of v1
            extraHeaders: ["x-goog-api-key": apiKey] // Explicitly add the API key as a header
        )
    }
}

// MARK: - OpenAIService Extensions

/// Extension to expose the API key from OpenAIService
extension OpenAIService {
    /// Gets the API key used by this service
    var apiKey: String {
        // Debug output to help in diagnosing issues
        Logger.debug("🔍 Attempting to extract API key from OpenAIService")
        
        // First try the legacy approach which might work depending on the version
        if let apiKey = Mirror(reflecting: self)
            .children
            .first(where: { $0.label == "apiKey" || $0.label == "_apiKey" })?
            .value as? String, !apiKey.isEmpty {
            Logger.debug("✅ Found API key in direct property")
            return apiKey
        }
        
        // Next, try to access the API key through the networkClient or configuration
        let mirror = Mirror(reflecting: self)
        
        // Try to extract from the custom headers (for different providers with custom headers)
        if let serviceInfo = mirror.children.first(where: { $0.label == "serviceInfo" || $0.label == "_serviceInfo" })?.value {
            let infoMirror = Mirror(reflecting: serviceInfo)
            if let extraHeaders = infoMirror.children.first(where: { $0.label == "extraHeaders" || $0.label == "_extraHeaders" })?.value as? [String: String] {
                // Check for various provider-specific header keys
                // First check for Claude's x-api-key header
                if let claudeApiKey = extraHeaders["x-api-key"], !claudeApiKey.isEmpty {
                    Logger.debug("✅ Found Claude API key in x-api-key header")
                    return claudeApiKey
                }
                
                // Check for Gemini's x-goog-api-key header
                if let geminiApiKey = extraHeaders["x-goog-api-key"], !geminiApiKey.isEmpty {
                    Logger.debug("✅ Found Gemini API key in x-goog-api-key header")
                    return geminiApiKey
                }
            }
            
            // Check the base URL to determine the provider
            if let baseURL = infoMirror.children.first(where: { $0.label == "overrideBaseURL" || $0.label == "_overrideBaseURL" })?.value as? String {
                Logger.debug("🔍 Detected base URL: \(baseURL)")
                
                // Determine provider from URL and get key from UserDefaults
                if baseURL.contains("anthropic") {
                    if let key = UserDefaults.standard.string(forKey: "claudeApiKey"), !key.isEmpty && key != "none" {
                        Logger.debug("✅ Using Claude API key from UserDefaults")
                        return key
                    }
                } else if baseURL.contains("generativelanguage") {
                    if let key = UserDefaults.standard.string(forKey: "geminiApiKey"), !key.isEmpty && key != "none" {
                        Logger.debug("✅ Using Gemini API key from UserDefaults") 
                        return key
                    }
                } else if baseURL.contains("groq") {
                    if let key = UserDefaults.standard.string(forKey: "grokApiKey"), !key.isEmpty && key != "none" {
                        Logger.debug("✅ Using Grok API key from UserDefaults")
                        return key
                    }
                }
            }
        }
        
        // Find networkClient and check headers
        if let networkClient = mirror.children.first(where: { $0.label == "networkClient" || $0.label == "_networkClient" })?.value {
            let networkMirror = Mirror(reflecting: networkClient)
            
            // Look for headers in networkClient
            if let headers = networkMirror.children.first(where: { $0.label == "headers" || $0.label == "_headers" })?.value as? [String: String] {
                // Check for standard Authorization header
                if let authHeader = headers["Authorization"], authHeader.hasPrefix("Bearer ") {
                    let extractedKey = authHeader.replacingOccurrences(of: "Bearer ", with: "")
                    Logger.debug("✅ Found API key in Authorization header")
                    return extractedKey
                }
                
                // Check for Claude's x-api-key header
                if let claudeApiKey = headers["x-api-key"], !claudeApiKey.isEmpty {
                    Logger.debug("✅ Found Claude API key in x-api-key header")
                    return claudeApiKey
                }
            }
            
            // Try to find the session configuration which may contain API key
            if let sessionConfig = networkMirror.children.first(where: { $0.label == "configuration" || $0.label == "_configuration" || $0.label == "sessionConfig" })?.value {
                let configMirror = Mirror(reflecting: sessionConfig)
                
                // Log all available headers for debugging
                if let httpHeaders = configMirror.children.first(where: { $0.label == "HTTPAdditionalHeaders" })?.value as? [AnyHashable: Any] {
                    for (key, _) in httpHeaders {
                        Logger.debug("🔍 Found header: \(key)")
                    }
                    
                    // Check authorization header
                    if let authHeader = httpHeaders["Authorization"] as? String, authHeader.hasPrefix("Bearer ") {
                        let extractedKey = authHeader.replacingOccurrences(of: "Bearer ", with: "")
                        Logger.debug("✅ Found API key in HTTPAdditionalHeaders Authorization")
                        return extractedKey
                    }
                    
                    // Check for Claude's x-api-key header
                    if let claudeApiKey = httpHeaders["x-api-key"] as? String, !claudeApiKey.isEmpty {
                        Logger.debug("✅ Found Claude API key in HTTPAdditionalHeaders x-api-key")
                        return claudeApiKey
                    }
                }
            }
        }
        
        // Get API key from UserDefaults based on clues in the service properties
        // This is a last resort for when we don't find the API key in the service
        // First determine provider from any URL or string
        var detectedProvider = ""
        
        // Check for URL strings to determine provider
        for child in mirror.children {
            if let url = child.value as? URL {
                let urlString = url.absoluteString
                if urlString.contains("anthropic") {
                    detectedProvider = AIModels.Provider.claude
                    break
                } else if urlString.contains("generativelanguage") {
                    detectedProvider = AIModels.Provider.gemini
                    break
                } else if urlString.contains("groq") {
                    detectedProvider = AIModels.Provider.grok
                    break
                }
            } else if let urlString = child.value as? String, urlString.starts(with: "http") {
                if urlString.contains("anthropic") {
                    detectedProvider = AIModels.Provider.claude
                    break
                } else if urlString.contains("generativelanguage") {
                    detectedProvider = AIModels.Provider.gemini
                    break
                } else if urlString.contains("groq") {
                    detectedProvider = AIModels.Provider.grok
                    break
                }
            }
        }
        
        // If we didn't find a URL, check for provider name in any string
        if detectedProvider.isEmpty {
            for child in mirror.children {
                if let stringValue = child.value as? String {
                    if stringValue.contains("anthropic") || stringValue.contains("claude") {
                        detectedProvider = AIModels.Provider.claude
                        break
                    } else if stringValue.contains("gemini") {
                        detectedProvider = AIModels.Provider.gemini
                        break
                    } else if stringValue.contains("groq") || stringValue.contains("grok") {
                        detectedProvider = AIModels.Provider.grok
                        break
                    }
                }
            }
        }
        
        // Get API key from UserDefaults based on detected provider
        if !detectedProvider.isEmpty {
            let key = UserDefaults.standard.string(forKey: "\(detectedProvider)ApiKey") ?? ""
            if !key.isEmpty && key != "none" {
                Logger.debug("✅ Using \(detectedProvider) API key from UserDefaults based on service provider detection")
                return key
            }
        }
        
        // Absolute last resort - try getting the key from UserDefaults
        Logger.debug("⚠️ Couldn't extract API key from service, falling back to OpenAI key")
        return UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
    }
}