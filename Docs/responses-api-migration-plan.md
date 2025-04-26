# OpenAI Responses API Migration Plan

## Overview

This document outlines the plan to migrate from OpenAI's ChatCompletion API to the Responses API with server-side conversation state. The migration will improve context window population during resume generation and cover letter generation by leveraging OpenAI's server-side conversation tracking.

## Current Implementation

1. The app uses the MacPaw/OpenAI Swift library for API interactions
2. Chat completions are initiated via:
   - `ResumeChatProvider` for resume-related operations
   - `CoverChatProvider` for cover letter operations
3. Message history is stored:
   - As `genericMessages` in both chat providers
   - For cover letters, also stored in `CoverLetter.messageHistory`
4. All context is provided in each API call by passing the entire message array

## Migration Goals

1. Integrate OpenAI's Responses API to replace the ChatCompletion API
2. Use server-side conversation state to maintain context between related requests
3. New conversations start with toolbar button presses, with all context provided via prompts
4. Subsequent interactions (like inspector button press or ReviewView submissions) should use `previous_response_id` for context tracking
5. Eliminate the need to maintain a complete message history in memory and pass it with every API call

## Implementation Tasks

### 1. Update Models

1. Add `previousResponseId` field to:
   - `Resume` model
   - `CoverLetter` model (or associated models)

2. Update `ChatCompletionResponse` to include the response ID from the OpenAI API

### 2. Update OpenAI Client Implementation

1. Modify `OpenAIClientProtocol` to support the Responses API
2. Update `MacPawOpenAIClient` implementation to handle Responses API requests
3. Add appropriate error handling for the new API

### 3. Update Chat Providers

1. Modify `ResumeChatProvider` to:
   - Start new conversations for toolbar button presses
   - Use `previous_response_id` for subsequent interactions
   - Store response IDs in the associated Resume

2. Modify `CoverChatProvider` to:
   - Start new conversations for toolbar button presses
   - Use `previous_response_id` for subsequent interactions
   - Store response IDs in the associated CoverLetter

### 4. Update UI Components

1. Update `AiFunctionView` to initiate new conversations for toolbar button presses
2. Update `CoverLetterAiView` to initiate new conversations for toolbar button presses
3. Update `ReviewView` to use `previous_response_id` for continuations

### 5. Testing Plan

1. Test new conversation initiation from toolbar buttons
2. Test conversation continuations from inspector and review interactions
3. Test context retention between related requests
4. Verify performance improvements
5. Compare response quality with the previous implementation

## Implementation Details

### Client Protocol Updates

```swift
// Update OpenAIClientProtocol.swift
protocol OpenAIClientProtocol {
    // Existing methods...
    
    // New methods for Responses API
    func sendResponseRequest(
        message: String,
        model: String,
        temperature: Double,
        previousResponseId: String?,
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    )
    
    func sendResponseRequestAsync(
        message: String,
        model: String,
        temperature: Double,
        previousResponseId: String?
    ) async throws -> ResponsesAPIResponse
    
    func sendResponseRequestStreaming(
        message: String,
        model: String,
        temperature: Double,
        previousResponseId: String?,
        onChunk: @escaping (Result<ResponsesAPIStreamChunk, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    )
}

// New response structure
struct ResponsesAPIResponse: Codable, Equatable {
    let id: String
    let content: String
    let model: String
}

struct ResponsesAPIStreamChunk: Codable, Equatable {
    let id: String?  // Only available in the final chunk
    let content: String
    let model: String
}
```

### Model Updates

```swift
// Update Resume.swift
@Model
class Resume: Identifiable, Hashable {
    // Existing properties...
    
    // Add this property to store the OpenAI response ID
    var previousResponseId: String?
}

// Update CoverLetter.swift
@Model
class CoverLetter: Identifiable, Hashable {
    // Existing properties...
    
    // Add this property to store the OpenAI response ID
    var previousResponseId: String?
    
    // We can potentially phase out messageHistory since we'll use server-side
    // conversation tracking, but keep it for backward compatibility initially
}
```

### Client Implementation Updates

The MacPawOpenAIClient will need to be updated to support the Responses API. This may involve direct HTTP requests if the MacPaw library doesn't yet support the Responses API.

## Timeline

1. Client Protocol and Model Updates (1-2 days)
2. Client Implementation (2-3 days)
3. Provider Updates (2-3 days)
4. UI Component Updates (1-2 days)
5. Testing and Bug Fixes (2-3 days)

## Risks and Mitigations

1. **Risk**: MacPaw library may not support Responses API
   **Mitigation**: Implement direct HTTP requests as needed

2. **Risk**: Response differences between APIs
   **Mitigation**: Comprehensive testing and fallback mechanisms

3. **Risk**: Breaking changes in data models
   **Mitigation**: Ensure backward compatibility with existing saved data

4. **Risk**: Performance issues
   **Mitigation**: Benchmark and optimize critical paths