import Foundation
import SwiftOpenAI
import os.log

struct OpenRouterClientFactory {
    private static let baseURL = "https://openrouter.ai/api/v1"
    
    static func createClient(apiKey: String) -> OpenAIService {
        Logger.shared.info("🔧 Creating OpenRouter client")
        
        return OpenAIServiceFactory.service(
            apiKey: apiKey,
            overrideBaseURL: baseURL
        )
    }
    
    static func createTTSClient(openAiApiKey: String) -> OpenAIService {
        Logger.shared.info("🔧 Creating dedicated OpenAI TTS client")
        
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