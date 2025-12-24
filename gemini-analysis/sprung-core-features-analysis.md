# Code Analysis: sprung-core-features.swift.txt

Here is the comprehensive code review of the Sprung codebase (Core + Features).

### Summary
The codebase demonstrates a sophisticated integration of SwiftData, SwiftUI, and LLM services. However, there are significant architectural schisms—specifically between the core "JobApp" logic and the newer "SearchOps" module—leading to data model duplication. There is also rampant copy-pasting of LLM utility logic (JSON parsing) across different service classes.

---

### Critical (Fix Immediately)

**1. Hardcoded API URL bypassing AppConfig**
**File:** `Sprung/Shared/AI/Models/Services/ModelValidationService.swift`
**Issue:** Anti-Pattern / Data Integrity
**Description:** The `ModelValidationService` defines a hardcoded `baseURL` string, ignoring the centralized `AppConfig.openRouterBaseURL`. If the API endpoint changes in `AppConfig`, this service will silently fail or point to the wrong location.
**Code Snippet:**
```swift
class ModelValidationService {
    private let baseURL = "https://openrouter.ai/api/v1" // Hardcoded
    // ...
}
```
**Recommendation:** Replace with `private let baseURL = AppConfig.openRouterBaseURL` to ensure a single source of truth for networking configuration.

**2. Synchronous File I/O on Main Thread during Drop**
**File:** `Sprung/ResRefs/Views/ResRefFormView.swift`
**Issue:** Anti-Pattern / UI Blocking
**Description:** Inside `handleOnDrop`, `try String(contentsOf: url, encoding: .utf8)` is called. While `loadItem` provides the URL asynchronously, the actual file reading happens on the queue provided by `NSItemProvider`. If the file is on a slow network drive or iCloud, this could block UI updates, especially since the subsequent block explicitly dispatches to `Main`.
**Code Snippet:**
```swift
provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
    // ... validation ...
    do {
        // This is a blocking file read
        let text = try String(contentsOf: url, encoding: .utf8) 
        DispatchQueue.main.async {
             // ...
        }
    }
}
```
**Recommendation:** Move the file reading inside a `Task.detached` or background queue before dispatching the result to the main actor.

---

### High Priority

**3. Rampant Duplication of JSON Extraction Logic**
**File(s):**
1. `Sprung/Resumes/AI/Services/ResumeReviewService.swift`
2. `Sprung/Resumes/AI/Services/SkillReorderService.swift`
3. `Sprung/JobApplications/AI/Services/ClarifyingQuestionsViewModel.swift`
4. `Sprung/Shared/AI/Models/Services/SearchOpsLLMService.swift`
5. `Sprung/Shared/AI/Models/Services/LLMResponseParser.swift`
**Issue:** Unnecessary Duplication
**Description:** The logic to robustly extract and parse JSON from an LLM response (handling markdown code blocks, finding the first `{`, etc.) is copy-pasted into at least 5 different files. They all implement `extractJSONFromText` or `parseJSONFromText` with nearly identical logic.
**Code Snippet (Example from ClarifyingQuestionsViewModel):**
```swift
private func parseJSONFromText<T: Codable>(_ text: String, as type: T.Type) throws -> T {
    // ... duplicated parsing logic ...
}
private func extractJSONFromText(_ text: String) -> String {
    // ... duplicated regex/substring logic ...
}
```
**Recommendation:** Consolidate all JSON extraction logic into `LLMResponseParser` (which already exists in Shared). Refactor all services to use `LLMResponseParser.parseJSON(_:as:)`.

**4. Duplicate Domain Models (JobApp vs. JobLead)**
**File(s):**
1. `Sprung/JobApplications/Models/JobApp.swift`
2. `Sprung/SearchOps/Models/JobLead.swift`
**Issue:** Architectural Duplication
**Description:** The app has two distinct models for tracking a job application. `JobApp` is the core model used for Resume/CoverLetter creation. `JobLead` is the model used in the "SearchOps" Kanban pipeline. They track the same data (company, role, source, URL, status/stage) but are totally separate entities in SwiftData. This fragmentation prevents a seamless flow from "Identifying a lead" (SearchOps) to "Creating a Resume" (Core).
**Code Snippet:**
```swift
// JobApp.swift
@Model class JobApp {
    var jobPosition: String
    var companyName: String
    var status: Statuses // .new, .applied, etc.
}

// JobLead.swift
@Model final class JobLead {
    var company: String
    var role: String?
    var stage: ApplicationStage // .identified, .applied, etc.
}
```
**Recommendation:** Merge these models. `JobLead` should likely replace `JobApp` or vice-versa, or one should act as a lightweight wrapper. At minimum, implement a conversion method to promote a `JobLead` to a `JobApp` when the user decides to apply.
**Dev Note** Please use JobApp everywhere

**5. Massive "God Object" Coordinator**
**File:** `Sprung/SearchOps/Services/SearchOpsCoordinator.swift`
**Issue:** Anti-Pattern
**Description:** `SearchOpsCoordinator` initializes and holds strong references to **11 different SwiftData stores** and **2 services** in its initializer. It acts as a massive Service Locator, making it difficult to test, maintain, or reason about data flow.
**Code Snippet:**
```swift
init(modelContext: ModelContext) {
    self.preferencesStore = SearchPreferencesStore(context: modelContext)
    self.settingsStore = SearchOpsSettingsStore(context: modelContext)
    self.jobSourceStore = JobSourceStore(context: modelContext)
    self.jobLeadStore = JobLeadStore(context: modelContext)
    // ... 7 more stores ...
}
```
**Recommendation:** Break `SearchOps` into smaller, feature-specific coordinators (e.g., `SearchOpsPipelineCoordinator`, `SearchOpsNetworkingCoordinator`) that only initialize the stores they actually need.

---

### Medium Priority

**6. Unsafe Force Try in Static Properties**
**File:** `Sprung/App/Views/TemplateEditor/TemplateEditorView+Validation.swift`
**Issue:** Anti-Pattern
**Description:** Using `try!` for regex compilation in a static property initializer. While unlikely to fail for a constant string, if the pattern is ever modified incorrectly, it will crash the app immediately on launch or class load.
**Code Snippet:**
```swift
private static let customFieldReferenceRegex: NSRegularExpression = {
    let pattern = #"custom(?:\.[A-Za-z0-9_\-]+)+"#
    return try! NSRegularExpression(pattern: pattern, options: []) // Crash risk
}()
```
**Recommendation:** Use a lazy property or a throwing accessor, or at minimum, unit test this regex heavily.

**7. Duplicate Networking Logic for Cloudflare**
**File:** `Sprung/App/Views/CloudflareChallengeView.swift` vs `Sprung/JobApplications/Utilities/WebViewHTMLFetcher.swift`
**Issue:** Unnecessary Duplication
**Description:** Both files implement `WKNavigationDelegate` to load a URL via a headless (or hidden) `WKWebView` to bypass challenges or get HTML. They share very similar logic for waiting and extracting HTML.
**Recommendation:** Refactor `WebViewHTMLFetcher` to be a shared utility that can optionally handle the "Challenge" visual presentation if needed, removing the logic from the View struct.

**8. Magic Strings in Template Manifests**
**File:** `Sprung/ResumeTree/Utilities/ExperienceDefaultsToTree.swift`
**Issue:** Anti-Pattern / Stringly Typed
**Description:** The code relies heavily on magic strings like "work", "volunteer", "education" to identify sections. These should be defined in a shared Enum or Constant struct to ensure safety between the Manifest parser and the Tree builder.
**Code Snippet:**
```swift
switch key {
case "summary": buildSummarySection(parent: parent)
case "work": buildWorkSection(parent: parent)
// ...
```
**Recommendation:** Use the `ExperienceSectionKey` enum defined in `Sprung/Experience/Models/ExperienceSchema.swift` universally, rather than raw strings.

---

### Low Priority / Suggestions

**9. Unused/Dead Code - Template Text Filters**
**File:** `Sprung/App/Views/TemplateEditor/TemplateTextFilters.swift`
**Issue:** Dead Code
**Description:** The struct defines a static `reference` array containing metadata about filters. This array appears to be used only for the `TemplateEditorSidebarView` snippet panel. If the editor sidebar isn't using all of them, or if new filters are added to `TemplateFilters` but not this reference list, they drift apart.
**Recommendation:** Ensure `TemplateFilters.register` uses a source of truth that generates this reference list to keep documentation and implementation in sync.

**10. Redundant Enum Definitions**
**File:** `Sprung/Resumes/AI/Types/ResumeReviewType.swift` vs `Sprung/JobApplications/AI/Types/ApplicationReviewType.swift`
**Issue:** Duplication
**Description:** Both enums define `.assessQuality` and `.custom` with very similar prompt generation logic. `ApplicationReviewType` seems to be a newer, slightly different version of `ResumeReviewType`.
**Recommendation:** If the intent is to review the *Application* (Resume + Cover Letter) vs just the *Resume*, keep them separate but share the underlying prompt construction logic (e.g., a shared `ReviewPromptBuilder`).

**11. View Logic in Model**
**File:** `Sprung/SearchOps/Models/JobLead.swift`
**Issue:** Anti-Pattern
**Description:** The model contains `displayTitle` logic. While minor, presentation logic usually belongs in a ViewModel or the View extension.
**Code Snippet:**
```swift
var displayTitle: String {
    if let role = role { return "\(role) at \(company)" }
    return company
}
```
**Recommendation:** Move to an extension or Helper.

