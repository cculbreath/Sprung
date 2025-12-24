# Code Analysis: sprung-core-features.swift.txt

Based on the provided codebase, here is a comprehensive code review focusing on dead code, anti-patterns, duplication, and legacy cleanup.

### Critical (Fix Immediately)

**1. Hardcoded Executable Paths (Crash Risk/Functionality Failure)**
*   **File:** `Sprung/Export/NativePDFGenerator.swift`
*   **Issue Type:** Anti-Pattern / Brittleness
*   **Description:** The PDF generator relies on finding a specific Chrome or Chromium executable at hardcoded paths. If the user installs Chrome in a non-standard location or uses a different Chromium-based browser (Brave, Edge, etc. not listed), PDF export will fail silently or throw a generic error.
*   **Code Snippet:**
    ```swift
    let chromePaths = [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        // ...
    ]
    ```
*   **Recommendation:** Use `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` to dynamically locate "com.google.Chrome" or allow the user to select their browser path in Settings if the default check fails.

**2. Legacy Data Model Retention (Data Integrity Risk)**
*   **File:** `Sprung/SearchOps/Models/JobLead.swift` & `Sprung/DataManagers/SchemaVersioning.swift`
*   **Issue Type:** Legacy Cruft
*   **Description:** `JobLead` is marked `@available(*, deprecated, message: "Use JobApp instead...")`. However, it is still included in `SprungSchema.models`, meaning it is still creating tables in the database. Furthermore, `SearchOpsPipelineCoordinator` initializes a `JobLeadStore`. If the app writes to `JobLead` instead of `JobApp` in specific SearchOps flows, data will be fragmented between the old and new models.
*   **Code Snippet:**
    ```swift
    // Sprung/SearchOps/Services/SearchOpsPipelineCoordinator.swift
    self.jobLeadStore = JobLeadStore(context: modelContext) // Initializes deprecated store
    ```
*   **Recommendation:**
    1.  Create a migration to move any existing `JobLead` data to `JobApp`.
    2.  Remove `JobLead` from `SprungSchema`.
    3.  Remove `JobLeadStore`.
    4.  Update `SearchOpsPipelineCoordinator` to use `JobAppStore` exclusively.

### High Priority

**1. Confusing AI Service Layer Architecture (Complexity)**
*   **File:** `Sprung/Shared/AI/Models/Services/LLMFacade.swift` vs `_LLMService.swift`
*   **Issue Type:** Anti-Pattern / Over-Engineering
*   **Description:** The architecture involves `LLMFacade`, `_LLMService`, `_LLMRequestExecutor`, and `LLMClient`. `LLMFacade` wraps `_LLMService` for some things (like streaming setup) but wraps `LLMClient` for others. `_LLMService` appears to be an internal implementation detail that leaked out or wasn't fully encapsulated. The naming convention `_ClassName` usually implies private/internal, but it is exposed publicly in `AppDependencies`.
*   **Recommendation:** Consolidate `_LLMService` functionality into `LLMFacade`. Remove the distinction or make `_LLMService` truly private/internal to the module. Ensure one clear entry point for all LLM interactions.

**2. Duplicate Resume Review Logic**
*   **File:** `Sprung/Resumes/AI/Services/ResumeReviewService.swift` vs `Sprung/Resumes/AI/Services/ResumeReviseViewModel.swift`
*   **Issue Type:** Duplication / Inconsistent Patterns
*   **Description:** There are two distinct ways to review a resume.
    1.  `ResumeReviewService` (used by the "Optimize" button) handles "Assess Quality", "Fix Overflow", and "Reorder Skills".
    2.  `ResumeReviseViewModel` (used by the "Customize" button) handles "Customize", "Clarify", and "Phase Review".
    Both construct prompts, handle LLM responses, and modify the resume, but they use different prompt builders (`ResumeReviewQuery` vs `ResumeApiQuery`) and different response handlers.
*   **Recommendation:** Merge these services. The "Fix Overflow" and "Reorder" logic should likely become workflows within `ResumeReviseViewModel` or tools within the `ToolConversationRunner`, unifying the prompt building and execution strategies.

**3. Massive View Model**
*   **File:** `Sprung/Resumes/AI/Services/ResumeReviseViewModel.swift`
*   **Issue Type:** God Object
*   **Description:** Despite delegating some logic to `PhaseReviewManager` and `RevisionNavigationManager`, this class acts as a massive central hub. It exposes 30+ properties and functions, mixing UI state (`showResumeRevisionSheet`), business logic (`submitSkillExperienceResults`), and data flow (`updateNodes`).
*   **Recommendation:** Continue the refactoring pattern seen with `PhaseReviewManager`. Move the "Tools" logic (`showSkillExperiencePicker`, `pendingSkillQueries`) entirely into a `ToolsViewModel` or similar, exposing only a clean state object to the View.

### Medium Priority

**1. Redundant HTML Fetchers**
*   **File:** `Sprung/JobApplications/Utilities/WebViewHTMLFetcher.swift` vs `Sprung/JobApplications/Utilities/HTMLFetcher.swift`
*   **Issue Type:** Duplication
*   **Description:** There are two separate mechanisms for fetching HTML. `HTMLFetcher` uses `URLSession` with headers. `WebViewHTMLFetcher` uses a headless `WKWebView`. `JobApp.importFromIndeed` attempts one, then falls back to the other.
*   **Recommendation:** Consolidate these into a single `WebResourceService` that handles the strategy pattern (try simple HTTP first, fall back to headless browser) internally, rather than exposing both implementations to the call sites.

**2. Unsafe Stringly-Typed Manifests**
*   **File:** `Sprung/Templates/Utilities/TemplateManifestDefaults.swift`
*   **Issue Type:** Anti-Pattern
*   **Description:** The template system relies heavily on string keys (`"work"`, `"summary"`, `"styling"`, etc.). While mapped to enums in some places, `TemplateManifestDefaults` uses raw string arrays and dictionaries extensively. A typo in `defaultSectionOrder` or `recommendedFontSizes` keys would silently fail or cause UI bugs.
*   **Recommendation:** Define static constants or an Enum for standard section keys (e.g., `StandardSection.work.rawValue`) and use them throughout the manifest defaults to ensure compile-time safety.

**3. Forced Unwrapping / Silent Failures in Scraping**
*   **File:** `Sprung/JobApplications/Models/AppleJobScrape.swift`
*   **Issue Type:** Anti-Pattern
*   **Description:** The parsing logic relies on specific HTML IDs (`#jobdetails-postingtitle`) and assumes `first()` returns valid elements. While inside a `try` block, it swallows errors via `Logger.error` and returns void, giving the user no feedback if parsing fails partially.
*   **Recommendation:** The parsing functions should `throw` specific errors (e.g., `ParsingError.titleNotFound`) so the UI can inform the user *why* the import failed, rather than just failing silently or logging to console.

### Legacy Cleanup (Dedicated Section)

This section identifies artifacts from the recent refactor that should be removed or finalized.

#### Safe to Delete Immediately
1.  **File:** `Sprung/SearchOps/Models/JobLead.swift`
    *   **Item:** `class JobLead`
    *   **Reason:** Deprecated in favor of `JobApp`.
2.  **File:** `Sprung/SearchOps/Stores/JobLeadStore.swift`
    *   **Item:** `class JobLeadStore`
    *   **Reason:** Supports the deprecated model.
3.  **File:** `Sprung/Resumes/AI/Types/ResumeQuery.swift`
    *   **Item:** `ResumeApiQuery` -> `clarifyingQuestionsSchema` (static property)
    *   **Reason:** Appears to be duplicated/redefined in `SearchOpsToolSchemas` or handled dynamically in `ClarifyingQuestionsViewModel` via `ResumeApiQuery` (Checking usage: It is used in `ClarifyingQuestionsViewModel`, so **Keep** for now, but mark for unification with the Tool registry).
4.  **File:** `Sprung/CoverLetters/AI/Services/CoverLetterService.swift`
    *   **Item:** `extractCoverLetterContent`
    *   **Reason:** This logic (JSON extraction) is duplicated in `LLMResponseParser.extractJSONFromText`. Use the shared utility instead.

#### Requires Verification
1.  **File:** `Sprung/Shared/AI/Models/Services/OpenAIResponsesConversationService.swift`
    *   **Item:** `onboardingToolSchemas` property (returns empty array).
    *   **Reason:** If this service is used for onboarding, it might need actual tools. If not, it's dead code.
2.  **File:** `Sprung/Shared/AI/Models/LLM/LLMVendorMapper.swift`
    *   **Item:** `streamChunkDTO(from: ChatCompletionChunkObject)`
    *   **Reason:** Maps `reasoningContent`. Verify OpenRouter/SwiftOpenAI actually returns this field in the chunk object (it's a relatively new/vendor-specific feature).

#### Needs Migration Completion
1.  **SearchOps Integration:**
    *   `SearchOpsPipelineCoordinator` currently initializes `JobLeadStore`. Change this to `JobAppStore`.
    *   Update `SprungSchema.models` to remove `JobLead.self`.
2.  **Settings Migration:**
    *   `DatabaseMigrationCoordinator` handles model capabilities. Ensure it also handles the migration of any data stored in `JobLead` tables to `JobApp` tables if the user updates the app.

### Dead Code Detection

1.  **Unused View:** `TemplateEditorOverlayOptionsView`
    *   **File:** `Sprung/App/Views/TemplateEditor/TemplateEditorOverlayOptionsView.swift`
    *   **Status:** It is referenced in `TemplateEditorView`, so it is *not* dead, but the logic inside `loadOverlayPDF` (security scoped resource handling) suggests it might be handling file permissions that aren't persisted, making the feature flaky across restarts.
2.  **Unused Filter:** `TemplateFilters.htmlStripFilter`
    *   **File:** `Sprung/Templates/Utilities/TemplateData/TemplateFilters.swift`
    *   **Status:** Logic exists, but search for usage in default templates. If no template uses `{{ htmlStrip ... }}`, it's dead logic.
3.  **Deprecated Logic:** `TextResumeGenerator.convertEmploymentToArray`
    *   **File:** `Sprung/Export/TextResumeGenerator.swift`
    *   **Status:** Contains logic for tree-based resumes AND flat dictionaries. Since `Resume` always has a `rootNode` (via `ResStore.create`), the flat dictionary fallback might be dead code from before the Tree structure was mandatory.

### Low Priority Suggestions

*   **View Modifiers:** In `AppSheets.swift`, the `AppSheetsModifier` is very large. Break this down into smaller, domain-specific modifiers (e.g., `ResumeSheets`, `NetworkingSheets`).
*   **Magic Strings:** `SearchOpsToolName` enums use raw strings like "discover_job_sources". These match the JSON schema filenames. A unit test should ensure the Enum raw values match the file names in the bundle to prevent crashes if a file is renamed.
*   **Logging:** `Logger` uses `OSLoggerBackend`. Ensure `subsystem` is unique per module if you want easier filtering in Console.app (e.g. `com.sprung.ai`, `com.sprung.data`).