# OpenRouter Migration Implementation Plan

## Overview

This document outlines the complete migration from provider-specific LLM clients to OpenRouter's unified API. The migration will eliminate all provider-specific code while maintaining existing functionality through OpenRouter's OpenAI-compatible interface using the SwiftOpenAI package.

## Migration Goals

- **Simplify Architecture**: Replace multiple provider-specific clients with single OpenRouter client
- **Reduce Complexity**: Eliminate provider-specific code paths and configurations
- **Enhance UX**: Improve model selection with capability-based filtering
- **Maintain Functionality**: Preserve all existing LLM operations and TTS support
- **Clean Migration**: No backwards compatibility code - complete paradigm shift

## Current Architecture Issues

### Provider-Specific Complexity
- 4 separate provider clients (OpenAI, Claude, Grok, Gemini)
- Provider-specific adapters and configuration classes
- Complex provider detection and routing logic
- Multiple API key management interfaces
- Scattered provider-specific handling logic

### Model Management Limitations
- Provider-siloed model discovery
- Manual model-to-provider mapping
- Complex multi-provider model selection UI
- Limited capability-based filtering

## Target Architecture

### Unified OpenRouter Integration
- Single OpenRouter client using SwiftOpenAI with custom base URL
- Dynamic model discovery from OpenRouter's `/models` endpoint
- Capability-based model filtering (structured output, vision, reasoning)
- Simplified API key management (OpenRouter + OpenAI for TTS only)

---

## Implementation Plan

### Phase 1: Core OpenRouter Infrastructure

#### 1.1 OpenRouter Model Structure
Create new model representation for OpenRouter API response:

```swift
struct OpenRouterModel: Codable {
    let id: String
    let name: String
    let description: String?
    let contextLength: Int
    let architecture: Architecture
    let pricing: Pricing
    let supportedParameters: [String]
    
    struct Architecture: Codable {
        let modality: String
        let inputModalities: [String]
        let outputModalities: [String]
    }
    
    struct Pricing: Codable {
        let prompt: String
        let completion: String
    }
    
    // Helper properties for capability detection
    var supportsStructuredOutput: Bool { 
        supportedParameters.contains("response_format") 
    }
    var supportsImages: Bool { 
        architecture.inputModalities.contains("image") 
    }
    var supportsReasoning: Bool { 
        supportedParameters.contains("reasoning") 
    }
}
```

#### 1.2 OpenRouter Service
Replace `ModelService` with `OpenRouterService`:
- Fetch models from `https://openrouter.ai/api/v1/models`
- Cache models locally with capability indexing
- Provide filtering methods by model capabilities
- Handle model availability and pricing information

#### 1.3 AppState Simplification
Reduce API key management to essentials:
```swift
@AppStorage("openRouterApiKey") var openRouterApiKey: String = ""
@AppStorage("openAiApiKey") var openAiApiKey: String = "" // TTS only
@AppStorage("selectedOpenRouterModels") var selectedOpenRouterModels: Set<String> = []
```

### Phase 2: Client Architecture Overhaul

#### 2.1 Unified Client Factory
Replace complex `AppLLMClientFactory` with simple OpenRouter client:
```swift
static func createOpenRouterClient(apiKey: String) -> OpenAIService {
    return OpenAIServiceFactory.service(
        apiKey: apiKey,
        overrideBaseURL: "https://openrouter.ai/api/v1"
    )
}
```

#### 2.2 Provider Code Elimination
Remove all provider-specific infrastructure:
- Delete `SwiftOpenAIAdapterForClaude.swift`
- Delete `SwiftOpenAIAdapterForGemini.swift`  
- Delete `SwiftOpenAIAdapterForGrok.swift`
- Remove `AIModels.Provider` enum entirely
- Delete `LLMProviderConfig` variations
- Eliminate provider detection logic

#### 2.3 Unified LLM Provider Architecture
Simplify all LLM providers to use single OpenRouter client:
- Remove provider-specific initialization paths
- Use OpenRouter model IDs directly
- Implement per-model structured output detection
- Add fallback system prompts for non-structured output models

### Phase 3: UI/UX Modernization

#### 3.1 Enhanced Model Selection Interface
Update settings to display OpenRouter models with capability indicators:
- Multi-column layout showing model capabilities
- Visual indicators for structured output support
- Vision capability indicators
- Reasoning capability indicators  
- Per-model enable/disable controls

#### 3.2 Contextual Model Pickers
Eliminate global model selection in favor of context-specific pickers:

**Resume Operations:**
- Replace toolbar model picker with generation-specific sheets
- Include model picker + ResRef checkboxes in revision generation
- Retain last-used model as default for subsequent operations

**Cover Letter Operations:**
- Remove cover letter inspector view entirely
- Add generate/revise buttons to cover letter toolbar
- Create toolbar pane with model picker + CoverLetterRef management
- Include CoverLetterRef add/delete functionality

**Recommendation Operations:**
- Present model picker before job recommendation requests
- Present model picker before cover letter recommendation requests

**Image Operations:**
- Filter model pickers to show only vision-compatible models
- Apply to resume review overflow detection and other image-based operations

#### 3.3 Cover Letter Workflow Enhancement
Redesign cover letter management:
- Create `CoverLetterRefManagementView` component
- Include add/delete capabilities with context menus
- Integrate into both single and batch cover letter views
- Remove dependency on separate inspector interface

### Phase 4: Enhanced Features

#### 4.1 Local Cover Letter Selection
Replace global `selectedCoverLetter` with local chosen draft system:
- Add `isChosenSubmissionDraft: Bool` property to `CoverLetter` model
- Display ⭐️ indicator for chosen submission drafts
- Ensure only one draft per job application can be marked as chosen
- Update all cover letter pickers to show star indicators

#### 4.2 Tree Node Bulk Operations
Add efficiency improvements to tree node management:
- Add "All" / "None" buttons when parent nodes are expanded
- Enable bulk toggle of AI sparkle status for all child nodes
- Improve tree node interaction efficiency

#### 4.3 UI Polish and Clarity
Visual improvements for better user experience:
- Change recommend job button to medal.star system icon
- Ensure clear visual distinction between job and cover letter recommendation buttons
- Maintain consistent iconography throughout the application

### Phase 5: TTS Functionality Preservation

#### 5.1 Separate OpenAI Client for TTS
Maintain existing TTS capabilities:
- Keep dedicated OpenAI client specifically for TTS operations
- Use separate OpenAI API key exclusively for TTS functionality
- Isolate TTS operations from main LLM client architecture
- Preserve all existing TTS features and interfaces

---

## Implementation Strategy

### Critical Path Dependencies
1. **OpenRouter Service & Model Structures** → Foundation for all other changes
2. **Unified Client Factory** → Enables provider elimination  
3. **AppState Simplification** → Required for UI updates
4. **Provider Code Elimination** → Core architecture simplification
5. **UI Interface Updates** → User-facing improvements

### Parallel Development Tracks
- **TTS Preservation**: Independent of main migration, can be developed in parallel
- **UI Polish Items**: Low priority, can be implemented after core migration
- **Enhanced Features**: Can be added incrementally after successful core migration

### Testing Strategy
- Test OpenRouter API integration with sample models
- Verify structured output detection across different model types
- Validate image-compatible model filtering
- Ensure TTS functionality remains unaffected
- Test all contextual model picker workflows

### Migration Benefits

#### Architecture Simplification
- **75% reduction** in LLM client code complexity
- **Elimination** of provider-specific configuration management
- **Unified** model discovery and capability detection
- **Simplified** API key management interface

#### Enhanced User Experience  
- **Dynamic** model discovery with real-time capability filtering
- **Context-aware** model selection for specific operations
- **Improved** cover letter workflow with integrated reference management
- **Streamlined** settings interface with capability-based model browsing

#### Maintenance Benefits
- **Single** API integration point for all LLM operations
- **Reduced** configuration complexity and potential error points
- **Simplified** debugging and troubleshooting workflows
- **Future-proof** architecture leveraging OpenRouter's model aggregation

---

## Risk Mitigation

### API Compatibility
- OpenRouter's OpenAI-compatible interface ensures minimal changes to existing SwiftOpenAI usage
- Structured output support mapped directly from OpenRouter model metadata
- Fallback system prompts for models without native structured output support

### Feature Preservation
- All existing LLM functionality maintained through OpenRouter routing
- TTS operations isolated to prevent any impact from main migration
- Model selection preferences preserved through new selection system

### User Experience Continuity
- Contextual model pickers provide better UX than global selection
- Enhanced capability visibility improves model selection decisions
- Simplified configuration reduces user confusion and support burden

This migration represents a significant architecture improvement that will simplify maintenance, enhance user experience, and provide a more robust foundation for future LLM feature development.