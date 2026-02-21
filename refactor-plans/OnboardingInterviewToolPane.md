# Refactor Plan: OnboardingInterviewToolPane.swift

**File:** `Sprung/Onboarding/Views/Components/OnboardingInterviewToolPane.swift`
**Line count:** 1,084
**Assessment date:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`OnboardingInterviewToolPane` is the right-hand side panel of the onboarding interview screen. Its job is to host the `ToolPaneTabsView` tab container and supply the content for the "Interview" tab. It also manages pane-level drop-zone behavior and signals to its parent (`OnboardingInterviewInteractiveCard`) whether the pane is "occupied" (showing actionable content that should suppress the spinner).

---

## 2. Distinct Logical Sections

| Section | Lines | Description |
|---|---|---|
| Root view + overlays | 16–110 | `body`: wraps `ToolPaneTabsView`, drop-zone highlight border, `ExtractionProgressOverlay` / `AnimatedThinkingText` overlays, `.onDrop`, `.alert` for skip warning |
| Pane drop handling | 112–162 | `handlePaneDrop` — routes file drops to the correct coordinator action based on current phase and pending upload requests |
| Interview tab layout | 164–196 | `interviewTabContent` — VStack with `interviewTabMainContent` + `SkipToNextPhaseCard` footer |
| Interactive card dispatch | 197–276 | `interviewTabMainContent` — long `if/else if` chain selecting which card to surface (upload requests, intake, choice prompt, validation, profile review, section toggle, profile summary, writing sample placeholder, phase default) |
| Validation routing | 278–307 | `validationContent` — routes to `KnowledgeCardValidationHost`, `EmptyView`, or `OnboardingValidationReviewCard` based on `dataType` |
| Phase-specific default content | 309–427 | `phaseSpecificInterviewContent` — `switch` on phase; shows `DocumentCollectionView`, `CardReviewWithStickyFooter`, `Phase1WritingSampleView`, or `InterviewTabEmptyState` |
| File panel helpers | 429–466 | `openWritingSamplePanel()` and `openDirectUploadPanel()` — configure and open `NSOpenPanel` |
| Upload request rendering | 467–529 | `uploadRequestsView(_:)` and `uploadRequests()` — filter pending uploads by wizard step and render `UploadRequestCard` list |
| Upload panel routing | 530–570 | `openPanel(for:)` and `allowedContentTypes(for:)` — open `NSOpenPanel` configured for a specific `OnboardingUploadRequest` |
| Pane occupation helpers | 571–604 | `isPaneOccupied`, `hasInteractiveCard`, `hasSummaryCard` — compute whether pane has live content |
| Phase 1 display predicates | 606–635 | `shouldShowWritingSampleUI`, `shouldShowProfileUntilTimelineLoads` — derived booleans controlling which Phase 1 content shows |
| Skip-to-complete safety check | 637–672 | `checkForMissingGoals()` — inspects stores to find which interview goals lack persisted data |
| Private struct: ExtractionProgressOverlay | 674–703 | Animated overlay showing document extraction progress |
| Private struct: KnowledgeCardValidationHost | 704–748 | Stateful host for editing a `KnowledgeCardDraft` inline |
| Private struct: ApplicantProfileSummaryCard | 749–838 | Displays profile fields (name, email, phone, location, image) from a `JSON` blob |
| Private struct: InterviewTabEmptyState | 840–906 | Phase-keyed icon + title + description shown when nothing else is active |
| Private struct: CardReviewWithStickyFooter | 908–1015 | Scrollable knowledge card + skills list with a sticky "Approve" footer |
| Private struct: SkipToNextPhaseCard | 1017–1084 | Button card for advancing to the next phase, with phase-specific labels |

---

## 3. SRP Assessment

The file violates SRP in two distinct ways.

**Violation 1 — The main struct does too much.**
`OnboardingInterviewToolPane` has five distinct responsibilities:

1. Hosting the tab container and its overlays (visual orchestration)
2. Routing pane-level file drops to the correct coordinator action (drop handling logic)
3. Dispatching interactive card rendering based on coordinator state (content switching)
4. Opening `NSOpenPanel` sessions for three different upload contexts (file I/O)
5. Filtering and computing upload requests by wizard step (business logic)

Responsibilities 4 and 5 in particular are pure coordination/logic that has nothing to do with the view hierarchy and carry non-trivial branching (the `uploadRequests()` function and the three `NSOpenPanel` helpers). `checkForMissingGoals()` also reaches directly into multiple stores to do a pre-flight business check; it belongs in a helper rather than a view.

**Violation 2 — Five private structs are bundled into the same file.**
Each of the five `private struct` views below the main struct is a cohesive, independently testable view that happens to be used only from this file. Bundling them here inflates the file to 1,084 lines and makes the file difficult to navigate. They range in complexity from trivial (`InterviewTabEmptyState`, `SkipToNextPhaseCard`) to substantial (`KnowledgeCardValidationHost`, `CardReviewWithStickyFooter`, `ApplicantProfileSummaryCard`).

**Overall verdict: the file should be split.**

---

## 4. Refactoring Plan

### Strategy

- Extract the five private structs into their own files.
- Extract the file-panel and upload-filtering logic out of the main struct into a focused helper object.
- Keep the main struct responsible only for view assembly + overlay + drop-zone + tab switching.

No access modifiers need to change because all extracted structs remain `private` within a narrower scope OR can simply be `internal` (Swift default) since they live in the same module. Because they are currently only consumed from within this one file, making them `internal` (file-private to module level) is fine — `ToolPaneTabsView.Tab` is already `internal`.

---

### New Files

#### File 1 — `ExtractionProgressOverlay.swift`

**Path:** `Sprung/Onboarding/Views/Components/ExtractionProgressOverlay.swift`
**Source lines:** 674–703
**Purpose:** Self-contained animated overlay shown during document extraction. Zero dependencies on the parent view. No `private` qualifier needed — `struct ExtractionProgressOverlay: View` at module scope.
**Interactions:** Used in `OnboardingInterviewToolPane.body`. No imports beyond `SwiftUI`.

---

#### File 2 — `KnowledgeCardValidationHost.swift`

**Path:** `Sprung/Onboarding/Views/Components/KnowledgeCardValidationHost.swift`
**Source lines:** 704–748
**Purpose:** Manages a mutable `KnowledgeCardDraft` and delegates approve/reject actions back to the coordinator. Has its own `@State` so it must remain a discrete struct. No `private` qualifier; `struct KnowledgeCardValidationHost: View`.
**Interactions:** Used in `OnboardingInterviewToolPane.validationContent(_:)`. Needs `SwiftUI`, `SwiftyJSON` (for `KnowledgeCardDraft` init from `JSON`), and the Onboarding module types (`OnboardingValidationPrompt`, `ArtifactRecord`, `ArtifactDisplayInfo`, `KnowledgeCardDraft`, `KnowledgeCardReviewCard`, `OnboardingInterviewCoordinator`).

---

#### File 3 — `ApplicantProfileSummaryCard.swift`

**Path:** `Sprung/Onboarding/Views/Components/ApplicantProfileSummaryCard.swift`
**Source lines:** 749–838
**Purpose:** Displays read-only profile data from a `SwiftyJSON.JSON` blob. Purely presentational with no coordinator dependency.
**Interactions:** Used in `OnboardingInterviewToolPane.interviewTabMainContent`. Needs `SwiftUI`, `SwiftyJSON`, `AppKit` (for `NSImage`). `struct ApplicantProfileSummaryCard: View` at module scope.

---

#### File 4 — `InterviewTabEmptyState.swift`

**Path:** `Sprung/Onboarding/Views/Components/InterviewTabEmptyState.swift`
**Source lines:** 840–906
**Purpose:** Simple phase-keyed icon/title/message empty state. No logic or state beyond a `let phase: InterviewPhase`.
**Interactions:** Used in `phaseSpecificInterviewContent` and one place in `interviewTabContent`. `struct InterviewTabEmptyState: View`.

---

#### File 5 — `CardReviewWithStickyFooter.swift`

**Path:** `Sprung/Onboarding/Views/Components/CardReviewWithStickyFooter.swift`
**Source lines:** 908–1015
**Purpose:** Scrollable card/skills list with a sticky "Approve & Add" footer button. Moderately complex; contains its own computed properties derived from coordinator state.
**Interactions:** Used in `phaseSpecificInterviewContent` for phases 2 and 3. Needs `SwiftUI` and the Onboarding module types. `struct CardReviewWithStickyFooter: View`.

---

#### File 6 — `SkipToNextPhaseCard.swift`

**Path:** `Sprung/Onboarding/Views/Components/SkipToNextPhaseCard.swift`
**Source lines:** 1017–1084
**Purpose:** Phase-advance button card with per-phase label copy. Purely presentational; only dependency is `InterviewPhase`.
**Interactions:** Used in `interviewTabContent`. `struct SkipToNextPhaseCard: View`.

---

#### File 7 — `ToolPaneUploadHandler.swift` (new helper)

**Path:** `Sprung/Onboarding/Views/Components/ToolPaneUploadHandler.swift`
**Purpose:** Extract the file-panel opening logic and upload-request filtering from the main struct. This is not a view — it is a plain `struct` (or `enum` with static methods if no stored state is needed) that handles `NSOpenPanel` configuration and the `uploadRequests()` phase-keyed filtering.

**Lines to move out of the main struct:**

| Method | Current lines |
|---|---|
| `uploadRequests()` | 490–529 |
| `openPanel(for:)` | 530–549 |
| `allowedContentTypes(for:)` | 550–570 |
| `openWritingSamplePanel()` | 429–445 |
| `openDirectUploadPanel()` | 447–466 |

**Proposed signature:**

```swift
// Sprung/Onboarding/Views/Components/ToolPaneUploadHandler.swift

import AppKit
import UniformTypeIdentifiers

struct ToolPaneUploadHandler {

    static func uploadRequests(
        for step: WizardStep,
        pending: [OnboardingUploadRequest]
    ) -> [OnboardingUploadRequest]

    static func openWritingSamplePanel(
        onComplete: @escaping ([URL]) -> Void
    )

    static func openDirectUploadPanel(
        onComplete: @escaping ([URL]) -> Void
    )

    static func openPanel(
        for request: OnboardingUploadRequest,
        onComplete: @escaping ([URL]) -> Void
    )

    static func allowedContentTypes(
        for request: OnboardingUploadRequest
    ) -> [UTType]?
}
```

The `coordinator` callbacks currently embedded in the `NSOpenPanel.begin` closures become simple `([URL]) -> Void` parameters, which makes the helper testable without a coordinator. The call sites in the main struct pass `{ urls in Task { await coordinator.uploadWritingSamples(urls) } }` etc., keeping the async coordinator bridging in the view layer where it belongs.

**Interactions:** Called from `OnboardingInterviewToolPane` and from `phaseSpecificInterviewContent` (which lives in the same main struct). Needs `AppKit`, `UniformTypeIdentifiers`, and the Onboarding model types (`OnboardingUploadRequest`, `WizardStep`, `OnboardingUploadRequestKind`).

---

### What Remains in `OnboardingInterviewToolPane.swift`

After extraction the main file retains:

- `struct OnboardingInterviewToolPane: View` with `body` (lines 16–110 less drop-routing internals now delegated to `ToolPaneUploadHandler`)
- `handlePaneDrop(providers:)` (lines 114–162) — phase routing logic; stays because it coordinates directly with `coordinator`
- `interviewTabContent` (lines 166–196)
- `interviewTabMainContent` (lines 198–276)
- `validationContent(_:)` (lines 278–307)
- `phaseSpecificInterviewContent` (lines 309–427) — call sites updated to use `ToolPaneUploadHandler.openWritingSamplePanel` / `openDirectUploadPanel`
- `isPaneOccupied`, `hasInteractiveCard`, `hasSummaryCard` (lines 571–604)
- `shouldShowWritingSampleUI`, `shouldShowProfileUntilTimelineLoads` (lines 606–635)
- `checkForMissingGoals()` (lines 637–672)

Estimated post-extraction line count for the main file: **~380 lines**, which is appropriate for a view that orchestrates several sub-views and moderately complex conditional content switching.

---

## 5. File Interaction Summary

```
OnboardingInterviewToolPane.swift
    imports (uses, same module, no explicit import needed):
        ExtractionProgressOverlay
        KnowledgeCardValidationHost
        ApplicantProfileSummaryCard
        InterviewTabEmptyState
        CardReviewWithStickyFooter
        SkipToNextPhaseCard
        ToolPaneUploadHandler   ← new helper struct

    calls back up to:
        OnboardingInterviewCoordinator (via @Bindable)
        ApplicantProfileStore, ExperienceDefaultsStore, CoverRefStore (via @Environment)
```

All extracted files reside in the same directory (`Sprung/Onboarding/Views/Components/`) and the same Swift module (`Sprung`), so no `import` statements are needed between them. The only access modifier change is removing `private` from the five struct declarations so they are accessible at module scope (still not public to the outside world).

---

## 6. Access Modifier Changes Required

| Type | Before | After |
|---|---|---|
| `ExtractionProgressOverlay` | `private struct` (in ToolPane file) | `struct` (internal, new file) |
| `KnowledgeCardValidationHost` | `private struct` (in ToolPane file) | `struct` (internal, new file) |
| `ApplicantProfileSummaryCard` | `private struct` (in ToolPane file) | `struct` (internal, new file) |
| `InterviewTabEmptyState` | `private struct` (in ToolPane file) | `struct` (internal, new file) |
| `CardReviewWithStickyFooter` | `private struct` (in ToolPane file) | `struct` (internal, new file) |
| `SkipToNextPhaseCard` | `private struct` (in ToolPane file) | `struct` (internal, new file) |
| `ToolPaneUploadHandler` | (does not exist) | `struct` (internal, new file) |

No types need to become `public` — this is all intra-module sharing.

---

## 7. Implementation Order

Recommended sequence to keep the file compiling at each step:

1. Create `ToolPaneUploadHandler.swift` with static methods. Update call sites in the main struct. Build to confirm no regressions.
2. Move `ExtractionProgressOverlay` to its own file (trivial — no state).
3. Move `InterviewTabEmptyState` to its own file (trivial — no state).
4. Move `SkipToNextPhaseCard` to its own file.
5. Move `CardReviewWithStickyFooter` to its own file.
6. Move `ApplicantProfileSummaryCard` to its own file.
7. Move `KnowledgeCardValidationHost` to its own file (last, because it has `@State` and `SwiftyJSON` dependency; verify `onChange(of: prompt.id)` still compiles correctly).
8. Final build and smoke-test.
