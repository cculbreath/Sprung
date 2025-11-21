//
//  ModelValidationService.swift
//  Sprung
//
//  Validates model availability and capabilities by calling OpenRouter endpoints
//
import Foundation
import SwiftUI
@MainActor
@Observable
class ModelValidationService {
    private let baseURL = "https://openrouter.ai/api/v1"
    
    // Validation state
    var isValidating = false
    var validationResults: [String: ModelValidationResult] = [:]
    var failedModels: [String] = []
    
    init() {}
    
    /// Result of model endpoint validation
    struct ModelValidationResult {
        let isAvailable: Bool
        let actualCapabilities: ModelCapabilities?
        let error: String?
        
        struct ModelCapabilities {
            let supportsStructuredOutputs: Bool
            let supportsResponseFormat: Bool
            let supportsImages: Bool
            let supportedParameters: [String]
        }
    }
    
    /// Validate a single model by calling its endpoint
    func validateModel(_ modelId: String) async -> ModelValidationResult {
        let apiKey = APIKeyManager.get(.openRouter) ?? ""
        guard !apiKey.isEmpty else {
            return ModelValidationResult(
                isAvailable: false,
                actualCapabilities: nil,
                error: "No API key configured"
            )
        }
        
        // Construct the endpoint URL
        let endpointPath = "/models/\(modelId)/endpoints"
        guard let url = URL(string: baseURL + endpointPath) else {
            return ModelValidationResult(
                isAvailable: false,
                actualCapabilities: nil,
                error: "Invalid URL"
            )
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return ModelValidationResult(
                isAvailable: false,
                actualCapabilities: nil,
                error: "Invalid response"
                )
            }
            
            if httpResponse.statusCode == 404 {
                return ModelValidationResult(
                isAvailable: false,
                actualCapabilities: nil,
                error: "Model not found (404)"
                )
            }
            
            guard httpResponse.statusCode == 200 else {
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                return ModelValidationResult(
                isAvailable: false,
                actualCapabilities: nil,
                error: "HTTP \(httpResponse.statusCode): \(responseBody)"
                )
            }
            
            // Parse the endpoint response to extract capabilities
            let capabilities = try parseEndpointResponse(data)
            
            return ModelValidationResult(
                isAvailable: true,
                actualCapabilities: capabilities,
                error: nil
            )
            
        } catch {
            return ModelValidationResult(
                isAvailable: false,
                actualCapabilities: nil,
                error: error.localizedDescription
            )
        }
    }
    
    /// Parse endpoint response to extract model capabilities
    private func parseEndpointResponse(_ data: Data) throws -> ModelValidationResult.ModelCapabilities {
        // Parse the JSON response from https://openrouter.ai/api/v1/models/author/slug/endpoints
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let dataObj = json?["data"] as? [String: Any],
              let endpoints = dataObj["endpoints"] as? [[String: Any]] else {
            throw NSError(domain: "ModelValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response structure"])
        }
        
        // Check the first available endpoint for capabilities
        let firstEndpoint = endpoints.first
        let supportedParams = firstEndpoint?["supported_parameters"] as? [String] ?? []
        
        return ModelValidationResult.ModelCapabilities(
            supportsStructuredOutputs: supportedParams.contains("structured_outputs"),
            supportsResponseFormat: supportedParams.contains("response_format"),
            supportsImages: false, // Would need to check input_modalities in architecture
            supportedParameters: supportedParams
        )
    }
    
    /// Validate multiple models in parallel
    func validateModels(_ modelIds: [String]) async -> [String: ModelValidationResult] {
        isValidating = true
        defer { isValidating = false }
        
        var results: [String: ModelValidationResult] = [:]
        
        // Validate in parallel with limited concurrency
        await withTaskGroup(of: (String, ModelValidationResult).self) { group in
            for modelId in modelIds {
                group.addTask {
                    let result = await self.validateModel(modelId)
                    return (modelId, result)
                }
            }
            
            for await (modelId, result) in group {
                results[modelId] = result
                
                await MainActor.run {
                    self.validationResults[modelId] = result
                    if !result.isAvailable {
                        self.failedModels.append(modelId)
                    }
                }
            }
        }
        
        return results
    }
    
}
