import Foundation
struct OpenRouterModel: Codable, Identifiable, Hashable, Equatable {
    let id: String
    let name: String
    let description: String?
    let contextLength: Int?
    let architecture: Architecture?
    let pricing: Pricing?
    let supportedParameters: [String]? // Legacy field, may be nil
    let endpoints: [Endpoint]?
    
    struct Architecture: Codable, Hashable {
        let modality: String
        let inputModalities: [String]
        
        enum CodingKeys: String, CodingKey {
            case modality
            case inputModalities = "input_modalities"
        }
    }
    
    struct Pricing: Codable, Hashable {
        let prompt: String?
        let completion: String?
        let internalReasoning: String?
        
        enum CodingKeys: String, CodingKey {
            case prompt, completion
            case internalReasoning = "internal_reasoning"
        }
        
        var promptCostPer1M: Double {
            guard let prompt = prompt else { return 0.0 }
            return Double(prompt) ?? 0.0
        }
        
        var completionCostPer1M: Double {
            guard let completion = completion else { return 0.0 }
            return Double(completion) ?? 0.0
        }
    }
    
    struct Endpoint: Codable, Hashable {
        let pricing: Pricing?
        let supportedParameters: [String]?
        
        enum CodingKeys: String, CodingKey {
            case pricing
            case supportedParameters = "supported_parameters"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, architecture, pricing, endpoints
        case contextLength = "context_length"
        case supportedParameters = "supported_parameters"
    }
}
extension OpenRouterModel {
    var supportsStructuredOutput: Bool {
        // 1. Check supported parameters from endpoints (primary source)
        if let endpoints = endpoints {
            for endpoint in endpoints {
                if let params = endpoint.supportedParameters,
                   (params.contains("structured_outputs") || params.contains("response_format")) {
                    return true
                }
            }
        }
        
        // 2. Fallback to legacy top-level supported parameters
        if let params = supportedParameters,
           (params.contains("structured_outputs") || params.contains("response_format")) {
            return true
        }
        
        return false
    }
    
    var supportsImages: Bool {
        architecture?.inputModalities.contains("image") ?? false
    }
    
    var supportsReasoning: Bool {
        // Only rely on API-provided data - no hardcoded model names
        
        // 1. Check supported parameters from endpoints (primary source)
        if let endpoints = endpoints {
            for endpoint in endpoints {
                if let params = endpoint.supportedParameters,
                   (params.contains("reasoning") || params.contains("include_reasoning")) {
                    return true
                }
            }
        }
        
        // 2. Fallback to legacy top-level supported parameters
        if let params = supportedParameters,
           (params.contains("reasoning") || params.contains("include_reasoning")) {
            return true
        }
        
        // 3. Check pricing for internal_reasoning cost (secondary indicator)
        if let pricing = pricing, 
           let internalReasoningCost = pricing.internalReasoning,
           !internalReasoningCost.isEmpty && internalReasoningCost != "0" {
            return true
        }
        
        // 4. Check endpoint pricing for internal_reasoning cost
        if let endpoints = endpoints {
            for endpoint in endpoints {
                if let pricing = endpoint.pricing,
                   let internalReasoningCost = pricing.internalReasoning,
                   !internalReasoningCost.isEmpty && internalReasoningCost != "0" {
                    return true
                }
            }
        }
        
        return false
    }
    
    var isTextToText: Bool {
        architecture?.modality == "text->text"
    }
    
    var displayName: String {
        name.isEmpty ? id : name
    }
    
    var providerName: String {
        let components = id.split(separator: "/")
        return components.first?.capitalized ?? "Unknown"
    }
    
    var costDescription: String {
        guard let pricing = pricing else {
            return "Pricing unavailable"
        }
        
        let promptCost = pricing.promptCostPer1M
        let completionCost = pricing.completionCostPer1M
        
        if promptCost == 0 && completionCost == 0 {
            return "Free"
        }
        
        return String(format: "$%.6f/$%.6f per 1M tokens", promptCost, completionCost)
    }
    
    func costLevel(using thresholds: [Double] = [0.0, 0.5, 2.0, 10.0, 50.0]) -> Int {
        guard let pricing = pricing else { return 0 }
        
        let promptCost = pricing.promptCostPer1M
        let completionCost = pricing.completionCostPer1M
        let avgCost = (promptCost + completionCost) / 2.0
        
        if avgCost == 0 { return 0 } // Free
        
        // Use provided thresholds for dynamic calculation
        for (index, threshold) in thresholds.enumerated().dropFirst() {
            if avgCost <= threshold {
                return index
            }
        }
        
        return thresholds.count // Highest tier
    }
    
    func costLevelDescription(using thresholds: [Double] = [0.0, 0.5, 2.0, 10.0, 50.0]) -> String {
        let level = costLevel(using: thresholds)
        switch level {
        case 0: return "Free"
        case 1: return "$"
        case 2: return "$$"
        case 3: return "$$$"
        case 4: return "$$$$"
        case 5: return "$$$$$"
        default: return "?"
        }
    }
    
    var isHighCostModel: Bool {
        guard let pricing = pricing else { return false }
        
        let promptCost = pricing.promptCostPer1M
        // Check if 50k tokens would cost more than $0.50
        let costFor50kTokens = (promptCost * 50.0) / 1000.0
        return costFor50kTokens > 0.5
    }
}
struct OpenRouterModelsResponse: Codable {
    let data: [OpenRouterModel]
}
