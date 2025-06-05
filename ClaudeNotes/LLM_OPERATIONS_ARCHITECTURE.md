================================================================================
                      LLM OPERATIONS ARCHITECTURE ANALYSIS
================================================================================

OVERVIEW
--------

This document analyzes all LLM operations in the PhysCloudResume codebase to 
design a unified, clean architecture. The app has successfully completed Phase 2.2 
of migration to a unified OpenRouter-based system with clean ViewModel architecture.

**Phase 2.2 Highlights:**
- Clean ViewModel architecture with ResumeReviseViewModel and ClarifyingQuestionsViewModel
- Symmetric prompt architecture with all prompts centralized in ResumeQuery
- Enhanced node classes with encapsulated business logic
- Unified model selection component (ModelSelectionSheet)
- Removal of deprecated legacy code (AiCommsView, AiFunctionView, old Toolbar)


CURRENT LLM OPERATION TYPES
----------------------------

1. ONE-SHOT OPERATIONS (NO CONTEXT)
   - Simple request → response
   - No conversation history
   - Examples: Skill reordering, job recommendations, review analysis

2. MULTI-TURN CONVERSATIONS (WITH CONTEXT)
   - Maintains conversation history
   - Follow-up messages build on previous context
   - Examples: Resume chat, cover letter revision dialog

2b. ITERATIVE REVISION LOOPS (HUMAN-IN-THE-LOOP)
   - Multi-turn conversations with human feedback cycles
   - User reviews and approves/rejects individual AI suggestions
   - Only rejected revisions resubmitted to AI for refinement
   - State preservation across revision rounds
   - Examples: Resume revision workflow with ReviewView.swift

2a. PARALLEL MULTI-MODEL OPERATIONS
   - Multiple models evaluate the same input simultaneously
   - Results aggregated using voting systems (FPTP or Score Voting)
   - Examples: Multi-model cover letter selection

3. IMAGE + TEXT PROMPTS (MULTIMODAL)
   - Text prompt with attached images (PDF → image conversion)
   - Can be one-shot or multi-turn  
   - Can return text or structured JSON
   - Examples: Resume review with screenshot, fixOverflow analysis, visual layout analysis

4. ONE-SHOT WITH STRUCTURED OUTPUT
   - Single request with JSON schema response
   - No conversation context needed
   - Examples: Clarifying questions, best cover letter selection

5. MULTI-TURN WITH STRUCTURED OUTPUT
   - Conversation context + JSON schema response
   - Most complex operation type
   - Examples: Resume revision workflow

6. TEXT-TO-SPEECH STREAMING
   - Real-time audio generation and playback
   - Separate from LLM operations
   - Uses dedicated OpenAI TTS client

7. API OPERATIONS
   - Model discovery and management
   - API key validation
   - Service configuration

---

## Detailed Operation Inventory

### **Resume Operations**

```
┌─────────────────────────────┬──────────────────────────────┬─────────────┬──────────┬─────────────┬────────────────────────────┬──────────────────────────────────────┐
│ Operation                   │ File                         │ Context     │ Schema   │ Image Input │ Schema Type                │ ModelPicker Location                 │
├─────────────────────────────┼──────────────────────────────┼─────────────┼──────────┼─────────────┼────────────────────────────┼──────────────────────────────────────┤
│ Resume Revision Analysis    │ ResumeReviseViewModel.swift  │ Multi-turn  │ * Yes    │ x No        │ RevisionsContainer         │ UnifiedToolbar "Customize" button    │
│ Resume Chat                 │ ResumeChatProvider.swift     │ Multi-turn  │ x No     │ x No        │ Plain text                 │ UnifiedToolbar (DEPRECATED)          │
│ Clarifying Questions        │ ClarifyingQuestionsVM.swift  │ One-shot    │ * Yes    │ x No        │ ClarifyingQuestionsRequest │ UnifiedToolbar "Clarify & Customize" │
│ Skill Reordering            │ SkillReorderService.swift    │ One-shot    │ * Yes    │ x No        │ ReorderSkillsResponse      │ ResumeReviewSheet:181 (Dropdown)     │
└─────────────────────────────┴──────────────────────────────┴─────────────┴──────────┴─────────────┴────────────────────────────┴──────────────────────────────────────┘
```

### **Cover Letter Operations**

```
┌─────────────────────────────┬─────────────────────────────────────────┬───────────────────┬──────────┬─────────────┬─────────────────────────┬─────────────────────────────────────────────┐
│ Operation                   │ File                                    │ Context           │ Schema   │ Image Input │ Schema Type             │ ModelPicker Location                        │
├─────────────────────────────┼─────────────────────────────────────────┼───────────────────┼──────────┼─────────────┼─────────────────────────┼─────────────────────────────────────────────┤
│ Cover Letter Generation     │ CoverChatProvider.swift                 │ Multi-turn        │ x No     │ x No        │ Plain text              │ Cover Letter Chat UI (needs implementation) │
│ Cover Letter Revision       │ CoverChatProvider.swift                 │ Multi-turn        │ x No     │ x No        │ Plain text              │ Cover Letter Chat UI (needs implementation) │
│ Best Letter Selection       │ CoverLetterRecommendationProvider.swift │ One-shot          │ * Yes    │ x No        │ BestCoverLetterResponse │ MultiModelChooseBestCoverLetterSheet:102    │
│ Multi-Model Letter Selection│ CoverLetterRecommendationProvider.swift │ Parallel one-shot │ * Yes    │ x No        │ BestCoverLetterResponse │ MultiModelChooseBestCoverLetterSheet:102    │
│ Batch Generation            │ BatchCoverLetterGenerator.swift         │ Parallel one-shot │ x No     │ x No        │ Plain text              │ BatchCoverLetterView:85 (Checkbox)         │
└─────────────────────────────┴─────────────────────────────────────────┴───────────────────┴──────────┴─────────────┴─────────────────────────┴─────────────────────────────────────────────┘
```

### **Job Application Operations**

```
┌─────────────────────────────┬─────────────────────────────────┬─────────────┬──────────┬─────────────┬────────────────────┬──────────────────────────────────────┐
│ Operation                   │ File                            │ Context     │ Schema   │ Image Input │ Schema Type        │ ModelPicker Location                 │
├─────────────────────────────┼─────────────────────────────────┼─────────────┼──────────┼─────────────┼────────────────────┼──────────────────────────────────────┤
│ Job Recommendation          │ JobRecommendationService.swift  │ One-shot    │ * Yes    │ x No        │ JobRecommendation  │ RecommendJobButton (DropdownPicker)  │
└─────────────────────────────┴─────────────────────────────────┴─────────────┴──────────┴─────────────┴────────────────────┴──────────────────────────────────────┘
```

### **Generic LLM Services**

```
┌─────────────────────────────┬──────────────────────────┬─────────────┬──────────┬─────────────┬───────────────┬──────────────────────────────────────┐
│ Operation                   │ File                     │ Context     │ Schema   │ Image Input │ Schema Type   │ ModelPicker Location                 │
├─────────────────────────────┼──────────────────────────┼─────────────┼──────────┼─────────────┼───────────────┼──────────────────────────────────────┤
│ Text Request                │ LLMService.swift         │ One-shot    │ x No     │ x No        │ Plain text    │ Via ModelSelectionSheet              │
│ Mixed Request               │ LLMService.swift         │ One-shot    │ x No     │ * Yes       │ Plain text    │ Via ModelSelectionSheet              │
│ Structured Mixed            │ LLMService.swift         │ One-shot    │ * Yes    │ * Yes       │ Configurable  │ Via ModelSelectionSheet              │
│ Resume Conversation         │ LLMService.swift         │ Multi-turn  │ x No     │ x No        │ Plain text    │ Via ModelSelectionSheet              │
│ Cover Letter Conversation   │ LLMService.swift         │ Multi-turn  │ x No     │ x No        │ Plain text    │ Via ModelSelectionSheet              │
└─────────────────────────────┴──────────────────────────┴─────────────┴──────────┴─────────────┴───────────────┴──────────────────────────────────────┘

### **Review Services**

```
┌─────────────────────────────┬─────────────────────────────────┬─────────────┬──────────┬─────────────┬─────────────────────┬───────────────────────────────────────┐
│ Operation                   │ File                            │ Context     │ Schema   │ Image Input │ Schema Type         │ ModelPicker Location                  │
├─────────────────────────────┼─────────────────────────────────┼─────────────┼──────────┼─────────────┼─────────────────────┼───────────────────────────────────────┤
│ Resume Review               │ ResumeReviewService.swift       │ One-shot    │ x No     │ * Yes       │ Plain text          │ ResumeReviewSheet:181 (Dropdown)      │
│ Application Review          │ ApplicationReviewService.swift  │ One-shot    │ * Yes    │ * Yes       │ Application analysis│ ApplicationReviewSheet:121 (Dropdown) │
└─────────────────────────────┴─────────────────────────────────┴─────────────┴──────────┴─────────────┴─────────────────────┴───────────────────────────────────────┘
```

### **Fix Overflow Operations (Image + Text → JSON)**

```
┌─────────────────────────────┬───────────────────────────┬─────────────────┬──────────┬─────────────┬─────────────────────────┬───────────────────────────────────┐
│ Operation                   │ File                      │ Context         │ Schema   │ Image Input │ Schema Type             │ ModelPicker Location              │
├─────────────────────────────┼───────────────────────────┼─────────────────┼──────────┼─────────────┼─────────────────────────┼───────────────────────────────────┤
│ Fix Skills Overflow         │ ResumeReviewService.swift │ Multi-iteration │ * Yes    │ * Yes       │ FixFitsResponseContainer│ ResumeReviewSheet:181 (Dropdown)  │
│ Content Fit Analysis        │ ResumeReviewService.swift │ One-shot        │ * Yes    │ * Yes       │ ContentsFitResponse     │ ResumeReviewSheet:181 (Dropdown)  │
└─────────────────────────────┴───────────────────────────┴─────────────────┴──────────┴─────────────┴─────────────────────────┴───────────────────────────────────┘
```

### **TTS Operations**

```
┌─────────────────────────────┬─────────────────────────┬─────────────┬───────────────────┬─────────────┬───────────┬───────────────────────────────────────┐
│ Operation                   │ File                    │ Context     │ Structured Output │ Image Input │ Streaming │ ModelPicker Location                   │
├─────────────────────────────┼─────────────────────────┼─────────────┼───────────────────┼─────────────┼───────────┼───────────────────────────────────────┤
│ Text-to-Speech              │ OpenAITTSProvider.swift │ N/A         │ N/A               │ N/A         │ * Yes     │ TextToSpeechSettingsView:70 (Dropdown) │
│ Audio Streaming             │ TTSAudioStreamer.swift  │ N/A         │ N/A               │ N/A         │ * Yes     │ TextToSpeechSettingsView:70 (Dropdown) │
└─────────────────────────────┴─────────────────────────┴─────────────┴───────────────────┴─────────────┴───────────┴───────────────────────────────────────┘
```

---

## Model Selection and Management System

### **Model Picker Components**

The app provides two reusable model picker components:

#### **1. DropdownModelPicker** (`DropdownModelPicker.swift`)
- **Purpose**: Single model selection for operations requiring one model
- **Style**: Menu-style dropdown picker within a GroupBox
- **Usage Locations**:
  - `ClarifyingQuestionsModelSheet:46` - For clarifying questions workflow
  - `ResumeReviewSheet:181` - For resume review, skill reordering, and fix overflow operations
  - `ApplicationReviewSheet:121` - For application review operations  
  - `BatchCoverLetterView:130,213` - For revision model selection
  - `TextToSpeechSettingsView:70` - For TTS voice selection (OpenAI voices)

#### **2. CheckboxModelPicker** (`CheckboxModelPicker.swift`)
- **Purpose**: Multiple model selection for parallel/collaborative operations
- **Style**: Checkbox list with Select All/None buttons within a GroupBox
- **Usage Locations**:
  - `MultiModelChooseBestCoverLetterSheet:102` - For multi-model cover letter voting
  - `BatchCoverLetterView:85` - For selecting multiple models for batch generation

#### **3. ModelSelectionSheet** (`ModelSelectionSheet.swift`) **NEW in Phase 2.2** ✅
- **Purpose**: Unified single model selection component for all LLM operations
- **Style**: Sheet presentation with model filtering and selection
- **Usage Pattern**: Generic component that takes capability filter and returns selected model ID
- **Usage Locations**:
  - UnifiedToolbar buttons (Customize, Clarify & Customize)
  - All single-model LLM operations requiring model selection

### **Model Selection Storage and Persistence**

#### **Primary Storage**: `AppState.selectedOpenRouterModels`
- **Type**: `Set<String>` containing model IDs
- **Persistence**: Automatically saved to and loaded from UserDefaults
- **Purpose**: Global list of models enabled by the user across the entire app

#### **Model Selection UI**: `OpenRouterModelSelectionSheet`
- **Access**: Via "Select Models..." button in SettingsView
- **Features**:
  - Filter models by provider (OpenAI, Anthropic, etc.)
  - Filter by model capabilities (vision, structured output, reasoning, etc.)
  - Search functionality for finding specific models
  - Enable/disable models with checkboxes
  - Models grouped by provider for organization

#### **Available Models**: `OpenRouterService.availableModels`
- **Source**: Fetched from OpenRouter API and cached in UserDefaults
- **Type**: `[OpenRouterModel]` with capabilities and metadata
- **Refresh**: Manual refresh button in model pickers and automatic fetch on app launch

### **Model Filtering System**

Model pickers apply a **two-stage filtering process**:

#### **Stage 1: Global Filter** 
- Only models in `AppState.selectedOpenRouterModels` are shown
- This respects the user's global model selection from Settings

#### **Stage 2: Capability Filter**
- Further filters by operation-specific requirements:
  - **`.vision`**: Models supporting image input (e.g., Fix Overflow operations)
  - **`.structuredOutput`**: Models supporting JSON schema responses
  - **`.reasoning`**: Models with advanced reasoning capabilities
  - **`.textOnly`**: Text-only models (excludes vision models)

### **Model Capabilities**

Models have capability flags stored in `OpenRouterModel`:
- **`supportsImages`**: Can process image inputs (vision capability)
- **`supportsStructuredOutput`**: Can follow JSON schemas for responses
- **`supportsReasoning`**: Advanced reasoning models (like o1 series)
- **`isTextToText`**: Standard text generation models

### **Implementation Notes**

#### **Missing Model Pickers**
Several operations currently lack dedicated model pickers and need implementation:
- **Cover Letter Chat UI**: Needs DropdownModelPicker for cover letter generation/revision
- **UnifiedToolbar "Customize" button**: Needs DropdownModelPicker implementation (follows JobRecommendationButton pattern)

#### **TTS Voice Selection**
TTS operations use a different system:
- **Voices**: Predefined OpenAI TTS voices (alloy, echo, fable, nova, onyx, shimmer)
- **Selection**: Standard Picker in `TextToSpeechSettingsView:70`
- **Storage**: `@AppStorage("ttsVoice")` with default "nova"
- **Not OpenRouter**: Uses direct OpenAI TTS API, not routed through OpenRouter

#### **Model Persistence Across Operations**
- Most operations use `@AppStorage("preferredLLMModel")` to remember the last selected model
- This provides consistency across similar operations within a session
- Model selection is validated against available models on picker display

---

## Current Architecture Issues

### **1. Multiple Abstraction Layers**
- `AppLLMClientProtocol` (new unified interface)
- `BaseLLMProvider` (mid-level abstraction) 
- `LLMRequestService` (high-level service)
- Individual provider classes (`ResumeChatProvider`, `CoverChatProvider`, etc.)
- **Problem**: Redundant code, inconsistent interfaces

### **2. Mixed Client Management**
- OpenRouter clients for LLM operations
- Direct OpenAI clients for TTS
- Legacy service configurations
- **Problem**: Complex client lifecycle management

### **3. Conversation Context Complexity**
- Provider-level conversation history
- `ConversationContextManager` for persistence
- Message format conversions (`ChatMessage` ↔ `AppLLMMessage`)
- **Problem**: Context management scattered across multiple classes

### **4. Inconsistent Error Handling**
- Different error types across providers
- Model-specific fallback logic
- Manual JSON extraction for malformed responses
- **Problem**: Fragile error recovery

### **5. Model Capability Detection**
- Hardcoded model compatibility checks
- Special handling for o1 models (no system messages)
- Image model substitution logic
- **Problem**: Difficult to maintain as models change

---

## Proposed Unified Architecture

### **Core LLM Operation Types Needed**

Based on the analysis, we need **7 core operation types**:

#### **1. Simple Query (Text → Text)**
```swift
func execute(
    prompt: String,
    modelId: String
) async throws -> String
```
- **Use Cases**: Text-only requests, basic LLM operations
- **Features**: Simple text response

#### **2. Multimodal Query (Text + Image → Text)**
```swift
func executeWithImages(
    prompt: String,
    modelId: String,
    images: [Data]
) async throws -> String
```
- **Use Cases**: Resume review with image, visual analysis
- **Features**: Text response from image + text input

#### **3. Structured Query (Text → JSON)**
```swift
func executeStructured<T: Codable>(
    prompt: String,
    modelId: String,
    responseType: T.Type
) async throws -> T
```
- **Use Cases**: Clarifying questions, job recommendations, skill reordering
- **Features**: JSON schema validation, type-safe responses

#### **4. Multimodal Structured Query (Text + Image → JSON)**
```swift
func executeStructuredWithImages<T: Codable>(
    prompt: String,
    modelId: String,
    images: [Data],
    responseType: T.Type
) async throws -> T
```
- **Use Cases**: Fix overflow analysis, content fit analysis, visual layout analysis with structured output
- **Features**: JSON schema validation from multimodal input
- **Examples**: `FixFitsResponseContainer`, `ContentsFitResponse`

#### **5. Conversation Query (Context + Text → Text)**
```swift
func continueConversation(
    userMessage: String,
    modelId: String,
    conversationId: UUID
) async throws -> String
```
- **Use Cases**: Resume chat, cover letter revision
- **Features**: Automatic context management, conversation persistence

#### **6. Structured Conversation Query (Context + Text → JSON)**
```swift
func continueConversationStructured<T: Codable>(
    userMessage: String,
    modelId: String,
    conversationId: UUID,
    responseType: T.Type
) async throws -> T
```
- **Use Cases**: Resume revision workflow, multi-turn structured operations
- **Features**: Context + structured output combined

#### **6b. Iterative Revision Loop (Context + Feedback → JSON)**
```swift
func processRevisionFeedback<T: Codable>(
    feedbackNodes: [FeedbackNode],
    modelId: String,
    conversationId: UUID,
    responseType: T.Type
) async throws -> T
```
- **Use Cases**: Human-in-the-loop revision workflows
- **Features**: 
  - Selective resubmission of only rejected/commented revisions
  - Preserves conversation context across feedback cycles
  - Validates revisions against current document state
  - Supports rich user feedback types (accept, reject, edit, restore, etc.)
- **Implementation**: ReviewView.swift + AiCommsView.swift coordination

#### **7. Parallel Multi-Model Query (Text → Multiple JSON → Aggregated Result)**
```swift
func executeParallelStructured<T: Codable>(
    prompt: String,
    modelIds: [String],
    responseType: T.Type,
    votingScheme: VotingScheme = .firstPastThePost
) async throws -> MultiModelResult<T>
```
- **Use Cases**: Multi-model cover letter selection, consensus-based decision making
- **Features**: 
  - Parallel execution across multiple models using TaskGroup
  - Two voting schemes: First Past The Post (FPTP) and Score Voting (20 points)
  - Automatic result aggregation and vote tallying
  - Comprehensive analysis summary generation
  - Error handling for individual model failures

### **Additional Operations**

#### **8. TTS Operations** (Separate from LLM)
```swift
func generateSpeech(
    text: String,
    voice: String,
    onAudioChunk: @escaping (Data) -> Void
) async throws
```
- **Use Cases**: Text-to-speech functionality
- **Implementation**: Keep separate OpenAI TTS client

#### **9. Model Management**
```swift
func getAvailableModels() async throws -> [OpenRouterModel]
func validateModel(modelId: String, capability: ModelCapability) -> Bool
```
- **Use Cases**: Model discovery, capability checking

---

## Implementation Strategy

### **1. Unified Service Layer**
Create a single `LLMService` class that handles all operations:

```swift
@MainActor
class LLMService {
    // Core operations
    func execute(prompt: String, modelId: String, images: [Data] = []) async throws -> String
    func executeStructured<T: Codable>(prompt: String, modelId: String, responseType: T.Type, images: [Data] = []) async throws -> T
    
    // Conversation operations  
    func startConversation(systemPrompt: String, userMessage: String, modelId: String) async throws -> (conversationId: UUID, response: String)
    func continueConversation(userMessage: String, modelId: String, conversationId: UUID, images: [Data] = []) async throws -> String
    func continueConversationStructured<T: Codable>(userMessage: String, modelId: String, conversationId: UUID, responseType: T.Type, images: [Data] = []) async throws -> T
    
    // Multi-model operations
    func executeParallelStructured<T: Codable>(prompt: String, modelIds: [String], responseType: T.Type, votingScheme: VotingScheme) async throws -> MultiModelResult<T>
    
    // Model management
    func getAvailableModels() async throws -> [OpenRouterModel]
    func validateModel(modelId: String, capability: ModelCapability) -> Bool
}
```

### **2. Conversation Management**
Centralized conversation context handling:

```swift
class ConversationManager {
    private var conversations: [UUID: [AppLLMMessage]] = [:]
    
    func createConversation(systemPrompt: String, userMessage: String) -> UUID
    func addMessage(conversationId: UUID, message: AppLLMMessage)
    func getMessages(conversationId: UUID) -> [AppLLMMessage]
    func clearConversation(conversationId: UUID)
}
```

### **3. Model Capability System**
Dynamic capability detection:

```swift
enum ModelCapability {
    case structuredOutput
    case imageInput
    case longContext
}

class ModelCapabilityManager {
    func checkCapability(modelId: String, capability: ModelCapability) -> Bool
    func getCompatibleModels(for capability: ModelCapability) -> [String]
}
```

### **4. Migration Plan**

#### **✅ Phase 1: Create Core Services** (COMPLETED)
- **COMPLETED**: Implement `LLMService` class and `ResumeReviseViewModel` for clean separation
- **Key Dependencies**: 
  - `AppState.selectedOpenRouterModels` (already exists)
  - `OpenRouterService` (already exists)
  - `DropdownModelPicker` and `CheckboxModelPicker` (already exist)
- **Implementation Order** ✅:
  1. ✅ Create `LLMService.swift` with basic LLM operations
  2. ✅ Create `ResumeReviseViewModel.swift` for revision workflow business logic
  3. ✅ Implement `ConversationManager` for context handling
  4. ✅ Add `ModelCapabilityManager` for dynamic capability detection
  5. ✅ Implement core operations: `execute()`, `executeStructured()`, `continueConversation()`

#### **✅ Phase 2.1: Simple One-Shot Operations** (COMPLETED)
- **✅ Start With**: Simple one-shot operations (easier to test)
  - ✅ Job recommendations (`JobRecommendationService`)
  - ✅ Skill reordering (`SkillReorderService`)

#### **✅ Phase 2.2: Multi-Turn Operations & Architecture Cleanup** (COMPLETED)
- **✅ Multi-turn operations**:
  - ✅ Resume revisions (ResumeReviseViewModel)
  - ✅ Clarifying questions workflow (ClarifyingQuestionsViewModel)
- **✅ Architecture improvements**:
  - ✅ Enhanced node classes with business logic
  - ✅ Unified model selection (ModelSelectionSheet)
  - ✅ Clean ViewModel separation of concerns
  - ✅ Removal of deprecated legacy code

#### **⏳ Phase 2.3: Cover Letter Migration** (NEXT)
- **⏳ Cover letter operations**:
  - Cover letter generation (CoverChatProvider → LLMService)
  - Cover letter revision (CoverChatProvider → LLMService)
- **⏳ Complex workflows**:
  - Fix overflow (multimodal + iterative)
  - Multi-model voting systems

#### **Phase 3: Remaining UI Components**
- **⏳ UnifiedToolbar Integration**: 
  - **PARTIAL**: Model selection added to some buttons, need completion
  - ✅ ModelSelectionSheet unified component created
  - ⏳ Add model selection to remaining buttons
  - ⏳ Verify Cover Letter toolbar buttons are properly wired to LLM operations
- **⏳ Missing Model Pickers**: 
  - Cover Letter Chat UI
  - Complete RecommendJobButton integration 
- **⏳ Toolbar Button Audit**: 
  - Ensure ALL buttons that trigger LLM operations have model selection
  - Test that button actions are connected to actual LLM services

#### **Phase 4: Legacy Code Cleanup**
- **✅ COMPLETED Phase 2.2 Cleanup**:
  - ✅ Removed `AiCommsView` (legacy revision workflow UI)
  - ✅ Removed `AiFunctionView` (legacy wrapper)
  - ✅ Removed old `Toolbar.swift` (replaced by UnifiedToolbar)
  - ✅ Removed `ReviewView.swift` (renamed to RevisionReviewView)
- **⏳ Remaining Cleanup**:
  - Remove `LLMRequestService` redundancy
  - Remove `ResumeChatProvider` after migration complete
  - Clean up `BaseLLMProvider` if no longer needed

#### **Phase 5: Polish & Optimization**
- Add comprehensive error handling
- Add operation timeout management  
- Add request/response logging
- Add performance monitoring

---

## Benefits of Unified Architecture

1. **Single Responsibility**: Each operation type has one clear implementation
2. **Type Safety**: Structured responses are type-safe with compile-time checking
3. **Consistency**: All operations use the same error handling and timeout logic
4. **Maintainability**: Model capabilities managed in one place
5. **Provider Independence**: Clean abstraction allows easy migration from OpenRouter to other providers
6. **Performance**: Conversation context managed efficiently
7. **Scalability**: Easy to add new operation types or model capabilities

### **Provider Abstraction Layer**

The unified `LLMService` provides a **clean abstraction layer** that isolates OpenRouter implementation details:

**API Independence:**
- `LLMService` methods use generic parameters (modelId, prompt, responseType)
- No OpenRouter-specific types leak into business logic
- `OpenRouterService` is encapsulated within `LLMService` implementation

**Migration Path for Future Providers:**
- To switch from OpenRouter → Direct Provider APIs: Replace `OpenRouterService` implementation
- To switch to different aggregator: Swap out the underlying HTTP client
- Business logic (conversations, model selection, UI) remains unchanged
- Only the `LLMService` implementation needs modification

**Preserved Interfaces:**
- Model selection UI components work with any provider
- Conversation management is provider-agnostic  
- Structured output handling works with any JSON-capable API
- Error handling and retry logic applies universally

---

## Current Operation Mapping to New Architecture

```
┌────────────────────────────────────────────────────┬─────────────────────────────────────┬─────────────────────────┐
│ Current Operation                                  │ New Method                          │ Notes                   │
├────────────────────────────────────────────────────┼─────────────────────────────────────┼─────────────────────────┤
│ ResumeReviseViewModel.startRevisionWorkflow()      │ startConversation()                 │ Multi-turn text         │
│ ResumeReviseViewModel.processFeedbackAndRevise()   │ continueConversationStructured()    │ Multi-turn + schema     │
│ ClarifyingQuestionsViewModel.startWorkflow()       │ executeStructured()                 │ One-shot + schema       │
│ ClarifyingQuestionsViewModel.processAnswers()      │ continueConversationStructured()    │ Multi-turn + schema     │
│ CoverChatProvider.coverChatAction()                │ continueConversation()              │ Multi-turn text         │
│ CoverLetterRecommendationProvider.multiModelVote() │ executeStructured() (parallel)      │ Parallel one-shot+schema│
│ SkillReorderService.fetchReorderedSkills()         │ executeStructured()                 │ One-shot + schema       │
│ JobRecommendationService.fetchRecommendation()     │ executeStructured()                 │ One-shot + schema       │
│ LLMRequestService.sendTextRequest()                │ execute()                           │ One-shot text           │
│ LLMRequestService.sendMixedRequest()               │ executeWithImages()                 │ Text + image → text     │
│ LLMRequestService.sendStructuredMixedRequest()     │ executeStructuredWithImages()       │ Text + image → JSON     │
│ ResumeReviewService.sendFixFitsRequest()           │ executeStructuredWithImages()       │ Image analysis + JSON   │
│ ResumeReviewService.sendContentsFitRequest()       │ executeStructuredWithImages()       │ Image analysis + JSON   │
│ ResumeReviewService.sendReviewRequest()            │ executeWithImages()                 │ Image analysis + text   │
└────────────────────────────────────────────────────┴─────────────────────────────────────┴─────────────────────────┘
```

This unified architecture will eliminate redundancy, improve maintainability, and provide a clean foundation for future LLM operations.

---

## 🚨 CRITICAL IMPLEMENTATION GUIDANCE

### **Key Files to Study First**
- `DropdownModelPicker.swift` and `CheckboxModelPicker.swift` - Already implement the model selection patterns you need
- `OpenRouterService.swift` - Study the existing model capability detection and API integration
- `ResumeChatProvider.swift` - Complex example of conversation management and structured output
- `ReviewView.swift` + `AiCommsView.swift` - Shows the iterative revision loop pattern (extract business logic to ResumeReviseService)

### **New Service Architecture**
**LLMService**: Handles all basic LLM operations
- Text requests (one-shot and multi-turn)
- Structured output with JSON schemas
- Image + text multimodal requests
- Conversation context management
- Model capability detection and selection

**ResumeReviseService**: Handles complex revision workflow business logic
- Managing revision nodes and their state
- Processing feedback arrays and user selections  
- Coordinating with LLMService for AI resubmissions
- Applying changes to resume tree structure
- Validation and node ID matching
- State persistence across revision rounds

**UnifiedToolbar**: Direct workflow integration (replaces AiCommsView) ✅
- **"Customize" button**: ModelSelectionSheet → ResumeReviseViewModel.startRevisionWorkflow() → RevisionReviewView ✅
- **"Clarify & Customize" button**: ModelSelectionSheet → ClarifyingQuestionsViewModel → ResumeReviseViewModel workflow → RevisionReviewView ✅
- **Pattern**: UnifiedToolbar button → ModelSelectionSheet → LLM operation → RevisionReviewView (clean architecture achieved) ✅

### **Important Patterns to Preserve**
1. **Two-Stage Model Filtering**: Global user selection + operation-specific capabilities
2. **Conversation Context Management**: Must persist across UI state changes and provider resets
3. **Structured Output with Fallback**: Always have backup parsing for malformed JSON responses
4. **Progressive Enhancement**: Start with basic operations, add complexity incrementally

### **Critical Architecture Decisions**
- **@MainActor for LLMService**: All UI updates must happen on main thread
- **Conversation IDs**: Use UUID for unique conversation tracking across app lifecycle
- **Error Recovery**: Implement retry logic with exponential backoff for network failures
- **Model Capability Caching**: Cache capability checks to avoid repeated API calls

### **Known Gotchas to Avoid**
1. **o1 Model Handling**: These models don't support system messages - handle this in capability detection
2. **Image Model Substitution**: Some operations require vision models - implement automatic fallback
3. **Provider Reset Issues**: AiCommsView shows how to handle provider recreation without losing state
4. **Node ID Validation**: Resume tree nodes can be deleted between revision rounds - always validate

### **Implementation Strategy**
1. **Start Simple**: Begin with basic one-shot operations before complex multi-turn workflows
2. **Incremental Testing**: Test each operation manually through the UI as you implement
3. **Error Handling**: Test network failures, malformed responses, and model capability mismatches
4. **Model Integration**: Verify model picker integration and capability filtering works correctly

### **Performance Considerations**
- Use `TaskGroup` for parallel operations (see BatchCoverLetterGenerator example)
- Implement request deduplication for identical prompts
- Cache conversation context to avoid redundant API calls
- Monitor token usage and implement rate limiting if needed