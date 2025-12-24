# Core Features Refactoring Plan

## Executive Summary

This plan addresses architectural issues across all non-onboarding modules identified in the Gemini analysis: `Shared/`, `Resumes/`, `SearchOps/`, `Experience/`, `Export/`, `ResumeTree/`, and `Templates/`. The codebase shows incomplete migrations, duplicate definitions, and architectural inconsistencies between modules.

**Core Principles:**
- Complete implementation only - no stubs, no empty methods
- No backwards compatibility shims - delete legacy code entirely
- Full adoption of new paradigms - eliminate all duplicate definitions
- Harmonize architecture across modules (eliminate Store vs Coordinator split)
- Regular commits after each discrete unit of work

---

## Parallel Work Streams

The refactoring is organized into **5 independent work streams** that can execute concurrently, plus a **final integration stream**.

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              PARALLEL EXECUTION PHASE                                        │
├─────────────────┬─────────────────┬─────────────────┬─────────────────┬─────────────────────┤
│   Stream A      │   Stream B      │   Stream C      │   Stream D      │   Stream E          │
│   SearchOps     │   Resume        │   LLM Layer     │   TreeNode      │   Export &          │
│   Cleanup       │   Services      │   Consolidation │   Refactor      │   Safety            │
│   (2 agents)    │   (2 agents)    │   (1 agent)     │   (2 agents)    │   (1 agent)         │
└────────┬────────┴────────┬────────┴────────┬────────┴────────┬────────┴───────────┬─────────┘
         │                 │                 │                 │                     │
         └─────────────────┴─────────────────┴─────────────────┴─────────────────────┘
                                             │
                                             ▼
                           ┌───────────────────────────────────┐
                           │   Stream F: Integration           │
                           │   Final verification & build      │
                           │   (1 agent)                       │
                           └───────────────────────────────────┘
```

---

## Stream A: SearchOps Tool Cleanup

**Agents Required:** 2 (one for schema migration, one for coordinator cleanup)
**Dependencies:** None
**Scope:** `Sprung/SearchOps/`

### A1: Delete Hardcoded Static Tool Schemas

**Agent A1 Assignment:**

**Problem:** Tools are defined TWICE:
1. `SearchOpsToolSchemas.swift` loads schemas from JSON via `SchemaLoader`
2. `SearchOpsToolExecutor.swift` has massive `buildAllToolsStatic()` with hardcoded schemas

The executor uses hardcoded static methods, making JSON files dead code.

**Task 1: Verify SchemaLoader Works**
- **File:** `Sprung/SearchOps/Tools/Schemas/SearchOpsToolSchemas.swift`
- Ensure `SchemaLoader` correctly loads all tool schemas from JSON resources
- Test that loaded schemas match the static definitions
- **Commit:** "Verify SearchOpsToolSchemas loads correctly from JSON"

**Task 2: Update SearchOpsToolExecutor to Use Loaded Schemas**
- **File:** `Sprung/SearchOps/Tools/SearchOpsToolExecutor.swift`
- **Implementation:**
  ```swift
  // BEFORE
  static func buildAllToolsStatic() -> [ChatCompletionTool] { ... }  // 200+ lines

  // AFTER
  func buildAllTools() -> [ChatCompletionTool] {
      return SearchOpsToolSchemas.allTools  // Use pre-loaded schemas
  }
  ```
- Update all callers to use instance method with loaded schemas
- **Commit:** "Update SearchOpsToolExecutor to use SchemaLoader schemas"

**Task 3: Delete All Static Builder Methods**
- **File:** `Sprung/SearchOps/Tools/SearchOpsToolExecutor.swift`
- **DELETE:** All methods matching pattern `build*ToolStatic()`
  - `buildGenerateDailyTasksToolStatic()`
  - `buildSearchJobsToolStatic()`
  - All other static tool builders (~200 lines of code)
- **Commit:** "Delete all hardcoded static tool builders from SearchOpsToolExecutor"

### A2: Harmonize Coordinator Pattern

**Agent A2 Assignment:**

**Problem:** `SearchOps` uses heavy Coordinator pattern (`SearchOpsCoordinator`, `SearchOpsPipelineCoordinator`) while rest of app uses Store pattern. This creates cognitive dissonance.

**Task 1: Analyze Coordinator Responsibilities**
- **Files:**
  - `Sprung/SearchOps/Services/SearchOpsCoordinator.swift`
  - `Sprung/SearchOps/Services/SearchOpsPipelineCoordinator.swift`
- Document what each coordinator does
- Identify which responsibilities could move to stores
- **Commit:** "Document SearchOps coordinator responsibilities" (optional documentation commit)

**Task 2: Simplify Coordinators to Thin Orchestration**
- Coordinators should only orchestrate store interactions, not contain business logic
- Move business logic to appropriate stores:
  - Task generation logic → `DailyTaskStore`
  - Pipeline logic → `JobSourceStore` or new `PipelineStore`
- **Implementation:**
  ```swift
  // Coordinator becomes thin orchestrator
  @Observable
  final class SearchOpsCoordinator {
      let dailyTaskStore: DailyTaskStore
      let networkingStore: NetworkingContactStore
      // ... other stores

      // Orchestration only - no business logic
      func refreshDailyTasks() async {
          await dailyTaskStore.regenerateTasks()
      }
  }
  ```
- **Commit:** "Simplify SearchOps coordinators to thin orchestration layer"

**Task 3: Update Views to Access Stores via Coordinator**
- Views should access stores through coordinator, not directly mix patterns
- Ensure consistent access pattern across all SearchOps views
- **Commit:** "Standardize SearchOps view access patterns"

---

## Stream B: Resume Service Consolidation

**Agents Required:** 2 (one for service refactoring, one for ViewModel cleanup)
**Dependencies:** None
**Scope:** `Sprung/Resumes/AI/`

### B1: Complete Service Extraction

**Agent B1 Assignment:**

**Problem:** `ResumeReviewService` retains specific networking methods (`sendFixFitsRequest`, `sendReorderSkillsRequest`) that should live in specialized services.

**Task 1: Move Fix Overflow Networking to FixOverflowService**
- **Files:**
  - `Sprung/Resumes/AI/Services/ResumeReviewService.swift`
  - `Sprung/Resumes/AI/Services/FixOverflowService.swift`
- **Implementation:**
  ```swift
  // MOVE from ResumeReviewService.swift to FixOverflowService.swift:
  // - sendFixFitsRequest() method
  // - All supporting prompt construction for fix fits
  // - Response parsing for fix fits

  // FixOverflowService should be self-contained:
  @Observable
  final class FixOverflowService {
      private let llmFacade: LLMFacade

      func sendFixFitsRequest(context: FixOverflowContext) async throws -> FixOverflowResult {
          // Full implementation here - moved from ResumeReviewService
      }
  }
  ```
- **DELETE:** `sendFixFitsRequest` from `ResumeReviewService.swift` entirely
- **Commit:** "Move fix overflow networking entirely to FixOverflowService"

**Task 2: Move Reorder Skills Networking to ReorderSkillsService**
- **Files:**
  - `Sprung/Resumes/AI/Services/ResumeReviewService.swift`
  - `Sprung/Resumes/AI/Services/ReorderSkillsService.swift`
- Same pattern as Task 1:
  - Move `sendReorderSkillsRequest()` and all supporting code
  - Delete from ResumeReviewService
- **Commit:** "Move reorder skills networking entirely to ReorderSkillsService"

**Task 3: Rename ResumeReviewService**
- **File:** `Sprung/Resumes/AI/Services/ResumeReviewService.swift`
- Rename to `GeneralResumeReviewService` to clarify it only handles generic review types (`.assessQuality`, `.assessFit`)
- Update all imports and references
- **Commit:** "Rename ResumeReviewService to GeneralResumeReviewService"

### B2: Slim Down ResumeReviseViewModel

**Agent B2 Assignment:**

**Problem:** `ResumeReviseViewModel` is 300+ lines of pass-through properties and methods.

**Task 1: Identify Direct Manager Access Patterns**
- **File:** `Sprung/Resumes/AI/Services/ResumeReviseViewModel.swift`
- List all pass-through methods to:
  - `NavigationManager`
  - `PhaseReviewManager`
  - `WorkflowOrchestrator`
  - `ToolRunner`

**Task 2: Expose Managers Directly**
- **Implementation:**
  ```swift
  // BEFORE: 50+ pass-through methods
  func moveToNextItem() {
      phaseReviewManager.moveToNextItem()
  }

  // AFTER: Expose managers
  @Observable
  final class ResumeReviseViewModel {
      let navigation: RevisionNavigationManager
      let phaseReview: PhaseReviewManager
      let workflow: WorkflowOrchestrator
      let toolRunner: ToolRunner

      // Only keep methods that genuinely orchestrate multiple managers
  }
  ```
- **Commit:** "Expose managers directly on ResumeReviseViewModel"

**Task 3: Update Views to Use Managers Directly**
- **File:** `Sprung/Resumes/AI/Views/RevisionReviewView.swift` and related views
- Update calls from `viewModel.moveToNextItem()` to `viewModel.phaseReview.moveToNextItem()`
- **Commit:** "Update resume revision views to use managers directly"

**Task 4: Delete All Pass-Through Methods**
- **File:** `Sprung/Resumes/AI/Services/ResumeReviseViewModel.swift`
- Delete ALL methods that simply forward to a single manager
- Only keep methods that:
  - Coordinate multiple managers
  - Transform data between managers
  - Handle complex orchestration
- **Commit:** "Delete pass-through methods from ResumeReviseViewModel"

---

## Stream C: LLM Layer Consolidation

**Agents Required:** 1
**Dependencies:** None
**Scope:** `Sprung/Shared/AI/`

### C1: Rename Internal Services

**Task 1: Rename Underscore-Prefixed Classes**
- **Files:** `Sprung/Shared/AI/Models/Services/LLMService.swift`
- **Problem:** `_LLMService`, `_LLMRequestExecutor`, `_SwiftOpenAIClient` use underscore convention but are not truly private
- **Solution:** Rename to descriptive names:
  - `_LLMService` → `OpenRouterServiceBackend`
  - `_LLMRequestExecutor` → `LLMRequestExecutor` (remove underscore)
  - `_SwiftOpenAIClient` → `SwiftOpenAIClientWrapper`
- Update all references
- **Commit:** "Rename internal LLM service classes to descriptive names"

### C2: Consolidate Response Parsers

**Task 1: Merge Duplicate Parsers**
- **Files:**
  - `Sprung/Shared/AI/Models/Services/LLMResponseParser.swift`
  - `Sprung/Shared/AI/Models/Services/_JSONResponseParser.swift` (or similar)
- **Problem:** Both parse JSON from strings, handling markdown blocks. `_JSONResponseParser` is essentially duplicate.
- **Solution:**
  - Merge all parsing logic into single `LLMResponseParser`
  - Delete `_JSONResponseParser` entirely
- **Implementation:**
  ```swift
  // Single consolidated parser
  struct LLMResponseParser {
      static func extractJSON(from text: String) -> JSON? { ... }
      static func extractJSONArray(from text: String) -> [JSON]? { ... }
      static func parseResponseDTO(from text: String) -> LLMResponseDTO? { ... }
  }
  ```
- **Commit:** "Consolidate response parsers into single LLMResponseParser"

### C3: Consolidate Prompt Builders

**Task 1: Merge Resume Query Types**
- **Files:**
  - `Sprung/Shared/AI/Types/ResumeReviewQuery.swift`
  - `Sprung/Resumes/AI/Types/ResumeApiQuery.swift`
- **Problem:** Both build prompts for resume analysis. `ResumeApiQuery` is "new", `ResumeReviewQuery` is "old".
- **Solution:**
  - Keep `ResumeApiQuery` as the canonical implementation
  - Migrate any unique functionality from `ResumeReviewQuery`
  - Delete `ResumeReviewQuery` entirely
  - Update `ResumeReviewService` (now `GeneralResumeReviewService`) to use `ResumeApiQuery`
- **Commit:** "Consolidate resume prompt builders into ResumeApiQuery"

### C4: Verify OpenAI Backend Usage

**Task 1: Audit OpenAIResponsesConversationService**
- **File:** `Sprung/Shared/AI/Models/Services/OpenAIResponsesConversationService.swift`
- Determine if actually used:
  - Check if "OpenAI Direct" feature is active anywhere
  - Check if `LLMFacade` ever routes to this service
- If not used, delete entirely
- If used, document when/why
- **Commit:** "Remove unused OpenAIResponsesConversationService" or "Document OpenAI direct backend usage"

---

## Stream D: TreeNode Architecture Split

**Agents Required:** 2 (one for model, one for view state)
**Dependencies:** None
**Scope:** `Sprung/ResumeTree/`

### D1: Create TreeNodeViewState

**Agent D1 Assignment:**

**Problem:** `TreeNode` is a "God Class" mixing:
- UI state (`isExpanded`, `includeInEditor`, `status: LeafStatus`)
- Data schema (`schemaValidationRule`)
- Hierarchy (`children`, `parent`)
- Content (`value`)

**Task 1: Define TreeNodeViewState Structure**
- **Create:** `Sprung/ResumeTree/ViewModels/TreeNodeViewState.swift`
- **Implementation:**
  ```swift
  @Observable
  final class TreeNodeViewState {
      let nodeId: UUID  // Links to TreeNode
      var isExpanded: Bool = false
      var isEditing: Bool = false
      var status: LeafStatus = .default
      var includeInEditor: Bool = true

      init(nodeId: UUID) {
          self.nodeId = nodeId
      }
  }

  @Observable
  final class TreeViewStateManager {
      private var states: [UUID: TreeNodeViewState] = [:]

      func state(for node: TreeNode) -> TreeNodeViewState {
          if let existing = states[node.id] {
              return existing
          }
          let newState = TreeNodeViewState(nodeId: node.id)
          states[node.id] = newState
          return newState
      }
  }
  ```
- **Commit:** "Create TreeNodeViewState for transient UI state"

**Task 2: Integrate TreeViewStateManager**
- Inject `TreeViewStateManager` via environment in tree-related views
- Views access UI state through manager, not through TreeNode directly
- **Commit:** "Integrate TreeViewStateManager into resume tree views"

### D2: Clean TreeNode Model

**Agent D2 Assignment:**

**Task 1: Remove UI State from TreeNode**
- **File:** `Sprung/ResumeTree/Models/TreeNodeModel.swift`
- **DELETE:** All UI state properties:
  ```swift
  // DELETE these from TreeNode:
  var isExpanded: Bool  // → TreeNodeViewState
  var isEditing: Bool   // → TreeNodeViewState
  var status: LeafStatus  // → TreeNodeViewState
  var includeInEditor: Bool  // → TreeNodeViewState
  ```
- Keep only persistent data:
  - `id`, `label`, `value`, `children`, `parent`
  - `schemaValidationRule` (data schema)
  - `editorLabel`, `displayLabel` (data, not UI state)
- **Commit:** "Remove UI state properties from TreeNode"

**Task 2: Convert Validation Rule to Enum**
- **File:** `Sprung/ResumeTree/Models/TreeNodeModel.swift`
- **Problem:** `schemaValidationRule` is a String with magic values ("regex", "email", etc.)
- **Solution:** Use existing `Validation.Rule` enum from `TemplateManifest.swift`
- **Implementation:**
  ```swift
  // BEFORE
  var schemaValidationRule: String?
  switch rule {
  case "minLength": ...
  case "regex": ...
  }

  // AFTER
  var validationRule: Validation.Rule?
  switch validationRule {
  case .minLength(let n): ...
  case .regex(let pattern): ...
  }
  ```
- **Commit:** "Convert schemaValidationRule to typed Validation.Rule enum"

**Task 3: Update All TreeNode Consumers**
- Update all views and services that read UI state from TreeNode
- Change to read from `TreeViewStateManager` instead
- **Commit:** "Update all consumers to use TreeViewStateManager for UI state"

---

## Stream E: Export Safety & Cleanup

**Agents Required:** 1
**Dependencies:** None
**Scope:** `Sprung/Export/`, `Sprung/Shared/`

### E1: Fix PDF Generator Safety

**Task 1: Remove Hardcoded Chrome Paths**
- **File:** `Sprung/Export/NativePDFGenerator.swift`
- **Problem:** Hardcoded paths (`/opt/homebrew/bin/chromium`) are brittle and will fail on user machines
- **Solution Options (implement ONE):
  - **Option A:** Bundle Chromium/Headless shell within app
  - **Option B:** Fall back to `WKWebView` PDF export if external Chrome not found
  - **Option C:** Remove Chrome dependency entirely, use only native PDFKit/WKWebView
- **Recommended:** Option B - graceful degradation
- **Implementation:**
  ```swift
  func generatePDF(from html: String) async throws -> Data {
      if let chromePath = findChromeBinary() {
          return try await generateWithChrome(html, path: chromePath)
      } else {
          // Graceful fallback to WKWebView
          return try await generateWithWKWebView(html)
      }
  }

  private func findChromeBinary() -> String? {
      // Check app bundle first
      if let bundledPath = Bundle.main.path(forResource: "chromium", ofType: nil) {
          return bundledPath
      }
      // Then check common locations
      let paths = ["/opt/homebrew/bin/chromium", "/usr/local/bin/chromium"]
      return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
  }
  ```
- **Commit:** "Add graceful fallback for PDF generation when Chrome not available"

**Task 2: Add Error Handling for Missing Chrome**
- Provide clear user feedback when Chrome-quality PDF not possible
- Log which rendering method was used
- **Commit:** "Add user feedback for PDF rendering method"

### E2: Fix Array Bounds Safety

**Task 1: Add Safe Array Indexing**
- **File:** `Sprung/Resumes/AI/Views/PhaseReviewBundledView.swift`
- **Problem:** Binding logic assumes arrays are in sync, can crash with index out of bounds
- **Solution:**
  ```swift
  // BEFORE - unsafe
  get: { return review.items[index] }

  // AFTER - safe with extension
  extension Array {
      subscript(safe index: Index) -> Element? {
          indices.contains(index) ? self[index] : nil
      }
  }

  // Or iterate over Identifiable items instead of indices
  ForEach(review.items) { item in
      // Binding via item.id, not index
  }
  ```
- Prefer Identifiable iteration over index-based binding
- **Commit:** "Fix array bounds safety in PhaseReviewBundledView"

### E3: Consolidate HTML Utilities

**Task 1: Merge HTML/Text Processing Logic**
- **Files:**
  - `Sprung/Shared/Utilities/TextFormatHelpers.swift`
  - `Sprung/Export/NativePDFGenerator.swift` (HTML manipulation methods)
- **Problem:** `stripTags` in TextFormatHelpers duplicates logic in NativePDFGenerator's `fixFontReferences`
- **Solution:**
  - Create `Sprung/Shared/Utilities/HTMLUtility.swift`
  - Move all HTML manipulation:
    - Tag stripping
    - Font reference fixing
    - Attribute cleaning
  - Delete duplicate implementations
- **Commit:** "Consolidate HTML manipulation into HTMLUtility"

### E4: Clean Up Dead Code Candidates

**Task 1: Verify and Remove Unused Code**
- **Files to audit:**
  - `Sprung/Shared/AI/Models/LLM/LLMVendorMapper.swift` - check if `makeImageDetail` used
  - `Sprung/Templates/Utilities/TemplateData/TemplateFilters.swift` - check if `htmlStripFilter` used in templates
  - `Sprung/Shared/UIComponents/WindowDragHandle.swift` - check if used
  - `Sprung/JobApplications/Models/IndeedJobScrape.swift` - check if `importFromIndeed` reachable
- For each:
  1. Grep for usage
  2. If unused, delete entirely
  3. If used, document where
- **Commit:** "Remove verified dead code" (one commit per file or grouped)

---

## Stream F: Integration & Verification

**Agents Required:** 1
**Dependencies:** Streams A-E must complete first
**Scope:** Full codebase

### F1: Cross-Stream Integration

**Task 1: Verify No Orphaned References**
- Grep for any remaining references to deleted code:
  - `buildAllToolsStatic`, `build*ToolStatic`
  - `sendFixFitsRequest`, `sendReorderSkillsRequest` (in ResumeReviewService)
  - `_LLMService`, `_JSONResponseParser`
  - `ResumeReviewQuery` (should only be `ResumeApiQuery`)
  - UI state properties on TreeNode

**Task 2: Verify Import Consistency**
- Ensure all imports updated for renamed files
- No broken imports after file deletions

### F2: Build Verification

```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung build 2>&1 | grep -Ei "(error:|warning:|failed|succeeded)" | head -30
```

### F3: Functional Verification

Test critical paths:
- SearchOps tool execution
- Resume review workflows
- PDF generation (with and without Chrome)
- Tree node editing
- LLM requests via facade

**Commit:** "Complete core features refactoring - verify build and functionality"

---

## Commit Checklist Summary

**Stream A - SearchOps (5 commits):**
- [ ] Verify SearchOpsToolSchemas loads correctly
- [ ] Update SearchOpsToolExecutor to use loaded schemas
- [ ] Delete all hardcoded static tool builders
- [ ] Simplify SearchOps coordinators
- [ ] Standardize SearchOps view access patterns

**Stream B - Resume Services (7 commits):**
- [ ] Move fix overflow networking to FixOverflowService
- [ ] Move reorder skills networking to ReorderSkillsService
- [ ] Rename ResumeReviewService to GeneralResumeReviewService
- [ ] Expose managers directly on ResumeReviseViewModel
- [ ] Update resume revision views to use managers
- [ ] Delete pass-through methods from ResumeReviseViewModel
- [ ] Stream B verification

**Stream C - LLM Layer (4 commits):**
- [ ] Rename internal LLM service classes
- [ ] Consolidate response parsers
- [ ] Consolidate resume prompt builders
- [ ] Remove/document OpenAI backend

**Stream D - TreeNode (5 commits):**
- [ ] Create TreeNodeViewState
- [ ] Integrate TreeViewStateManager
- [ ] Remove UI state from TreeNode
- [ ] Convert schemaValidationRule to enum
- [ ] Update all TreeNode consumers

**Stream E - Export & Safety (5 commits):**
- [ ] Add PDF generation fallback
- [ ] Add user feedback for rendering method
- [ ] Fix array bounds safety
- [ ] Consolidate HTML utilities
- [ ] Remove dead code

**Stream F - Integration (1 commit):**
- [ ] Final integration verification

---

## Success Criteria

The refactoring is complete when:

1. **Zero hardcoded tool schemas** in SearchOpsToolExecutor
2. **All resume services** are self-contained (no cross-service networking)
3. **ResumeReviseViewModel** has fewer than 50 lines of methods (only orchestration)
4. **No underscore-prefixed classes** in LLM layer
5. **No duplicate parsers or query builders**
6. **TreeNode contains only persistent data** (no UI state)
7. **PDF generation gracefully degrades** when Chrome unavailable
8. **No unsafe array indexing** in bindings
9. **All duplicate HTML utilities consolidated**
10. **Build succeeds** with no new warnings
11. **All dead code candidates verified and removed**
