import Foundation

struct OpenRouterModel: Codable, Identifiable, Hashable, Equatable {
    let id: String
    let name: String
    let description: String?
    let contextLength: Int
    let architecture: Architecture
    let pricing: Pricing
    let supportedParameters: [String]
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
        let prompt: String
        let completion: String
        let request: String
        let image: String
        let webSearch: String?
        let internalReasoning: String?
        
        enum CodingKeys: String, CodingKey {
            case prompt, completion, request, image
            case webSearch = "web_search"
            case internalReasoning = "internal_reasoning"
        }
        
        var promptCostPer1M: Double {
            Double(prompt) ?? 0.0
        }
        
        var completionCostPer1M: Double {
            Double(completion) ?? 0.0
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
        supportedParameters.contains("response_format")
    }
    
    var supportsImages: Bool {
        architecture.inputModalities.contains("image")
    }
    
    var supportsReasoning: Bool {
        supportedParameters.contains("reasoning") || 
        supportedParameters.contains("include_reasoning")
    }
    
    var isTextToText: Bool {
        architecture.modality == "text->text"
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
        let promptCost = pricing.promptCostPer1M
        let completionCost = pricing.completionCostPer1M
        
        if promptCost == 0 && completionCost == 0 {
            return "Free"
        }
        
        return String(format: "$%.4f/$%.4f per 1M tokens", promptCost, completionCost)
    }
}

struct OpenRouterModelsResponse: Codable {
    let data: [OpenRouterModel]
}