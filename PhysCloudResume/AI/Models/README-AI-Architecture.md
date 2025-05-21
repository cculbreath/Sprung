# PhysCloudResume AI Architecture

This document describes the AI subsystem architecture in the PhysCloudResume app following the refactoring to consolidate multiple competing abstraction layers.

## Overview

The AI subsystem has been refactored to use a single, unified interface for all LLM interactions. This eliminates redundancy, simplifies the codebase, and makes it easier to maintain and extend.

### Core Components

1. **AppLLMClientProtocol**: The unified interface for all LLM clients
2. **BaseLLMProvider**: Base class for all provider implementations
3. **MessageConverter**: Centralized utility for message format conversions
4. **LLMSchemaBuilder**: Utility for JSON schema generation and handling

## Architecture Diagram

```
┌─────────────────┐     ┌────────────────────┐     ┌───────────────────┐
│     UI Layer    │     │    Provider Layer   │     │    Client Layer   │
│                 │     │                     │     │                   │
│  View           │     │  BaseLLMProvider    │     │ AppLLMClient      │
│  Components     │────▶│  ResumeChatProvider │────▶│ Protocol          │
│                 │     │  CoverChatProvider  │     │                   │
└─────────────────┘     └────────────────────┘     └───────────┬───────┘
                                                               │
                                                               ▼
┌─────────────────┐     ┌────────────────────┐     ┌───────────────────┐
│   Utilities     │     │   Adapters Layer    │     │  External SDKs    │
│                 │     │                     │     │                   │
│ MessageConverter│◀───▶│ SwiftOpenAIAdapter  │────▶│ SwiftOpenAI       │
│ LLMSchemaBuilder│     │ ForOpenAI/Anthropic │     │ Library           │
└─────────────────┘     └────────────────────┘     └───────────────────┘
```

## Key Interfaces

### AppLLMClientProtocol

This is the main interface for all LLM client interactions, supporting text completion and structured output.

```swift
protocol AppLLMClientProtocol {
    /// Executes a query expecting a single, non-streaming response (text or structured).
    func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse
}
```

### BaseLLMProvider

Base class that implements common functionality for all providers, reducing code duplication.

```swift
class BaseLLMProvider {
    private(set) var appLLMClient: AppLLMClientProtocol
    var conversationHistory: [AppLLMMessage] = []
    
    // Initializers
    init(appState: AppState)
    init(client: AppLLMClientProtocol)
    
    // Common methods
    func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse
    func initializeConversation(systemPrompt: String, userPrompt: String) -> [AppLLMMessage]
    func addUserMessage(_ userInput: String) -> [AppLLMMessage]
    func addAssistantMessage(_ assistantResponse: String) -> [AppLLMMessage]
}
```

## Utilities

### MessageConverter

Centralizes all message format conversions, eliminating duplicated conversion logic.

```swift
class MessageConverter {
    // Convert between AppLLMMessage and ChatMessage (legacy format)
    static func appLLMMessageFrom(chatMessage: ChatMessage) -> AppLLMMessage
    static func chatMessageFrom(appMessage: AppLLMMessage) -> ChatMessage
    
    // Convert between AppLLMMessage and SwiftOpenAI format
    static func swiftOpenAIMessageFrom(appMessage: AppLLMMessage) -> ChatCompletionParameters.Message
    static func appLLMMessageFrom(swiftMessage: ChatCompletionParameters.Message) -> AppLLMMessage
}
```

### LLMSchemaBuilder

Handles JSON schema generation for structured outputs.

```swift
class LLMSchemaBuilder {
    // Create schemas for common types
    static func createSchema(for type: Decodable.Type) -> SwiftOpenAI.JSONSchema
    
    // Parse JSON schema strings
    static func parseJSONSchemaString(_ jsonString: String) -> SwiftOpenAI.JSONSchema?
    
    // Create response formats for SwiftOpenAI
    static func createResponseFormat(for responseType: Decodable.Type?, jsonSchema: String?) -> SwiftOpenAI.ResponseFormat?
}
```

## Migration Guide

### Migrating from OpenAIClientProtocol to AppLLMClientProtocol

The OpenAIClientProtocol has been deprecated in favor of AppLLMClientProtocol. Here's how to migrate:

#### Before:

```swift
let client = OpenAIClientFactory.createClient(apiKey: apiKey)
let response = try await client.sendChatCompletionAsync(
    messages: messages,
    model: modelName,
    responseFormat: nil,
    temperature: 0.7
)
```

#### After:

```swift
let client = AppLLMClientFactory.createClient(for: providerType, appState: appState)
let query = AppLLMQuery(
    messages: Array<AppLLMMessage>.fromChatMessages(messages),
    modelIdentifier: modelName,
    temperature: 0.7
)
let response = try await client.executeQuery(query)
```

### Provider Implementation

When implementing a new provider, inherit from BaseLLMProvider instead of implementing from scratch:

```swift
class MyCustomProvider: BaseLLMProvider {
    // Initialize with the app state
    override init(appState: AppState) {
        super.init(appState: appState)
    }
    
    // Custom functionality
    func processCustomInteraction(userInput: String) async throws -> String {
        // Add user message to conversation
        _ = addUserMessage(userInput)
        
        // Execute query with conversation history
        let query = AppLLMQuery(
            messages: conversationHistory,
            modelIdentifier: "model-name",
            temperature: 0.7
        )
        
        let response = try await executeQuery(query)
        
        // Extract text response
        let responseText: String
        switch response {
        case .text(let text):
            responseText = text
        case .structured(let data):
            responseText = String(data: data, encoding: .utf8) ?? ""
        }
        
        // Add assistant response to conversation
        _ = addAssistantMessage(responseText)
        
        return responseText
    }
}
```

## Best Practices

1. **Use the MessageConverter**: Always use the MessageConverter for any conversions between message formats.
2. **Inherit from BaseLLMProvider**: All provider implementations should inherit from BaseLLMProvider.
3. **Use AppLLMQuery**: Create AppLLMQuery instances for all requests to standardize parameters.
4. **Handle return values**: Remember to capture or discard return values from methods like `addUserMessage` and `initializeConversation`.
5. **Error handling**: Use the error handling mechanisms provided by BaseLLMProvider.

