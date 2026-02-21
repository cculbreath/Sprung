# Refactor Plan: ChipChildrenView.swift

**File:** `Sprung/ResumeTree/Views/ChipChildrenView.swift`
**Lines:** 845
**Date assessed:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`ChipChildrenView` renders the children of a `TreeNode` as a horizontal flow of pill-shaped chips. It is specifically tailored for skill-list sections (e.g., a "Languages" or "Frameworks" skill category), where each child node is a skill value. It ties together:

- Displaying existing chips (delegating to `ChipView`)
- Inline chip creation with skill-bank autocomplete
- Browsing the full skill library via `SkillSelectionSheet`
- Displaying two types of skill suggestions: gap suggestions (matched skills not yet added) and AI recommendations from job preprocessing
- Drag-and-drop reordering of chips (delegating to `ChipDropDelegate`)
- A toggle/button to sync chip changes back to the skill library

---

## 2. Distinct Logical Sections

### Section A: `ChipChildrenView` — container/orchestrator (lines 11–536)

This is the outermost view. It owns:

1. **Body layout** (lines 39–112): `FlowStack` of chips, add-chip controls, recommendations row, gap-suggestions row, sync-toggle row.
2. **Autocomplete filtering** (lines 116–138): Two computed properties — `autocompleteSuggestions` (for the add-chip text field) and `relevantRecommendations` (AI suggestions from job preprocessing, filtered to exclude already-added skills).
3. **Subview: `addChipButton`** (lines 142–164): A small "+" capsule button that activates the add-chip mode.
4. **Subview: `addChipWithAutocomplete`** (lines 166–235): Text field + inline autocomplete dropdown for entering a new chip.
5. **Subview: `browseSourceButton`** (lines 237–254): A "Browse" button that opens `SkillSelectionSheet`.
6. **Subview: `skillGapRow`** (lines 256–289): Renders matched-but-not-yet-added skills (green suggestion pills).
7. **Subview: `recommendationsRow`** (lines 291–325): Renders AI-suggested skills from job preprocessing (orange suggestion pills).
8. **Subview: `syncToggleRow`** (lines 327–358): Checkbox + "Sync all" button for skill library sync.
9. **Logic: `isChipMatched`** (lines 362–369): Checks whether a chip node is in the matched-skill set.
10. **Logic: `gapSuggestions`** (lines 372–379): Computed set of matched skills not yet present in this chip list.
11. **Logic: `addChild`** (lines 381–425): Creates a `TreeNode`, saves, optionally syncs a new plain-text chip to the skill library.
12. **Logic: `cancelAdd`** (lines 427–431): Resets add-chip state.
13. **Logic: `addFromSkillBank`** (lines 433–458): Creates a `TreeNode` from a `Skill` object, saves, resets state.
14. **Logic: `addFromSuggestion`** (lines 460–462): Trivially delegates to `addFromSkillBank`.
15. **Logic: `chipDropIndicator`** (lines 464–479): `@ViewBuilder` overlay for drag-drop position indicator.
16. **Logic: `addFromRecommendation`** (lines 481–515): Creates a `TreeNode` from a `SkillRecommendation`, saves, optionally syncs to skill library. Nearly duplicates `addChild` and `addFromSkillBank`.
17. **Logic: `syncAllToSkillBank`** (lines 517–535): Batch-syncs all existing chips to the skill library.

### Section B: `ChipView` — individual chip display and editing (lines 540–756)

A separate `private struct` embedded in the same file. Handles:

1. **State management** for hover, edit mode, autocomplete within an individual chip.
2. **Display view** (lines 581–644): Non-editing state — chip background, checkmark for match, AI status icon (with group-member awareness), delete button, tap-to-edit gesture.
3. **Editing view** (lines 652–717): Text field in place of chip label, inline autocomplete dropdown for editing the chip value.
4. **Logic: `commitEdit`** (lines 719–737): Saves the edited chip value, optionally syncs to skill library.
5. **Logic: `syncToSkillLibrary`** (lines 739–750): Finds the skill in the store by old canonical/variant, renames it.
6. **Logic: `cancelEdit`** (lines 752–755): Resets edit state.

### Section C: `ChipDropDelegate` — drag-and-drop reordering (lines 760–844)

A `private struct` conforming to `DropDelegate`. Handles all five `DropDelegate` methods (`validateDrop`, `dropEntered`, `dropUpdated`, `performDrop`, `dropExited`) plus a private `reorder` helper that mutates `myIndex` values and saves to SwiftData.

---

## 3. SRP Assessment

**The file violates Single Responsibility Principle in a meaningful way.** It contains three distinct, independently changeable types:

| Type | Reason to Change |
|------|-----------------|
| `ChipChildrenView` | Layout of chip list, suggestion UI, add-chip flow |
| `ChipView` | Individual chip display, inline editing, AI status icon |
| `ChipDropDelegate` | Drag-and-drop protocol, reordering algorithm |

These are not just extracted helpers for the sake of brevity. `ChipView` has its own full lifecycle (hover, edit state, autocomplete, skill-library sync), its own `@Environment` dependencies, and its own logic that has no coupling to `ChipChildrenView`'s add-chip flow. `ChipDropDelegate` is a pure behavioral type with zero UI and its own persistence logic.

Additionally, within `ChipChildrenView` itself there is a secondary concern worth noting: **skill-library sync logic** (`addChild`, `addFromRecommendation`, `syncAllToSkillBank`, and `ChipView.syncToSkillLibrary`) is interleaved with layout code. This is borderline but not an immediate refactoring priority since it involves state (`syncToSkillLibrary` toggle) owned by the view.

**The 845-line length is not justified.** The length comes from three structurally independent types being placed in one file, not from a single deeply organized concern.

---

## 4. Refactoring Recommendation: SPLIT

The file should be split into three files, each containing one type. The split is clean — there are no circular dependencies between the three types, and all types are currently `private` to the file (making them `internal` to the module is the only change needed to access them across files).

---

## 5. Concrete Refactoring Plan

### New File 1: `ChipView.swift`

**Path:** `Sprung/ResumeTree/Views/ChipView.swift`

**Contents:** Lines 538–756 (the `// MARK: - Chip View` section and the `ChipView` struct).

**Change required:** Remove the `private` access modifier from `struct ChipView`. The type becomes `internal` (the Swift default), visible throughout the module. No other changes are needed — all its dependencies (`TreeNode`, `SkillStore`, `ResumeDetailVM`, `AIIconMode`, `AIIconModeResolver`, `AIIconMenuButton`, `AIStatusIcon`, `PopoverMenuItem`, `Logger`) are already module-internal.

**Purpose:** Renders and manages a single skill chip: display state, hover state, inline editing with autocomplete, AI status icon with group-member awareness, and optional skill-library sync on edit commit.

**Interactions:**
- `ChipChildrenView` creates `ChipView(node:isMatched:onDelete:skillStore:syncToLibrary:)` instances.
- No import changes needed — same module.

---

### New File 2: `ChipDropDelegate.swift`

**Path:** `Sprung/ResumeTree/Views/ChipDropDelegate.swift`

**Contents:** Lines 758–844 (the `// MARK: - Chip Drop Delegate` section and the `ChipDropDelegate` struct).

**Change required:** Remove the `private` access modifier from `struct ChipDropDelegate`. Becomes `internal`. Dependencies (`TreeNode`, `DragInfo`, `AppEnvironment`, `Logger`) are all module-internal.

**Purpose:** Implements `DropDelegate` for chip reordering within a `FlowStack`. Manages drop-target tracking via `DragInfo`, determines left/right insertion position, mutates `myIndex` values on the parent's children array, and persists the new order via the resume's `modelContext`.

**Interactions:**
- `ChipChildrenView.body` instantiates `ChipDropDelegate(node:siblings:dragInfo:appEnvironment:canReorder:)` in the `.onDrop(of:delegate:)` modifier for each chip.
- No import changes needed.

---

### Revised `ChipChildrenView.swift`

**Path:** `Sprung/ResumeTree/Views/ChipChildrenView.swift` (unchanged path)

**Retains:** Lines 1–536 only — the `ChipChildrenView` struct with its layout, add-chip subviews, suggestion rows, sync toggle, and all action methods.

**Change required:** None — `ChipDropDelegate` and `ChipView` become module-internal so they are accessible without any import.

**Line count after split:** ~536 lines. This is still substantial but justified: the view genuinely orchestrates many distinct UI concerns (chip list, two suggestion surfaces, add flow, browse sheet, sync controls) that are all tightly coupled to the same parent-node state and environment dependencies. No further split is warranted without introducing unnecessary indirection.

---

## 6. Split Summary

| File | Lines (approx) | Purpose |
|------|---------------|---------|
| `ChipChildrenView.swift` | 1–536 (~536) | Container view: chip flow, add-chip UI, suggestions, sync controls |
| `ChipView.swift` | 538–756 (~219) | Individual chip: display, hover, inline edit, AI status, skill-library sync |
| `ChipDropDelegate.swift` | 758–844 (~87) | DropDelegate: validation, position tracking, reorder algorithm, persistence |

---

## 7. Access-Level Changes

| Symbol | Before | After |
|--------|--------|-------|
| `struct ChipView` | `private` (file-private) | `internal` (module) |
| `struct ChipDropDelegate` | `private` (file-private) | `internal` (module) |

All other types remain unchanged.

---

## 8. What Does NOT Need to Change

- No protocol conformances change.
- No initializer signatures change.
- `ChipChildrenView`'s usage of both types is identical — the only difference is that those types are no longer defined in the same file.
- No test targets reference these types directly (they are UI view structs), so no test updates are needed.
- Xcode's filesystem-synced groups will pick up the new files automatically — no manual group edits required.

---

## 9. Verification Checklist (after implementing the split)

1. `grep -r "private struct ChipView" .` — should return zero results.
2. `grep -r "private struct ChipDropDelegate" .` — should return zero results.
3. Build with `xcodebuild -project Sprung.xcodeproj -scheme Sprung build 2>&1 | grep -Ei "(error:|warning:|failed|succeeded)" | head -20` — should show `BUILD SUCCEEDED` with no errors.
4. Confirm `ChipChildrenView.swift` references `ChipView(` and `ChipDropDelegate(` — types resolve without import because they share the module.
