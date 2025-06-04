import Foundation
import SwiftOpenAI
import os.log

struct OpenRouterClientFactory {
    private static let baseURL = "https://openrouter.ai"
    
    static func createClient(apiKey: String) -> OpenAIService {
        Logger.info("🔧 Creating OpenRouter client")
        
        // Log API key info (not the actual key for security)
        Logger.debug("🔑 API key length: \(apiKey.count) characters")
        Logger.debug("🔑 API key starts with: \(String(apiKey.prefix(10)))...")
        
        // OpenRouter may require additional headers
        let extraHeaders = [
            "HTTP-Referer": "https://physicscloud.net",  // Optional, but helps with OpenRouter rankings
            "X-Title": "PhysCloudResume"  // Optional, but helps with OpenRouter rankings
        ]
        
        return OpenAIServiceFactory.service(
            apiKey: apiKey,
            overrideBaseURL: baseURL,
            proxyPath: "api",
            extraHeaders: extraHeaders,
            debugEnabled: true  // Enable debug mode to see API errors
        )
    }
    
    static func createTTSClient(openAiApiKey: String) -> OpenAIService {
        Logger.info("🔧 Creating dedicated OpenAI TTS client")
        
        return OpenAIServiceFactory.service(
            apiKey: openAiApiKey
        )
    }
}

extension OpenRouterClientFactory {
    static func supportsStructuredOutput(model: OpenRouterModel) -> Bool {
        model.supportsStructuredOutput
    }
    
    static func supportsImages(model: OpenRouterModel) -> Bool {
        model.supportsImages
    }
    
    static func supportsReasoning(model: OpenRouterModel) -> Bool {
        model.supportsReasoning
    }
}