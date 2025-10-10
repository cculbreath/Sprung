================================================================================
                      LLM OPERATIONS ARCHITECTURE ANALYSIS
================================================================================
As of 6/11/2025 this document is somewhat out of date.

> **June 2025 refactor note:** The unified LLM surface now flows through `LLMFacade`
> exclusively. Legacy `LLMService.execute*` entry points have been removed in favor
> of `LLMClient` primitives plus three focused collaborators:
> `ConversationCoordinator`, `StreamingExecutor`, and `FlexibleJSONExecutor`.
> Update any new workflows to consume the facade APIs (`executeText`,
> `executeStructured`, `executeFlexibleJSON`, conversation streaming helpers) rather
> than calling the service directly.

OVERVIEW
--------

This document analyzes all LLM operations in the PhysCloudResume codebase to 
design a unified, clean architecture. The app has successfully completed Phase 4 
of migration to a unified OpenRouter-based system with complete LLM architecture unification.

**Phase 4 Migration Complete (June 5, 2025):**
- All LLM operations now use unified LLMService architecture
- ApplicationReviewService and ResumeReviewService migrated from LLMRequestService
- ApplicationReviewQuery and ResumeReviewQuery for centralized prompt management
- All services follow consistent model selection and LLMService integration patterns
- Legacy code dependencies cleaned up across the codebase
- Build success with unified architecture - migration fully complete


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

8. PROMPT-ENCOURAGED STRUCTED OUTPUT
	- For models that don't support json_object schema, we append extra prompt insturctions and generalized response parsing

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
│ Cover Letter Generation     │ CoverLetterService.swift                │ Multi-turn        │ x No     │ x No        │ Plain text              │ UnifiedToolbar "Cover Letter" button       │
│ Cover Letter Revision       │ CoverLetterService.swift                │ Multi-turn        │ x No     │ x No        │ Plain text              │ CoverLetterInspectorView (Revisions tab)   │
│ Best Letter Selection       │ BestCoverLetterService.swift            │ One-shot          │ * Yes    │ x No        │ BestCoverLetterResponse │ UnifiedToolbar "Best Letter" button        │
│ Multi-Model Letter Selection│ MultiModelCoverLetterService.runModelTasks │ Parallel one-shot │ * Yes    │ x No        │ BestCoverLetterResponse │ MultiModelChooseBestCoverLetterSheet:102    │
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
│ Text Request                │ LLMFacade.executeText    │ One-shot    │ x No     │ x No        │ Plain text    │ Via ModelSelectionSheet              │
│ Mixed Request               │ LLMFacade.executeTextWithImages │ One-shot │ x No  │ * Yes       │ Plain text    │ Via ModelSelectionSheet              │
│ Structured / Flexible JSON  │ LLMFacade.executeStructured / executeFlexibleJSON │ One-shot │ * Yes │ optional │ Configurable  │ Via ModelSelectionSheet              │
│ Conversation Streaming      │ LLMFacade.startConversationStreaming / continueConversationStreaming │ Multi-turn │ optional │ optional │ Plain text / JSON │ Via ModelSelectionSheet              │
└─────────────────────────────┴──────────────────────────┴─────────────┴──────────┴─────────────┴───────────────┴──────────────────────────────────────┘

### **Review Services**

```
┌─────────────────────────────┬─────────────────────────────────┬─────────────┬──────────┬─────────────┬─────────────────────┬───────────────────────────────────────┐
│ Operation                   │ File                            │ Context     │ Schema   │ Image Input │ Schema Type         │ ModelPicker Location                  │
├─────────────────────────────┼─────────────────────────────────┼─────────────┼──────────┼─────────────┼─────────────────────┼───────────────────────────────────────┤
│ Resume Review               │ ResumeReviewService.swift       │ One-shot    │ x No     │ * Yes       │ Plain text          │ ResumeReviewSheet:181 (Dropdown)      │
│ Application Review          │ ApplicationReviewService.swift  │ One-shot    │ x No     │ * Yes       │ Plain text          │ ApplicationReviewSheet:121 (Dropdown) │
└─────────────────────────────┴─────────────────────────────────┴─────────────┴──────────┴─────────────┴─────────────────────┴───────────────────────────────────────┘
```

### **Fix Overflow Operations (Image + Text → JSON)

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


 Unified Architecture


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
try await withThrowingTaskGroup(of: (String, Result<BestCoverLetterResponse, Error>).self) { group in
    for modelId in selectedModels {
        let prompt = modelPrompts[modelId]!
        group.addTask {
            do {
                let response = try await llm.executeFlexibleJSON(
                    prompt: prompt,
                    modelId: modelId,
                    as: BestCoverLetterResponse.self,
                    temperature: nil,
                    jsonSchema: CoverLetterQuery.getJSONSchema(for: selectedVotingScheme)
                )
                return (modelId, .success(response))
            } catch {
                return (modelId, .failure(error))
            }
        }
    }
    // process results incrementally…
}
```
- **Use Cases**: Multi-model cover letter selection, consensus-based decision making
- **Features**: 
  - Parallel execution via `TaskGroup` with per-model schema enforcement
  - Voting aggregation handled inside `MultiModelCoverLetterService`
  - Failures captured per model without aborting the overall workflow

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


## Current Operation Mapping to Unified Architecture

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
