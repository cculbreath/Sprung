# PhaseReviewManager.swift Refactoring Assessment

**File**: `/Users/cculbreath/devlocal/codebase/Sprung/Sprung/Resumes/AI/Services/PhaseReviewManager.swift`
**Lines**: 1040
**Date**: 2025-12-27

---

## File Overview and Primary Purpose

`PhaseReviewManager` manages a manifest-driven multi-phase review workflow for resume content. It orchestrates LLM-powered review of resume sections, handling:

- Two-round review workflow (Phase 1 and Phase 2 items)
- LLM interaction through multiple pathways (streaming, tools, non-streaming)
- User decisions (accept/reject/edit) on proposed changes
- Resubmission of rejected items for LLM revision
- Application of approved changes to the resume tree

The class acts as a coordinator between the view model (via delegate), various LLM services, and the resume data model.

---

## Responsibility Analysis

### Identified Responsibilities

1. **Phase/Round Detection and Building** (Lines 140-292)
   - `sectionsWithActiveReviewPhases()` - Detecting which sections have review phases
   - `buildReviewRounds()` - Building two-round review structure
   - `exportAllAISelectedNodes()` - Exporting nodes for review
   - `extractAttributeName()` - Path parsing for phase assignment

2. **Workflow Orchestration** (Lines 300-484, 959-1008)
   - `startTwoRoundReview()` - Entry point for workflow
   - `startRound()` - Starting individual rounds
   - `finishPhaseReview()` - Completing rounds and transitioning
   - `finalizeWorkflow()` - Cleanup after all rounds complete

3. **LLM Interaction** (Lines 92-136, 404-464, 609-658, 844-892)
   - `parsePhaseReviewFromResponse()` - Response parsing
   - `buildToolSystemPromptAddendum()` - Tool prompt building
   - Three LLM pathways: streaming with reasoning, tool-enabled, and non-streaming

4. **Phase Progression** (Lines 486-549, 554-675)
   - `completeCurrentPhase()` - Phase completion logic
   - `advanceToNextRound()` / `advanceToNextPhase()` - Navigation between phases
   - `applyAllChangesAndAdvance()` - Applying changes during transitions

5. **Item-Level Review Operations** (Lines 677-793)
   - `acceptCurrentItemAndMoveNext()` - Accept action
   - `rejectCurrentItemAndMoveNext()` - Reject action
   - `rejectCurrentItemWithFeedback()` - Reject with feedback
   - `acceptCurrentItemWithEdits()` - Accept with edits
   - `acceptOriginalAndMoveNext()` - Revert to original
   - Navigation: `goToPreviousItem()`, `goToNextItem()`, `goToItem(at:)`
   - Query helpers: `canGoToPrevious`, `canGoToNext`, `hasItemsNeedingResubmission`

6. **Resubmission Handling** (Lines 796-954)
   - `performPhaseResubmission()` - Resubmitting rejected items
   - `mergeResubmissionResults()` - Merging revised proposals back

7. **Tool UI State Forwarding** (Lines 72-90)
   - Forwarding `showSkillExperiencePicker`, `pendingSkillQueries` to `ToolConversationRunner`
   - Pass-through methods: `submitSkillExperienceResults()`, `cancelSkillExperienceQuery()`

8. **Change Application** (Lines 1010-1040)
   - `hasUnappliedApprovedChanges()` - Query state
   - `applyApprovedChangesAndClose()` - Final application
   - `discardAllAndClose()` - Discard workflow

### Responsibility Count: 8 distinct areas

---

## Code Quality Observations

### Strengths

1. **Clear MARK sections** - The file is well-organized with descriptive section markers
2. **Comprehensive documentation** - Methods have clear doc comments explaining purpose
3. **Consistent error handling** - Try/catch with appropriate logging
4. **Protocol-based delegation** - Clean separation from view model via `PhaseReviewDelegate`
5. **Dependency injection** - All dependencies injected via initializer
6. **State encapsulation** - `PhaseReviewState` centralizes phase-related state

### Concerns

1. **Multiple LLM pathways duplicated** - The same three-branch pattern (reasoning, tools, non-streaming) appears in:
   - `startRound()` (lines 404-464)
   - `advanceToNextPhase()` (lines 609-658)
   - `performPhaseResubmission()` (lines 844-892)

   This is 180+ lines of similar code with minor variations.

2. **Tool UI forwarding is pass-through** - Lines 72-90 are pure delegation to `ToolConversationRunner`. This is a sign of leaky abstraction - the view model should interact with `ToolConversationRunner` directly if it needs these properties.

3. **Large method sizes** - Several methods exceed 50 lines:
   - `startRound()` - 130 lines
   - `advanceToNextPhase()` - 120 lines
   - `performPhaseResubmission()` - 110 lines

4. **Tight coupling to multiple services** - The class depends on 8 injected dependencies, making it a coordination point for many concerns.

### Code Smells Detected

| Smell | Location | Severity |
|-------|----------|----------|
| Duplicated LLM pathway logic | Lines 404-464, 609-658, 844-892 | Medium |
| Pass-through delegation | Lines 72-90 | Low |
| Large methods | Multiple | Low |
| High dependency count (8) | Constructor | Medium |

---

## Coupling and Testability Assessment

### Coupling Analysis

**External Dependencies (8):**
- `LLMFacade` - LLM abstraction
- `OpenRouterService` - Model lookup
- `ReasoningStreamManager` - UI state for reasoning display
- `ResumeExportCoordinator` - Export triggering
- `RevisionStreamingService` - Streaming LLM calls
- `ApplicantProfileStore` - Profile data access
- `ResRefStore` - Reference materials
- `ToolConversationRunner` - Tool-enabled conversations

**Internal Coupling:**
- `PhaseReviewState` - Tightly coupled (directly mutated)
- `PhaseReviewDelegate` - Loose coupling via protocol
- `TreeNode` - Used for data operations but not injected

### Testability

**Positive factors:**
- Dependencies are injected, enabling mock injection
- Protocol-based delegate pattern allows test verification
- State changes are observable via `@Observable`

**Negative factors:**
- Direct mutation of `phaseReviewState` makes state verification tricky
- Multiple async operations with side effects are hard to unit test
- The three LLM pathways make tests repetitive

---

## Recommendation

### **DO NOT REFACTOR**

### Rationale

While this file has some code smells (particularly the duplicated LLM pathway logic), it does not meet the threshold for mandatory refactoring per the project guidelines:

1. **Single cohesive purpose**: Despite having multiple responsibilities, they all serve one coherent goal - managing the phase review workflow. This is a complex domain-specific coordinator, and its responsibilities are tightly related.

2. **Working code**: The file functions correctly as part of the resume revision system. There's no indication of bugs, maintenance pain, or difficulty understanding the code.

3. **Testability is adequate**: With 8 injected dependencies and protocol-based delegation, the class can be unit tested by providing mocks. The coupling is high but not problematic.

4. **Refactoring risk outweighs benefit**: Extracting the LLM pathway logic would require:
   - A new abstraction layer for "LLM conversation strategies"
   - Passing significant context to the extracted logic
   - Risk of introducing bugs in a working system

5. **Not a pain point**: There's no evidence this file is difficult to modify or causes development friction.

### Recommended Minor Improvements (Optional, Non-Breaking)

If future work touches this file, consider these lightweight improvements:

1. **Remove tool UI pass-through** (Lines 72-90): Have the view model access `ToolConversationRunner` directly rather than forwarding through this class.

2. **Extract LLM pathway selection** (Future): If the three-branch LLM logic needs to change, consider extracting a `PhaseReviewLLMStrategy` or similar pattern. But only when an actual change triggers this need.

3. **Consider method extraction**: Large methods like `startRound()` could have their setup/teardown logic extracted to private helpers, but this is a stylistic preference rather than a structural issue.

---

## Summary

| Metric | Assessment |
|--------|------------|
| Line Count | 1040 (above 500 threshold) |
| Distinct Responsibilities | 8 (related, cohesive) |
| SRP Violation | Borderline - complex coordinator role |
| Code Duplication | Medium (LLM pathways) |
| Testability | Good (DI, protocols) |
| Pain Points | None identified |
| **Recommendation** | **DO NOT REFACTOR** |

The file is large and has some duplication, but it represents a complex workflow coordinator that benefits from having its logic co-located. The responsibilities, while numerous, are all related to the same workflow. Refactoring would create complexity without solving an actual problem.
