# Refactor Plan: SkillsBankBrowser.swift

**File:** `Sprung/Shared/Views/SkillsBankBrowser.swift`
**Line count:** 1,466
**Date assessed:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`SkillsBankBrowser` is the full-featured skills bank management UI. It shows all skills grouped by category in an expandable list, and bundles every interaction the user can have with skills: searching, filtering by proficiency, adding skills, editing skills inline, renaming categories, creating new categories, cycling proficiency, and launching five different LLM-powered batch operations (deduplicate, ATS expand, refine, curate, extract from artifacts).

---

## 2. Distinct Logical Sections

| # | Lines | Section | What it does |
|---|-------|---------|--------------|
| 1 | 1-11 | `RefineResponse` model | Private Codable struct for the LLM JSON response used by `refineSkills()`. Lives here because it is only ever used by the refine action. |
| 2 | 13-113 | State declarations + computed filtering | `@State` for all sub-features (~20 properties), plus `allSkills`, `groupedSkills`, `sortedCategories` computed vars. |
| 3 | 115-212 | `body` | Top-level layout: ZStack with filter bar, empty state, no-matches state, or skills list; sheet and alert modifiers. |
| 4 | 214-351 | Inline Add Skill | `startAddingSkill`, `cancelAddingSkill`, `commitNewSkill` (which calls `SkillsProcessingService` to generate ATS variants), and `inlineAddSkillRow` view builder. |
| 5 | 353-492 | Filter bar + Action buttons | `filterBar` and `actionButtons` computed views — search field, proficiency chips, and the five toolbar action buttons. |
| 6 | 494-545 | Refine popover UI | `refinePopoverContent` — the instruction entry form that triggers `refineSkills()`. |
| 7 | 547-563 | Processing overlay | `processingOverlay` — the spinner/progress overlay shown during any LLM operation. |
| 8 | 565-762 | LLM processing actions | Three heavy async methods: `consolidateDuplicates`, `expandATSVariants`, `refineSkills`. Each builds a service, polls progress, and updates shared state. `refineSkills` also contains the full LLM prompt and JSON schema inline. |
| 9 | 764-822 | New category creation | `newCategoryRow` view and `commitNewCategory` method. |
| 10 | 824-881 | Inline skill editing | `startEditing`, `commitEdit`, `deleteEditingSkill`, `cancelEdit`. |
| 11 | 883-1006 | Category section view | `proficiencyChip`, `categorySection` — the expandable category header with rename TextField and skill list. |
| 12 | 1008-1245 | Skill row view | `skillRow` — a dense composite view that handles display mode, inline editing mode, ATS variant expansion, proficiency badge tap-to-cycle, and the expanded ATS synonyms panel. |
| 13 | 1247-1335 | UI interaction helpers | `cycleProficiency` (with sort-freeze debounce), `toggleCategory`, `commitCategoryRename`, `colorForCategory`. |
| 14 | 1337-1386 | Curation action | `curateSkills` async method and `colorFor(_ proficiency:)` helper. |
| 15 | 1388-1421 | Empty/no-match states | `emptyState` and `noMatchesState` views. |
| 16 | 1424-1465 | `FlowLayout` | A private `Layout` implementation for wrapping ATS synonym tags. A near-duplicate of `FlowStack/_FlowLayout` already in `Sprung/Shared/Views/FlowStack.swift`. |

---

## 3. SRP Assessment

**Verdict: SRP is violated — this file has at least four distinct reasons to change.**

### Reason 1 — Skill CRUD interaction model changes
The inline add, inline edit, category rename, and category creation state + logic would need updating when the interaction model for editing skills changes. That is one reason to change.

### Reason 2 — LLM processing action implementations change
`consolidateDuplicates`, `expandATSVariants`, `refineSkills`, and `curateSkills` each contain async Task scaffolding, progress-polling loops, and direct calls into `SkillsProcessingService` / `SkillBankCurationService`. The `refineSkills` method additionally contains an inline LLM prompt string and JSON schema literal. These actions would change when the service API changes, when the model configuration changes, or when the refine prompt is iterated on. That is a second reason to change.

### Reason 3 — Category and skill display/layout changes
`categorySection`, `skillRow`, `inlineAddSkillRow`, `proficiencyChip`, `colorForCategory`, `colorFor(_ proficiency:)`, `cycleProficiency`, and `sortFrozenOrder` debounce logic all belong to rendering. They change when visual design or interaction affordances change. That is a third reason to change.

### Reason 4 — FlowLayout is an independent utility
`FlowLayout` (lines 1426-1465) is a general-purpose `Layout` primitive that has nothing to do with skills. The project already has `FlowStack` in `Shared/Views/FlowStack.swift` that wraps the equivalent `_FlowLayout`. `FlowLayout` here is a duplicate.

---

## 4. Length Justification

1,466 lines is **not justified**. The length arises from three co-located concerns (CRUD interaction, async LLM orchestration, and rendering) that could each be meaningfully separated. The refine function alone (lines 659-762) is 103 lines containing an embedded prompt string and JSON schema dictionary — that is pure business logic inside a View type.

The file is also holding state for operations that are conceptually independent. The 20+ `@State` properties span four feature areas: LLM batch processing, inline skill editing, inline skill addition, and category management. When reading or modifying any one feature, the developer must mentally filter out state that belongs to the others.

---

## 5. Refactoring Plan

### Decision: Split into four files

The split follows logical cohesion, not arbitrary line-count reduction. The goal is that each file has one reason to change.

---

### File A — Keep, reduced: `SkillsBankBrowser.swift`

**Path:** `Sprung/Shared/Views/SkillsBankBrowser.swift`
**Purpose:** Top-level container view. Owns the shell layout, sheet/alert presentation, filter bar wiring, and the `@State` properties that coordinate between child views and actions. Imports and delegates to the extracted files.

**What stays here (approximate lines after extraction):**
- Struct declaration with `skillStore`, `llmFacade`, `@Environment` (lines 15-19)
- Expansion/search/proficiency filter state (lines 21-24)
- Processing state (lines 27-34) — but consider moving to a dedicated observable model (see File B)
- Curation/extraction sheet-trigger state (lines 37-71)
- `ProcessingOperation` enum (lines 73-79)
- `allSkills`, `groupedSkills`, `sortedCategories` computed vars (lines 82-113)
- `body` (lines 115-212)
- `filterBar` and `actionButtons` views (lines 353-492)
- `refinePopoverContent` view (lines 494-545)
- `processingOverlay` view (lines 547-563)
- `proficiencyChip` (lines 885-913) — stays because it is tightly coupled to the filter bar
- `emptyState` / `noMatchesState` (lines 1388-1421)

**Projected size:** ~400-450 lines.

---

### File B — New: `SkillsProcessingActions.swift`

**Path:** `Sprung/Shared/Views/SkillsProcessingActions.swift`

**Purpose:** Contains the four async LLM processing actions as an extension on `SkillsBankBrowser`, plus the `RefineResponse` Codable type. This file changes when service APIs, LLM prompts, or progress-monitoring patterns change.

**What moves here:**

| Lines in original | Content |
|-------------------|---------|
| 1-11 | `private struct RefineResponse: Codable` |
| 565-611 | `func consolidateDuplicates()` |
| 613-657 | `func expandATSVariants()` |
| 659-762 | `func refineSkills()` — including the inline LLM prompt string, JSON schema, and response-application loop |
| 1337-1378 | `func curateSkills()` |

**Implementation note:** This is a Swift extension:
```swift
// SkillsProcessingActions.swift
import SwiftUI

private struct RefineResponse: Codable { ... }

extension SkillsBankBrowser {
    func consolidateDuplicates() { ... }
    func expandATSVariants() { ... }
    func refineSkills() { ... }
    func curateSkills() { ... }
}
```

`RefineResponse` must remain `private` (file-private) or be moved to `internal` if the extension file is in the same module. Since Swift extensions in separate files share the same access to `internal` members, `private` on `RefineResponse` must become `fileprivate` or the struct can simply be declared at file scope without an access modifier (defaults to `internal`, which is fine and not visible outside the module).

**State access:** The extension methods already access `@State` via the parent struct's stored properties. This works correctly because Swift extensions on a struct have full access to its stored properties when they are in the same module.

**Projected size:** ~220 lines.

---

### File C — New: `SkillRowView.swift`

**Path:** `Sprung/Shared/Views/SkillRowView.swift`

**Purpose:** Contains `categorySection` and `skillRow` as private view-builder functions on `SkillsBankBrowser`, plus the inline skill editing UI and add-skill row UI, and the interaction helpers that are purely display-related. This file changes when the visual design of a skill row or category header changes.

**What moves here:**

| Lines in original | Content |
|-------------------|---------|
| 214-351 | Inline Add Skill: `startAddingSkill`, `cancelAddingSkill`, `commitNewSkill`, `inlineAddSkillRow` |
| 764-822 | New Category: `newCategoryRow`, `commitNewCategory` |
| 824-881 | Inline Editing: `startEditing`, `commitEdit`, `deleteEditingSkill`, `cancelEdit` |
| 915-1006 | `categorySection` view builder |
| 1008-1245 | `skillRow` view builder |
| 1247-1335 | `cycleProficiency`, `toggleCategory`, `commitCategoryRename`, `colorForCategory` |
| 1380-1386 | `colorFor(_ proficiency:)` |

**Implementation note:** Also a Swift extension:
```swift
// SkillRowView.swift
import SwiftUI

extension SkillsBankBrowser {
    func categorySection(_ category: String) -> some View { ... }
    func skillRow(_ skill: Skill) -> some View { ... }
    // etc.
}
```

**Projected size:** ~650 lines. This is still the largest file after the split, but that is appropriate — skill row rendering is genuinely complex (display mode, inline edit mode, ATS variant expansion, proficiency cycling) and it changes together as a single concern.

---

### File D — FlowLayout dedup — ALREADY COMPLETED

**COMPLETED:** The private `FlowLayout` duplicate has already been deleted from `SkillsBankBrowser.swift` and the usage at line 1227 replaced with `FlowStack(spacing: 6)` as part of a cross-cutting FlowLayout dedup pass. No action needed for this step.

---

## 6. File Interaction Summary

```
SkillsBankBrowser.swift          (container, layout, filter bar, sheets)
    |
    +-- SkillsProcessingActions.swift   (extension: async LLM operations)
    |       uses: SkillsProcessingService, SkillBankCurationService, LLMFacade
    |       defines: RefineResponse (fileprivate)
    |
    +-- SkillRowView.swift              (extension: row/section views + CRUD helpers)
            uses: SkillStore, Skill, Proficiency, SkillCategoryUtils, FlowStack
```

No imports are needed between the extension files and the main file — they are all in the same Swift module (`Sprung`) and Swift resolves extensions automatically. All three files must use the same struct name (`SkillsBankBrowser`) and access level (`struct SkillsBankBrowser: View` stays in the main file only; the others are plain `extension SkillsBankBrowser`).

---

## 7. Access Level Changes Required

| Symbol | Current | After refactor | Reason |
|--------|---------|---------------|--------|
| `RefineResponse` | `private` (file-private in Swift) | `private` stays valid only if it remains in the same file. Move to the extension file and keep it `private` — this works in Swift because `private` on a file-scope type means file-private, not type-private. Alternatively use no modifier (internal). Recommended: keep `private` and move it to `SkillsProcessingActions.swift`. | Used only in `refineSkills()` which lives in that file. |
| `ProcessingOperation` | `private enum` inside struct | No change needed — it will remain accessible to extensions in the same module via `internal`. Promote to `internal` (remove `private`) or leave as-is; in practice Swift extensions in the same module can see internal members. | Accessed in `actionButtons` (main file) and the processing action methods (extension file). |
| `FlowLayout` | `private struct` | Delete entirely. | Replaced by `FlowStack`. |

---

## 8. Implementation Order

1. Replace `FlowLayout` usage with `FlowStack` and delete the `FlowLayout` struct (lines 1227, 1424-1465). Build to verify.
2. Create `SkillsProcessingActions.swift` as an extension. Move the four processing functions and `RefineResponse`. Remove those lines from the main file. Build to verify.
3. Create `SkillRowView.swift` as an extension. Move the CRUD helpers, row views, and category section views. Remove those lines from the main file. Build to verify.
4. Verify zero references to the old locations: `grep -n "RefineResponse\|consolidateDuplicates\|expandATSVariants\|refineSkills\|curateSkills\|categorySection\|skillRow\|inlineAddSkillRow\|commitNewSkill\|commitEdit\|colorForCategory" Sprung/Shared/Views/SkillsBankBrowser.swift` should only show call sites, not definitions.

---

## 9. What NOT to Extract

- **`filterBar` / `actionButtons` / `processingOverlay`**: These are tightly coupled to the toolbar state (`isProcessing`, `currentOperation`, `showRefinePopover`) and do not merit their own file. They read cleanly as nested view builders.
- **`proficiencyChip`**: Four lines of display logic. No justification to separate.
- **`emptyState` / `noMatchesState`**: Trivial, change with the overall view design, keep in main file.
- **`groupedSkills` / `sortedCategories`**: Pure filtering computed properties. Keep in main file near the state they consume.
