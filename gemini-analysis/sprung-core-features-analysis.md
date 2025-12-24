# Code Analysis: sprung-core-features.swift.txt

Here is the comprehensive code review for the **Sprung** codebase.

Based on the provided files, the application has recently undergone significant architectural changes, particularly in the AI/LLM layer (moving to a Facade pattern) and the modularization of features (SearchOps). However, there are significant remnants of previous architectures and incomplete refactoring efforts.

---

### 1. Critical (Fix Immediately)

**Issue**: Unsafe Shell Execution & Hardcoded Paths
**File**: `Sprung/Export/NativePDFGenerator.swift`
**Description**: The PDF generator attempts to find a Chrome binary by checking hardcoded paths (e.g., `/opt/homebrew/bin/chrome`). It then uses `Process()` to execute it. This is brittle, insecure, and will likely fail on user machines without Chrome installed in specific locations or in sandboxed App Store environments.
**Code Snippet**:
```swift
let binaryPaths = [
    "/opt/homebrew/bin/chromium",
    "/usr/local/bin/chromium", // ...
]
// ...
process.executableURL = URL(fileURLWithPath: chromePath)
```
**Recommendation**: Embed a specific version of Chromium/Headless shell within the app bundle (as hinted at in the code but implemented alongside hardcoded system paths), or switch to `PDFKit` / `WKWebView`'s native PDF export which doesn't require external binaries. If external binaries are required, proper checking and error handling for missing binaries are needed to prevent crashes/silent failures.

**Issue**: Force Unwraps in UI Binding Logic
**File**: `Sprung/Resumes/AI/Views/PhaseReviewBundledView.swift`
**Description**: The binding logic assumes arrays are in sync. If the underlying data changes while the view is rendering, `currentReview.items[index]` could crash with an index out of bounds.
**Code Snippet**:
```swift
get: {
    guard let review = viewModel.phaseReviewState.currentReview,
          index < review.items.count else {
        // Returns dummy item
        return PhaseReviewItem(...)
    }
    return review.items[index]
}
```
**Recommendation**: Use `Safe` array indexing or refactor the view to iterate over `Identifiable` items rather than indices to generate Bindings safely.

---

### 2. High Priority (Architectural & Quality)

**Issue**: Incomplete Service Refactoring (God Object)
**File**: `Sprung/Resumes/AI/Services/ResumeReviewService.swift`
**Description**: Attempts were made to extract logic into `FixOverflowService` and `ReorderSkillsService`. However, `ResumeReviewService` still retains specific networking methods for those features (`sendFixFitsRequest`, `sendReorderSkillsRequest`). This creates a tight coupling where the "specialized" services depend on the "generic" service to do their specific work.
**Code Snippet**:
```swift
// In ResumeReviewService.swift
func sendFixFitsRequest(...) { ... }
func sendReorderSkillsRequest(...) { ... }

// In FixOverflowService.swift
init(reviewService: ResumeReviewService, ...) { ... }
```
**Recommendation**: Move `sendFixFitsRequest` logic entirely into `FixOverflowService` and `sendReorderSkillsRequest` into `ReorderSkillsService`. Make `ResumeReviewService` purely for the generic review types, or refactor the networking layer to be generic enough that it doesn't need specific methods for each feature.

**Issue**: Duplicate Tool Definitions (Hardcoded vs Loaded)
**File**: `Sprung/SearchOps/Tools/SearchOpsToolExecutor.swift` vs `Sprung/SearchOps/Tools/Schemas/SearchOpsToolSchemas.swift`
**Description**: Tools are defined **twice**.
1. `SearchOpsToolSchemas.swift` loads schemas from JSON resources via `SchemaLoader`.
2. `SearchOpsToolExecutor.swift` has a massive `buildAllToolsStatic()` function with hardcoded schemas inside the code.
The executor currently uses `buildAllToolsStatic`, meaning the JSON files and `SchemaLoader` are likely dead code or the hardcoded static methods are legacy cruft.
**Recommendation**: Delete the hardcoded static builder methods in `SearchOpsToolExecutor` and switch it to use the `SearchOpsToolSchemas` loaded from JSON. This reduces file size and centralizes schema definitions.

**Issue**: Massive View Controller (ViewModel)
**File**: `Sprung/Resumes/AI/Services/ResumeReviseViewModel.swift`
**Description**: This class acts as a massive coordinator. It forwards calls to `NavigationManager`, `PhaseReviewManager`, `WorkflowOrchestrator`, `ToolRunner`, etc. It has over 300 lines of pass-through properties and methods.
**Recommendation**: The view (`RevisionReviewView`) should likely depend directly on `PhaseReviewManager` or `RevisionNavigationManager` for specific states rather than proxying everything through `ResumeReviseViewModel`.

---

### 3. Medium Priority (Anti-Patterns & Duplication)

**Issue**: Stringly-Typed Logic
**File**: `Sprung/ResumeTree/Models/TreeNodeModel.swift`
**Description**: `schemaValidationRule` is a String, but there is logic checking for specific values like "regex", "email", etc.
**Code Snippet**:
```swift
var schemaValidationRule: String?
// ... later ...
switch rule {
case "minLength": ...
case "regex": ...
}
```
**Recommendation**: Use the `Validation.Rule` enum defined in `TemplateManifest.swift` instead of raw strings to ensure type safety.

**Issue**: Retain Cycle Risk in Closures
**File**: `Sprung/Shared/AI/Models/Services/LLMFacade.swift`
**Description**: `makeStreamingHandle` creates a cancel closure that captures `self` weakly, but then executes a Task on MainActor.
**Code Snippet**:
```swift
let cancelClosure: @Sendable () -> Void = { [weak self] in
    Task { @MainActor in
        self?.cancelStreaming(handleId: handleId)
    }
}
```
**Recommendation**: While `[weak self]` is present, the logic involving `activeStreamingTasks` management across actor boundaries is complex. Ensure `cancelStreaming` handles `self` being nil gracefully (it seems to, but verify thread safety of `activeStreamingTasks` dictionary access).

**Issue**: Duplicated HTML/Text Parsing Logic
**File**: `Sprung/Shared/Utilities/TextFormatHelpers.swift`
**Description**: Methods like `stripTags` use `NSAttributedString` to strip HTML. This logic is repeated or similar to logic found in `NativePDFGenerator` (e.g., `fixFontReferences`).
**Recommendation**: Consolidate HTML cleaning/manipulation logic into a single `HTMLUtility` class.

---

### 4. Legacy Cleanup & Incomplete Migrations

This is the most critical section for this specific codebase review.

#### A. Internal/Underscore Classes (Safe to Refactor)
**File**: `Sprung/Shared/AI/Models/Services/LLMService.swift`
**Finding**: `_LLMService`, `_LLMRequestExecutor`, `_SwiftOpenAIClient`.
**Analysis**: The underscore prefix suggests these were internal implementation details intended to be hidden behind `LLMFacade`.
**Recommendation**: Rename these to remove the underscore (e.g., `OpenRouterServiceBackend`, `LLMRequestExecutor`) and ensure `LLMFacade` is the *only* public consumer.

#### B. OpenAI Backend Shim
**File**: `Sprung/Shared/AI/Models/Services/OpenAIResponsesConversationService.swift`
**Finding**: This class exists to force the generic OpenAI Responses API to behave like a conversation service.
**Analysis**: It maintains local state (`conversations` dict) to mimic a persistent conversation because the underlying API might be stateless or handle it differently.
**Action**: Verify if `LLMConversationService` protocol conformance is actually used for OpenAI backends. If `LLMFacade` primarily uses OpenRouter (which it seems to default to), this might be dead code if the "OpenAI Direct" feature isn't active.

#### C. SearchOps Tool Schemas (Duplicate Truth)
**File**: `Sprung/SearchOps/Tools/SearchOpsToolExecutor.swift`
**Finding**: `buildGenerateDailyTasksToolStatic()` and similar methods.
**Status**: **Legacy Cruft / Incomplete Migration**.
**Recommendation**: The app seems to have moved *towards* using JSON files (`SchemaLoader`), but the code still executes the hardcoded static methods.
**Action**:
1. Verify `SchemaLoader` works correctly.
2. Update `SearchOpsToolExecutor` to use `SearchOpsToolSchemas`.
3. **Delete** all `build...Static` methods in `SearchOpsToolExecutor`.

#### D. Resume Review Networking
**File**: `Sprung/Resumes/AI/Services/ResumeReviewService.swift`
**Finding**: Methods `sendFixFitsRequest` and `sendReorderSkillsRequest`.
**Status**: **Incomplete Migration**.
**Analysis**: The logic for handling the response and prompting resides here, but the *business logic* for what to do with that response has moved to `FixOverflowService` and `ReorderSkillsService`.
**Action**: Move the networking/prompt construction logic into the specific service classes. `ResumeReviewService` should likely be renamed to `GeneralResumeReviewService` and only handle the `.assessQuality`, `.assessFit`, etc., types.

#### E. Experience Defaults "Draft" Pattern
**File**: `Sprung/Experience/Models/ExperienceDrafts.swift`
**Finding**: `ExperienceDefaultsDraft`, `WorkExperienceDraft`, etc.
**Status**: **Potentially Redundant**.
**Analysis**: These structs map 1:1 to `ExperienceDefaults` (SwiftData models).
**Recommendation**: While this isn't strictly "legacy", using `Codable` structs to edit SwiftData models is a valid pattern (Data Transfer Object). However, ensure that the mapping logic in `ExperienceDefaultsDraft.init(model:)` and `apply(to:)` is kept in sync. If the SwiftData models are not shared across threads, binding directly to the model in the UI might be simpler, removing this entire file.

---

### 5. Dead Code Candidates

*   **`Sprung/Shared/AI/Models/LLM/LLMVendorMapper.swift`**:
    *   Method `makeImageDetail` creates a data URL from Data. This is used, but verify if `LLMAttachment` struct is actually used anywhere other than mapping.
*   **`Sprung/Templates/Utilities/TemplateData/TemplateFilters.swift`**:
    *   Filter `htmlStripFilter` appears to be registered but check if Mustache templates actually use `{{ htmlStrip ... }}`.
*   **`Sprung/Shared/UIComponents/WindowDragHandle.swift`**:
    *   `WindowDragHandleView` and `WindowDragHandle`. Check if these are actually used in `BorderlessOverlayWindow`. The window sets `isMovableByWindowBackground = false`, implying it might need this, but `OnboardingInterviewView` (not included) might be the only consumer.
*   **`Sprung/JobApplications/Models/IndeedJobScrape.swift`**:
    *   The `importFromIndeed` function relies on `WebResourceService`. If `CloudflareChallengeView` (which handles Indeed challenges) is the primary way Indeed is loaded, the direct scraping logic in `importFromIndeed` might be unreachable or broken due to anti-bot measures.

### 6. Unnecessary Duplication

1.  **Model Definitions**:
    *   `OpenRouterModel` (Shared) vs `EnabledLLM` (DataManagers). They store almost identical data (ID, name, capabilities). `EnabledLLM` acts as a local cache/settings object, but fields like `contextLength` and `pricingTier` are duplicated.

2.  **Prompt Building**:
    *   `ResumeReviewQuery.swift` and `ResumeApiQuery.swift` (in `Shared/AI/Types` and `Resumes/AI/Types`). Both build prompts for resume analysis. `ResumeApiQuery` seems to be the "New" structured approach, while `ResumeReviewQuery` handles the "Old" text-based reviews.
    *   **Recommendation**: Merge these. `ResumeReviewService` should likely use `ResumeApiQuery`.

3.  **Parsers**:
    *   `LLMResponseParser.swift` (Shared) vs `_JSONResponseParser` (Shared).
    *   `LLMResponseParser` parses JSON from strings (handling markdown blocks).
    *   `_JSONResponseParser` does... essentially the same thing but specifically for `LLMResponseDTO`.
    *   **Recommendation**: Merge into a single robust JSON extraction/parsing utility.

### Summary Plan

1.  **Refactor SearchOps Tools**: Switch `SearchOpsToolExecutor` to use `SearchOpsToolSchemas` and delete the hardcoded static methods (~200 lines of code).
2.  **Clean up Resume Services**: Move networking logic from `ResumeReviewService` into `FixOverflowService` and `ReorderSkillsService`.
3.  **Consolidate Parsers**: Merge `LLMResponseParser` and `_JSONResponseParser`.
4.  **Fix PDF Generator**: Remove hardcoded paths to Chrome; implement a safe fallback or bundle check.
5.  **Rename Internal Services**: Rename `_LLMService` to `LLMServiceBackend` and make it private to the module if possible, exposing only `LLMFacade`.