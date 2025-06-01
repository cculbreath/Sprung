import Foundation
import SwiftOpenAI
import os.log

@MainActor
final class OpenRouterService: ObservableObject {
    static let shared = OpenRouterService()
    
    @Published var availableModels: [OpenRouterModel] = []
    @Published var isLoading = false
    @Published var lastError: String?
    
    private let baseURL = "https://openrouter.ai/api/v1"
    private let modelsEndpoint = "/models"
    private let cacheKey = "openrouter_models_cache"
    private let cacheTimestampKey = "openrouter_models_cache_timestamp"
    private let cacheValidityDuration: TimeInterval = 3600 // 1 hour
    
    private var openRouterClient: OpenAIService?
    private var apiKey: String = ""
    
    private init() {
        loadCachedModels()
    }
    
    func configure(apiKey: String) {
        guard !apiKey.isEmpty else {
            Logger.error("🔴 OpenRouter API key is empty")
            return
        }
        
        Logger.info("🔧 Configuring OpenRouter client")
        self.apiKey = apiKey
        openRouterClient = OpenAIServiceFactory.service(
            apiKey: apiKey,
            overrideBaseURL: baseURL
        )
    }
    
    func fetchModels() async {
        guard let client = openRouterClient else {
            lastError = "OpenRouter client not configured"
            Logger.error("🔴 OpenRouter client not configured")
            return
        }
        
        isLoading = true
        lastError = nil
        
        do {
            Logger.info("🌐 Fetching models from OpenRouter")
            
            let url = URL(string: baseURL + modelsEndpoint)!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenRouterError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw OpenRouterError.httpError(httpResponse.statusCode)
            }
            
            let modelsResponse = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            
            await MainActor.run {
                availableModels = modelsResponse.data.sorted { $0.name < $1.name }
                Logger.info("✅ Fetched \(availableModels.count) models from OpenRouter")
                cacheModels()
            }
            
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
                Logger.error("🔴 Failed to fetch OpenRouter models: \(error.localizedDescription)")
            }
        }
        
        isLoading = false
    }
    
    func getModelsWithCapability(_ capability: ModelCapability) -> [OpenRouterModel] {
        switch capability {
        case .structuredOutput:
            return availableModels.filter { $0.supportsStructuredOutput }
        case .vision:
            return availableModels.filter { $0.supportsImages }
        case .reasoning:
            return availableModels.filter { $0.supportsReasoning }
        case .textOnly:
            return availableModels.filter { $0.isTextToText && !$0.supportsImages }
        }
    }
    
    func findModel(id: String) -> OpenRouterModel? {
        availableModels.first { $0.id == id }
    }
    
    private func cacheModels() {
        do {
            let data = try JSONEncoder().encode(availableModels)
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
            Logger.debug("💾 Cached \(availableModels.count) models")
        } catch {
            Logger.error("🔴 Failed to cache models: \(error.localizedDescription)")
        }
    }
    
    private func loadCachedModels() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            Logger.debug("📭 No cached models found")
            return
        }
        
        let cacheTimestamp = UserDefaults.standard.double(forKey: cacheTimestampKey)
        let cacheAge = Date().timeIntervalSince1970 - cacheTimestamp
        
        if cacheAge > cacheValidityDuration {
            Logger.debug("⏰ Cached models expired (age: \(Int(cacheAge))s)")
            return
        }
        
        do {
            availableModels = try JSONDecoder().decode([OpenRouterModel].self, from: data)
            Logger.info("📦 Loaded \(availableModels.count) cached models")
        } catch {
            Logger.error("🔴 Failed to load cached models: \(error.localizedDescription)")
        }
    }
}

enum ModelCapability: CaseIterable {
    case structuredOutput
    case vision
    case reasoning
    case textOnly
    
    var displayName: String {
        switch self {
        case .structuredOutput: return "Structured Output"
        case .vision: return "Vision"
        case .reasoning: return "Reasoning"
        case .textOnly: return "Text Only"
        }
    }
    
    var icon: String {
        switch self {
        case .structuredOutput: return "list.bullet.rectangle"
        case .vision: return "eye"
        case .reasoning: return "brain"
        case .textOnly: return "text.alignleft"
        }
    }
}

enum OpenRouterError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenRouter API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        }
    }
}