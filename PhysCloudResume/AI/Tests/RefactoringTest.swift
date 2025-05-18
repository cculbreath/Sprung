//
//  RefactoringTest.swift
//  PhysCloudResume
//
//  Created by Claude on 5/17/25.
//

import Foundation

/// Simple test to verify that the refactoring was successful
/// This file should compile without any OpenAI import dependencies
class RefactoringTest {
    /// Test that we can create a ResumeChatProvider without OpenAI dependencies
    func testResumeChatProviderCreation() {
        // Create a mock client
        let mockClient = MockOpenAIClient()
        
        // Create the provider - this should compile without OpenAI dependency
        let provider = ResumeChatProvider(client: mockClient)
        
        // Basic verification
        assert(provider.messages.isEmpty)
        assert(provider.genericMessages.isEmpty)
        assert(provider.errorMessage.isEmpty)
    }
    
    /// Test that we can use structured output types without OpenAI dependency
    func testStructuredOutputTypes() {
        // Create a RevisionsContainer - this should not require OpenAI import
        let container = RevisionsContainer(revArray: [])
        
        // Verify basic functionality
        assert(container.revArray.isEmpty)
        
        // Test encoding/decoding
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(container)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(RevisionsContainer.self, from: data)
            assert(decoded.revArray.isEmpty)
        } catch {
            assertionFailure("Failed to encode/decode RevisionsContainer: \(error)")
        }
    }
}

/// Mock implementation of OpenAIClientProtocol for testing
class MockOpenAIClient: OpenAIClientProtocol {
    var apiKey: String = "test-key"
    
    /// Initialize with custom configuration
    /// - Parameter configuration: The configuration to use
    required init(configuration: OpenAIConfiguration) {
        apiKey = configuration.token ?? "test-key"
    }
    
    /// Initialize with API key (convenience initializer)
    /// - Parameter apiKey: The API key to use
    required init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    /// Convenience initializer for testing
    convenience init() {
        self.init(apiKey: "test-key")
    }
    
    func sendChatCompletionAsync(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) async throws -> ChatCompletionResponse {
        return ChatCompletionResponse(content: "Mock response", model: model)
    }
    
    func sendChatCompletionWithStructuredOutput<T: StructuredOutput>(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        structuredOutputType: T.Type
    ) async throws -> T {
        // Return mock structured output
        if T.self == RevisionsContainer.self {
            return RevisionsContainer(revArray: []) as! T
        }
        throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported type"])
    }
    
    func sendResponseRequestAsync(
        message: String,
        model: String,
        temperature: Double?,
        previousResponseId: String?,
        schema: String?
    ) async throws -> ResponsesAPIResponse {
        return ResponsesAPIResponse(id: "mock-id", content: "Mock content", model: model)
    }
    
    func sendTTSRequest(
        text: String,
        voice: String,
        instructions: String?,
        onComplete: @escaping (Result<Data, Error>) -> Void
    ) {
        onComplete(.success(Data()))
    }
    
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        instructions: String?,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        onChunk(.success(Data()))
        onComplete(nil)
    }
}
