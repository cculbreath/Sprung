import Foundation
import SwiftOpenAI
import SwiftUI
import os.log
import Observation

@Observable
final class OpenRouterService {
    var availableModels: [OpenRouterModel] = []
    var isLoading = false
    var lastError: String?
    
    // Dynamic pricing thresholds based on actual data
    private(set) var pricingThresholds: [Double] = []
    
    private let baseURL = "https://openrouter.ai/api/v1"
    private let modelsEndpoint = "/models"
    private let cacheKey = "openrouter_models_cache"
    private let cacheTimestampKey = "openrouter_models_cache_timestamp"
    private let cacheValidityDuration: TimeInterval = 3600 // 1 hour
    
    private var openRouterClient: OpenAIService?
    private var apiKey: String = ""
    
    init() {
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
        guard openRouterClient != nil else {
            await MainActor.run {
                self.lastError = "OpenRouter client not configured"
            }
            Logger.error("🔴 OpenRouter client not configured")
            return
        }

        await MainActor.run {
            self.isLoading = true
            self.lastError = nil
        }

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
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                Logger.error("🔴 HTTP \(httpResponse.statusCode): \(responseBody)")
                throw OpenRouterError.httpError(httpResponse.statusCode)
            }
            
            
            do {
                let modelsResponse = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
                
                await MainActor.run {
                    self.availableModels = modelsResponse.data.sorted { $0.name < $1.name }
                    self.calculatePricingThresholds()
                    Logger.info("✅ Fetched \(availableModels.count) models from OpenRouter")
                    self.cacheModels()
                }
            } catch let decodingError as DecodingError {
                await MainActor.run {
                    let errorMessage = "JSON decoding failed: \(decodingError.localizedDescription)"
                    lastError = errorMessage
                    Logger.error("🔴 \(errorMessage)")
                    
                    // Log detailed decoding error
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        Logger.error("🔴 Missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .typeMismatch(let type, let context):
                        Logger.error("🔴 Type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .valueNotFound(let type, let context):
                        Logger.error("🔴 Value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .dataCorrupted(let context):
                        Logger.error("🔴 Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    @unknown default:
                        Logger.error("🔴 Unknown decoding error: \(decodingError)")
                    }
                }
            }
            
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
                Logger.error("🔴 Failed to fetch OpenRouter models: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            self.isLoading = false
        }
    }
    
    
    @MainActor
    func findModel(id: String) -> OpenRouterModel? {
        availableModels.first { $0.id == id }
    }
    
    /// Returns a friendly display name for a model ID
    /// - Parameter modelId: The model ID to look up
    /// - Returns: The display name if found, otherwise the original ID
    @MainActor
    func friendlyModelName(for modelId: String) -> String {
        if let model = findModel(id: modelId) {
            return model.displayName
        }
        return modelId
    }
    
    @MainActor
    private func cacheModels() {
        do {
            let data = try JSONEncoder().encode(availableModels)
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
            Logger.info("💾 Cached \(availableModels.count) models")
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
            Logger.info("⏰ Cached models expired (age: \(Int(cacheAge))s)")
            return
        }
        
        do {
            let models = try JSONDecoder().decode([OpenRouterModel].self, from: data)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.availableModels = models.sorted { $0.name < $1.name }
                self.calculatePricingThresholds()
                Logger.info("📦 Loaded \(models.count) cached models")
            }
        } catch {
            Logger.error("🔴 Failed to load cached models: \(error.localizedDescription)")
        }
    }
    
    /// Calculates dynamic pricing thresholds based on actual model pricing distribution
    @MainActor
    private func calculatePricingThresholds() {
        // Collect all valid pricing data (average of prompt + completion costs)
        let pricingData: [Double] = availableModels.compactMap { model in
            guard let pricing = model.pricing else { return nil }
            let promptCost = pricing.promptCostPer1M
            let completionCost = pricing.completionCostPer1M
            let avgCost = (promptCost + completionCost) / 2.0
            return avgCost > 0 ? avgCost : nil
        }.sorted()
        
        guard !pricingData.isEmpty else {
            pricingThresholds = [0.0, 0.5, 2.0, 10.0, 50.0] // fallback to arbitrary if no data
            return
        }
        
        let count = pricingData.count
        Logger.debug("📊 Calculating pricing thresholds from \(count) models")
        if let first = pricingData.first, let last = pricingData.last {
            Logger.debug("💰 Price range: $\(String(format: "%.6f", first)) - $\(String(format: "%.6f", last))")
        }
        
        // Use percentiles to create meaningful thresholds
        // Free models (0 cost) get their own tier
        // Then distribute the rest across 4 tiers using quartiles
        let nonFreePricing = pricingData.filter { $0 > 0 }
        
        if nonFreePricing.isEmpty {
            pricingThresholds = [0.0, 0.1, 0.5, 2.0, 10.0]
            return
        }
        
        let q1Index = Int(Double(nonFreePricing.count) * 0.25)
        let q2Index = Int(Double(nonFreePricing.count) * 0.50)
        let q3Index = Int(Double(nonFreePricing.count) * 0.75)
        let q4Index = Int(Double(nonFreePricing.count) * 0.90) // 90th percentile for highest tier
        
        let q1 = nonFreePricing[min(q1Index, nonFreePricing.count - 1)]
        let q2 = nonFreePricing[min(q2Index, nonFreePricing.count - 1)]
        let q3 = nonFreePricing[min(q3Index, nonFreePricing.count - 1)]
        let q4 = nonFreePricing[min(q4Index, nonFreePricing.count - 1)]
        
        pricingThresholds = [0.0, q1, q2, q3, q4]
        
        Logger.debug("💵 Dynamic pricing thresholds:")
        Logger.debug("   Free: $0.00")
        Logger.debug("   $:    $0.00 - $\(String(format: "%.6f", q1))")
        Logger.debug("   $$:   $\(String(format: "%.6f", q1)) - $\(String(format: "%.6f", q2))")
        Logger.debug("   $$$:  $\(String(format: "%.6f", q2)) - $\(String(format: "%.6f", q3))")
        Logger.debug("   $$$$: $\(String(format: "%.6f", q3)) - $\(String(format: "%.6f", q4))")
        Logger.debug("   $$$$$: > $\(String(format: "%.6f", q4))")
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
