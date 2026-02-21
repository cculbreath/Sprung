# Refactor Plan: SkillsProcessingService.swift

**File:** `Sprung/Onboarding/Services/SkillsProcessingService.swift`
**Lines:** 837
**Branch assessed:** `unified-toolbar-customization`

---

## 1. Primary Responsibility / Purpose

`SkillsProcessingService` is the orchestration layer for two distinct LLM-driven skill bank operations:

1. **Deduplication** — identifies semantically equivalent skills across the bank and merges them in-place via `SkillStore`.
2. **ATS synonym expansion** — generates Applicant Tracking System keyword variants for every skill, dispatching work across parallel subagents.

It owns the full lifecycle of each operation: prompt construction, LLM invocation, response parsing, data mutation, and agent-activity telemetry.

---

## 2. Distinct Logical Sections

| Lines | Section | What it does |
|-------|---------|--------------|
| 15–60 | **Types** | Defines `SkillsProcessingStatus`, `SkillsProcessingResult`, `DuplicateGroup`, `DeduplicationResponse`, `SkillATSVariants`, `ATSExpansionResponse` |
| 64–102 | **Service shell** | `@Observable @MainActor` class declaration, stored properties, `getModelId()`, `parallelAgentCount`, `init`, `updateFacade` |
| 104–187 | **Deduplication — public entry point** | `consolidateDuplicates()` — orchestrates, manages agent-activity lifecycle, calls private helpers |
| 189–262 | **Deduplication — multi-part LLM loop** | `analyzeAllSkillsForDuplicates()` — iterative paging loop with MAX_TOKENS error recovery |
| 264–329 | **Deduplication — prompt builder** | `buildDeduplicationPrompt()` — constructs first-pass and continuation prompts |
| 331–371 | **Deduplication — JSON schema** | `deduplicationSchema` computed property — inline dictionary schema for structured output |
| 373–439 | **Deduplication — data mutation** | `applyDuplicateMerges()` — merges evidence, variants, related skills; deletes duplicates from `SkillStore` |
| 441–589 | **ATS expansion — public entry point** | `expandATSSynonyms()` — batches skills, spawns `TaskGroup` of subagents, applies results |
| 591–668 | **ATS expansion — batch LLM call** | `generateATSVariantsForBatch()` — builds prompt + inline schema, calls Gemini |
| 670–733 | **ATS expansion — single-skill variant** | `generateATSVariantsForSkill()` — on-demand variant generation for a freshly added skill |
| 735–812 | **Combined orchestration** | `processAllSkills()` — sequences dedup then ATS expansion, manages the top-level agent |
| 814–819 | **State reset** | `reset()` |
| 822–836 | **Error enum** | `SkillsProcessingError` |

---

## 3. SRP Violation Assessment

The file violates SRP in three clear ways:

### Violation A — Types mixed with service logic

`DuplicateGroup`, `DeduplicationResponse`, `SkillATSVariants`, `ATSExpansionResponse`, `SkillsProcessingError`, and `SkillsProcessingResult` are all defined inside the same file as the service. These are pure data contracts; they have no reason to change when the LLM invocation strategy changes and vice versa.

Precedent in this codebase: `SkillBankPrompts.swift` and `SkillBankCurationService.swift` separate type definitions from service logic. The same pattern should apply here.

### Violation B — Prompt construction and JSON schema embedded in the orchestrator

`buildDeduplicationPrompt()` and `deduplicationSchema` live inside the service class. The inline ATS prompt string and schema dictionary inside `generateATSVariantsForBatch()` and `generateATSVariantsForSkill()` are a second set of the same problem. Prompt text and schema construction are authoring concerns; they change on different schedules than the execution loop.

Precedent: `SkillBankPrompts.swift` is a dedicated `enum` for prompt/schema concerns in the adjacent service. This file should mirror that pattern.

### Violation C — Three distinct operations in one orchestrator

The service currently owns:
- Deduplication (LLM analysis + data mutation)
- Batch ATS expansion (parallel subagent dispatch + data mutation)
- Single-skill ATS generation (used from `SkillExtractionSheet` for on-save generation)
- The two-phase combined pipeline

Each of these is invoked from different call sites for different reasons. Deduplication and ATS expansion share `SkillStore` and `LLMFacade` but are otherwise independent: different prompts, different schemas, different response types, different error recovery strategies.

At 837 lines the file is long but not unmanageable. However, the co-location of unrelated prompt text, schema dictionaries, and data-mutation logic inside `@MainActor` class methods makes it harder to change any one concern without touching the whole file. The real cost is cognitive: a developer fixing a prompt typo must navigate agent-activity plumbing; a developer changing the merge strategy must scroll past ATS expansion code.

---

## 4. Verdict: Refactor

The file should be split. The split is straightforward and low-risk because the boundaries are already clean — the MARK comments and function groupings map almost exactly to the proposed file boundaries.

---

## 5. Refactoring Plan

### Proposed Files

#### 5.1 `Sprung/Onboarding/Services/SkillsProcessingTypes.swift`

**Purpose:** All shared value types and the error enum. No logic.

**Moves from current file:**

| Lines | Symbol |
|-------|--------|
| 15–20 | `enum SkillsProcessingStatus` |
| 24–29 | `struct SkillsProcessingResult` |
| 34–38 | `struct DuplicateGroup` |
| 41–47 | `struct DeduplicationResponse` |
| 52–55 | `struct SkillATSVariants` |
| 58–60 | `struct ATSExpansionResponse` |
| 822–836 | `enum SkillsProcessingError` |

**Imports:** `Foundation` only.

**Access level:** All types are `internal` (default). No changes needed — they are already visible within the module.

---

#### 5.2 `Sprung/Onboarding/Services/SkillsProcessingPrompts.swift`

**Purpose:** Prompt builders and JSON schemas for deduplication and ATS expansion. A pure-function `enum` namespace — no stored state, no `@MainActor`, no async.

**Moves from current file:**

| Lines | Symbol |
|-------|--------|
| 264–329 | `buildDeduplicationPrompt(skills:processedSkillIds:isFirstPart:partNumber:)` → becomes `static func` |
| 331–371 | `deduplicationSchema` → becomes `static var` |
| Inline in `generateATSVariantsForBatch` (lines 602–649) | ATS batch prompt string and `schema` dictionary |
| Inline in `generateATSVariantsForSkill` (lines 681–713) | Single-skill ATS prompt string and `schema` dictionary |

**How to reorganize:**

```swift
enum SkillsProcessingPrompts {
    // MARK: - Deduplication
    static func deduplicationPrompt(
        skills: [String],
        processedSkillIds: Set<String>,
        isFirstPart: Bool,
        partNumber: Int
    ) -> String { ... }

    static var deduplicationSchema: [String: Any] { ... }

    // MARK: - ATS Batch Expansion
    static func atsBatchPrompt(skillDescriptions: [String]) -> String { ... }
    static var atsExpansionSchema: [String: Any] { ... }

    // MARK: - Single-Skill ATS
    static func singleSkillATSPrompt(canonical: String, category: String) -> String { ... }
    static var singleSkillATSSchema: [String: Any] { ... }
}
```

The `SingleSkillATSResponse` struct (currently local to `generateATSVariantsForSkill`, lines 715–717) can also move into `SkillsProcessingTypes.swift` since it is a response type.

**Imports:** `Foundation` only.

**Call sites in service:** Replace all inline prompt construction and schema literals with calls to `SkillsProcessingPrompts.*`.

---

#### 5.3 `Sprung/Onboarding/Services/SkillsProcessingService.swift` (retained, slimmed)

**Purpose:** Orchestration only — LLM invocation loops, agent-activity tracking, `SkillStore` mutation, state/progress management. No prompt text. No schema definitions. No type definitions.

**Retains:**

| Lines | Symbol |
|-------|--------|
| 64–102 | Class declaration, properties, `init`, `updateFacade`, `getModelId`, `parallelAgentCount` |
| 104–187 | `consolidateDuplicates()` |
| 189–262 | `analyzeAllSkillsForDuplicates()` |
| 373–439 | `applyDuplicateMerges()` |
| 441–589 | `expandATSSynonyms()` |
| 591–668 | `generateATSVariantsForBatch()` |
| 670–733 | `generateATSVariantsForSkill()` |
| 735–812 | `processAllSkills()` |
| 814–819 | `reset()` |

After extraction, the prompt and schema bodies in `generateATSVariantsForBatch` and `generateATSVariantsForSkill` are replaced with single-line calls to `SkillsProcessingPrompts`. Estimated final line count: ~500 lines.

**Imports:** `Foundation`, `Observation`, `SwiftyJSON` (unchanged).

---

### File Summary

| New File | Lines (est.) | Content |
|----------|-------------|---------|
| `SkillsProcessingTypes.swift` | ~80 | Types + error enum |
| `SkillsProcessingPrompts.swift` | ~160 | Prompt builders + schemas |
| `SkillsProcessingService.swift` | ~500 | Orchestration logic only |

---

## 6. Call Site Impact

No call sites outside `SkillsProcessingService.swift` reference the internal prompt/schema symbols — those are all `private`. The public-facing types (`SkillsProcessingStatus`, `SkillsProcessingResult`, `SkillsProcessingError`) are already `internal`; moving them to a separate file in the same module requires no access-level changes.

Files that import or use `SkillsProcessingService` and its public API:

- `Sprung/Shared/Views/SkillsBankBrowser.swift`
- `Sprung/Shared/Views/SkillExtractionSheet.swift`
- `Sprung/Onboarding/Services/KnowledgeCardWorkflowService.swift`
- `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`
- `Sprung/KnowledgeCardBrowser/Services/StandaloneKCCoordinator.swift`

None of these will require changes — the public interface of `SkillsProcessingService` is unchanged.

---

## 7. Implementation Order

1. Create `SkillsProcessingTypes.swift` — move all type definitions and the error enum. Build to verify no reference breaks. (This is the safest first step; types move without any logic change.)
2. Create `SkillsProcessingPrompts.swift` — extract `buildDeduplicationPrompt`, `deduplicationSchema`, and the two inline ATS prompt+schema blocks as static members. Update call sites in `SkillsProcessingService` to use `SkillsProcessingPrompts.*`.
3. Delete the now-empty `private` methods and inline definitions from `SkillsProcessingService.swift`. Build and verify.
4. Move `SingleSkillATSResponse` (currently a local struct at line 715) into `SkillsProcessingTypes.swift`.

---

## 8. What NOT to do

- Do not split deduplication logic and ATS expansion into separate service classes. They share `SkillStore`, `LLMFacade`, `agentActivityTracker`, and the common state properties (`status`, `progress`, `currentBatch`, `totalBatches`). The orchestration boundary between them (`processAllSkills`) justifies keeping both in one service.
- Do not mark anything `@available(*,deprecated)`. The types and symbols being moved are identical; access level does not change. Simply delete from the old location and add to the new file.
- Do not add a backwards-compatibility typealiases or re-exports. The module boundary is the same; consumers see no difference.
