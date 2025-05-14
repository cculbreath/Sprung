# AI Module Architecture

The AI module is organized into the following structure:

## Models

### Core
Foundational components that are used across the AI module:
- **CustomResponseDecoder.swift**: Decodes responses from various LLM APIs

### Clients
API client implementations for interacting with different LLM providers:
- **OpenAIClientProtocol.swift**: Interface for OpenAI API clients
- **MacPawOpenAIClient.swift**: Implementation for OpenAI API using MacPaw SDK
- **OpenAIClientFactory.swift**: Factory for creating appropriate client instances
- **SystemFingerprintFixClient.swift**: Client for handling fingerprint fixes

### Services
Core services that provide broad functionality used by multiple components:
- **ResumeReviewService.swift**: Coordinates resume review operations
- **ApplicationReviewService.swift**: Coordinates application review operations
- **ImageConversionService.swift**: Handles PDF to image conversion
- **PromptBuilderService.swift**: Builds structured prompts for LLMs
- **TreeNodeExtractor.swift**: Extracts and manipulates tree node data
- **LLMRequestService.swift**: Manages API requests to LLM providers
- **OpenAIModelFetcher.swift**: Retrieves OpenAI model information
- **GeminiModelFetcher.swift**: Retrieves Gemini model information

### Providers
Specialized interaction managers that use services to perform domain-specific tasks:
- **ResumeChatProvider.swift**: Manages resume-related chat interactions
- **CoverChatProvider.swift**: Manages cover letter-related chat interactions
- **JobRecommendationProvider.swift**: Provides job recommendations
- **CoverLetterRecommendationProvider.swift**: Provides cover letter recommendations

### ResponseTypes
Data structures for API responses:
- **APIResponses.swift**: Common API response structures
- **FixOverflowTypes.swift**: Response types for fixing text overflow

### Types
Domain models and type definitions:
- **AIModels.swift**: AI model definitions
- **ResumeReviewType.swift**: Types of resume reviews
- **ApplicationReviewType.swift**: Types of application reviews
- **ResumeQuery.swift**: Query structure for resume-related requests
- **ResumeUpdateNode.swift**: Node structure for resume updates

### Extensions
Extensions to existing types:
- **OpenAIModelExtension.swift**: Extensions for OpenAI models
- **StringModelExtension.swift**: Extensions for string handling

## Views
UI components for AI features:
- **ResumeReviewSheet.swift**: UI for resume reviews
- **ApplicationReviewSheet.swift**: UI for application reviews
- **AiCommsView.swift**: Communication view for AI interactions
- **AiFunctionView.swift**: Function-specific AI view
- **And other view components**