# Refactor Plan: TitleSetsBrowserTab.swift

**File:** `Sprung/Shared/Views/TitleSetsBrowserTab.swift`
**Line count:** 821
**Assessment date:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`TitleSetsBrowserTab` is a browser tab view that provides the UI surface for creating and managing "title sets" — sets of four professional identity words used in resume title lines. At its core it is a split-panel view: a left panel listing approved combinations and a right panel with an interactive AI-driven generator.

---

## 2. Distinct Logical Sections

The file contains five clearly distinguishable clusters of concern.

### 2a. Main View + Layout Shell (lines 14–54)
`TitleSetsBrowserTab` body: HStack split, wires left/right panels together. Pure layout glue.

### 2b. Left Panel — Approved Combinations Browser (lines 56–174)
- `approvedCombinationsPanel`: header badge, list of `TitleSetBrowserRow`
- `pendingSection`: orange-highlighted section for unreviewed bulk-generated sets
- `approvePendingSet`, `rejectPendingSet`, `deleteTitleSet`, `emptyStateView`
- This group manages **displaying and approving/rejecting stored sets**.

### 2c. Right Panel — Interactive Generator UI (lines 176–317)
- `generatorPanel`: wraps word slots, instructions field, AI comment, action buttons
- `wordSlotsGrid`, `instructionsField`, `aiCommentView`, `actionButtons`
- Pure SwiftUI layout; orchestrates UI components with no business logic of its own.

### 2d. AI Generation Logic (lines 319–673)
- State: `currentWords`, `isGenerating`, `conversationHistory`, `pendingSets`, `aiComment`
- `generateWords()`: single-set generation — builds prompts, selects backend, calls LLMFacade, parses response
- `bulkGenerate(count:)`: multi-set generation — distinct prompt, schema, loops results into `pendingSets`
- `buildHistoryContext()`, `buildApprovedContext()`, `buildExperienceContext()`: prompt context builders
- `getModelConfig()`: reads UserDefaults for backend + model ID
- `saveCurrentSet()`, `clearGenerator()`, `loadTitleSet()`: generator lifecycle management
- `lockedCount`, `hasValidWords`: computed helpers
- **This is by far the heaviest concern**: two async LLM calls, prompt construction, schema definitions, response parsing.

### 2e. Private Sub-Views and Response Types (lines 676–821)
- `WordSlotView` (lines 678–704): editable word chip with lock toggle
- `PendingTitleSetRow` (lines 708–743): approve/reject row for bulk-generated sets
- `TitleSetBrowserRow` (lines 747–805): approved-set row with hover actions
- `TitleGenerationResponse`, `BulkTitleResponse` (lines 809–820): Codable response structs for LLM output

---

## 3. Single Responsibility Principle Assessment

The file violates SRP on two axes:

**Axis 1 — View layer doing model/service work.**
`generateWords()` and `bulkGenerate()` contain:
- Prompt engineering (multi-line string construction, schema dictionaries)
- Backend selection (`getModelConfig()` reading UserDefaults)
- Direct `LLMFacade` calls with backend-conditional branching
- Response parsing and state mutation

These are service/ViewModel concerns embedded directly in a `View` struct. The generation logic has an independent reason to change (prompt updates, new backend support, schema evolution) that is entirely separate from layout changes.

**Axis 2 — Multiple unrelated sub-views in one file.**
`WordSlotView`, `PendingTitleSetRow`, and `TitleSetBrowserRow` are fully self-contained views. They are `private` but their internal complexity and visual distinct purposes make them candidates for their own files. More critically, the three response-type structs at the bottom are domain/network types that happen to live in a view file.

---

## 4. Length Justification

821 lines is **not justified** for this file. The length is driven by:
1. Embedding two substantial async AI generation methods (with prompts and schemas) in the view
2. Three private sub-views that each could stand alone
3. Response types that belong in a service layer

A refactored version of the main view would be ~250–300 lines; the service would be ~200–250 lines; each sub-view ~60–100 lines.

---

## 5. Refactoring Plan

The refactoring has two mandatory splits and one optional quality-of-life split.

---

### Split 1 — Extract Generation Service (MANDATORY)

**New file:** `Sprung/Shared/Services/TitleSetGenerationService.swift`

**Purpose:** Encapsulates all AI-driven generation logic for title sets. Owns prompt construction, backend routing, LLMFacade calls, and response parsing. The view becomes a pure consumer of this service.

**What moves there (from `TitleSetsBrowserTab.swift`):**

| Content | Current lines |
|---|---|
| `TitleGenerationResponse` struct | 809–812 |
| `BulkTitleResponse` + `BulkTitleSet` structs | 814–820 |
| `getModelConfig()` method | 657–673 |
| `buildExperienceContext()` method | 639–655 |
| `buildApprovedContext()` method | 628–637 |
| `buildHistoryContext()` method | 608–626 |
| `generateWords()` method body | 361–481 |
| `bulkGenerate(count:)` method body | 483–606 |

**Service shape:**

```swift
// Sprung/Shared/Services/TitleSetGenerationService.swift

import Foundation
import SwiftOpenAI

@Observable
@MainActor
final class TitleSetGenerationService {

    private let llmFacade: LLMFacade

    init(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }

    func generate(
        currentWords: [TitleWord],
        instructions: String,
        conversationHistory: [GenerationTurn],
        approvedSets: [TitleSetRecord],
        skills: [Skill]
    ) async throws -> TitleGenerationResponse { ... }

    func bulkGenerate(
        count: Int,
        currentWords: [TitleWord],
        instructions: String,
        approvedSets: [TitleSetRecord],
        skills: [Skill]
    ) async throws -> BulkTitleResponse { ... }

    // context builders become private
    private func buildExperienceContext(skills: [Skill]) -> String { ... }
    private func buildApprovedContext(approvedSets: [TitleSetRecord]) -> String { ... }
    private func buildHistoryContext(history: [GenerationTurn]) -> String { ... }
    private func getModelConfig() -> (modelId: String, backend: LLMFacade.Backend) { ... }
}

// Response types (promote from private to internal — no access modifier needed)
struct TitleGenerationResponse: Codable { ... }
struct BulkTitleResponse: Codable { ... }
```

**View interaction after split:**

The view holds `@State private var generationService: TitleSetGenerationService?` (constructed lazily when `llmFacade` is non-nil) or receives it as an injected parameter. `generateWords()` and `bulkGenerate()` in the view become thin wrappers:

```swift
private func generateWords() async {
    guard let service = generationService else { return }
    isGenerating = true
    defer { isGenerating = false }
    do {
        let response = try await service.generate(
            currentWords: currentWords,
            instructions: instructions,
            conversationHistory: conversationHistory,
            approvedSets: titleSetStore?.allTitleSets ?? [],
            skills: skills
        )
        applyGenerationResponse(response)
    } catch {
        Logger.error("Title generation failed: \(error)", category: .ai)
        aiComment = "Generation failed. Please try again."
    }
}
```

**Access modifiers:** `TitleGenerationResponse` and `BulkTitleResponse` must change from `private` to `internal` (no modifier needed in Swift — remove the `private` keyword) so the view can reference them.

---

### Split 2 — Extract Sub-Views (MANDATORY)

Three private view types currently live in the main file. They should each get their own file under `Sprung/Shared/Views/TitleSets/`.

Create the directory: `Sprung/Shared/Views/TitleSets/`

#### 2a. WordSlotView

**New file:** `Sprung/Shared/Views/TitleSets/WordSlotView.swift`

**Lines moved:** 676–704 (the `WordSlotView` struct and its `// MARK:` header)

**Access modifier change:** Change `private struct WordSlotView` to `struct WordSlotView` (remove `private`).

**Content:**

```swift
// WordSlotView.swift
// Single editable word slot with lock toggle for the title set generator.

import SwiftUI

struct WordSlotView: View {
    @Binding var word: TitleWord
    let index: Int
    // ... body unchanged
}
```

#### 2b. PendingTitleSetRow

**New file:** `Sprung/Shared/Views/TitleSets/PendingTitleSetRow.swift`

**Lines moved:** 706–743

**Access modifier change:** `private struct PendingTitleSetRow` → `struct PendingTitleSetRow`

#### 2c. TitleSetBrowserRow

**New file:** `Sprung/Shared/Views/TitleSets/TitleSetBrowserRow.swift`

**Lines moved:** 745–805

**Access modifier change:** `private struct TitleSetBrowserRow` → `struct TitleSetBrowserRow`

No import changes are needed for any of these — all three only import SwiftUI and reference types already in the module.

---

### Split 3 — Move Main View to TitleSets Subdirectory (OPTIONAL / LOW PRIORITY)

If the `TitleSets/` subdirectory is created for the sub-views, the main tab file could also move to it for co-location:

**Rename/move:** `Sprung/Shared/Views/TitleSetsBrowserTab.swift` → `Sprung/Shared/Views/TitleSets/TitleSetsBrowserTab.swift`

This is cosmetic and can be deferred. Xcode's filesystem-synced groups will pick it up automatically on disk move.

---

## 6. File Dependency Map After Refactoring

```
TitleSetsBrowserTab.swift
  ├── imports SwiftUI
  ├── depends on: TitleSetGenerationService (new)
  ├── depends on: TitleSetStore, TitleSetRecord (existing)
  ├── depends on: TitleWord, GenerationTurn (existing, in TitleSetStore.swift)
  ├── depends on: LLMFacade (existing)
  ├── uses: WordSlotView (new file)
  ├── uses: PendingTitleSetRow (new file)
  └── uses: TitleSetBrowserRow (new file)

TitleSetGenerationService.swift
  ├── imports Foundation, SwiftOpenAI
  ├── depends on: LLMFacade (existing)
  ├── depends on: TitleWord, GenerationTurn (existing)
  ├── depends on: TitleSetRecord (existing)
  ├── depends on: Skill (existing)
  └── owns: TitleGenerationResponse, BulkTitleResponse

WordSlotView.swift         → imports SwiftUI, depends on TitleWord
PendingTitleSetRow.swift   → imports SwiftUI, depends on TitleWord
TitleSetBrowserRow.swift   → imports SwiftUI, depends on TitleSetRecord
```

---

## 7. What Stays in TitleSetsBrowserTab.swift

After all splits, the main file retains only:

- `TitleSetsBrowserTab` struct declaration and stored properties (lines 14–41)
- `body` (lines 43–54)
- `approvedCombinationsPanel` (lines 58–103)
- `pendingSection` (lines 107–138)
- `approvePendingSet`, `rejectPendingSet`, `deleteTitleSet` (lines 142–157)
- `emptyStateView` (lines 159–174)
- `generatorPanel` (lines 178–213)
- `wordSlotsGrid`, `instructionsField`, `aiCommentView`, `actionButtons` (lines 215–317)
- `lockedCount`, `hasValidWords` (lines 321–327)
- `loadTitleSet`, `saveCurrentSet`, `clearGenerator` (lines 331–359)
- Thin `generateWords()` and `bulkGenerate()` wrappers that call the service

Estimated remaining size: ~280–310 lines. That is appropriate for a complex interactive browser tab.

---

## 8. Implementation Order

1. Create `TitleSetGenerationService.swift` with the response types and all generation logic. Build to verify no import issues.
2. Wire `TitleSetsBrowserTab` to call the service instead of inline logic. Remove the inlined methods and response type definitions. Build.
3. Extract `WordSlotView`, `PendingTitleSetRow`, `TitleSetBrowserRow` into their own files one at a time (simplest last as a clean-up step). Build after each.
4. Optionally move `TitleSetsBrowserTab.swift` into `TitleSets/` subdirectory.

Each step is independently compilable and can be committed atomically.

---

## 9. Clean Break Verification Checklist

After completing the refactor:

- [ ] `grep -r "TitleGenerationResponse\|BulkTitleResponse" Sprung/` — results only in `TitleSetGenerationService.swift`
- [ ] `grep -rn "private struct WordSlotView\|private struct PendingTitleSetRow\|private struct TitleSetBrowserRow" Sprung/` — zero results
- [ ] `grep -rn "buildExperienceContext\|buildApprovedContext\|buildHistoryContext\|getModelConfig" Sprung/` — results only in `TitleSetGenerationService.swift`
- [ ] No `bridge`, `adapter`, `legacy`, `shim`, or `fallback` symbols introduced
- [ ] `TitleSetsBrowserTab.swift` has zero inlined prompt strings or JSON schema dictionaries
