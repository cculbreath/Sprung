import Foundation

struct OpenRouterModel: Codable, Identifiable, Hashable, Equatable {
    let id: String
    let name: String
    let description: String?
    let contextLength: Int?
    let architecture: Architecture?
    let pricing: Pricing?
    let supportedParameters: [String]?
    let created: TimeInterval?
    
    struct Architecture: Codable, Hashable {
        let modality: String
        let inputModalities: [String]
        let outputModalities: [String]
        let tokenizer: String?
        let instructType: String?
        
        enum CodingKeys: String, CodingKey {
            case modality
            case inputModalities = "input_modalities"
            case outputModalities = "output_modalities"
            case tokenizer
            case instructType = "instruct_type"
        }
    }
    
    struct Pricing: Codable, Hashable {
        let prompt: String?
        let completion: String?
        let request: String?
        let image: String?
        let webSearch: String?
        let internalReasoning: String?
        
        enum CodingKeys: String, CodingKey {
            case prompt, completion, request, image
            case webSearch = "web_search"
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
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, created, architecture, pricing
        case contextLength = "context_length"
        case supportedParameters = "supported_parameters"
    }
}

extension OpenRouterModel {
    var supportsStructuredOutput: Bool {
        guard let params = supportedParameters else { return false }
        return params.contains("structured_outputs") || params.contains("response_format")
    }
    
    var supportsImages: Bool {
        architecture?.inputModalities.contains("image") ?? false
    }
    
    var supportsReasoning: Bool {
        guard let params = supportedParameters else { return false }
        return params.contains("reasoning") || params.contains("include_reasoning")
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
    
    var modelName: String {
        let components = id.split(separator: "/")
        return components.dropFirst().joined(separator: "/")
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