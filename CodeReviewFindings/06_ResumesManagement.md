# Code Review Report: Resumes Management Layer

- **Shard/Scope:** `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes`
- **Languages:** `swift`
- **Excluded:** `node_modules/**, dist/**, build/**, .git/**, **/*.min.js, **/vendor/**`
- **Objectives:** Phase 1-6 Refactoring Assessment (DI, Safety, LLM Facade, @MainActor, Export Boundaries)
- **Run started:** 2025-10-07

> This report assesses the Resumes management layer against Phase 1-6 refactoring objectives from Final_Refactor_Guide_20251007.md. Each finding includes specific file locations, code excerpts, phase alignment, and actionable recommendations.

---

## Executive Summary

**Overall Health: Good → Excellent**

The Resumes management layer shows **strong adherence** to most Phase 1-6 objectives:

✅ **Strengths:**
- LLM facade successfully integrated (Phase 6 complete)
- DI patterns well-implemented in ViewModels (Phase 1 complete)
- Good separation of concerns in service layer
- @MainActor properly applied to UI-critical operations
- No unsafe force-unwraps in user-facing paths (Phase 2 compliance)
- Clean ViewModel architecture with proper state management

⚠️ **Areas for Improvement:**
- Singleton dependency on `ImageConversionService.shared` (Phase 1/6 violation)
- Legacy comment references `LLMService.shared` (stale documentation)
- TreeToJson usage in Resume model (Phase 4 opportunity)
- NotificationCenter usage for sheet coordination (Phase 8 potential)
- Some export logic in Resume model (Phase 5 boundary concern)

🎯 **Priority:** Medium - Most critical work complete, remaining items are polish and alignment

---

## File: `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes/Models/Resume.swift`

**Language:** Swift
**Size/LOC:** ~228 LOC
**Summary:** Core SwiftData model for resumes. Generally well-structured but contains export logic and legacy JSON transformation that should be in service layer.

### Quick Metrics
- Longest function: `debounceExport()` (~30 LOC)
- Max nesting depth: 3
- TODO/FIXME: 0
- Comment ratio: 0.15
- Notable deps: SwiftData, TreeNode, TreeToJson, ResumeExportService

### Top Findings (prioritized)

#### 1. **Export Logic in Model Layer** — *Medium, High Confidence*
- **File:** Resume.swift:158-189
- **Phase:** Phase 5 (Export Pipeline Boundary)
- **Code Excerpt:**
```swift
func debounceExport(onStart: (() -> Void)? = nil,
                    onFinish: (() -> Void)? = nil)
{
    exportWorkItem?.cancel()
    isExporting = true
    onStart?()

    exportWorkItem = DispatchWorkItem { [weak self] in
        guard let self = self else { return }
        if let jsonFile = FileHandler.saveJSONToFile(jsonString: jsonTxt) {
            Task { @MainActor in
                do {
                    try await ResumeExportService().export(jsonURL: jsonFile, for: self)
```

- **Why it matters:** Models should be pure data containers. Export coordination, file I/O, and UI callbacks belong in a service or ViewModel layer. This violates Single Responsibility Principle and Phase 5 export boundary objectives.

- **Recommendation:**
  - **Primary:** Extract `debounceExport()` and `ensureFreshRenderedText()` to a dedicated `ResumeExportCoordinator` service
  - Create protocol `ResumeExportable` to define the contract
  - Pass coordinator via DI to ViewModels that need export functionality
  - Keep only export state flags (`isExporting`) in the model
  - **Code Example:**
```swift
// New service
@Observable
class ResumeExportCoordinator {
    private let exportService: ResumeExportService
    private var exportWorkItem: DispatchWorkItem?

    func debounceExport(
        resume: Resume,
        onStart: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        // Move implementation here
    }
}

// Usage in ViewModel
class ResumeDetailVM {
    private let exportCoordinator: ResumeExportCoordinator

    func refreshPDF() {
        exportCoordinator.debounceExport(resume: resume)
    }
}
```

**Priority:** Medium

---

#### 2. **Legacy JSON Transformation (TreeToJson)** — *Medium, Medium Confidence*
- **File:** Resume.swift:84-92
- **Phase:** Phase 4 (JSON and Template Context Modernization)
- **Code Excerpt:**
```swift
var jsonTxt: String {
    guard let myRoot = rootNode, let builder = TreeToJson(rootNode: myRoot) else { return "" }
    // Build via JSONSerialization for correctness
    if let context = builder.buildContextDictionary(),
       let data = try? JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted]) {
        return String(data: data, encoding: .utf8) ?? ""
    }
    return ""
}
```

- **Why it matters:** Phase 4 calls for removing `TreeToJson` in favor of a unified `ResumeTemplateDataBuilder` that maps TreeNode → template context. This computed property should delegate to the new builder.

- **Recommendation:**
  - **Primary:** Replace `TreeToJson` usage with `ResumeTemplateDataBuilder.buildContextDictionary(from: TreeNode)`
  - Update Resume model to use the new builder
  - Remove TreeToJson dependency from Resume.swift
  - **Code Example:**
```swift
var jsonTxt: String {
    guard let myRoot = rootNode else { return "" }
    let builder = ResumeTemplateDataBuilder()
    if let context = builder.buildContextDictionary(from: myRoot),
       let data = try? JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted]) {
        return String(data: data, encoding: .utf8) ?? ""
    }
    return ""
}
```

**Priority:** Medium (Phase 4 alignment)

---

#### 3. **Stale Documentation - LLMService.shared Reference** — *Low, High Confidence*
- **File:** Resume.swift:14-18
- **Phase:** Phase 6 (LLM Facade Documentation)
- **Code Excerpt:**
```swift
@MainActor
func clearConversationContext() {
    // Note: Conversation management now handled by LLMService.shared
    Logger.debug("Resume conversation context clear requested - handled by LLMService")
}
```

- **Why it matters:** Comment references `.shared` singleton pattern that was removed in Phase 6. Misleading documentation can confuse future developers about the actual architecture.

- **Recommendation:**
  - **Primary:** Update comment to reflect new DI-based LLM facade architecture
  - Consider removing this method entirely if it's no longer used (search codebase for callers)
  - **Code Example:**
```swift
@MainActor
func clearConversationContext() {
    // Note: Conversation management delegated to injected LLMFacade in ViewModels
    Logger.debug("Resume conversation context clear requested - handled by injected LLMFacade")
}
```

**Priority:** Low (documentation only)

---

#### 4. **Weak jobApp Reference** — *Low, Medium Confidence*
- **File:** Resume.swift:67
- **Phase:** Phase 1 (SwiftData Relationships)
- **Code Excerpt:**
```swift
weak var jobApp: JobApp?
```

- **Why it matters:** SwiftData models typically use `@Relationship` for inter-model references. A `weak` reference here may indicate a non-SwiftData pattern or potential lifecycle issue.

- **Recommendation:**
  - **Investigate:** Verify if this should be a SwiftData `@Relationship` instead of weak reference
  - If intentionally weak to avoid retain cycles, document why
  - **Code Example:**
```swift
// If bidirectional relationship needed:
@Relationship(deleteRule: .nullify, inverse: \JobApp.resumes)
var jobApp: JobApp?

// Or document if intentionally weak:
/// Weak reference to parent JobApp to avoid retain cycle in non-SwiftData context
weak var jobApp: JobApp?
```

**Priority:** Low (verify architecture intent)

---

### Problem Areas (hotspots)
- Export logic mixing with model layer (lines 141-216)
- TreeToJson dependency (line 85) - Phase 4 target
- Multiple responsibilities: data, export coordination, rendering coordination

### Objectives Alignment
- **Phase 1 (DI/Lifecycle):** Partial - Model is SwiftData-compliant but contains service logic
- **Phase 4 (JSON Modernization):** Gap - Still uses TreeToJson instead of unified builder
- **Phase 5 (Export Boundaries):** Gap - Export coordination in model layer
- **Phase 6 (LLM Facade):** Mostly aligned - Stale comment needs update
- **Readiness:** `partially_ready` - Needs export extraction and Phase 4 migration

### Suggested Next Steps
- **Quick win (≤4h):** Update stale LLMService.shared comment, verify jobApp relationship
- **Medium (1-3d):** Extract export coordination to dedicated service, migrate to ResumeTemplateDataBuilder
- **Deep refactor (≥1w):** Full Phase 5 export boundary cleanup across Resume-related components

---

## File: `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes/ViewModels/ResumeDetailVM.swift`

**Language:** Swift
**Size/LOC:** 144 LOC
**Summary:** Clean ViewModel for resume editing UI. Excellent DI pattern, proper @MainActor usage, well-separated concerns.

### Quick Metrics
- Longest function: `addChild(to:)` (~20 LOC)
- Max nesting depth: 2
- TODO/FIXME: 0
- Comment ratio: 0.20
- Notable deps: Resume, ResStore, TreeNode

### Top Findings (prioritized)

#### 1. **Excellent DI Implementation** — *Strength, High Confidence*
- **File:** ResumeDetailVM.swift:40-47
- **Phase:** Phase 1 (DI Skeleton)
- **Code Excerpt:**
```swift
// MARK: - Dependencies
private let resStore: ResStore

init(resume: Resume, resStore: ResStore) {
    self.resume = resume
    self.resStore = resStore
}
```

- **Why it matters:** Perfect example of Phase 1 DI objectives. Dependencies explicitly declared, injected via initializer, no hidden singletons.

- **Recommendation:** ✅ **No action needed** - This is the pattern to replicate elsewhere

**Priority:** N/A (positive finding)

---

#### 2. **Proper @MainActor Usage** — *Strength, High Confidence*
- **File:** ResumeDetailVM.swift:15-16
- **Phase:** Phase 6 (@MainActor Hygiene)
- **Code Excerpt:**
```swift
@Observable
@MainActor
final class ResumeDetailVM {
```

- **Why it matters:** Class-level @MainActor annotation is appropriate for a ViewModel that manages UI state. All methods safely access main-actor-isolated properties.

- **Recommendation:** ✅ **No action needed** - Correct pattern for UI-layer ViewModels

**Priority:** N/A (positive finding)

---

### Problem Areas (hotspots)
- None identified - This is a model implementation

### Objectives Alignment
- **Phase 1 (DI):** ✅ Complete - Perfect DI implementation
- **Phase 2 (Safety):** ✅ Complete - No force-unwraps, safe optionals
- **Phase 6 (@MainActor):** ✅ Complete - Proper main actor annotation
- **Readiness:** `ready` - Production-quality ViewModel

### Suggested Next Steps
- **Quick win:** Use as reference implementation for other ViewModels
- **Pattern to replicate:** DI constructor, explicit dependencies, @MainActor annotation

---

## File: `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes/ViewModels/ResumePDFViewModel.swift`

**Language:** Swift
**Size/LOC:** 29 LOC
**Summary:** Minimal ViewModel for PDF display. Clean and focused.

### Quick Metrics
- Longest function: `updateResume(_:)` (~3 LOC)
- Max nesting depth: 1
- TODO/FIXME: 0
- Comment ratio: 0.10
- Notable deps: Resume

### Top Findings (prioritized)

#### 1. **Simple, Focused ViewModel** — *Strength, High Confidence*
- **File:** ResumePDFViewModel.swift:11-28
- **Phase:** Phase 1 (DI/Clean Architecture)
- **Code Excerpt:**
```swift
@Observable
@MainActor
final class ResumePDFViewModel {
    private(set) var resume: Resume
    var isUpdating: Bool = false

    init(resume: Resume) {
        self.resume = resume
    }
```

- **Why it matters:** Demonstrates Single Responsibility Principle perfectly. Manages only PDF display state, nothing else.

- **Recommendation:** ✅ **No action needed** - Exemplary focused ViewModel

**Priority:** N/A (positive finding)

---

### Objectives Alignment
- **Phase 1 (DI):** ✅ Complete
- **Phase 6 (@MainActor):** ✅ Complete
- **Readiness:** `ready`

---

## File: `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes/AI/Services/ResumeReviseViewModel.swift`

**Language:** Swift
**Size/LOC:** 1,141 LOC
**Summary:** Complex ViewModel orchestrating resume revision workflow with LLM. Successfully migrated to LLMFacade (Phase 6), proper DI, but contains NotificationCenter usage and some UI coordination concerns.

### Quick Metrics
- Longest function: `startFreshRevisionWorkflow(resume:modelId:)` (~135 LOC)
- Max nesting depth: 4
- TODO/FIXME: 0
- Comment ratio: 0.12
- Notable deps: LLMFacade (injected), AppState, ResumeApiQuery, ProposedRevisionNode

### Top Findings (prioritized)

#### 1. **LLM Facade Successfully Integrated** — *Strength, High Confidence*
- **File:** ResumeReviseViewModel.swift:18-20
- **Phase:** Phase 6 (LLM Facade Migration)
- **Code Excerpt:**
```swift
// MARK: - Dependencies
private let llm: LLMFacade
let appState: AppState

init(llmFacade: LLMFacade, appState: AppState) {
    self.llm = llmFacade
    self.appState = appState
```

- **Why it matters:** Perfect Phase 6 compliance. No `.shared` singleton usage, LLMFacade properly injected via DI.

- **Recommendation:** ✅ **No action needed** - This is the target pattern

**Priority:** N/A (positive finding)

---

#### 2. **NotificationCenter for Sheet Coordination** — *Medium, High Confidence*
- **File:** ResumeReviseViewModel.swift:23-34
- **Phase:** Phase 8 (NotificationCenter Boundaries)
- **Code Excerpt:**
```swift
var showResumeRevisionSheet: Bool = false {
    didSet {
        Logger.debug("🔍 [ResumeReviseViewModel] showResumeRevisionSheet changed from \(oldValue) to \(showResumeRevisionSheet)")
        if showResumeRevisionSheet {
            Logger.debug("🔍 [ResumeReviseViewModel] Posting showResumeRevisionSheet notification")
            NotificationCenter.default.post(name: .showResumeRevisionSheet, object: nil)
        } else {
            Logger.debug("🔍 [ResumeReviseViewModel] Posting hideResumeRevisionSheet notification")
            NotificationCenter.default.post(name: .hideResumeRevisionSheet, object: nil)
        }
    }
}
```

- **Why it matters:** Phase 8 calls for minimizing NotificationCenter to menu/toolbar bridging and documenting UI sheet toggles. This appears to be sheet coordination - verify if SwiftUI binding would work instead.

- **Recommendation:**
  - **Investigate:** Check if sheet can be driven directly by `@Environment` binding to this ViewModel
  - If NotificationCenter is needed for menu/toolbar → view coordination, document the purpose
  - Consider `@FocusedBinding` for macOS menu integration
  - **Code Example:**
```swift
// If this ViewModel is in @Environment, sheets can bind directly:
// In View:
.sheet(isPresented: $viewModel.showResumeRevisionSheet) { ... }

// Or document if NC is needed:
/// Posts notification for menu bar integration (NC required for macOS menu → view coordination)
var showResumeRevisionSheet: Bool = false {
    didSet {
        // Documented use case: Menu command cannot access SwiftUI environment
        NotificationCenter.default.post(name: .showResumeRevisionSheet, object: nil)
    }
}
```

**Priority:** Medium (Phase 8 alignment)

---

#### 3. **Complex Multi-Step Workflow Logic** — *Observation, Medium Confidence*
- **File:** ResumeReviseViewModel.swift:106-244
- **Phase:** General Architecture
- **Code Excerpt:**
```swift
func startFreshRevisionWorkflow(
    resume: Resume,
    modelId: String
) async throws {
    // Reset UI state
    resumeRevisions = []
    feedbackNodes = []
    currentRevisionNode = nil
    currentFeedbackNode = nil
    aiResubmit = false
    isProcessingRevisions = true

    do {
        // Create query for revision workflow
        let query = ResumeApiQuery(resume: resume, saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts"))

        // Start conversation with system prompt and user query
        let systemPrompt = query.genericSystemMessage.textContent
        let userPrompt = await query.wholeResumeQueryString()

        // Check if model supports reasoning for streaming
        let model = appState.openRouterService.findModel(id: modelId)
        let supportsReasoning = model?.supportsReasoning ?? false

        // ... 120 more lines ...
```

- **Why it matters:** This 135-line method orchestrates streaming, reasoning UI, JSON parsing, and validation. While functional, it's at the edge of Single Responsibility.

- **Recommendation:**
  - **Consider:** Extracting sub-workflows into private methods:
    - `configureReasoningStream(modelId:)`
    - `executeStreamingRevision(systemPrompt:userPrompt:modelId:)`
    - `executeNonStreamingRevision(systemPrompt:userPrompt:modelId:)`
  - Keep orchestration in `startFreshRevisionWorkflow`, but delegate details
  - **Not urgent** - Current implementation is comprehensible, just dense

**Priority:** Low (code organization, not a bug)

---

#### 4. **UserDefaults Direct Access** — *Low, Medium Confidence*
- **File:** ResumeReviseViewModel.swift:121, 150, 297, 566
- **Phase:** Phase 3 (Configuration)
- **Code Excerpt:**
```swift
let query = ResumeApiQuery(resume: resume, saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts"))
// ...
let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
```

- **Why it matters:** Phase 3 introduces `AppConfig` for non-secret configuration. Direct UserDefaults access scatters config logic.

- **Recommendation:**
  - **Primary:** Create `DebugConfig` or `LLMConfig` to centralize these settings
  - Inject via AppState or dedicated config object
  - **Code Example:**
```swift
// In AppConfig or LLMConfig
struct LLMConfig {
    static let saveDebugPrompts: Bool = UserDefaults.standard.bool(forKey: "saveDebugPrompts")
    static let reasoningEffort: String = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
}

// Usage
let query = ResumeApiQuery(resume: resume, saveDebugPrompt: LLMConfig.saveDebugPrompts)
```

**Priority:** Low (Phase 3 alignment, not critical)

---

### Problem Areas (hotspots)
- Long `startFreshRevisionWorkflow` method (135 LOC) - consider decomposition
- NotificationCenter usage for sheet coordination (lines 23-34) - Phase 8 concern
- Multiple UserDefaults direct accesses - Phase 3 opportunity
- Complex state management across multiple rounds of revision

### Objectives Alignment
- **Phase 1 (DI):** ✅ Complete - LLMFacade and AppState properly injected
- **Phase 2 (Safety):** ✅ Complete - Safe optional handling throughout
- **Phase 6 (LLM Facade):** ✅ Complete - Excellent integration, streaming support
- **Phase 8 (NC Boundaries):** Gap - NotificationCenter usage needs documentation/review
- **Readiness:** `ready` - Minor polish items only

### Suggested Next Steps
- **Quick win (≤4h):** Document NotificationCenter usage purpose, centralize UserDefaults access
- **Medium (1-3d):** Decompose long orchestration methods into focused helpers

---

## File: `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes/AI/Services/ResumeReviewService.swift`

**Language:** Swift
**Size/LOC:** 548 LOC
**Summary:** Service for resume review operations. Properly uses injected LLMFacade, good @MainActor discipline. Has singleton dependency on ImageConversionService.

### Quick Metrics
- Longest function: `sendFixFitsRequest(...)` (~85 LOC)
- Max nesting depth: 4
- TODO/FIXME: 0
- Comment ratio: 0.15
- Notable deps: LLMFacade (injected), ResumeReviewQuery, ImageConversionService.shared (singleton)

### Top Findings (prioritized)

#### 1. **LLM Facade Properly Injected** — *Strength, High Confidence*
- **File:** ResumeReviewService.swift:13-24
- **Phase:** Phase 6 (LLM Facade)
- **Code Excerpt:**
```swift
/// Service for handling resume review operations with LLM
class ResumeReviewService: @unchecked Sendable {
    // MARK: - Properties

    /// The LLM service for AI operations
    private let llm: LLMFacade

    /// Initialize with LLM service
    init(llmFacade: LLMFacade) {
        self.llm = llmFacade
    }
```

- **Why it matters:** Perfect Phase 6 compliance. No hidden globals, clean DI.

- **Recommendation:** ✅ **No action needed** - Reference implementation

**Priority:** N/A (positive finding)

---

#### 2. **Singleton Dependency on ImageConversionService** — *High, High Confidence*
- **File:** ResumeReviewService.swift:65, 191
- **Phase:** Phase 1/6 (DI, Eliminate Singletons)
- **Code Excerpt:**
```swift
if let base64Image = ImageConversionService.shared.convertPDFToBase64Image(pdfData: pdfData),
```

- **Why it matters:** Phase 1 and 6 explicitly call for eliminating `.shared` singletons in favor of DI. This creates a hidden dependency that makes testing harder and violates DI principles.

- **Recommendation:**
  - **Primary:** Inject `ImageConversionService` via initializer
  - Update all call sites to pass injected instance
  - **Code Example:**
```swift
class ResumeReviewService: @unchecked Sendable {
    private let llm: LLMFacade
    private let imageConversion: ImageConversionService

    init(llmFacade: LLMFacade, imageConversion: ImageConversionService) {
        self.llm = llmFacade
        self.imageConversion = imageConversion
    }

    // Usage:
    if let base64Image = imageConversion.convertPDFToBase64Image(pdfData: pdfData)
```

**Priority:** High (Phase 1/6 compliance, testability)

---

#### 3. **@MainActor Methods Without Class-Level Annotation** — *Medium, Medium Confidence*
- **File:** ResumeReviewService.swift:30-34, 45-114, etc.
- **Phase:** Phase 6 (@MainActor Hygiene)
- **Code Excerpt:**
```swift
/// Initialize the LLM client
@MainActor
func initialize() {
    // No longer needed - LLMService manages its own initialization
    Logger.debug("ResumeReviewService: Initialization delegated to LLMService")
}

@MainActor
func sendReviewRequest(
    reviewType: ResumeReviewType,
```

- **Why it matters:** Service has many @MainActor methods but is not @MainActor class. Phase 6 calls for narrow @MainActor: keep only UI entry points main-isolated, run network/parse on background.

- **Recommendation:**
  - **Investigate:** Determine which methods actually need @MainActor
  - Network operations should run off main thread
  - Only final UI callbacks need @MainActor
  - **Code Example:**
```swift
// Remove @MainActor from class and most methods
class ResumeReviewService {

    // Only entry points from UI keep @MainActor
    @MainActor
    func sendReviewRequest(...) {
        Task {
            // Heavy work happens in background
            let result = await performReviewInBackground(...)
            // Return to main for UI callback
            await MainActor.run {
                onComplete(result)
            }
        }
    }

    // Background work without @MainActor
    private func performReviewInBackground(...) async throws -> String {
        // Network and processing here
    }
}
```

**Priority:** Medium (Phase 6 alignment, performance)

---

#### 4. **Dead `initialize()` Method** — *Low, High Confidence*
- **File:** ResumeReviewService.swift:30-34
- **Phase:** Code Cleanup
- **Code Excerpt:**
```swift
/// Initialize the LLM client
@MainActor
func initialize() {
    // No longer needed - LLMService manages its own initialization
    Logger.debug("ResumeReviewService: Initialization delegated to LLMService")
}
```

- **Why it matters:** Method does nothing and says it's no longer needed. Dead code should be removed.

- **Recommendation:**
  - **Primary:** Search codebase for callers of `initialize()`
  - If none found, delete this method
  - If callers exist, remove the calls and then delete method

**Priority:** Low (cleanup)

---

### Problem Areas (hotspots)
- `ImageConversionService.shared` singleton usage (lines 65, 191) - Phase 1/6 violation
- Excessive @MainActor on service methods - Phase 6 suggests background work
- Long `sendFixFitsRequest` method (85 LOC) - consider decomposition
- Dead `initialize()` method

### Objectives Alignment
- **Phase 1 (DI):** Partial - LLMFacade injected, but ImageConversionService is singleton
- **Phase 6 (LLM Facade):** ✅ Complete for LLM, but @MainActor overused
- **Readiness:** `partially_ready` - Need to inject ImageConversionService, review @MainActor

### Suggested Next Steps
- **Quick win (≤4h):** Delete dead `initialize()` method, review @MainActor necessity
- **Medium (1-3d):** Inject ImageConversionService via DI, move network work off main thread

---

## File: `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes/AI/Services/ReorderSkillsService.swift`

**Language:** Swift
**Size/LOC:** 188 LOC
**Summary:** Service for skill reordering workflow. Clean architecture, properly depends on ResumeReviewService.

### Quick Metrics
- Longest function: `generateOrderingMessages(...)` (~80 LOC)
- Max nesting depth: 3
- TODO/FIXME: 0
- Comment ratio: 0.10
- Notable deps: ResumeReviewService (injected), Resume, AppState

### Top Findings (prioritized)

#### 1. **Good DI Pattern** — *Strength, High Confidence*
- **File:** ReorderSkillsService.swift:11-16
- **Phase:** Phase 1 (DI)
- **Code Excerpt:**
```swift
@MainActor
class ReorderSkillsService {
    private let reviewService: ResumeReviewService

    init(reviewService: ResumeReviewService) {
        self.reviewService = reviewService
    }
```

- **Why it matters:** Clean dependency injection, no hidden singletons.

- **Recommendation:** ✅ **No action needed**

**Priority:** N/A (positive finding)

---

#### 2. **AppState Passed as Parameter** — *Low, Low Confidence*
- **File:** ReorderSkillsService.swift:18-23
- **Phase:** Phase 1 (DI)
- **Code Excerpt:**
```swift
func performReorderSkills(
    resume: Resume,
    selectedModel: String,
    appState: AppState,
    onStatusUpdate: @escaping (ReorderSkillsStatus) -> Void
) async -> Result<String, Error> {
```

- **Why it matters:** AppState is passed as parameter but only forwarded to reviewService. Consider if this indicates missing dependency injection.

- **Recommendation:**
  - **Investigate:** Check if AppState is actually used in this service or just passed through
  - If only passed through, remove from signature and inject into ResumeReviewService instead
  - **Not urgent** - Current implementation works, just may be over-parameterized

**Priority:** Low (architecture cleanup)

---

### Objectives Alignment
- **Phase 1 (DI):** ✅ Complete
- **Phase 2 (Safety):** ✅ Complete
- **Readiness:** `ready`

---

## File: `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes/AI/Services/FixOverflowService.swift`

**Language:** Swift
**Size/LOC:** 369 LOC
**Summary:** Service for iterative overflow fixing. Good architecture, proper DI, singleton dependency on ImageConversionService.

### Quick Metrics
- Longest function: `performFixOverflow(...)` (~160 LOC)
- Max nesting depth: 4
- TODO/FIXME: 0
- Comment ratio: 0.12
- Notable deps: ResumeReviewService (injected), ImageConversionService.shared (singleton)

### Top Findings (prioritized)

#### 1. **ImageConversionService Singleton Usage** — *High, High Confidence*
- **File:** FixOverflowService.swift:51, 298
- **Phase:** Phase 1/6 (DI, No Singletons)
- **Code Excerpt:**
```swift
let currentImageBase64 = ImageConversionService.shared.convertPDFToBase64Image(pdfData: currentPdfData)
// ...
let updatedImageBase64 = ImageConversionService.shared.convertPDFToBase64Image(pdfData: updatedPdfData)
```

- **Why it matters:** Same Phase 1/6 violation as ResumeReviewService. Hidden dependency, harder to test, violates DI principles.

- **Recommendation:**
  - **Primary:** Inject ImageConversionService via initializer
  - **Code Example:**
```swift
@MainActor
class FixOverflowService {
    private let reviewService: ResumeReviewService
    private let imageConversion: ImageConversionService

    init(reviewService: ResumeReviewService, imageConversion: ImageConversionService) {
        self.reviewService = reviewService
        self.imageConversion = imageConversion
    }

    // Usage:
    let currentImageBase64 = imageConversion.convertPDFToBase64Image(pdfData: currentPdfData)
```

**Priority:** High (Phase 1/6 compliance)

---

#### 2. **Large Orchestration Method** — *Low, Medium Confidence*
- **File:** FixOverflowService.swift:19-159
- **Phase:** General Architecture
- **Code Excerpt:**
```swift
func performFixOverflow(
    resume: Resume,
    allowEntityMerge: Bool,
    selectedModel: String,
    maxIterations: Int,
    supportsReasoning: Bool = false,
    onStatusUpdate: @escaping (FixOverflowStatus) -> Void,
    onReasoningUpdate: ((String) -> Void)? = nil
) async -> Result<String, Error> {
    var loopCount = 0
    var operationSuccess = false
    var currentOverflowLineCount = 0
    var statusMessage = ""
    var changeMessage = ""

    Logger.debug("FixOverflow: Starting performFixOverflow with max iterations: \(maxIterations)")

    // ... 140 more lines of loop logic ...
```

- **Why it matters:** 160-line method with complex loop logic. Harder to understand, test, and maintain.

- **Recommendation:**
  - **Consider:** The helper methods (`ensurePDFAvailable`, `getAISuggestions`, `applyChanges`, etc.) are good decomposition
  - Main loop could be further extracted to `performSingleIteration(...)` method
  - **Not urgent** - Helper decomposition already makes this readable

**Priority:** Low (code organization)

---

### Objectives Alignment
- **Phase 1 (DI):** Partial - ReviewService injected, but ImageConversionService is singleton
- **Phase 2 (Safety):** ✅ Complete
- **Readiness:** `partially_ready` - Need ImageConversionService injection

### Suggested Next Steps
- **Quick win (≤4h):** Inject ImageConversionService
- **Medium (1-3d):** Consider extracting iteration logic to separate method for testability

---

## File: `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes/AI/Types/ResumeQuery.swift`

**Language:** Swift
**Size/LOC:** 518 LOC
**Summary:** Query builder for resume revision prompts. Good separation of prompt logic, uses native SwiftOpenAI types directly (not wrapped in facade).

### Quick Metrics
- Longest function: `wholeResumeQueryString()` (~85 LOC)
- Max nesting depth: 2
- TODO/FIXME: 0
- Comment ratio: 0.15
- Notable deps: Resume, Applicant, JSONSchema (SwiftOpenAI)

### Top Findings (prioritized)

#### 1. **Direct SwiftOpenAI Type Usage** — *Observation, Medium Confidence*
- **File:** ResumeQuery.swift:23-122
- **Phase:** Phase 6 (LLM Facade DTOs)
- **Code Excerpt:**
```swift
static let revNodeArraySchema: JSONSchema = {
    // Define the revision node schema
    let revisionNodeSchema = JSONSchema(
        type: .object,
        properties: [
            "id": JSONSchema(
                type: .string,
```

- **Why it matters:** Phase 6 calls for confining vendor types (SwiftOpenAI) to adapter boundaries. This query builder uses `JSONSchema` directly from SwiftOpenAI.

- **Recommendation:**
  - **Investigate:** Verify if query builders are considered "inside the facade boundary" or if JSONSchema should be wrapped
  - If schemas are meant to be internal to facade, current usage is fine
  - If schemas should be in application layer, create `LLMJSONSchema` DTO wrapper
  - **Likely fine as-is** - Query builders are tightly coupled to LLM operations

**Priority:** Low (architecture verification)

---

#### 2. **@Observable Class Without @MainActor** — *Low, Low Confidence*
- **File:** ResumeQuery.swift:13
- **Phase:** Phase 6 (@MainActor)
- **Code Excerpt:**
```swift
@Observable class ResumeApiQuery {
```

- **Why it matters:** @Observable classes are typically for UI-bound state, usually need @MainActor. This class is @Observable but not @MainActor.

- **Recommendation:**
  - **Investigate:** If this class is used in UI bindings, add @MainActor
  - If it's only used in background tasks, @Observable may be unnecessary
  - **Code Example:**
```swift
// If UI-bound:
@Observable @MainActor class ResumeApiQuery {

// If not UI-bound, consider removing @Observable:
class ResumeApiQuery {
```

**Priority:** Low (verify usage pattern)

---

### Objectives Alignment
- **Phase 6 (LLM Types):** Partial - Direct SwiftOpenAI usage, may be acceptable
- **Readiness:** `ready` - Verify architecture intent

---

## File: `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes/AI/Types/ResumeReviewQuery.swift`

**Language:** Swift
**Size/LOC:** 289 LOC
**Summary:** Centralized prompt management for review operations. Clean separation of concerns.

### Quick Metrics
- Longest function: `buildFixFitsPrompt(...)` (~47 LOC)
- Max nesting depth: 2
- TODO/FIXME: 0
- Comment ratio: 0.18
- Notable deps: Resume, ResumeReviewType

### Top Findings (prioritized)

#### 1. **@Observable Without Clear UI Binding** — *Low, Low Confidence*
- **File:** ResumeReviewQuery.swift:12
- **Phase:** Phase 6
- **Code Excerpt:**
```swift
@Observable class ResumeReviewQuery {
```

- **Why it matters:** Same as ResumeApiQuery - @Observable suggests UI binding, but this appears to be a utility class.

- **Recommendation:**
  - **Investigate:** If not used in SwiftUI bindings, remove @Observable
  - If used in UI, add @MainActor

**Priority:** Low (cleanup)

---

### Objectives Alignment
- **Readiness:** `ready` - Minor cleanup opportunity

---

## File: `/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes/AI/Types/ResumeUpdateNode.swift`

**Language:** Swift
**Size/LOC:** 465 LOC
**Summary:** Types for revision workflow (ProposedRevisionNode, FeedbackNode, PostReviewAction). Well-structured with collection extensions for workflow logic.

### Quick Metrics
- Longest function: Collection extension `applyAcceptedChanges(to:)` (~35 LOC)
- Max nesting depth: 4
- TODO/FIXME: 0
- Comment ratio: 0.12
- Notable deps: Resume, TreeNode, Logger

### Top Findings (prioritized)

#### 1. **Good Encapsulation via Extensions** — *Strength, High Confidence*
- **File:** ResumeUpdateNode.swift:358-464
- **Phase:** General Architecture
- **Code Excerpt:**
```swift
// MARK: - Collection Extensions for Review Workflow Logic

extension Array where Element == FeedbackNode {

    /// Apply all accepted changes to the resume
    /// Moved from ReviewView for better encapsulation
    func applyAcceptedChanges(to resume: Resume) {
        Logger.debug("✅ Applying accepted changes to resume")

        let acceptedNodes = filter { $0.shouldBeApplied }
        for node in acceptedNodes {
            node.applyToResume(resume)
        }
```

- **Why it matters:** Excellent use of Swift collection extensions to encapsulate workflow logic. Comments indicate this was intentionally moved from UI layer - good refactoring.

- **Recommendation:** ✅ **No action needed** - This is proper separation of concerns

**Priority:** N/A (positive finding)

---

#### 2. **Potential Main Actor Isolation Issue** — *Medium, Medium Confidence*
- **File:** ResumeUpdateNode.swift:380-396
- **Phase:** Phase 6 (@MainActor)
- **Code Excerpt:**
```swift
// After applying all changes, check for nodes that should be deleted
// Delete any TreeNodes where both name and value are empty
let nodesToDelete = resume.nodes.filter { treeNode in
    let nameIsEmpty = treeNode.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let valueIsEmpty = treeNode.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return nameIsEmpty && valueIsEmpty
}

if !nodesToDelete.isEmpty {
    Logger.debug("🗑️ Deleting \(nodesToDelete.count) empty nodes")
    if let context = resume.modelContext {
        // Ensure deletion happens on main actor for UI coordination
        Task { @MainActor in
            // Batch delete all empty nodes
            for nodeToDelete in nodesToDelete {
                TreeNode.deleteTreeNode(node: nodeToDelete, context: context)
            }
```

- **Why it matters:** Creates Task { @MainActor in } inside a non-@MainActor function. This is async deletion without waiting, which could cause race conditions.

- **Recommendation:**
  - **Primary:** Make the entire `applyAcceptedChanges(to:)` function @MainActor since it modifies SwiftData context
  - Remove inner Task wrapper
  - **Code Example:**
```swift
extension Array where Element == FeedbackNode {
    @MainActor
    func applyAcceptedChanges(to resume: Resume) {
        // ... existing logic ...

        if !nodesToDelete.isEmpty, let context = resume.modelContext {
            // No Task wrapper needed - already on @MainActor
            for nodeToDelete in nodesToDelete {
                TreeNode.deleteTreeNode(node: nodeToDelete, context: context)
            }

            do {
                try context.save()
            } catch {
                Logger.error("Failed to save context: \(error)")
            }
        }
    }
}
```

**Priority:** Medium (concurrency safety)

---

### Objectives Alignment
- **Phase 2 (Safety):** Gap - Potential async/await issue
- **Phase 6 (@MainActor):** Partial - Needs @MainActor annotation
- **Readiness:** `partially_ready` - Fix concurrency issue

### Suggested Next Steps
- **Quick win (≤4h):** Add @MainActor to `applyAcceptedChanges(to:)` and remove Task wrapper

---

## Summary Table: Critical Issues by Priority

| Priority | File | Issue | Phase | Effort |
|----------|------|-------|-------|--------|
| **High** | ResumeReviewService.swift | ImageConversionService.shared singleton | Phase 1/6 | 4-8h |
| **High** | FixOverflowService.swift | ImageConversionService.shared singleton | Phase 1/6 | 2-4h |
| **Medium** | Resume.swift | Export logic in model layer | Phase 5 | 1-2d |
| **Medium** | Resume.swift | TreeToJson usage instead of unified builder | Phase 4 | 4-8h |
| **Medium** | ResumeReviseViewModel.swift | NotificationCenter for sheet coordination | Phase 8 | 4-8h |
| **Medium** | ResumeReviewService.swift | Excessive @MainActor on service methods | Phase 6 | 4-8h |
| **Medium** | ResumeUpdateNode.swift | Missing @MainActor on applyAcceptedChanges | Phase 6 | 2h |
| **Low** | Resume.swift | Stale LLMService.shared comment | Phase 6 | 15m |
| **Low** | ResumeReviewService.swift | Dead initialize() method | Cleanup | 30m |

---

## Shard Summary: Resumes Management Layer

### Files Reviewed: 12

### Worst Offenders (Qualitative):
1. **Resume.swift** - Contains export coordination logic that belongs in service layer, uses legacy TreeToJson
2. **ResumeReviewService.swift** - ImageConversionService.shared singleton, overly broad @MainActor
3. **FixOverflowService.swift** - ImageConversionService.shared singleton

### Thematic Risks:
1. **Singleton Leakage:** `ImageConversionService.shared` used in 3 files - violates Phase 1/6 DI objectives
2. **Export Boundary Blur:** Export logic in Resume model rather than dedicated service (Phase 5 gap)
3. **Phase 4 Migration Incomplete:** TreeToJson still in use instead of unified ResumeTemplateDataBuilder
4. **NotificationCenter Usage:** Sheet coordination may need Phase 8 review/documentation

### Suggested Sequencing:

**Sprint 1 (Quick Wins - 1 day):**
1. Fix stale LLMService.shared comment (15m)
2. Delete dead `initialize()` method (30m)
3. Add @MainActor to `applyAcceptedChanges` (2h)
4. Document NotificationCenter usage purpose (2h)
5. Centralize UserDefaults config access (2h)

**Sprint 2 (DI Cleanup - 2-3 days):**
1. Inject ImageConversionService into ResumeReviewService (4h)
2. Inject ImageConversionService into FixOverflowService (2h)
3. Update all call sites (4h)
4. Verify tests still pass (2h)

**Sprint 3 (Export Boundary - 3-5 days):**
1. Create ResumeExportCoordinator service (1d)
2. Extract debounceExport and ensureFreshRenderedText (1d)
3. Update ViewModels to use coordinator (1d)
4. Test export workflows (1d)

**Sprint 4 (Phase 4 Migration - 2-3 days):**
1. Migrate Resume.jsonTxt to ResumeTemplateDataBuilder (4h)
2. Verify template rendering (4h)
3. Remove TreeToJson dependency if safe (2h)

---

## Final Assessment

**Overall Grade: B+**

The Resumes management layer demonstrates **strong architectural discipline** with successful Phase 6 LLM facade integration, excellent ViewModel patterns, and safe optional handling throughout. The main gaps are:

1. Incomplete DI migration (ImageConversionService singleton)
2. Phase 5 export boundary violations (logic in model)
3. Phase 4 legacy code (TreeToJson)

**Production Readiness:** ✅ **Ready with caveats** - Current code is functional and safe, but architectural improvements would enhance testability and maintainability.

**Recommended Action:** Prioritize **Sprint 1** (quick wins) and **Sprint 2** (DI cleanup) to achieve Phase 1/6 compliance. Sprint 3 and 4 can be deferred to align with broader Phase 4/5 refactoring efforts.

<!-- Progress: 12 / 12 files reviewed in /Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resumes -->
