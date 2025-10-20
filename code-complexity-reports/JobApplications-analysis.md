# Architecture Analysis: JobApplications Module

**Analysis Date**: October 20, 2025
**Module Path**: `Sprung/Sprung/JobApplications/`
**Total Swift Files Analyzed**: 26
**Total Lines of Code**: 5,198

## Executive Summary

The JobApplications module demonstrates a **well-organized, multi-layered architecture** with clear separation of concerns across Models, Utilities, Views, and AI Services. The module is designed to track job applications with support for web scraping, AI-powered reviews, and multi-step workflows.

**Key Findings**:
- **Strong architectural discipline** with appropriate use of service patterns and dependency injection
- **Moderate complexity justified by requirements** - the module handles intricate web scraping, multi-turn LLM conversations, and complex UI workflows
- **Well-designed web scraping strategy** with fallback mechanisms and anti-blocking measures (Cloudflare handling)
- **Main concern**: The LinkedInJobScrape.swift file exhibits high complexity (646 lines) due to sophisticated WebView state management and multi-step navigation logic
- **Opportunity**: Some view composition could be simplified to improve maintainability

## Overall Architecture Assessment

### Architectural Style

The JobApplications module employs a **layered architecture** with distinct responsibilities:

```
┌─────────────────────────────────────────────┐
│         Views Layer (UI Components)         │
├─────────────────────────────────────────────┤
│      Services Layer (Business Logic)        │
│  - ApplicationReviewService                 │
│  - JobRecommendationService                │
│  - ClarifyingQuestionsViewModel             │
├─────────────────────────────────────────────┤
│       Utilities Layer (Infrastructure)      │
│  - CloudflareCookieManager                  │
│  - HTMLFetcher / WebViewHTMLFetcher        │
├─────────────────────────────────────────────┤
│      Models Layer (Data & Domain Logic)     │
│  - JobApp (SwiftData @Model)               │
│  - Parsing Extensions (Apple/Indeed/LinkedIn)│
└─────────────────────────────────────────────┘
```

**Key Architectural Patterns**:
- **Service-Oriented**: ApplicationReviewService and JobRecommendationService encapsulate business logic
- **Extension-Based Parsing**: JobApp extensions handle domain-specific parsing (AppleJobScrape, IndeedJobScrape, LinkedInJobScrape)
- **Observable State Management**: @Observable classes (JobAppForm, ClarifyingQuestionsViewModel) handle UI state
- **Dependency Injection**: Services receive dependencies (LLMFacade, ResumeExportCoordinator) via initializers
- **Async/Await Concurrency**: Modern Swift concurrency patterns throughout

### Strengths

- **Clean Separation of Concerns**: Models, Utilities, Views, and Services occupy distinct layers with minimal cross-layer coupling
- **Robust Web Scraping Strategy**: Multiple fallback mechanisms (JSON-LD parsing, HTML scraping, WebView fallback) ensure reliability across platform changes
- **Comprehensive Error Handling**: Specific error types (CloudflareChallengeError, URLError categories) with appropriate recovery strategies
- **Concurrency Best Practices**: Proper use of @MainActor, async/await, and continuation-based patterns for WebView operations
- **Testability**: Service layer abstractions (LLMFacade parameter injection) enable dependency injection for testing
- **Intelligent Cookie Management**: Cloudflare cookie persistence reduces redundant challenge completions
- **Multi-turn Conversation Support**: ClarifyingQuestionsViewModel demonstrates sophisticated conversation handoff between ViewModels
- **Type Safety**: Strong use of Swift types (Statuses enum, custom error types) rather than string-based states

### Concerns

1. **LinkedInJobScrape.swift Complexity (High)**
   - 646 lines with deeply nested async/await logic
   - Complex state management (hasResumed flag, navigationStep tracking)
   - Multiple timeout mechanisms with overlapping concerns
   - Debug window visibility logic interleaved with core scraping

2. **WebView Lifecycle Management (Moderate)**
   - Manual WebView cleanup with associated object retention patterns
   - Multiple continuation and deinit cleanup paths create potential for memory leaks
   - Associated keys pattern (ObjectiveC) reduces type safety

3. **View Composition Fragmentation (Moderate)**
   - Multiple small view files (JobAppHeaderView, JobAppInfoSectionView, etc.) create cognitive load
   - Could benefit from component composition patterns to reduce file proliferation

4. **ApplicationReviewSheet Initialization (Low)**
   - Model selection state initialized as empty string, creating implicit dependencies
   - selectedModel binding not explicitly initialized

5. **CSS/HTML Selector Brittleness (Low)**
   - LinkedIn extraction uses 16 different CSS selectors as fallbacks
   - Indicates the UI changes frequently; maintainability concern for future changes

## File-by-File Analysis

### Models/JobApp.swift

**Purpose**: Core data model for job applications using SwiftData persistence
**Lines of Code**: 252
**Dependencies**: SwiftData, Foundation
**Complexity**: Low-Medium

**Observations**:
- Well-designed composite property `selectedRes` handles optional resume selection with fallback logic
- `resumeDeletePrep()` implements careful state management to prevent dangling selections
- Model implements Equatable, Hashable, and Decodable for flexibility
- JobApp.jobListingString computed property provides readable text representation
- Clear separation between persistence attributes (@Attribute) and computed properties
- Legacy spelling (`abandonned`) maintained for backward compatibility with existing data

**Recommendations**:
- Consider extracting resume/cover letter selection logic into a dedicated protocol (ResumesContainer)
- The replaceUUIDsWithLetterNames() method belongs in an extension focused on text transformation

---

### Models/JobApp+Color.swift

**Purpose**: UI-specific color mapping for status indicators
**Lines of Code**: 44
**Dependencies**: SwiftUI
**Complexity**: Low

**Observations**:
- Correctly separates UI concerns from core model
- Handles backward compatibility for "abandoned" vs legacy "abandonned"
- Case-insensitive string matching provides robustness
- Clear default fallback to black for unknown statuses

**Recommendations**:
- Well-structured; no significant issues

---

### Models/JobAppForm.swift

**Purpose**: Observable form state for job application editing
**Lines of Code**: 41
**Dependencies**: SwiftData
**Complexity**: Low

**Observations**:
- Simple Observable container with 12 properties
- populateFormFromObj() provides one-way binding to JobApp
- No complex logic or state transitions

**Recommendations**:
- This could be simplified using property projections or a more generic approach
- Consider whether JobApp itself could use @Observable for simpler UI binding

---

### Models/AppleJobScrape.swift

**Purpose**: Parse Apple careers website job listings
**Lines of Code**: 139
**Dependencies**: SwiftSoup, Foundation
**Complexity**: Medium

**Observations**:
- Dual parsing strategy: JSON-LD extraction first (more reliable) with HTML fallback
- Handles location data from complex nested structure gracefully
- Comprehensive description assembly from multiple fields
- HTML entity decoding applied appropriately

**Recommendations**:
- The extensive field extraction could be extracted into a private struct to reduce visual complexity
- Consider a JSONDecoder-based approach if Apple ever publishes their API structure

---

### Models/IndeedJobScrape.swift

**Purpose**: Parse Indeed job postings using JSON-LD schema and fallback mechanisms
**Lines of Code**: 287
**Dependencies**: SwiftSoup, Foundation
**Complexity**: Medium-High

**Observations**:
- Excellent strategy: primary JSON-LD parsing (most stable), fallback to EmbeddedData, fallback to Mosaic provider
- Handles array/single object polymorphism correctly in jobPostingDictionary()
- Duplicate detection prevents importing the same job twice
- Comprehensive address extraction handles all components (locality, region, country)
- The nested helper functions improve readability within parsing logic

**Recommendations**:
- The three parsing fallback paths (JSON-LD, EmbeddedData, Mosaic) are well-structured but could be clearer with extraction into separate methods
- Debug file writing for failed parses is helpful; consider making this configurable per site

---

### Models/LinkedInJobScrape.swift

**Purpose**: Extract LinkedIn job details using authenticated WebView and complex navigation
**Lines of Code**: 647
**Dependencies**: WebKit, ObjectiveC, SwiftSoup, Foundation
**Complexity**: High

**Observations**:
- **LinkedInSessionManager**: Manages session cookies and clearance
- **Complex Multi-Step Navigation**:
  - Step 0: Load LinkedIn feed to establish session
  - Step 1: Navigate to job page
  - Step 2: Extract HTML
- **Sophisticated Timeout Management**:
  - Debug window reveals after 10 seconds
  - Fallback polling with 0.5-second intervals
  - Ultimate 60-second timeout with graceful degradation
- **Advanced State Tracking**:
  - hasResumed flag prevents duplicate completions
  - navigationStep tracks current loading stage
  - Manual lifecycle management with associated objects

**Recommendations**:
- **HIGH PRIORITY**: Extract the timeout/fallback polling logic into a separate helper type (LinkedInPageLoader or similar)
- **HIGH PRIORITY**: The 646-line file should be split into:
  - LinkedInSessionManager (currently nested)
  - LinkedInJobExtractor (extraction logic)
  - LinkedInJobScrapeDelegate (delegation logic)
- Consider using a state machine pattern instead of navigationStep integer
- The debug window visibility logic could be extracted to a separate concern
- Memory management with associated objects is fragile; consider using a WeakBox pattern

**Critical Issue**: The deeply nested `loadJobPageHTML()` function (207 lines, lines 134-341) contains multiple callback chains and timeout handling that would benefit greatly from refactoring.

---

### Utilities/CloudflareCookieManager.swift

**Purpose**: Cache and refresh Cloudflare clearance cookies to bypass challenge pages
**Lines of Code**: 173
**Dependencies**: WebKit, Foundation
**Complexity**: Medium

**Observations**:
- Persistent cookie storage using PropertyListSerialization
- Polling mechanism waits up to 20 seconds for cookie to appear
- Proper resource cleanup with self-retain pattern for async callbacks
- Handles cookie expiration verification
- Centralized directory management for plist storage

**Recommendations**:
- The polling mechanism (0.5-second intervals up to 40 attempts) could use asyncSequence instead
- Consider moving to Keychain for iOS compatibility (as noted in comments)
- The property-list key conversion logic could be simplified with a helper extension

---

### Utilities/HTMLFetcher.swift

**Purpose**: Download job listing HTML with desktop user agent and Cloudflare bypass
**Lines of Code**: 83
**Dependencies**: Foundation
**Complexity**: Low-Medium

**Observations**:
- Retry mechanism automatically invokes Cloudflare challenge refresh on detection
- Comprehensive Cloudflare challenge detection (9 indicators)
- User-Agent and Accept headers properly configured for desktop browser emulation
- Clean separation between URL fetching and challenge detection

**Recommendations**:
- Well-designed; consider extracting Cloudflare indicators into an extension

---

### Utilities/WebViewHTMLFetcher.swift

**Purpose**: Fallback HTML extraction using hidden WKWebView for sites blocking URLSession
**Lines of Code**: 95
**Dependencies**: WebKit, Foundation
**Complexity**: Low-Medium

**Observations**:
- Elegant use of continuation-based async API
- Proper WebView lifecycle management (isHidden: true)
- Self-retain pattern prevents premature deallocation
- Timeout mechanism with configurable duration

**Recommendations**:
- Well-structured; minimal issues

---

### AI/Types/ApplicationReviewType.swift

**Purpose**: Define review types and prompt templates for application analysis
**Lines of Code**: 79
**Dependencies**: Foundation, PDFKit, AppKit, SwiftUI
**Complexity**: Low

**Observations**:
- Enum-based type system with CaseIterable for UI binding
- Prompt template uses placeholder replacement pattern ({jobPosition}, etc.)
- CustomApplicationReviewOptions provides flexibility for user customization
- Clear documentation of each review type

**Recommendations**:
- Consider extracting prompt templates to external files for easier maintenance
- The placeholder system is functional but could be more type-safe with a dedicated struct

---

### AI/Types/ApplicationReviewQuery.swift

**Purpose**: Build and manage prompts for application review operations
**Lines of Code**: 133
**Dependencies**: Foundation
**Complexity**: Low-Medium

**Observations**:
- Clean Observable pattern for query management
- Comprehensive text replacement handles all template placeholders
- backgroundItemsString and enabledSources from resume are properly included
- Debug logging helps diagnose custom prompt issues
- Handles both text and image inclusion conditionally

**Recommendations**:
- The text replacement chain could be refactored into a template engine
- Consider using a dedicated type for prompt building instead of string replacements

---

### AI/Services/ApplicationReviewService.swift

**Purpose**: Service coordinating application review requests with LLM
**Lines of Code**: 171
**Dependencies**: PDFKit, AppKit, SwiftUI, Foundation
**Complexity**: Medium

**Observations**:
- Proper @MainActor isolation for thread safety
- Service ensures fresh text resume rendering before LLM request
- Intelligent image handling (PDF to base64 conversion)
- Request cancellation mechanism prevents orphaned requests
- Clear separation between text-only and image-based requests

**Recommendations**:
- The image conversion logic could be extracted to a dedicated ImageConversionService (or reuse existing one)
- Consider making the prompt building more modular with strategy pattern

---

### AI/Services/JobRecommendationService.swift

**Purpose**: AI-powered job matching against candidate's resume
**Lines of Code**: 376
**Dependencies**: Foundation
**Complexity**: Medium

**Observations**:
- Sophisticated resume selection logic considering status priority and recency
- Context truncation prevents exceeding token limits (maxResumeContextBytes = 120,000)
- Proper background documentation assembly from multiple sources
- Structured response parsing with validation
- Debug prompt saving for troubleshooting

**Recommendations**:
- The byte-counting logic in truncateContext() is correct but could use String.count APIs more directly
- The large buildPrompt() method could be split into focused sub-methods
- Consider making priority scoring configurable

---

### AI/Services/ClarifyingQuestionsViewModel.swift

**Purpose**: Coordinate multi-turn conversation for resume clarification and revision workflow
**Lines of Code**: 502
**Dependencies**: Foundation, SwiftUI
**Complexity**: High

**Observations**:
- Sophisticated multi-turn conversation management:
  - Start conversation with background docs
  - Collect user answers
  - Hand off to ResumeReviseViewModel for revisions
- Proper streaming support with reasoning integration
- JSON extraction with robust fallback strategies
- Conversation ID persistence for multi-turn continuity
- Careful reasoning stream management with modal visibility control

**Recommendations**:
- **MEDIUM PRIORITY**: Extract JSON parsing logic into a dedicated JSONExtractor utility
- **MEDIUM PRIORITY**: The startClarifyingQuestionsWorkflow() method (58-184 lines) could be split into:
  - Conversation initialization
  - Reasoning vs. non-reasoning branches
  - Question handling
- Consider creating a ConversationManager abstraction for multi-turn workflows
- The parseJSONFromText() method has good fallback strategies but could be more type-safe

---

### AI/Views/ApplicationReviewSheet.swift

**Purpose**: UI for submitting job application for AI review
**Lines of Code**: 313
**Dependencies**: SwiftUI, WebKit
**Complexity**: Medium

**Observations**:
- Well-organized responsive layout with fixed header/footer and scrollable content
- Conditional rendering for different review types and states
- Good UX with progress indication and error messages
- Custom options UI only appears for custom review type
- Model selection properly handled through environment

**Concerns**:
- selectedModel initialized as empty string with implicit binding
- No validation that model is selected before allowing submit

**Recommendations**:
- Add explicit model validation before enabling submit button
- Extract customOptionsView and responseContent into separate view types
- Consider using a more type-safe approach than String for model selection

---

### AI/Views/ClarifyingQuestionsSheet.swift

**Purpose**: UI for answering clarifying questions during resume revision
**Lines of Code**: 261
**Dependencies**: SwiftUI
**Complexity**: Medium

**Observations**:
- Clean question rendering with optional context
- Decline mechanism lets users skip questions
- Keyboard navigation support (Tab/Shift+Tab between questions)
- Custom NSTextView-based editor for proper tab handling
- Validation prevents submission until all questions are answered or declined

**Recommendations**:
- The TabNavigableTextEditor could be extracted to a shared component library
- Consider using AppKit keybindings more directly

---

### Views/JobAppDetailView.swift

**Purpose**: Main detail view for displaying/editing job application
**Lines of Code**: 62
**Dependencies**: SwiftData, SwiftUI
**Complexity**: Low

**Observations**:
- Simple container composing section views
- Clear state management for edit/save/cancel operations
- Proper form lifecycle with onChange handlers

**Recommendations**:
- Well-structured; minimal issues

---

### Views/JobAppFormView.swift

**Purpose**: Form fields for job application details
**Lines of Code**: 43
**Dependencies**: SwiftUI
**Complexity**: Low

**Observations**:
- Focused view displaying posting details section
- Reusable Cell component handles display/edit modes

**Recommendations**:
- Consider whether more sections should be included or if this is intentionally minimal

---

### Views/JobAppRowView.swift

**Purpose**: Row representation of job application in list
**Lines of Code**: 28
**Dependencies**: SwiftUI
**Complexity**: Low

**Observations**:
- Simple list item with company and position
- Context menu for deletion

**Recommendations**:
- Minor syntax issue: extra closing brace at line 27 should be removed

---

### Views/NewAppSheetView.swift

**Purpose**: UI for importing job applications from various sources
**Lines of Code**: 356
**Dependencies**: Foundation, SwiftUI
**Complexity**: High

**Observations**:
- Supports three job sources: LinkedIn, Indeed, Apple
- Smart fallback strategy:
  - LinkedIn: Direct extraction -> ScrapingDog
  - Indeed: Direct fetch -> Cloudflare challenge -> WebView fallback
  - Apple: Direct HTML parsing
- Session management for LinkedIn authentication
- Comprehensive error handling with user-friendly messages
- Loading states with timeout indicators

**Concerns**:
- Long handleNewApp() method (57 lines) with nested closures
- Multiple state flags (isLoading, delayed, verydelayed, etc.) create cognitive load
- Error messages could be more consistent in format

**Recommendations**:
- Extract handling logic into separate methods per source (handleLinkedInJob, handleIndeedJob, handleAppleJob)
- Consolidate loading state into a dedicated enum (LoadingState)
- Consider extracting URL parsing into a URLJobSource protocol/enum

---

## Identified Issues

### Over-Abstraction

**None identified**. The module's abstraction levels are well-justified:
- Service layer appropriately abstracts LLM interactions
- Extension-based parsing keeps domain logic close to models
- Utility layer properly handles infrastructure concerns

### Unnecessary Complexity

1. **LinkedInJobScrape.swift - Navigation and Timeout Logic**
   - **Issue**: The loadJobPageHTML() continuation uses multiple overlapping timeout mechanisms
   - **Lines**: 134-341 (207 lines, deeply nested)
   - **Impact**: Makes testing and debugging difficult; hard to understand execution flow
   - **Cause**: Complex multi-step WebView navigation with fallback polling

2. **NewAppSheetView.swift - Multiple State Flags**
   - **Issue**: Uses 6+ boolean state flags (isLoading, delayed, verydelayed, showCloudflareChallenge, baddomain, showError, showLinkedInLogin)
   - **Lines**: 14-25
   - **Impact**: Difficult to reason about valid state combinations
   - **Cause**: Incremental feature additions without state consolidation

3. **ClarifyingQuestionsViewModel - Multi-turn Logic**
   - **Issue**: startClarifyingQuestionsWorkflow() spans 127 lines with two major branches
   - **Lines**: 57-184
   - **Impact**: Hard to follow the distinction between reasoning and non-reasoning paths
   - **Cause**: Need to support both model types

### Design Pattern Misuse

**None identified**. Patterns are applied appropriately:
- Continuation usage is correct for WebView callbacks
- @Observable used correctly for UI state
- Service layer properly isolated with dependency injection

### Testability Issues

1. **LinkedInSessionManager Integration**
   - WebView session management is difficult to mock in tests
   - No protocol abstraction for session management

2. **ApplicationReviewService**
   - ImageConversionService reference via .shared is not injectable
   - Makes unit testing difficult

## Recommended Refactoring Approaches

### Approach 1: LinkedIn Scraping Decomposition

**Effort**: Medium
**Impact**: Significantly improves readability and testability

**Steps**:

1. **Extract LinkedInPageLoader** - Handles multi-step navigation with timeout
   ```swift
   actor LinkedInPageLoader {
       func loadPage(targetURL: URL, using webView: WKWebView) async throws -> String
   }
   ```

2. **Extract LinkedInJobScrapeDelegate** - Manages navigation callbacks
   - Already separated, but remove from LinkedInJobScrape.swift into dedicated file

3. **Create LinkedInExtractor** - Pure HTML parsing
   ```swift
   struct LinkedInExtractor {
       static func parse(html: String, url: String) -> JobApp?
   }
   ```

4. **Refactor timeout logic** - Use structured concurrency properly
   - Replace manual timeout tracking with Swift.Task.sleep()
   - Use AsyncStream for polling instead of recursive calls

**Result**: LinkedInJobScrape.swift reduced from 647 to ~200 lines; LinkedInPageLoader ~200 lines; LinkedInExtractor ~150 lines

---

### Approach 2: State Management Consolidation in NewAppSheetView

**Effort**: Low
**Impact**: Improves code clarity and correctness

**Steps**:

1. **Create LoadingState enum**:
   ```swift
   enum ImportLoadingState {
       case idle
       case loading(progress: String?)
       case cloudflareChallenge(url: URL)
       case linkedInLogin
       case error(message: String)
   }
   ```

2. **Replace 6+ boolean flags** with single `@State private var loadingState: ImportLoadingState`

3. **Conditional views based on state** instead of multiple if statements

**Result**: Clearer state transitions; impossible to have invalid state combinations

---

### Approach 3: Multi-turn Conversation Framework

**Effort**: High
**Impact**: Enables reuse across resume revision and other workflows

**Steps**:

1. **Create ConversationManager protocol**:
   ```swift
   protocol ConversationManager {
       var conversationId: UUID? { get }
       func startConversation(...) async throws
       func continueConversation(...) async throws
   }
   ```

2. **Extract JSON parsing** into shared JSONExtractor

3. **Create ConversationWorkflow** type:
   ```swift
   struct ConversationWorkflow {
       let steps: [WorkflowStep]
       func execute() async throws
   }
   ```

**Result**: ClarifyingQuestionsViewModel reduced to ~250 lines; enables reuse for other multi-turn workflows

---

## Simpler Alternative Architectures

### Alternative 1: Single-Responsibility Services

**Current Approach**: Service layers handle both business logic and UI coordination
**Simpler Approach**: Separate concerns more aggressively

```
Models ← Services (pure logic) ← ViewModels (UI coordination)
```

**Pros**:
- Easier to test services
- Clear responsibility hierarchy
- ViewModels become thin coordinators

**Cons**:
- More files
- Potential over-engineering for this use case
- Additional layer increases cognitive overhead

**Recommendation**: Not applicable here - current approach balances simplicity with testability appropriately

---

### Alternative 2: Protocol-Based Job Source Abstraction

**Current Approach**: Separate static methods for each job source
**Simpler Approach**: Protocol-based extraction

```swift
protocol JobSourceExtractor {
    static func canHandle(url: URL) -> Bool
    static func extract(html: String, url: URL) async throws -> JobApp
}

extension AppleJobScrape: JobSourceExtractor { ... }
extension IndeedJobScrape: JobSourceExtractor { ... }
extension LinkedInJobScrape: JobSourceExtractor { ... }
```

**Pros**:
- NewAppSheetView becomes a generic dispatcher
- Easy to add new sources
- Better testability

**Cons**:
- More boilerplate
- Current approach simpler for 3 sources

**Recommendation**: Consider this if adding more sources; current approach adequate for 3

---

## Conclusion

The JobApplications module demonstrates **solid architectural practices** with appropriate separation of concerns, well-designed service layers, and robust error handling. The module successfully manages complex requirements including web scraping with anti-blocking measures, multi-turn AI conversations, and sophisticated UI workflows.

### Priority Recommendations

**High Priority (Significant Impact)**:
1. **Refactor LinkedInJobScrape.swift** (Issue: 647 lines, excessive complexity)
   - Split into LinkedInPageLoader, LinkedInExtractor, LinkedInJobScrapeDelegate
   - Time estimate: 3-4 hours
   - Impact: Improves testability and maintainability significantly

2. **Consolidate NewAppSheetView state** (Issue: 6+ boolean flags)
   - Introduce LoadingState enum
   - Time estimate: 1-2 hours
   - Impact: Prevents impossible states; improves code clarity

**Medium Priority (Good to Have)**:
3. **Extract JSON parsing utilities** (Issue: Multiple files parse JSON with similar fallback logic)
   - Create JSONExtractor utility
   - Time estimate: 1-2 hours
   - Impact: Reduces code duplication

4. **Abstraction for LLM image handling** (Issue: ApplicationReviewService depends on ImageConversionService.shared)
   - Inject ImageConverter dependency
   - Time estimate: 1 hour
   - Impact: Improves testability

**Low Priority (Minor Issues)**:
5. Fix JobAppRowView syntax error (extra closing brace)
6. Add selectedModel validation in ApplicationReviewSheet
7. Extract TabNavigableTextEditor to shared component library

### Complexity Rating

**Rating**: Medium
**Justification**:
- Core models (JobApp, JobAppForm) are simple (Low)
- Most utilities and services are well-scoped (Low-Medium)
- LinkedIn scraping (High) and multi-turn workflows (High) introduce localized complexity
- Complexity is justified by requirements but would benefit from the recommended refactoring

### Strengths to Preserve

- Clean layered architecture with proper dependency injection
- Robust web scraping with multiple fallback strategies
- Modern Swift concurrency patterns throughout
- Excellent error handling and user feedback
- Well-separated concerns across Models/Utilities/Services/Views

The module is production-ready and maintainable, with clear opportunities for incremental improvement through the recommended refactoring approaches.
