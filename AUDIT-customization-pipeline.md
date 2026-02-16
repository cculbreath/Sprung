# Customization Pipeline Audit Report

**Scope:** TreeNode → RevNode → Customization → Review Loop → Apply
**Date:** 2026-02-15
**Files Analyzed:** 20+

---

## Table of Contents

1. [Pipeline Architecture Overview](#1-pipeline-architecture-overview)
2. [Critical Bugs](#2-critical-bugs)
3. [Dead Code](#3-dead-code)
4. [Redundancy & Duplication](#4-redundancy--duplication)
5. [Over-Abstraction](#5-over-abstraction)
6. [Technical Debt](#6-technical-debt)
7. [Silent Failures & Missing Validation](#7-silent-failures--missing-validation)
8. [Summary Table](#8-summary-table)
9. [Recommended Fix Order](#9-recommended-fix-order)

---

## 1. Pipeline Architecture Overview

```
TreeNode (persistent @Model)
    ↓ exportNodesMatchingPath() / exportSectionAsObject()
ExportedReviewNode (transient value type)
    ↓ RevisionTaskBuilder.buildTasks()
RevisionTask (LLM prompt + metadata)
    ↓ CustomizationParallelExecutor.executeTaskInternal()
ProposedRevisionNode (LLM response)
    ↓ CustomizationReviewQueue.addItem()
PhaseReviewItem (user review)
    ↓ user approve/reject/edit
    ↓ RevisionWorkflowOrchestrator.completeCurrentPhaseAndAdvance()
TreeNode mutation (applied back to resume)
```

**Separate path — Revision Agent (interactive chat):**
```
TreeNode → ResumeRevisionWorkspaceService (ephemeral copy)
    ↓ LLM tool loop (propose_changes / write_json_file / ask_user / complete_revision)
    ↓ User accept/reject proposals
    ↓ buildAndActivateResumeFromWorkspace() → new Resume clone
```

**Key files:**

| Stage | File | Lines |
|-------|------|-------|
| Model | `ResumeTree/Models/TreeNodeModel.swift` | 1,072 |
| Rev Types | `Resumes/AI/Types/ResumeUpdateNode.swift` | 326 |
| Context | `Resumes/AI/Types/CustomizationContext.swift` | ~170 |
| Task Builder | `Resumes/AI/Services/RevisionTaskBuilder.swift` | ~1,070 |
| Executor | `Resumes/AI/Services/CustomizationParallelExecutor.swift` | ~800 |
| Prompt Cache | `Resumes/AI/Services/CustomizationPromptCacheService.swift` | ~780 |
| Orchestrator | `Resumes/AI/Services/RevisionWorkflowOrchestrator.swift` | ~1,125 |
| Review Queue | `Resumes/AI/Services/CustomizationReviewQueue.swift` | ~530 |
| Phase Manager | `Resumes/AI/Services/PhaseReviewManager.swift` | ~240 |
| ViewModel | `Resumes/AI/Services/ResumeReviseViewModel.swift` | ~200 |
| Revision Agent | `Resumes/AI/RevisionAgent/ResumeRevisionAgent.swift` | 1,155 |
| Workspace Svc | `Resumes/AI/RevisionAgent/ResumeRevisionWorkspaceService.swift` | 635 |
| LLM Facade | `Shared/AI/Models/Services/LLMFacade.swift` | ~1,020 |
| LLM Service | `Shared/AI/Models/Services/LLMService.swift` | ~300 |
| Streaming | `Shared/AI/Models/Services/StreamingExecutor.swift` | ~90 |

---

## 2. Critical Bugs

### 2.1 Continuation Leak in Concurrency Limiter

**Files:** `CustomizationParallelExecutor.swift:779-801`, `RevisionWorkflowOrchestrator.swift:149-174`
**Severity:** CRITICAL

The actor-based concurrency limiter uses `withCheckedContinuation` to queue tasks waiting for a slot. If a running task is cancelled or crashes after acquiring a slot but before calling `releaseSlot()`, the continuation is never resumed and remains in the dictionary forever.

```swift
// CustomizationParallelExecutor.swift:779-787
private func waitForSlot() async {
    if runningCount >= maxConcurrent {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let id = UUID()
            continuations[id] = continuation  // leaked if task crashes
        }
    }
    runningCount += 1
}
```

Compounding this, `releaseSlot()` is called via a detached `Task { await self.releaseSlot() }` in the orchestrator (line 174), which may not run if the parent task is cancelled.

**Impact:** Workflow hangs — waiting tasks are never woken. Users must force-quit and restart.

### 2.2 runningCount Can Exceed maxConcurrent

**File:** `CustomizationParallelExecutor.swift:780-786`
**Severity:** CRITICAL

```swift
if runningCount >= maxConcurrent {
    await withCheckedContinuation { ... }  // waits for slot
}
runningCount += 1  // ALWAYS increments, even if we didn't wait
```

The `runningCount += 1` is outside the `if` block. Between the time the condition is checked and the continuation is stored, another task could call `releaseSlot()`, making the slot available. The waiting task resumes, and `runningCount` gets incremented again — exceeding `maxConcurrent`.

**Impact:** More concurrent LLM requests than intended; potential rate limiting or API errors.

### 2.3 Silent Streaming Persistence Failures

**File:** `LLMService.swift:166-168, 279-281`
**Severity:** HIGH

```swift
} catch {
    break  // Silently breaks on streaming error
}
```

When conversation persistence fails during streaming, the error is swallowed. The LLM response is yielded but conversation state is not persisted. Subsequent turns may lose context.

**Impact:** Data loss — conversation history becomes inconsistent, causing degraded LLM responses in multi-turn flows.

### 2.4 Network Errors Masked by JSON Retry Loop

**File:** `CustomizationParallelExecutor.swift:744-748`
**Severity:** HIGH

```swift
} catch {
    lastError = error
    Logger.warning("[ParallelExecutor] LLM call failed on correction attempt \(attempt): \(error.localizedDescription)", category: .ai)
    continue  // retries even for network errors
}
```

Network/API errors are caught in the JSON retry loop and retried up to `maxJSONRetries` times. The final error thrown says "JSON decode failed" when the real issue was a network timeout on attempt 3. Original error context is overwritten by subsequent attempts.

**Impact:** Misleading error messages; unnecessary retries waste time and API credits.

### 2.5 Substring Matching Causes False Positive Category Matches

**File:** `RevisionTaskBuilder.swift:1038-1044`
**Severity:** HIGH

```swift
return allCategories.first {
    name.contains($0.lowercased()) || $0.lowercased().contains(name)
}
```

"JavaScript" matches "Java" because `"javascript".contains("java")` is true. Skills could be assigned to wrong categories, producing incorrect LLM prompts.

**Impact:** Wrong skill categories in prompts, leading to poor customization quality.

---

## 3. Dead Code

### 3.1 `traverseAndExportNodes()` and `collectDescendantValues()`

**File:** `TreeNodeModel.swift:343-430`
**Status:** DEAD — old export system before manifest-driven `ExportedReviewNode` approach
**Only caller:** `Resume.getUpdatableNodes()` which itself has zero callers
**Action:** Delete both methods and `getUpdatableNodes()`

### 3.2 `ProposedRevisionNode` (Legacy)

**File:** `ResumeUpdateNode.swift:11-101`
**Status:** LEGACY — modern flow uses `PhaseReviewItem` exclusively
**Evidence:** Custom decoder with fallbacks for old responses (lines 84-98), complex `originalText()` method (lines 35-68) with debugging iteration
**Action:** Verify no active code paths depend on it, then remove

### 3.3 `messageComplete` Event in RevisionStreamProcessor

**File:** `RevisionStreamProcessor.swift:104-107`, `ResumeRevisionAgent.swift:308-309`
**Status:** DEAD — event is generated but handler is `break` (no-op)
**Token counts are collected but discarded**
**Action:** Remove event generation or implement token tracking

### 3.4 `.compound` Case Returns Empty String

**File:** `CustomizationParallelExecutor.swift:274-277`
**Status:** DEAD PATH — compound tasks use `generateCompoundPrompt()`, never hit this case

```swift
case .compound:
    return ""  // Should never reach here
```

**Action:** Replace with `assertionFailure()` or throw

### 3.5 `toDictionary()` / `toJSONString()` on TreeNode

**File:** `TreeNodeModel.swift:1028-1051`
**Status:** Only used by FixOverflowService and SkillReorderService (edge services, not main pipeline)
**Action:** Review if these services can use the standard export path instead

---

## 4. Redundancy & Duplication

### 4.1 Three Overlapping Node Export Systems

| System | Location | Status |
|--------|----------|--------|
| `traverseAndExportNodes()` | TreeNodeModel.swift:343 | OBSOLETE |
| `exportNodesMatchingPath()` + `exportSectionAsObject()` | TreeNodeModel.swift:606-792 | ACTIVE |
| `ProposedRevisionNode` with oldValue/newValue | ResumeUpdateNode.swift:11-101 | LEGACY COMPAT |

Three ways to represent the same concept. Only the middle one is actively used.

### 4.2 Knowledge Card Filtering Logic Duplicated 3x

The same fallback logic appears in:
- `CustomizationContext.build()` (lines 136-142)
- `CustomizationPromptCacheService.buildVariableContext()` (line 125-126)
- `CustomizationPromptCacheService.buildVariableContext()` again (line 136)

```swift
let cardsForSection = context.allCards.isEmpty ? context.knowledgeCards : context.allCards
```

**Action:** Extract to a single computed property on `CustomizationContext`.

### 4.3 Preamble Construction Duplicated

**File:** `RevisionWorkflowOrchestrator.swift`

Lines 301-305 and 426-430 are identical:
```swift
let corePreamble = cacheService.buildCorePreamble(context: promptContext)
let variableContext = cacheService.buildVariableContext(context: promptContext)
self.cachedCorePreamble = corePreamble
self.cachedPreamble = corePreamble + "\n\n---\n\n" + variableContext
```

**Action:** Extract to `buildAndCachePreamble()`.

### 4.4 Reasoning State Clearing Duplicated

**File:** `RevisionWorkflowOrchestrator.swift:331-334, 449-452`

```swift
if cachedReasoning != nil {
    reasoningStreamManager.clear()
    reasoningStreamManager.isVisible = false
}
```

**Action:** Extract to `clearReasoningState()`.

### 4.5 Duplicate Build/Activate Calls in Revision Agent

**File:** `ResumeRevisionAgent.swift`

`buildAndActivateResumeFromWorkspace()` is called from 4 separate locations (lines 205-206, 367-368, 499-500, 892), with duplicate cancellation guard blocks at lines 202-216 and 364-378.

**Action:** Consolidate into a single cleanup path.

### 4.6 JSON Encoding for Logging Repeated 8x

**File:** `LLMFacade.swift:179, 203, 228, 289, 323, 543, 966`

```swift
let jsonString = (try? JSONEncoder().encode(result))
    .flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: result)
```

**Action:** Extract to `func jsonLogString<T: Encodable>(_ value: T) -> String`.

### 4.7 Duplicate Title Template Parsing

**File:** `TreeNodeModel.swift:299-315` (computedTitle) and `TreeNodeModel.swift:513-547` (makeTemplateClone)

Both parse `schemaTitleTemplate` and substitute `{{fieldName}}` patterns independently.

**Action:** Extract template substitution to a shared helper.

---

## 5. Over-Abstraction

### 5.1 RevisionTaskBuilder Has 10 Parameters

**File:** `RevisionTaskBuilder.swift:30-41`

```swift
func buildTasks(
    from revNodes: [ExportedReviewNode],
    resume: Resume,
    jobDescription: String,
    skills: [Skill],
    titleSets: [TitleSet],
    phase: Int,
    targetingPlan: TargetingPlan? = nil,
    phase1Decisions: String? = nil,
    knowledgeCards: [KnowledgeCard] = [],
    textResumeSnapshot: String? = nil
) -> [RevisionTask]
```

`resume`, `jobDescription`, `skills`, `titleSets`, `knowledgeCards` could be bundled into `CustomizationContext` (which already holds most of these).

### 5.2 ExportedReviewNode Mixes Concerns

Properties mix node metadata (id, path), display data (displayName), content (value, childValues), and UI state flags (isBundled, isMultiAttributeIterate). Has a `withMultiAttributeFlag()` method that creates a full copy just to set one boolean.

### 5.3 TreeNodeModel.swift is 1,072 Lines

Contains 4 extensions adding 300+ lines of export/path logic. Should be split into:
- `TreeNode.swift` — core model
- `TreeNode+Export.swift` — export/path matching
- `TreeNode+Schema.swift` — schema utilities

### 5.4 ResumeUpdateNode.swift Has 6 Types in One File

Contains `ProposedRevisionNode`, `ExportedReviewNode`, `PhaseReviewItem`, `PhaseReviewContainer`, `PhaseReviewState`, `NodeType`. Should be split by active usage.

### 5.5 LLMFacade Exposes 37 Public Methods

The customization pipeline uses only 6 of them. While the facade serves the whole app, the surface area makes it hard to reason about what the pipeline actually needs.

---

## 6. Technical Debt

### 6.1 Manual JSON Escaping

**Files:** `ResumeRevisionAgent.swift:869`, `ProposeChangesTool.swift:98-104`

```swift
return "{\"answer\": \"\(answer.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n"))\"}"
```

Doesn't handle tabs, backslashes, Unicode, or other control chars. Should use `JSONEncoder`/`JSONSerialization`.

### 6.2 Hard-Coded Reasoning Token Budgets

**File:** `StreamingExecutor.swift:16-51`

```swift
private static let effortBudgets: [String: Int] = [
    "minimal": 1024, "low": 4096, "medium": 10000, "high": 25000,
]
```

Model-dependent values that should be looked up from a model capabilities mapping.

### 6.3 "new-" ID Prefix Convention is Fragile

**File:** `ResumeRevisionWorkspaceService.swift:485`

```swift
if nodeId.hasPrefix("new-") {
    // New node — create and add
```

If the LLM uses any other ID format, the change is treated as an existing node lookup (which silently fails or matches wrong nodes). Should validate ID format or use an explicit field.

### 6.4 Orphaned Tool Use Repair is Anthropic-Specific

**File:** `ResumeRevisionAgent.swift:941-1025`

85 lines of intricate logic to handle interrupted Anthropic API streams. While necessary and correct, it's tightly coupled to Anthropic's conversation format. Should be documented as Anthropic-specific with a comment about portability.

### 6.5 Magic Numbers

**File:** `RevisionWorkflowOrchestrator.swift:417, 490`

Hardcoded `8` for bullet limits in two places. Should be `private let maxSuggestedBullets = 8`.

### 6.6 O(n^2) Document ID Lookup

**File:** `CustomizationPromptCacheService.swift:577-589`

```swift
if !titles.contains(card.title) {  // O(n) on every iteration
    titles.append(card.title)
```

Use a `Set<String>` internally, convert to array on return.

### 6.7 Regex Compiled on Every Call

**File:** `RevisionWorkflowOrchestrator.swift:1086-1104`

`parseArrayFromString()` compiles regex `^[•\\-\\*\\d\\.\\)]+\\s*` on every invocation. Should be a static cached pattern.

### 6.8 Dual Execution Paths in ParallelExecutor

**File:** `CustomizationParallelExecutor.swift:273-300`

Two branches — Path A (split preamble with cache_control) and Path B (legacy single-prompt) — coexist. Path B is a fallback when `systemPrompt` is nil. Should migrate all callers to Path A and remove Path B.

### 6.9 No Maximum Regeneration Depth

**File:** `CustomizationReviewQueue.swift:54-55`

`regenerationCount` has no limit enforced. A user could reject the same item 50 times, causing 50 LLM calls. Should cap at ~5 with a "manual edit" suggestion.

### 6.10 Superseded Items Never Cleaned Up

**File:** `CustomizationReviewQueue.swift:175-184`

Superseded items remain in the `items` array forever, filtered out only for UI display. Memory grows with each regeneration cycle.

---

## 7. Silent Failures & Missing Validation

### 7.1 CustomizationContext.build() Has No Data Validation

**File:** `CustomizationContext.swift:102-167`

No validation of required data — nil profile, empty skill store, empty knowledge cards all pass through silently. Downstream failures are hard to diagnose.

### 7.2 Non-Editable Node Changes Silently Ignored

**File:** `ResumeRevisionWorkspaceService.swift:489-508`

When the LLM modifies a node not in `editableNodeIDs`, the change is logged at debug level only. The LLM believes its change was applied.

**Action:** Return a tool result informing the LLM the node is read-only.

### 7.3 Stale Prompt Cache

**File:** `CustomizationPromptCacheService.swift:71-84`

Cache hash doesn't include dossier content if dossier is initially nil. If dossier is fetched after initial cache, it won't invalidate. No TTL or versioning.

### 7.4 Compound Group History Uses Only First Item

**File:** `RevisionWorkflowOrchestrator.swift:682-689`

```swift
for groupItem in groupItems {
    compoundHistory = groupItem.rejectionHistory
    break  // ONLY USES FIRST ITEM
}
```

If group items have different rejection histories, all but the first are lost. The LLM receives incomplete context for regeneration.

### 7.5 Missing Review Queue Throws Silent Return

**File:** `RevisionWorkflowOrchestrator.swift:758, 791`

```swift
guard let queue = reviewQueue else {
    Logger.error("No review queue available")
    return  // silent return, caller doesn't know it failed
}
```

Should throw `RevisionWorkflowError.missingDependency`.

### 7.6 Backend Inference Defaults to OpenRouter

**File:** `LLMFacade.swift:52-58`

```swift
static func infer(from modelId: String) -> Backend {
    if lower.hasPrefix("anthropic/") || lower.hasPrefix("claude-") { return .anthropic }
    return .openRouter  // silent fallback for ANY unknown model
}
```

Invalid model IDs silently route to OpenRouter, producing late API errors.

### 7.7 Regeneration Has No Timeout

**File:** `CustomizationReviewQueue.swift:459-507`

If `onRegenerationRequested` hangs (network timeout, API down), the item stays in `isRegenerating = true` forever. No timeout wrapper exists.

### 7.8 Mutable Field Contradicts "Immutable Snapshot" Doc

**File:** `CustomizationContext.swift:71`

```swift
var clarifyingQA: [(question: ClarifyingQuestion, answer: QuestionAnswer)]?
```

Comment on line 14 says "immutable context snapshot" but `clarifyingQA` is `var`.

### 7.9 `editedContent` / `editedChildren` Mutual Exclusivity Not Enforced

**File:** `CustomizationReviewQueue.swift:509-525`

Both can be set simultaneously. Application logic prefers one over the other, but nothing prevents both being populated, creating ambiguity.

---

## 8. Summary Table

### By Severity

| # | Issue | Severity | File | Lines |
|---|-------|----------|------|-------|
| 2.1 | Continuation leak in concurrency limiter | CRITICAL | CustomizationParallelExecutor | 779-801 |
| 2.2 | runningCount exceeds maxConcurrent | CRITICAL | CustomizationParallelExecutor | 780-786 |
| 2.3 | Silent streaming persistence failures | HIGH | LLMService | 166-168, 279-281 |
| 2.4 | Network errors masked by JSON retry | HIGH | CustomizationParallelExecutor | 744-748 |
| 2.5 | Substring matching false positives | HIGH | RevisionTaskBuilder | 1038-1044 |
| 7.4 | Compound group history uses first item only | MEDIUM | RevisionWorkflowOrchestrator | 682-689 |
| 7.1 | No data validation in context builder | MEDIUM | CustomizationContext | 102-167 |
| 7.7 | No regeneration timeout | MEDIUM | CustomizationReviewQueue | 459-507 |
| 7.2 | Non-editable node changes silently ignored | MEDIUM | ResumeRevisionWorkspaceService | 489-508 |
| 4.5 | Duplicate build/activate in revision agent | MEDIUM | ResumeRevisionAgent | 202-378, 499, 892 |
| 7.3 | Stale prompt cache | MEDIUM | CustomizationPromptCacheService | 71-84 |
| 6.10 | Superseded items memory leak | MEDIUM | CustomizationReviewQueue | 175-184 |

### By Category

| Category | Count | Critical | High | Medium | Low |
|----------|-------|----------|------|--------|-----|
| Bugs | 5 | 2 | 3 | 0 | 0 |
| Dead Code | 5 | 0 | 0 | 0 | 5 |
| Redundancy | 7 | 0 | 0 | 2 | 5 |
| Over-Abstraction | 5 | 0 | 0 | 2 | 3 |
| Technical Debt | 10 | 0 | 0 | 4 | 6 |
| Silent Failures | 9 | 0 | 0 | 6 | 3 |

---

## 9. Recommended Fix Order

### Phase 1: Critical Bugs (Immediate)

1. **Fix continuation pool** — Replace `waitForSlot()`/`releaseSlot()` with a proper `AsyncSemaphore` or `withTaskCancellationHandler` to ensure slot release on cancellation
2. **Fix runningCount race** — Move `runningCount += 1` inside the wait logic or use atomic operations
3. **Separate network errors from JSON retries** — Only retry on JSON decode failures, propagate network errors immediately
4. **Fix category substring matching** — Use word-boundary or exact matching instead of `contains()`

### Phase 2: High-Impact Cleanup (Next Sprint)

5. **Delete dead export system** — Remove `traverseAndExportNodes()`, `collectDescendantValues()`, `getUpdatableNodes()`
6. **Fix compound group history** — Merge all group items' histories, not just the first
7. **Add regeneration timeout** — 30-second wrapper around `onRegenerationRequested`
8. **Add regeneration depth limit** — Cap at 5, suggest manual edit
9. **Fix silent streaming persistence** — Add error logging in catch blocks

### Phase 3: Consolidation (Planned)

10. **Extract duplicated logic** — KC filtering, preamble construction, reasoning state clearing, JSON log encoding
11. **Consolidate revision agent cleanup paths** — Single exit path for `buildAndActivateResumeFromWorkspace()`
12. **Remove ProposedRevisionNode** if truly unused
13. **Bundle RevisionTaskBuilder parameters** into context object
14. **Split TreeNodeModel.swift** into core + export + schema files

### Phase 4: Polish (Backlog)

15. **Replace manual JSON escaping** with `JSONEncoder`
16. **Cache regex in parseArrayFromString**
17. **Clean up superseded items** from review queue
18. **Make CustomizationContext truly immutable**
19. **Add input validation** to `CustomizationContext.build()`
20. **Deprecate LLM executor Path B** (legacy single-prompt)
