# Architecture Analysis: Onboarding Module

**Analysis Date**: October 20, 2025
**Subdirectory**: `/Users/cculbreath/devlocal/codebase/Sprung/Sprung/Onboarding/`
**Total Swift Files Analyzed**: 17

## Executive Summary

The Onboarding module implements a sophisticated multi-phase conversational interview system for collecting applicant information, artifacts, and writing samples. The architecture demonstrates strong separation of concerns with a clear layered design: data models, services, and UI views. However, the module exhibits **moderate architectural complexity** that, while justified by the domain requirements, creates several maintenance and testability challenges. The primary concerns include: (1) deep dependency chains between services, (2) heavy reliance on JSON as an intermediate data format, (3) significant state management responsibilities concentrated in a single service, and (4) diffuse responsibility for validation logic across multiple services. The module is well-organized but would benefit from further abstraction of concerns, particularly around data transformation and validation pipelines.

## Overall Architecture Assessment

### Architectural Style

The Onboarding module employs a **Multi-Layered Service-Oriented Architecture** with the following characteristics:

1. **Data Layer**: SwiftData persistence (`OnboardingArtifactRecord`) with in-memory caching
2. **Service Layer**: Specialized services for specific concerns (extraction, validation, persistence, transformation)
3. **Presentation Layer**: SwiftUI views with Observable pattern state management
4. **Tool Execution Layer**: A command dispatcher for LLM-requested operations

The architecture follows a **reactive flow** where LLM responses are parsed, tool calls are executed, and state is persisted through a specialized store. This creates a sophisticated request-response loop that maintains conversation history and manages multiple data artifacts simultaneously.

### Strengths

- **Clear responsibility segregation**: Each service has a well-defined purpose (extraction, validation, summarization, etc.)
- **Persistent state management**: `OnboardingArtifactStore` effectively manages data serialization/deserialization to SwiftData
- **Type-safe protocols and enums**: Use of `OnboardingPhase` enum with comprehensive phase metadata prevents string-based errors
- **Explicit consent management**: Web search and writing analysis features respect user consent through explicit toggles
- **Structured extraction workflow**: Resume extraction surfaces uncertainties to users for review via `OnboardingPendingExtraction`
- **Comprehensive validation**: `SchemaValidator` ensures all persisted artifacts meet schema requirements
- **Async/await adoption**: Modern Swift concurrency patterns throughout
- **MainActor isolation**: Proper threading guarantees for UI-related services
- **Deduplication logic**: Smart duplicate detection for knowledge cards, fact ledger entries, and writing samples
- **Phase-based workflow**: `OnboardingPhase` enum provides structured progression through interview stages

### Concerns

- **Monolithic service**: `OnboardingInterviewService` (500 lines) handles multiple responsibilities: session lifecycle, message management, artifact persistence, tool coordination, and schema validation
- **Heavy JSON dependency**: Extensive use of SwiftyJSON throughout creates runtime type safety gaps and makes refactoring error-prone
- **Cascading imports**: Tool executor depends on 6+ external stores and services, making local testing difficult
- **Limited error recovery**: Errors are logged but not systematically categorized or handled with recovery strategies
- **Validation scattered**: Schema validation logic split between `OnboardingArtifactValidator`, `SchemaValidator`, and service-level checks
- **Unclear data flow**: Multiple services transform and persist JSON data; the transformation pipeline is implicit rather than explicit
- **Tool call duplication tracking**: `processedToolIdentifiers` Set prevents re-execution but is reset on service reset, creating potential re-execution bugs
- **Bidirectional dependencies**: `OnboardingToolExecutor` receives callbacks to update parent service state, creating circular dependencies
- **Incomplete test considerations**: No visible test seams or dependency injection abstractions for testing individual components

### Complexity Rating

**Rating**: **Medium-High**

**Justification**:

The module implements genuinely complex domain logic:
- Multi-phase state machine with contextual behavior (16 different expected outputs across 4 phases)
- Bidirectional data transformation (LLM response parsing, JSON merging, schema validation)
- Sophisticated extraction and summarization (PDF/text processing, NLP-based analysis)
- Concurrent tool execution with state persistence

However, complexity is **artificially elevated** by:
- Service coupling through callback chains rather than clear data flows
- JSON as the universal data representation (trades type safety for flexibility)
- Monolithic responsibility distribution in the interview service
- Lack of clear pipeline abstractions for data transformation
- Callback-based dependency injection instead of composition patterns

The complexity is ~70% justified by requirements, ~30% introduced by implementation choices.

## File-by-File Analysis

### OnboardingArtifactRecord.swift

**Purpose**: SwiftData persistent model for onboarding artifacts and conversation state
**Lines of Code**: ~47
**Dependencies**: SwiftData, Foundation
**Complexity**: Low

**Observations**:
- Well-structured @Model with appropriate @Attribute unique constraint on UUID
- Stores serialized Data blobs for all artifact types (applicant profile, defaults, knowledge cards, skill map, fact ledger, style profile, writing samples, conversation state)
- Simple data holder with no business logic
- Uses Data encoding for JSON serialization to support flexible schemas

**Recommendations**:
- Consider separating conversation state into its own model (`OnboardingConversationRecord`) to reduce coupling between interview state and artifact state
- Add computed properties to decode common JSON artifacts for convenience

### OnboardingArtifacts.swift

**Purpose**: In-memory representation of all onboarding artifacts and phase metadata
**Lines of Code**: ~95
**Dependencies**: SwiftyJSON, Foundation
**Complexity**: Low

**Observations**:
- Clear separation between data models (`OnboardingArtifacts` struct) and phase state (`OnboardingPhase` enum)
- `OnboardingPhase` excellently encodes all phase-specific metadata (displayName, focusSummary, expectedOutputs, interviewPrompts)
- `OnboardingMessage` and `OnboardingQuestion` are simple value types with clear responsibilities
- Uses JSON from SwiftyJSON library for flexible nested structures
- `OnboardingPhase.expectedOutputs` and `interviewPrompts` provide excellent documentation for LLM behavior

**Recommendations**:
- Extract phase metadata into a separate `OnboardingPhaseDefinition` struct to reduce enum size
- Consider creating typed structs for commonly-accessed JSON structures (e.g., `ApplicantProfileJSON`, `DefaultValuesJSON`) to reduce runtime errors

### ArtifactSummarizer.swift

**Purpose**: Summarizes uploaded artifacts (PDFs, documents) into knowledge card format
**Lines of Code**: ~60
**Dependencies**: Foundation, NaturalLanguage, SwiftyJSON
**Complexity**: Medium

**Observations**:
- Static enum pattern for utility functions (no mutable state)
- Uses NLTokenizer for basic NLP analysis
- Extracts metrics containing "$" and "%" patterns with regex
- Simple heuristic-based keyword extraction
- Combines filename, summary, skills, and metrics into JSON card structure

**Recommendations**:
- Extract keyword tokenization logic into a reusable `TextAnalyzer` utility
- Consider caching NLTokenizer instances to avoid repeated initialization
- Add fallback handling for documents with no extractable metrics
- Document regex patterns as constants with explanations

### LinkedInProfileExtractor.swift

**Purpose**: Extracts profile information from LinkedIn HTML via web scraping
**Lines of Code**: ~85
**Dependencies**: Foundation, SwiftSoup, SwiftyJSON
**Complexity**: Medium

**Observations**:
- Async/await based HTTP fetching with proper error handling
- SwiftSoup CSS selector parsing is fragile but pragmatic for web scraping
- Handles multiple CSS selector variations to account for LinkedIn layout changes
- Properly sets User-Agent header to avoid blocking
- Returns structured `Result` containing extraction and uncertainties
- Clear error types with localized descriptions

**Recommendations**:
- Extract CSS selectors into named constants for maintainability
- Add configuration for selector fallback chains
- Consider adding retry logic for transient failures
- Document which LinkedIn UI version selectors target
- Add rate limiting to respect LinkedIn's terms of service

### OnboardingArtifactStore.swift

**Purpose**: Persistence layer for onboarding artifacts using SwiftData
**Lines of Code**: ~293
**Dependencies**: Foundation, SwiftyJSON, SwiftData
**Complexity**: High

**Observations**:
- MainActor isolation ensures thread safety
- Implements caching of single `OnboardingArtifactRecord` to reduce frequent database fetches
- Comprehensive merge/append operations for various artifact types:
  - `mergeApplicantProfile` - shallow merge
  - `appendKnowledgeCards` - deduplication by lowercased title
  - `appendFactLedgerEntries` - deduplication by id/claim_id/statement/title
  - `saveWritingSamples` - merge or append with deduplication
- Intelligent deduplication logic prevents duplicate entries based on multiple key strategies
- JSON encoding/decoding is handled consistently through private helpers
- Recursive JSON merge logic for nested dictionaries

**Issues**:
- Heavy JSON manipulation creates runtime type safety gaps
- Deduplication logic is duplicated across multiple methods
- `normalizedIdentifier` attempts multiple fallback keys, indicating schema inconsistency
- `mergeJSON` is recursive and could hit stack limits with deeply nested structures
- No transaction semantics; `saveContext()` called after each operation

**Recommendations**:
- Extract deduplication strategy into a reusable `DuplicateDetector` protocol/struct
- Create typed wrappers for common JSON structures to reduce casting
- Consider batch operations to reduce `saveContext()` calls
- Add transaction support or batch operations for atomic multi-artifact updates
- Document schema expectations for each artifact type

### OnboardingArtifactValidator.swift

**Purpose**: Validates artifacts for schema compliance and timeline conflicts
**Lines of Code**: ~159
**Dependencies**: Foundation, SwiftyJSON
**Complexity**: Medium

**Observations**:
- `issues()` method aggregates validation from multiple schema validators
- `timelineConflicts()` implements sophisticated overlap detection for employment timelines
- Handles partial dates (year-only, year-month, full ISO dates)
- Returns detailed conflict information with start/end dates and suggested fixes
- Proper nil coalescing for missing timeline fields

**Issues**:
- Date parsing logic is duplicated (similar logic exists in OnboardingArtifactValidator and elsewhere)
- No validation for circular/self-overlapping intervals
- Conflict detection is O(n²), potentially expensive for large employment histories
- Error messages are constructed as strings, making localization difficult

**Recommendations**:
- Extract date parsing into a reusable `PartialDateParser` utility
- Add configuration for what constitutes a "conflict" (same day? hours overlap?)
- Consider using an interval tree for O(log n) overlap detection
- Create structured error types instead of string messages

### OnboardingInterviewService.swift

**Purpose**: Core service orchestrating the interview workflow, managing state, and coordinating tool execution
**Lines of Code**: ~500
**Dependencies**: Multiple (LLMFacade, stores, tool executor, validators)
**Complexity**: High

**Observations**:
- @MainActor @Observable manages session lifecycle and UI state
- Comprehensive state properties (messages, artifacts, phase, processing status, errors)
- Handles backend selection (OpenAI vs OpenRouter) with conversation persistence
- Resume/restart capability with saved OpenAI thread state
- Manages uploads through `OnboardingUploadRegistry`
- Lazy initialization of `OnboardingToolExecutor` with callback-based dependency injection
- Three consent toggles: web search, writing analysis, backend selection
- Phase transitions trigger control messages sent to LLM

**Issues**:
- **Monolithic responsibility**: Handles UI state, artifact management, tool coordination, error handling, and message buffering (too many reasons to change)
- **Callback-based dependency injection**: `OnboardingToolExecutor` is created with 7 closures for callbacks, creating tight coupling
- **Bidirectional dependencies**: Tool executor can call back to set `pendingExtraction`, forcing circular references
- **State duplication**: Maintains messages list separately from LLM response parsing
- **Implicit data flow**: The transformation from LLM response → parsed fields → artifact updates is complex and implicit
- **Tool identifier tracking**: Set-based deduplication can fail across reset cycles
- **Hard to test**: No dependency injection abstractions; everything is tightly coupled to concrete implementations
- **Long methods**: `startInterview` and `send` are complex with nested error handling

**Recommendations**:
- Split into smaller, focused services:
  - `OnboardingSessionManager` - lifecycle, phase management
  - `OnboardingMessageBuffer` - message history and state updates
  - `OnboardingToolCoordinator` - tool dispatch and result aggregation
- Create clear data flow types (`LLMResponseEvent`, `ArtifactUpdatePipeline`) instead of ad-hoc parsing
- Implement dependency injection protocol instead of callbacks
- Extract error handling into a dedicated `OnboardingErrorHandler` service
- Add deterministic tool call tracking independent of reset cycles

### OnboardingLLMResponseParser.swift

**Purpose**: Parses LLM JSON responses into structured `OnboardingLLMResponse` objects
**Lines of Code**: ~101
**Dependencies**: Foundation, SwiftyJSON
**Complexity**: Medium

**Observations**:
- Resilient JSON extraction handles both naked JSON and markdown-wrapped JSON
- Flexible field parsing with fallbacks (e.g., `assistant_reply` or `assistant_message`)
- Handles both array and single-object forms for delta_updates
- Creates `OnboardingQuestion` only if both id and question text are present
- Creates `OnboardingToolCall` with UUID fallback for missing id

**Issues**:
- **Permissive parsing**: Accepts multiple field name variations, indicating schema inconsistency upstream
- **Silent failures**: Silently drops tool calls/questions with missing required fields
- **Limited validation**: No validation that parsed response actually contains expected fields
- **Magic string keys**: Field names are strings without type safety
- **Fragile JSON extraction**: Regex-based extraction of JSON from markdown could fail with nested braces

**Recommendations**:
- Define a strict schema with required vs optional fields
- Log warnings for missing required fields instead of silently dropping them
- Create a formal response schema struct that validates on init
- Use SwiftJSON's decoding features more directly instead of field-by-field access
- Add test cases for malformed/unexpected responses

### OnboardingPendingExtraction.swift

**Purpose**: Holds pending resume extraction awaiting user confirmation
**Lines of Code**: ~7
**Dependencies**: SwiftyJSON
**Complexity**: Low

**Observations**:
- Simple value type holding raw extraction and uncertainties list
- Marked @unchecked Sendable for concurrency
- Used for the extraction review sheet modal

**Recommendations**:
- Consider richer type information instead of just `[String]` for uncertainties (e.g., enum cases for known uncertainty types)
- Add timestamp for tracking how long extraction has been pending

### OnboardingPromptBuilder.swift

**Purpose**: Constructs LLM system prompts and context messages
**Lines of Code**: ~130
**Dependencies**: Foundation, SwiftyJSON
**Complexity**: Medium

**Observations**:
- Well-structured prompt engineering with clear schema definition
- System prompt defines output JSON format explicitly
- Three message builders: `systemPrompt()`, `kickoffMessage()`, `resumeMessage()`
- Phase directives include focus, expected outputs, and interview prompts
- Incremental message building with optional sections based on artifact presence
- Clear documentation of JSON output schema in prompt

**Issues**:
- **Prompt size**: Messages can become very large when all artifacts are present (context bloat)
- **Embedding artifacts**: Raw JSON artifacts embedded in prompts rather than references (scalability issue)
- **Prompt fragility**: LLM behavior depends on exact prompt wording; difficult to A/B test variations
- **Duplicated structure**: Similar logic in `kickoffMessage` and `resumeMessage`
- **No prompt versioning**: No way to track which prompt version generated a response

**Recommendations**:
- Extract long sections into separate "instruction cards" to reduce message size
- Add artifact summaries instead of full JSON in prompts
- Create a `PromptVersion` struct to track which version generated responses
- Implement prompt templating to reduce duplication
- Add configuration for prompt variants (detail level, style, etc.)

### OnboardingToolExecutor.swift

**Purpose**: Executes tool calls requested by LLM, transforming between request/response formats
**Lines of Code**: ~436
**Dependencies**: Multiple (stores, extractors, analyzers, validators)
**Complexity**: High

**Observations**:
- Dispatches to 11 tool implementations (parse_resume, parse_linkedin, summarize_artifact, summarize_writing, web_lookup, persist_delta, persist_card, persist_skill_map, persist_facts_from_card, persist_style_profile, verify_conflicts)
- Tool execution is a large switch statement (typical command pattern)
- Handles bidirectional data transformation:
  - Input: JSON tool calls
  - Execution: Runs domain logic
  - Output: JSON results
- Applies patches to external stores (ApplicantProfileStore, ExperienceDefaultsStore)
- Callbacks to parent service for artifact refresh and extraction state
- Validates persisted data against schemas before storing

**Issues**:
- **Massive responsibility**: Handles extraction, transformation, validation, AND persistence
- **Callback dependency injection**: 7 closures passed to constructor create implicit dependencies
- **Tool dispatch is brittle**: Large switch with string keys; easy to add tools but no type safety
- **Implicit data flow**: Each tool has different patterns (some persist directly, some return results, some set pending state)
- **Social profile merging**: Complex logic in `mergeSocialProfiles` that belongs in a dedicated service
- **Weak reference risk**: `coverRefStore` is held weak; could be deallocated during async operations
- **Deduplication duplication**: Similar deduplication logic appears in multiple persistence methods
- **Hard to extend**: Adding new tools requires modifying this class and the parent service

**Recommendations**:
- Split into smaller focused executors:
  - `ExtractionToolExecutor` - parse_resume, parse_linkedin, summarize_artifact
  - `AnalysisToolExecutor` - summarize_writing, web_lookup, verify_conflicts
  - `PersistenceToolExecutor` - persist_* operations
- Create a `Tool` protocol with execute method for type-safe dispatch
- Extract social profile merging into `ApplicantProfileMerger` service
- Use Result type instead of throwing for tool execution
- Add logging/metrics for tool execution (latency, errors, etc.)

### OnboardingUploadRegistry.swift

**Purpose**: Manages temporary in-memory storage of uploaded files
**Lines of Code**: ~99
**Dependencies**: Foundation
**Complexity**: Low

**Observations**:
- Simple value holder without persistence
- Stores 4 upload kinds: resume, linkedInProfile, artifact, writingSample
- Methods return `OnboardingUploadedItem` which includes data or URL
- Provides accessors for data and URL retrieval
- Reset clears all uploads between sessions

**Issues**:
- **Memory management**: No size limits or cleanup for large uploads
- **Temporary storage**: Uploads are lost when service resets
- **No cleanup strategy**: Large binary data could accumulate if not properly reset

**Recommendations**:
- Add size limits with error handling for overly large files
- Implement automatic cleanup after tool execution
- Add timestamp to track upload staleness
- Consider using temporary disk storage for large uploads instead of memory

### ResumeRawExtractor.swift

**Purpose**: Extracts structured data from resume PDFs and text files
**Lines of Code**: ~148
**Dependencies**: Foundation, PDFKit, SwiftyJSON
**Complexity**: Medium

**Observations**:
- Handles both PDF and text file formats
- Falls back to raw text if PDF extraction fails
- Regex-based extraction for contact info (email, phone, website)
- Section-based extraction for education and experience
- Location detection via comma-separated pattern
- Simple heuristic for candidate name (first line if ≤6 words)

**Issues**:
- **Brittle regex**: Phone and website patterns may not match all valid formats
- **Fragile assumptions**: Name detection assumes first line ≤6 words (international names often longer)
- **Location detection**: Assumes city, state format in first 5 lines
- **Limited PDF support**: Relies on PDFKit which may struggle with complex layouts
- **No fallback extraction**: Single strategy for each field type
- **Section boundary detection**: Stops section parsing at hardcoded keywords (skills, summary, projects)

**Recommendations**:
- Create a `ResumeExtractor` protocol with multiple implementation strategies
- Add regex library with validated patterns for common fields
- Implement multiple extraction strategies and combine results
- Add confidence scores to extracted fields
- Consider ML-based extraction for better accuracy
- Add test fixtures with real resume examples

### SchemaValidator.swift

**Purpose**: Validates onboarding artifacts against schema requirements
**Lines of Code**: ~147
**Dependencies**: Foundation, SwiftyJSON
**Complexity**: Medium

**Observations**:
- Five validation methods for different artifact types
- Returns structured `ValidationResult` with error list
- Checks required fields in ApplicantProfile (name, email, phone, city, state)
- Validates collection fields have minimum entries
- Nested validation for education/employment entries
- Validates fact ledger structure and content
- Style profile requires style_vector and sample references

**Issues**:
- **Repeated validation patterns**: Similar null/empty checks repeated across methods
- **String-based error messages**: No structured error types
- **No localization**: Error messages are English-only
- **Magic strings**: Field names are hardcoded strings
- **Incomplete validation**: No checks for data type correctness or value ranges
- **Validation logic scattered**: Similar checks exist in OnboardingInterviewService and other places

**Recommendations**:
- Create a `ValidationSchema` protocol for defining schema rules
- Use a declarative validation library or DSL to reduce repetition
- Create structured `ValidationError` enum with localized descriptions
- Add type validation (not just null checks)
- Add value range validation (e.g., reasonable date ranges)
- Consolidate all validation logic into this single source of truth

### WebLookupService.swift

**Purpose**: Performs web searches via DuckDuckGo for artifact context
**Lines of Code**: ~67
**Dependencies**: Foundation, SwiftSoup, SwiftyJSON
**Complexity**: Medium

**Observations**:
- Async/await web scraping from DuckDuckGo HTML results
- Parses search results using SwiftSoup selectors
- Returns up to 5 results with title, link, and snippet
- Includes notice system for reporting issues (e.g., no results)
- Proper error handling with localized descriptions
- Sets User-Agent to avoid blocking

**Issues**:
- **Fragile scraping**: DuckDuckGo HTML structure changes break scraping
- **No rate limiting**: Could quickly hit rate limits with repeated searches
- **CSS selectors**: Hardcoded selectors will break if DuckDuckGo updates UI
- **Limited to 5 results**: No pagination support
- **No caching**: Identical searches run multiple times

**Recommendations**:
- Consider using a search API instead of HTML scraping (more stable)
- Add rate limiting with exponential backoff
- Implement simple caching of recent searches
- Add pagination support if needed
- Monitor selector changes and add fallbacks

### WritingSampleAnalyzer.swift

**Purpose**: Analyzes writing samples to extract style metrics and characteristics
**Lines of Code**: ~151
**Dependencies**: Foundation, PDFKit, SwiftyJSON
**Complexity**: Medium

**Observations**:
- Handles PDF and text files
- Calculates 5 style metrics:
  - Average sentence length
  - Active voice ratio (heuristic-based)
  - Quantitative density (numeric tokens per 100 words)
  - Tone inference (confident/cautious/neutral based on keyword presence)
  - Notable phrases (sentences with numbers or length >80 chars)
- Returns comprehensive analysis JSON

**Issues**:
- **Heuristic metrics**: Active voice detection is overly simplistic (looks for passive indicators followed by "by")
- **Limited tone detection**: Only 8 positive keywords and 6 negative keywords
- **No statistical rigor**: Metrics are rough approximations rather than linguistically validated
- **No context handling**: Ignores domain/context when analyzing writing
- **Fixed notable phrase criteria**: Hardcoded threshold of 80 chars for long sentences

**Recommendations**:
- Document that metrics are heuristic approximations, not linguistically rigorous
- Add confidence scores to each metric
- Expand keyword dictionaries for tone detection
- Consider using NaturalLanguage framework for more robust analysis
- Make thresholds configurable
- Add sentence complexity scoring
- Consider domain-specific analysis patterns

### OnboardingInterviewView.swift

**Purpose**: SwiftUI interface for the onboarding interview conversation and artifact management
**Lines of Code**: ~745
**Dependencies**: Multiple (SwiftUI, AppKit, UniformTypeIdentifiers, SwiftyJSON)
**Complexity**: High

**Observations**:
- Comprehensive UI with 5 main sections:
  1. Header with model/backend selection, phase picker, upload buttons
  2. Chat panel with message bubbles and input
  3. Artifact panel showing all collected data
  4. Extraction review sheet (modal)
  5. File import dialog integration
- Uses file import panel for resume/artifact/writing sample uploads
- Shows real-time artifact display as data is collected
- Supports phase switching with UI feedback
- Error handling with alert dialogs
- Auto-scrolling chat when new messages arrive

**Issues**:
- **Monolithic view**: 745 lines with 8 subviews defined locally
- **Tight coupling**: Directly accesses all service properties and methods
- **Complex state management**: Multiple @State properties with interrelated effects
- **UI/UX consistency**: Mixed patterns (toggles, buttons, selectors at different hierarchy levels)
- **JSON rendering**: Direct rendering of SwiftyJSON without type safety (possible crashes)
- **File handling**: Error handling relies on single-use modal for all errors
- **Artifact display**: Long scrollable list could perform poorly with hundreds of artifacts

**Recommendations**:
- Extract subviews into separate files
- Create a `OnboardingViewState` coordinator to manage complex state
- Use view composition instead of massive VStack hierarchies
- Add virtualization for long artifact lists
- Create typed wrappers for artifact display (e.g., `ArtifactDisplayModel`)
- Move file handling into a dedicated coordinator
- Implement proper accessibility labels
- Add loading state indicators for async operations

## Identified Issues

### Over-Abstraction

**Issue 1: Callback-Based Dependency Injection**
- **Location**: `OnboardingInterviewService` creates `OnboardingToolExecutor` with 7 closures
- **Problem**: Creates pseudo-dependency-injection pattern that is harder to understand than direct composition
- **Code**:
  ```swift
  private lazy var toolExecutor: OnboardingToolExecutor = makeToolExecutor()

  private func makeToolExecutor() -> OnboardingToolExecutor {
      OnboardingToolExecutor(
          artifactStore: artifactStore,
          applicantProfileStore: applicantProfileStore,
          experienceDefaultsStore: experienceDefaultsStore,
          coverRefStore: coverRefStore,
          uploadRegistry: uploadRegistry,
          artifactValidator: artifactValidator,
          allowWebSearch: { [weak self] in self?.allowWebSearch ?? false },
          allowWritingAnalysis: { [weak self] in self?.allowWritingAnalysis ?? false },
          refreshArtifacts: { [weak self] in self?.refreshArtifacts() },
          setPendingExtraction: { [weak self] extraction in self?.pendingExtraction = extraction }
      )
  }
  ```
- **Impact**: Makes testing difficult, obscures actual dependencies, creates bidirectional coupling

### Unnecessary Complexity

**Issue 1: JSON Everywhere**
- **Location**: Throughout the codebase (OnboardingArtifacts, OnboardingArtifactStore, OnboardingToolExecutor)
- **Problem**: Uses JSON as universal intermediate format, sacrificing type safety for flexibility
- **Example**: `onboardingArtifacts.skillMap` is `JSON?` with no compile-time guarantees of structure
- **Impact**: Runtime errors possible, refactoring is error-prone, IDE support is limited

**Issue 2: Implicit Data Transformation Pipeline**
- **Location**: `OnboardingInterviewService.handleLLMResponse()` (lines 364-411)
- **Problem**: Complex multi-step transformation from LLM response string → parsed JSON → multiple artifact updates, but no explicit pipeline representation
- **Code Flow**:
  1. Parse response (OnboardingLLMResponseParser)
  2. Apply delta updates (OnboardingToolExecutor.applyDeltaUpdates)
  3. Append knowledge cards (artifactStore.appendKnowledgeCards)
  4. Execute tool calls (processToolCalls)
  5. Update UI state (refreshArtifacts, nextQuestions)
- **Impact**: Hard to understand, test, or modify the transformation sequence

**Issue 3: Validation Logic Scattered**
- **Location**: `OnboardingArtifactValidator`, `SchemaValidator`, `OnboardingInterviewService.issues()`
- **Problem**: Same validation concepts implemented in multiple places with different approaches
- **Example**: Timeline validation in `OnboardingArtifactValidator` vs schema validation in `SchemaValidator`
- **Impact**: Maintenance burden, risk of inconsistency, hard to understand complete validation picture

### Design Pattern Misuse

**Issue 1: Tool Executor as God Object**
- **Location**: `OnboardingToolExecutor` (436 lines)
- **Problem**: Implements command pattern but also handles data transformation, validation, and cross-store synchronization
- **Impact**: Single class with too many reasons to change, difficult to unit test individual tool implementations

**Issue 2: Service as Observable State Container**
- **Location**: `OnboardingInterviewService` marked @Observable
- **Problem**: Service is used both for orchestration and as a UI state container, conflating two concerns
- **Impact**: Service becomes tightly coupled to UI, cannot be used in other contexts without UI framework

**Issue 3: Callbacks Instead of Proper Dependency Injection**
- **Location**: `OnboardingToolExecutor` initialization
- **Problem**: Uses closures for dependency injection instead of protocols or direct injection
- **Impact**: Harder to reason about, harder to test, implicit bidirectional dependencies

## Recommended Refactoring Approaches

### Approach 1: Extract Data Transformation Pipeline (Effort: Medium, Impact: High)

**Goal**: Make implicit data transformation explicit and testable

**Steps**:

1. **Create Pipeline Protocol**:
   ```swift
   protocol OnboardingTransformationStep {
       func transform(_ input: OnboardingPipelineContext) async throws
   }

   struct OnboardingPipelineContext {
       let parsedResponse: OnboardingLLMResponse
       let uploadRegistry: OnboardingUploadRegistry
       var deltaUpdates: [JSON] = []
       var toolResults: [JSON] = []
       var errors: [Error] = []
   }
   ```

2. **Create Concrete Steps**:
   - `DeltaUpdateStep` - applies schema patches
   - `ToolExecutionStep` - dispatches and executes tools
   - `ArtifactPersistenceStep` - persists results to store
   - `StateRefreshStep` - updates UI state

3. **Implement Pipeline Orchestrator**:
   ```swift
   class OnboardingTransformationPipeline {
       let steps: [OnboardingTransformationStep]

       func execute(_ context: OnboardingPipelineContext) async throws -> OnboardingPipelineContext {
           var context = context
           for step in steps {
               try await step.transform(&context)
           }
           return context
       }
   }
   ```

4. **Refactor OnboardingInterviewService**:
   - Remove inline transformation logic
   - Use pipeline in `handleLLMResponse()`
   - Pipeline handles all state mutations

**Benefits**:
- Each transformation step is independently testable
- Easy to reorder or add new steps
- Clear data flow
- Better error handling with context

### Approach 2: Extract Tool Execution System (Effort: Medium, Impact: High)

**Goal**: Separate tool dispatch from tool implementation, improve extensibility

**Steps**:

1. **Define Tool Protocol**:
   ```swift
   protocol OnboardingTool: AnyObject {
       associatedtype Input: Decodable
       associatedtype Output: Encodable

       var name: String { get }
       func execute(_ input: Input) async throws -> Output
   }
   ```

2. **Implement Tool Registry**:
   ```swift
   class OnboardingToolRegistry {
       private var tools: [String: AnyOnboardingTool] = [:]

       func register<T: OnboardingTool>(_ tool: T) {
           tools[tool.name] = tool
       }

       func execute(name: String, arguments: JSON) async throws -> JSON {
           guard let tool = tools[name] else {
               throw OnboardingError.unsupportedTool(name)
           }
           return try await tool.execute(arguments)
       }
   }
   ```

3. **Create Concrete Tools**:
   ```swift
   class ParseResumeTool: OnboardingTool {
       typealias Input = ResumeParseRequest
       typealias Output = ResumeParseResult

       let uploadRegistry: OnboardingUploadRegistry

       func execute(_ input: Input) async throws -> Output {
           // Implementation
       }
   }
   ```

4. **Refactor Tool Executor**:
   - Becomes thin wrapper around registry
   - Handles JSON serialization/deserialization
   - Each tool is independently testable

**Benefits**:
- Tools are independently testable
- Easy to add new tools
- Tool implementations are self-contained
- Tool registry can be swapped for testing

### Approach 3: Create Typed Schema Layer (Effort: High, Impact: Medium)

**Goal**: Add compile-time type safety without losing flexibility

**Steps**:

1. **Define Artifact Schemas**:
   ```swift
   struct ApplicantProfileSchema: Codable {
       let name: String
       let email: String
       let phone: String
       let city: String
       let state: String
       // ... other fields
   }

   struct DefaultValuesSchema: Codable {
       let education: [EducationEntry]
       let employment: [EmploymentEntry]
   }
   ```

2. **Create Schema Codec**:
   ```swift
   class OnboardingSchemaCodec {
       func encodeProfile(_ profile: ApplicantProfileSchema) throws -> JSON
       func decodeProfile(from: JSON) throws -> ApplicantProfileSchema
       func mergeProfile(_ base: ApplicantProfileSchema, _ patch: JSON) throws -> ApplicantProfileSchema
   }
   ```

3. **Refactor Store**:
   - Use codable types internally
   - Convert to/from JSON only at boundaries
   - Type-safe artifact access

**Benefits**:
- Compile-time type checking
- IDE autocomplete for artifact fields
- Self-documenting schemas
- Easier refactoring

**Tradeoffs**:
- More code upfront
- Less flexible for schema evolution
- Still need JSON at boundaries for LLM responses

### Approach 4: Split OnboardingInterviewService (Effort: High, Impact: High)

**Goal**: Break monolithic service into focused responsibilities

**Steps**:

1. **Create Session Manager**:
   ```swift
   @MainActor
   class OnboardingSessionManager {
       var conversationId: UUID?
       var modelId: String?
       var backend: LLMFacade.Backend

       func startSession(modelId: String, backend: LLMFacade.Backend) async throws
       func resetSession()
   }
   ```

2. **Create Message Buffer**:
   ```swift
   @MainActor
   class OnboardingMessageBuffer {
       var messages: [OnboardingMessage] = []
       var nextQuestions: [OnboardingQuestion] = []

       func appendMessage(_ message: OnboardingMessage)
       func appendQuestions(_ questions: [OnboardingQuestion])
       func clear()
   }
   ```

3. **Create Phase Manager**:
   ```swift
   @MainActor
   class OnboardingPhaseManager {
       var currentPhase: OnboardingPhase = .resumeIntake

       func transitionToPhase(_ phase: OnboardingPhase, context: LLMContext) async throws
   }
   ```

4. **Create Tool Coordinator**:
   ```swift
   @MainActor
   class OnboardingToolCoordinator {
       func executeTools(_ calls: [OnboardingToolCall]) async throws -> [JSON]
   }
   ```

5. **New Orchestrator** (minimal):
   ```swift
   @MainActor @Observable
   class OnboardingInterviewService {
       let sessionManager: OnboardingSessionManager
       let messageBuffer: OnboardingMessageBuffer
       let phaseManager: OnboardingPhaseManager
       let toolCoordinator: OnboardingToolCoordinator
       // ...delegates to specialized services
   }
   ```

**Benefits**:
- Each service has single responsibility
- Easier to test each component
- Easier to reuse components in different contexts
- Clearer dependencies

## Simpler Alternative Architectures

### Alternative 1: Simplified Event-Driven Architecture

**Overview**: Instead of complex service orchestration, use a simpler event stream:

```swift
enum OnboardingEvent {
    case responseReceived(String)
    case toolExecuted(String, JSON)
    case artifactUpdated(ArtifactType, JSON)
    case phaseChanged(OnboardingPhase)
}

class OnboardingEventProcessor {
    func processEvent(_ event: OnboardingEvent) async throws {
        // Simple pattern matching
        switch event {
        case .responseReceived(let text):
            try await handleResponse(text)
        case .toolExecuted(let tool, let result):
            try await handleToolResult(tool, result)
        // ...
        }
    }
}
```

**Pros**:
- Simpler data flow
- Easier to add logging/analytics
- Natural fit for UI reactions
- Testable with event recording

**Cons**:
- Event sequence dependencies are implicit
- Harder to ensure ordered processing
- Debugging event chains is complex
- State mutations spread across handlers

### Alternative 2: Lightweight Functional Pipeline

**Overview**: Treat interview processing as a pure functional pipeline:

```swift
typealias InterviewState = (
    artifacts: OnboardingArtifacts,
    messages: [OnboardingMessage],
    phase: OnboardingPhase
)

func processLLMResponse(
    _ response: String,
    state: InterviewState,
    store: OnboardingArtifactStore
) async throws -> InterviewState {
    let parsed = try OnboardingLLMResponseParser.parse(response)
    let updatedState = try applyDeltaUpdates(parsed.deltaUpdates, to: state)
    let toolState = try await executeTools(parsed.toolCalls, state: updatedState)
    return addMessages(parsed.assistantReply, to: toolState)
}
```

**Pros**:
- Pure functions are easily testable
- State mutations are explicit
- Time-travel debugging possible
- Composition and chaining are natural

**Cons**:
- Awkward with side effects (persistence, UI)
- State parameter passing is verbose
- Less convenient with SwiftUI Observable pattern
- Doesn't fit SwiftUI reactivity as naturally

## Conclusion

The Onboarding module implements genuinely complex domain logic with reasonable architectural choices. The module successfully manages a sophisticated multi-phase interview flow with extraction, validation, and persistence. However, the implementation introduces additional complexity through:

1. **Service coupling via callbacks** rather than clear composition patterns
2. **JSON as universal representation** trading type safety for flexibility
3. **Monolithic responsibilities** concentrated in two large services
4. **Implicit data transformation pipelines** that are hard to understand and test
5. **Scattered validation logic** across multiple services

### Priority Recommendations

**High Priority** (Do first - unblocks other improvements):
1. **Extract Typed Schema Layer** - Create Codable wrappers for common artifacts to reduce JSON everywhere
2. **Create Tool Registry** - Refactor tool dispatch to use protocol-based registration instead of switch statement
3. **Consolidate Validation** - Move all validation logic into SchemaValidator with structured error types

**Medium Priority** (Improves maintainability):
4. **Extract Data Transformation Pipeline** - Make implicit flow explicit with transformation steps
5. **Split Interview Service** - Separate session management, message buffering, and tool coordination into focused services
6. **Replace Callbacks with Protocols** - Use dependency injection protocols instead of closure callbacks

**Low Priority** (Nice to have, lower ROI):
7. **Create Tool Protocol** - Already covered under Tool Registry
8. **Add Configuration Layer** - Allow tweaking thresholds, selectors, patterns from config
9. **Extract NLP Utilities** - Move text analysis into reusable components

### Success Metrics

After refactoring, target these improvements:
- **Testability**: Each service should be testable with <3 mock dependencies
- **Coupling**: No circular dependencies between services
- **Clarity**: Data transformation flow should be clear in a single method/function
- **Type Safety**: Minimize JSON string-based field access to <10% of codebase
- **Maintainability**: Average method size should decrease from ~50 lines to ~25 lines

The module has a solid foundation and clear business logic. The recommended refactorings maintain the existing strengths while reducing incidental complexity and improving testability.
