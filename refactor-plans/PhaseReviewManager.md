# PhaseReviewManager.swift - Refactoring Assessment

**File:** `Sprung/Resumes/AI/Services/PhaseReviewManager.swift`
**Line count:** 1,196
**Date assessed:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`PhaseReviewManager` orchestrates the two-round, manifest-driven AI review workflow for resume customization. At its highest level, a caller invokes `startTwoRoundReview(resume:modelId:)`, the class drives phase 1 and phase 2 LLM calls, presents a review sheet through its `PhaseReviewDelegate`, collects user accept/reject/edit decisions item by item, handles resubmission of rejected items, and finally applies all approved changes back to the `TreeNode` tree.

---

## 2. Distinct Logical Sections

| Lines | MARK / Region | What it does |
|-------|---------------|--------------|
| 9–89 | Architecture comment block | Documents the AI review system design — pattern syntax, phase assignments, export flow. This is documentation, not logic. |
| 96–109 | `PhaseReviewDelegate` protocol | Callback surface to the owning view model (show/hide sheet, set processing state, etc.). |
| 111–158 | Class declaration, stored properties, `init` | Wires up nine injected dependencies. |
| 160–202 | Title Set Constraint helpers | Builds a prompt addendum listing available job-title sets when the review includes `jobTitles` nodes. Three private methods. |
| 204–241 | Tool Response Parsing / Prompt Addendum | `parsePhaseReviewFromResponse(_:)` extracts JSON from a raw LLM string; `buildToolSystemPromptAddendum()` returns a boilerplate string. |
| 243–277 | `mergeOriginalValues(into:from:)` | Post-processes an LLM `PhaseReviewContainer` by back-filling `originalValue`, `originalChildren`, and `sourceNodeIds` from the exported source nodes. |
| 279–438 | `buildReviewRounds(for:)` | Walks the entire `TreeNode` tree and classifies every AI-enabled node into Phase 1 or Phase 2 `ExportedReviewNode` arrays. This is the tree-traversal / export engine. |
| 440–497 | `startTwoRoundReview(resume:modelId:)` | Entry point: resets state, calls `buildReviewRounds`, decides which round to start first. |
| 499–626 | `startRound(nodes:roundNumber:resume:modelId:)` | Constructs prompt, dispatches to the correct LLM path (streaming/reasoning, tool-enabled, or plain structured), merges originals, hands result to `phaseReviewState`. Three fully-implemented LLM dispatch branches. |
| 628–693 | `completeCurrentPhase` / `applyAllChangesAndAdvance` / `advanceToNextRound` | Called when the user finishes reviewing a round. Applies accepted items, checks for resubmission, delegates to next-round or finish. |
| 695–823 | `advanceToNextPhase(resume:)` | A second, partially-duplicated LLM dispatch (same three branches as `startRound`) for advancing within a single phase when the phase config has multiple sub-phases. |
| 825–897 | Item-level decision methods | `acceptCurrentItemAndMoveNext`, `rejectCurrentItemAndMoveNext`, `rejectCurrentItemWithFeedback`, `acceptCurrentItemWithEdits`, `acceptOriginalAndMoveNext`. Each mutates `phaseReviewState.currentReview` and advances the item index. |
| 899–935 | Navigation & computed properties | `goToPreviousItem`, `goToNextItem`, `canGoToPrevious`, `canGoToNext`, `hasItemsNeedingResubmission`, `itemsNeedingResubmission`. |
| 937–1057 | `performPhaseResubmission(resume:originalReview:)` | Third copy of the three-branch LLM dispatch; sends only rejected items back to the LLM and awaits revised proposals. |
| 1059–1109 | `mergeResubmissionResults(_:into:)` | Filters the LLM's revised proposals against the set of actually-rejected IDs, rebuilds `currentReview` with only those items. |
| 1111–1195 | Workflow completion | `finishPhaseReview`, `finalizeWorkflow`, `hasUnappliedApprovedChanges`, `applyApprovedChangesAndClose`, `discardAllAndClose`. |

---

## 3. Single Responsibility Principle Assessment

`PhaseReviewManager` violates SRP. It has **four distinct reasons to change**:

### Reason 1 — Tree traversal / phase classification changes
`buildReviewRounds(for:)` (lines 291–438) is a self-contained tree-walking algorithm. It has no dependency on LLM services, prompt construction, or UI state. If the pattern-matching rules change (e.g., a new wildcard symbol, a new phase-assignment scheme), this function must change — independently of everything else.

### Reason 2 — LLM dispatch strategy changes
The three-branch dispatch block (`supportsReasoning` / `useTools` / plain structured) is copy-pasted verbatim in three methods:
- `startRound` (lines 554–604)
- `advanceToNextPhase` (lines 755–803)
- `performPhaseResubmission` (lines 989–1037)

If the dispatch strategy changes — for example, adding a fourth LLM path — all three blocks must be updated in lockstep. This is a textbook maintenance hazard.

### Reason 3 — User decision / item-navigation changes
The five `acceptCurrentItem*` / `rejectCurrentItem*` methods (lines 828–897) and the `goToPrevious/Next` helpers (899–923) manage purely local `phaseReviewState` mutations. They have no LLM calls and no tree-traversal logic. If the review UX changes (e.g., skip-to-item, bulk-accept), only this group of methods changes.

### Reason 4 — Resubmission result merging changes
`mergeResubmissionResults(_:into:)` (lines 1061–1109) and `mergeOriginalValues(into:from:)` (lines 245–277) are pure data transformation functions. If the schema of `PhaseReviewContainer` or `ExportedReviewNode` changes, these change — independently of LLM dispatch or tree traversal.

### What the class does correctly
The class is not a random grab-bag. All four concerns converge on a single workflow. The `PhaseReviewDelegate` protocol, `phaseReviewState`, and the orchestration in `startTwoRoundReview` / `completeCurrentPhase` / `finishPhaseReview` represent a legitimate orchestration layer. The problem is not that the file exists — it is that too much implementation detail lives inside it.

---

## 4. Recommendation: Split into Four Files

The file should be refactored. The primary drivers are:

1. **Duplicated LLM dispatch** — the three identical `if supportsReasoning / else if useTools / else` blocks total roughly 150 lines of copy-paste. Any change must be made three times.
2. **Testability** — `buildReviewRounds` is a pure(ish) function that should be unit-testable without instantiating nine dependencies.
3. **Size** — 1,196 lines exceeds the practical upper bound for a single-responsibility class; the 500-line guideline in `agents.md` is breached by more than double.

---

## 5. Refactoring Plan

### File 1 (keep): `PhaseReviewManager.swift`

**Purpose:** Orchestrates the two-round review workflow. Owns state, coordinates between the three extracted helpers, and communicates with the delegate.

**Retains:**
- `PhaseReviewDelegate` protocol (lines 97–109)
- Class declaration + stored properties + `init` (lines 112–158)
- `isHierarchicalReviewActive` computed property (line 132–134)
- `phase1Completed`, `cachedPhase2Nodes` (lines 441–444)
- `startTwoRoundReview(resume:modelId:)` (lines 451–497)
- `startRound(nodes:roundNumber:resume:modelId:)` — caller calls into `PhaseReviewLLMDispatcher` instead of inlining three branches
- `completeCurrentPhase(resume:context:)` (lines 630–677)
- `applyAllChangesAndAdvance` (lines 680–688)
- `advanceToNextRound` (lines 691–693)
- `advanceToNextPhase(resume:)` — delegating LLM dispatch to `PhaseReviewLLMDispatcher`
- `finishPhaseReview(resume:)` (lines 1114–1155)
- `finalizeWorkflow()` (lines 1158–1164)
- `hasUnappliedApprovedChanges()` (lines 1167–1169)
- `applyApprovedChangesAndClose(resume:context:)` (lines 1172–1188)
- `discardAllAndClose()` (lines 1191–1195)

**Post-refactor estimated size:** ~350–400 lines

---

### File 2 (new): `PhaseReviewRoundBuilder.swift`

**Path:** `Sprung/Resumes/AI/Services/PhaseReviewRoundBuilder.swift`

**Purpose:** Owns the tree-walking logic that converts a `Resume`'s `TreeNode` tree into Phase 1 and Phase 2 `ExportedReviewNode` arrays. No LLM knowledge, no UI state.

**Moves from `PhaseReviewManager.swift`:**
- Lines 279–438: entire `buildReviewRounds(for:)` method and its nested helper closures (`phaseFor`, `addToPhase`, `processNode`)

**Type declaration:**

```swift
/// Builds the two-round review node arrays from the Resume's TreeNode tree.
struct PhaseReviewRoundBuilder {
    func buildReviewRounds(for resume: Resume) -> (phase1: [ExportedReviewNode], phase2: [ExportedReviewNode])
}
```

This is a `struct` with no stored state — all inputs come from the `Resume` argument.

**Dependencies:** `TreeNode`, `ExportedReviewNode`, `Resume`, `TemplateManifest.ReviewPhaseConfig`, `Logger`. No `Foundation` framework features beyond what is already imported.

**How `PhaseReviewManager` uses it:**

Replace the current `buildReviewRounds(for:)` call site in `startTwoRoundReview` with:

```swift
let builder = PhaseReviewRoundBuilder()
let (phase1Nodes, phase2Nodes) = builder.buildReviewRounds(for: resume)
```

The method `buildReviewRounds(for:)` is currently called only once in `PhaseReviewManager` (line 468) and referenced nowhere else. Remove it from `PhaseReviewManager` entirely.

**Access level:** `struct` and its one method are `internal` (no change needed from current implicit `internal`).

---

### File 3 (new): `PhaseReviewLLMDispatcher.swift`

**Path:** `Sprung/Resumes/AI/Services/PhaseReviewLLMDispatcher.swift`

**Purpose:** Encapsulates the three-path LLM dispatch (reasoning/streaming, tool-enabled, plain structured) for phase review calls. Eliminates the three copy-pasted blocks in `startRound`, `advanceToNextPhase`, and `performPhaseResubmission`.

**Moves from `PhaseReviewManager.swift`:**
- The repeated `if supportsReasoning / else if useTools / else` blocks from:
  - Lines 552–604 (`startRound`)
  - Lines 753–803 (`advanceToNextPhase`)
  - Lines 987–1037 (`performPhaseResubmission`)
- `buildToolSystemPromptAddendum()` (lines 232–241) — belongs with the tool dispatch path
- `parsePhaseReviewFromResponse(_:)` (lines 207–229) — only used by tool dispatch path

**Type declaration:**

```swift
/// Dispatches a phase review LLM call across the three supported execution paths:
/// reasoning/streaming, tool-enabled, and plain structured.
@MainActor
struct PhaseReviewLLMDispatcher {
    private let llm: LLMFacade
    private let openRouterService: OpenRouterService
    private let streamingService: RevisionStreamingService
    private let toolRunner: ToolConversationRunner
    private let reasoningStreamManager: ReasoningStreamManager

    init(
        llm: LLMFacade,
        openRouterService: OpenRouterService,
        streamingService: RevisionStreamingService,
        toolRunner: ToolConversationRunner,
        reasoningStreamManager: ReasoningStreamManager
    )

    /// Dispatch a review call, returning a parsed PhaseReviewContainer.
    /// Handles all three execution paths internally.
    func dispatch(
        systemPrompt: String,
        userPrompt: String,
        modelId: String,
        conversationId: UUID?,
        resume: Resume,
        isNewConversation: Bool
    ) async throws -> (container: PhaseReviewContainer, conversationId: UUID?)
}
```

The `isNewConversation` flag distinguishes `startRound` (new conversation, needs to store the returned `conversationId`) from `advanceToNextPhase` / `performPhaseResubmission` (continuation, uses existing `conversationId` for reasoning/non-reasoning paths).

**How `PhaseReviewManager` uses it:**

`PhaseReviewManager.init` constructs a `PhaseReviewLLMDispatcher` from its own injected dependencies and stores it. Each of `startRound`, `advanceToNextPhase`, and `performPhaseResubmission` calls `dispatcher.dispatch(...)` and handles only the result, not the routing.

**Access level:** `struct` is `internal`. `dispatch` is `internal`. All three private parsing/addendum helpers stay `private` inside the new file.

---

### File 4 (new): `PhaseReviewItemHandler.swift`

**Purpose:** Contains the item-level user decision methods and navigation helpers that mutate `PhaseReviewState`. These have zero LLM involvement and zero tree-traversal logic.

**Path:** `Sprung/Resumes/AI/Services/PhaseReviewItemHandler.swift`

**Moves from `PhaseReviewManager.swift`:**

| Lines | Method |
|-------|--------|
| 828–840 | `acceptCurrentItemAndMoveNext(resume:context:)` |
| 843–852 | `rejectCurrentItemAndMoveNext()` |
| 855–865 | `rejectCurrentItemWithFeedback(_:)` |
| 867–882 | `acceptCurrentItemWithEdits(_:editedChildren:resume:context:)` |
| 884–897 | `acceptOriginalAndMoveNext(resume:context:)` |
| 902–905 | `goToPreviousItem()` |
| 907–912 | `goToNextItem()` |
| 914–923 | `canGoToPrevious`, `canGoToNext` computed properties |
| 925–935 | `hasItemsNeedingResubmission`, `itemsNeedingResubmission` computed properties |
| 243–277 | `mergeOriginalValues(into:from:)` — pure data transform, no LLM dependency |
| 1061–1109 | `mergeResubmissionResults(_:into:)` — pure data transform |

**Type declaration:**

```swift
/// Handles item-level decisions and navigation within a phase review round.
/// All methods operate on PhaseReviewState and have no LLM or tree-traversal dependencies.
@MainActor
struct PhaseReviewItemHandler {
    // No stored state — all mutations are performed on the inout PhaseReviewState.

    func acceptCurrentItem(in state: inout PhaseReviewState, resume: Resume, context: ModelContext) -> Bool
    func rejectCurrentItem(in state: inout PhaseReviewState)
    func rejectCurrentItemWithFeedback(_ feedback: String, in state: inout PhaseReviewState)
    func acceptCurrentItemWithEdits(_ editedValue: String?, editedChildren: [String]?, in state: inout PhaseReviewState, resume: Resume, context: ModelContext) -> Bool
    func acceptOriginal(in state: inout PhaseReviewState, resume: Resume, context: ModelContext) -> Bool
    func goToPrevious(in state: inout PhaseReviewState)
    func goToNext(in state: inout PhaseReviewState)
    func canGoToPrevious(in state: PhaseReviewState) -> Bool
    func canGoToNext(in state: PhaseReviewState) -> Bool
    func hasItemsNeedingResubmission(in state: PhaseReviewState) -> Bool
    func itemsNeedingResubmission(in state: PhaseReviewState) -> [PhaseReviewItem]
    func mergeOriginalValues(into container: PhaseReviewContainer, from nodes: [ExportedReviewNode]) -> PhaseReviewContainer
    func mergeResubmissionResults(_ resubmission: PhaseReviewContainer, into original: PhaseReviewContainer) -> PhaseReviewContainer
}
```

The return `Bool` on accept/reject methods signals whether the phase is now complete (so `PhaseReviewManager` can call `completeCurrentPhase`).

**How `PhaseReviewManager` uses it:**

`PhaseReviewManager` stores an `itemHandler = PhaseReviewItemHandler()`. Its own public `acceptCurrentItemAndMoveNext(resume:context:)` etc. become thin one-liners:

```swift
func acceptCurrentItemAndMoveNext(resume: Resume, context: ModelContext) {
    let phaseComplete = itemHandler.acceptCurrentItem(in: &phaseReviewState, resume: resume, context: context)
    if phaseComplete {
        completeCurrentPhase(resume: resume, context: context)
    }
}
```

The `mergeOriginalValues` and `mergeResubmissionResults` calls inside `startRound`, `advanceToNextPhase`, and `performPhaseResubmission` delegate to `itemHandler`.

**Access level:** All methods `internal`.

---

### Title Set Constraint Helpers — Stay in `PhaseReviewManager`

Lines 160–202 (`titleSetsConstraint(for:)`, `titleSetsConstraint(forReviewIn:)`, `buildTitleSetsConstraintString()`) are prompt construction helpers that depend on `TitleSetStore`, which is a dependency of `PhaseReviewManager`. They are called from `startRound` and `performPhaseResubmission` — both of which stay in `PhaseReviewManager` as thin orchestration shells after the refactor. Three private methods totalling ~40 lines do not justify a separate file. They stay.

---

## 6. Dependency / Import Map After Split

| File | Imports | Key Types Used |
|------|---------|----------------|
| `PhaseReviewManager.swift` | Foundation, SwiftUI, SwiftData, SwiftOpenAI | All four extracted types; `Resume`, `PhaseReviewState`, `PhaseReviewDelegate`, `ResumeApiQuery`, `TitleSetStore`, `InferenceGuidanceStore` |
| `PhaseReviewRoundBuilder.swift` | Foundation | `Resume`, `TreeNode`, `ExportedReviewNode`, `TemplateManifest.ReviewPhaseConfig`, `Logger` |
| `PhaseReviewLLMDispatcher.swift` | Foundation, SwiftOpenAI | `LLMFacade`, `OpenRouterService`, `RevisionStreamingService`, `ToolConversationRunner`, `ReasoningStreamManager`, `PhaseReviewContainer`, `ResumeApiQuery`, `LLMError`, `Logger` |
| `PhaseReviewItemHandler.swift` | Foundation, SwiftData | `PhaseReviewState`, `PhaseReviewContainer`, `PhaseReviewItem`, `ExportedReviewNode`, `Resume`, `ModelContext`, `Logger` |

No types need access-level changes. All extracted types are `internal` structs with `internal` methods, which matches the existing `internal` access of the methods they absorb.

---

## 7. File Size Projections After Split

| File | Estimated Lines |
|------|----------------|
| `PhaseReviewManager.swift` (trimmed) | ~380 |
| `PhaseReviewRoundBuilder.swift` | ~170 |
| `PhaseReviewLLMDispatcher.swift` | ~220 |
| `PhaseReviewItemHandler.swift` | ~200 |
| **Total** | ~970 |

(Net reduction of ~225 lines from elimination of duplicated LLM dispatch.)

---

## 8. Migration Steps (Order Matters)

1. Create `PhaseReviewRoundBuilder.swift`. Cut `buildReviewRounds(for:)` and its nested closures verbatim. Add `struct PhaseReviewRoundBuilder` wrapper. Build to confirm.
2. Create `PhaseReviewItemHandler.swift`. Cut item-level methods and both merge helpers. Build.
3. Create `PhaseReviewLLMDispatcher.swift`. Extract and unify the three LLM dispatch blocks into `dispatch(...)`. Build.
4. Update `PhaseReviewManager.swift`: remove extracted methods, add stored `itemHandler` and `dispatcher`, and update call sites to delegate.
5. Final build. Grep for any remaining references to the deleted method bodies (there should be none — `buildReviewRounds` has exactly one call site).

---

## 9. What Should NOT Change

- The `PhaseReviewDelegate` protocol stays in `PhaseReviewManager.swift` — it is the public contract between this cluster of files and the view model, and that contract belongs with the orchestrator.
- The architecture comment block (lines 9–89) stays in `PhaseReviewManager.swift`. It documents the system design, not any particular extracted file.
- `phaseReviewState: PhaseReviewState` stays owned by `PhaseReviewManager`. The extracted structs operate on it via parameters, not by owning it.
