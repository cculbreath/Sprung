# Refactor Assessment: OnboardingInterviewCoordinator.swift

**File:** `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`
**Lines:** 1,150
**Functions:** ~65 (public + private)

---

## 1. Primary Responsibility / Purpose

`OnboardingInterviewCoordinator` is the **application facade** for the onboarding interview subsystem. It is the single object that SwiftUI views, tools, and app-level code receive through `@Environment` injection to interact with everything inside the interview. It delegates nearly all real work to services inside `OnboardingDependencyContainer`; its own methods are almost entirely one- or two-line pass-throughs.

Its declared purpose: expose a unified, view-friendly API over the event-driven onboarding architecture.

---

## 2. Distinct Logical Sections

| # | MARK Section | Lines | What It Does |
|---|---|---|---|
| 1 | Dependency Container | 9–10 | Holds `OnboardingDependencyContainer` |
| 2 | Public Dependencies | 11–20 | Computed vars forwarding to container sub-services for View access |
| 3 | Public Sub-Services | 21–30 | Additional computed service accessors |
| 4 | Private Accessors | 31–48 | Private computed vars for internal delegation |
| 5 | Computed Properties | 49–84 | `currentPhase`, `artifacts`, session/knowledge card queries |
| 6 | Multi-Agent Infrastructure | 86–111 | Trackers and debug store accessors |
| 7 | User Action Queue Infrastructure | 113–126 | `userActionQueue`, `drainGate`, `queueDrainCoordinator` |
| 8 | UI State Properties (from ToolRouter) | 127–148 | Six `pendingXxx` computed vars forwarding to `toolRouter` |
| 9 | Initialization | 149–197 | Container construction, late init, event subscription setup |
| 10 | Event Subscription | 198–201 | `subscribeToEvents()` – one-liner delegation |
| 11 | State Updates | 202–206 | `subscribeToStateUpdates()` – one-liner delegation |
| 12 | Interview Lifecycle | 207–216 | `startInterview`, `hasActiveSession` – one-liner delegations |
| 13 | UI Tool Interruption | 217–258 | `interruptPendingUITools()` – 40 lines of real logic |
| 14 | User Action Helpers | 327–445 | `ensureUserActionSucceeds`, `completeWritingSamplesCollection`, `skipWritingSamplesCollection` – 3 methods with LLM message-building logic |
| 15 | Evidence Handling | 447–450 | One-line delegation to `artifactIngestionCoordinator` |
| 16 | Objective Management | 451–471 | `updateObjectiveStatus` – event publish + JSON construction |
| 17 | Timeline Management | 472–492 | `applyUserTimelineUpdate`, `deleteTimelineCardFromUI` – second method has UI mutation logic |
| 18 | Artifact Queries | 493–513 | Four one-liner delegations to `state` and `eventBus` |
| 19 | Artifact Ingestion | 515–537 | `startGitRepoAnalysis`, `fetchURLForArtifact` |
| 20 | Tool Management | 539–638 | `presentUploadRequest`, `completeUpload`, `skipUpload`, `submitValidationResponse` – `submitValidationResponse` is the largest method (75 lines) with complex phase-driven objective + LLM-message logic |
| 21 | Applicant Profile Intake | 641–668 | Seven thin delegations to `toolRouter` / `uiResponseCoordinator` |
| 22 | Phase Advance | 669–708 | `advanceToNextPhaseFromUI`, `requestPhaseAdvanceFromUI` (legacy shell) |
| 23 | UI Response Handling | 709–887 | ~20 delegation methods plus `stopProcessing` (30 lines), `interruptWithMessage`, `deleteArtifactRecord` (30 lines), `demoteArtifact` (20 lines), `sendCoordinatorMessage` |
| 24 | Archived Artifacts Management | 889–931 | Six delegations to `artifactArchiveManager` |
| 25 | Data Store Management | 999–1005 | Two one-liner delegations to `lifecycleController` |
| 26 | Utility | 1006–1012 | `clearModelAvailabilityMessage`, `transcriptExportString` |
| 27 | Debug Event Diagnostics (`#if DEBUG`) | 1013–1149 | 10 debug-only methods, one of which (`resetAllOnboardingData`) is 47 lines of direct file-system and SwiftData manipulation |

---

## 3. Single Responsibility Principle Assessment

### Verdict: MIXED — the coordinator is largely a justified facade, but contains two genuine SRP violations that inflate it significantly.

### What IS justified

The vast majority of the file (roughly 800 of 1,150 lines) is boilerplate accessor delegation:

- Computed `var` properties forwarding container members to views (lines 11–148)
- One- and two-liner `func` methods that call a single sub-service (the majority of sections 10–12, 14–26)

This pattern is the deliberate price of using a **Facade** over a dependency container. The coordinator's role is to be the single injection point for ~25 downstream services, so views never import internals. A facade of this size is not a SRP violation in itself — it has one reason to change: the public API contract with views and tools.

### What IS a SRP violation

Three areas contain real logic that belongs elsewhere:

---

#### Violation A: `submitValidationResponse` (lines 563–638, ~75 lines)

This method does four conceptually distinct things:
1. Forwards the validation result to `toolRouter`
2. Publishes a `knowledgeCardPersisted` event when conditions match
3. When the data type is `skeleton_timeline` and the user approved: publishes an objective completion event AND constructs a `sendCoordinatorMessage` payload with hard-coded LLM prompt text
4. When the data type is `section_cards` and the user approved: does the same for a different objective

The conditional phase-specific objective-update-then-LLM-prompt logic (lines 591–636) belongs in `UIResponseCoordinator`, which already handles all other `submitValidation*` concerns. The coordinator should not know which data types require which follow-up objective events.

---

#### Violation B: `interruptPendingUITools` (lines 231–258, ~28 lines)

This method clears tool router state, publishes multiple cancellation events to the event bus, then calls `uiToolContinuationManager.interruptAll()`. The multi-step event publishing sequence is orchestration logic, not facade delegation. It belongs in `UIResponseCoordinator` or a dedicated `UIInterruptionHandler`, matching the pattern used for `stopProcessing` (which delegates to `uiResponseCoordinator` and `agentActivityTracker`).

---

#### Violation C: `resetAllOnboardingData` in `#if DEBUG` (lines 1102–1148, ~47 lines)

This method directly manipulates `ApplicantProfile` fields, deletes files from `applicationSupportDirectory`, calls `MainActor.run` blocks, and coordinates with multiple stores. `OnboardingDataResetService` already exists (per the comment in `OnboardingDataResetService.swift`: "Extracted from OnboardingInterviewCoordinator to follow Single Responsibility Principle"). This method was not moved there, leaving a partial migration.

---

#### Minor observation: `completeWritingSamplesCollection` and `skipWritingSamplesCollection` (lines 352–445)

These methods build and publish `SwiftyJSON` LLM message payloads directly. While this is a grey area — they are user-action handlers that must produce side effects — the inline JSON construction and hard-coded prompt strings are a maintainability concern. However, given that `UIResponseCoordinator` already exists and handles analogous methods (`completeTimelineEditingAndRequestValidation`, `completeSectionCardsAndAdvancePhase`), these methods are candidates for migration to `UIResponseCoordinator` as part of the same pass.

---

## 4. Should It Be Refactored?

**Yes — but surgically.** The file does not need to be broken into many pieces. Three targeted moves eliminate the violations cleanly.

The goal is: every method in `OnboardingInterviewCoordinator` becomes a one-liner delegation. No method should contain conditional branching on data types or inline JSON/LLM prompt construction.

---

## 5. Concrete Refactoring Plan

### Move 1 — Push `submitValidationResponse` logic into `UIResponseCoordinator`

**File:** `Sprung/Onboarding/Core/Coordinators/UIResponseCoordinator.swift`

**What moves:** Lines 563–638 of `OnboardingInterviewCoordinator.swift` — the entire `submitValidationResponse` body, including:
- The `knowledgeCardPersisted` event publish
- The `skeleton_timeline` conditional block (objective update + `sendCoordinatorMessage` payload)
- The `section_cards` conditional block (objective update + `sendCoordinatorMessage` payload)
- The `validationPromptCleared` event publish

**New signature in `UIResponseCoordinator`:**
```swift
func submitValidationResponse(
    status: String,
    updatedData: JSON?,
    changes: JSON?,
    notes: String?
) async -> JSON?
```

**Coordinator replacement (lines 563–638 collapse to):**
```swift
func submitValidationResponse(
    status: String,
    updatedData: JSON?,
    changes: JSON?,
    notes: String?
) async -> JSON? {
    await uiResponseCoordinator.submitValidationResponse(
        status: status,
        updatedData: updatedData,
        changes: changes,
        notes: notes
    )
}
```

**Dependencies `UIResponseCoordinator` needs access to** (check current implementation for what it already holds):
- `toolRouter: ToolHandler` — to call `pendingValidationPrompt` and `submitValidationResponse`
- `eventBus: EventCoordinator` — already used by `UIResponseCoordinator`

If `UIResponseCoordinator` does not currently hold `toolRouter`, inject it via the existing initializer path through `OnboardingDependencyContainer`. Do not create a new container accessor — wire it at container construction time.

**Access level:** `UIResponseCoordinator.submitValidationResponse` stays `internal` (same module).

---

### Move 2 — Push `interruptPendingUITools` into `UIResponseCoordinator`

**File:** `Sprung/Onboarding/Core/Coordinators/UIResponseCoordinator.swift`

**What moves:** Lines 231–258 — the entire `interruptPendingUITools` body:
- `toolRouter.clearChoicePrompt()` / `clearValidationPrompt()` / `clearPendingUploadRequests()` / `clearSectionToggle()`
- The `Task { await eventBus.publish(...) }` block for all five cancellation events
- `uiToolContinuationManager.interruptAll()`

**New signature in `UIResponseCoordinator`:**
```swift
func interruptPendingUITools() async
```

**Coordinator replacement:**
```swift
var hasPendingUITools: Bool {
    uiToolContinuationManager.hasPendingTools
}

var pendingUIToolNames: [String] {
    uiToolContinuationManager.pendingToolNames
}

func interruptPendingUITools() async {
    await uiResponseCoordinator.interruptPendingUITools()
}
```

**Note:** The guard `hasPendingUITools` check at line 232 moves inside the new method in `UIResponseCoordinator`. The coordinator's two computed properties (`hasPendingUITools`, `pendingUIToolNames`) remain as-is — they are pure pass-throughs and belong on the coordinator for view access.

**Dependencies needed by `UIResponseCoordinator`:**
- `toolRouter: ToolHandler` (same as Move 1)
- `uiToolContinuationManager: UIToolContinuationManager` — inject via container
- `eventBus: EventCoordinator` — already present

---

### Move 3 — Move `resetAllOnboardingData` into `OnboardingDataResetService`

**File:** `Sprung/Onboarding/Services/OnboardingDataResetService.swift`

**What moves:** Lines 1102–1148 (inside `#if DEBUG`) — the entire `resetAllOnboardingData` method body.

**New signature in `OnboardingDataResetService`:**
```swift
#if DEBUG
func resetAllOnboardingData() async
#endif
```

`OnboardingDataResetService` already holds references to all the stores this method needs (it already contains `clearAllOnboardingData` and `deleteCurrentSession`). Verify it has:
- `knowledgeCardStore: KnowledgeCardStore`
- `applicantProfileStore: ApplicantProfileStore`
- `artifactRecordStore: ArtifactRecordStore` or lifecycle handle for `clearArtifacts`

If any are missing, add them to `OnboardingDataResetService`'s initializer (injected from the container — no singletons).

**Coordinator replacement:**
```swift
#if DEBUG
func resetAllOnboardingData() async {
    await container.dataResetService.resetAllOnboardingData()
}
#endif
```

---

### Optional Move 4 — `completeWritingSamplesCollection` and `skipWritingSamplesCollection` into `UIResponseCoordinator`

**Priority:** Lower — address in a follow-up pass if desired.

**Lines:** 352–445 (~93 lines total for both methods)

**Rationale:** These methods build `SwiftyJSON` payloads and publish LLM messages inline. `UIResponseCoordinator` already holds the same pattern for `completeTimelineEditingAndRequestValidation` and `completeSectionCardsAndAdvancePhase`.

**Move to:** `Sprung/Onboarding/Core/Coordinators/UIResponseCoordinator.swift`

**Coordinator replacements:**
```swift
func completeWritingSamplesCollection() async {
    await uiResponseCoordinator.completeWritingSamplesCollection()
}

func skipWritingSamplesCollection() async {
    await uiResponseCoordinator.skipWritingSamplesCollection()
}
```

`UIResponseCoordinator` will need the `ui: OnboardingUIState` reference (for `ui.phase` check) and `container.sessionUIState` access — check what it already holds. The `ensureUserActionSucceeds` helper (lines 332–346) can either move with them or be re-implemented inline in `UIResponseCoordinator` using the same pattern.

---

## 6. What Does NOT Need to Change

- The entire accessor/computed-var section (lines 9–148) — this is the facade's value, not a violation.
- Sections: Event Subscription, State Updates, Interview Lifecycle, Evidence Handling, Objective Management, Artifact Queries, Artifact Ingestion, Applicant Profile Intake, Phase Advance, UI Response Handling (the delegating methods), Archived Artifacts Management, Data Store Management, Utility — all of these are already correct one-liner delegations.
- The `#if DEBUG` debug event diagnostics methods (lines 1015–1100 except `resetAllOnboardingData`) — these are thin pass-throughs to `debugRegenerationService` and `eventBus`. They are acceptable as-is.

---

## 7. Post-Refactor Expected State

After Moves 1–3 (mandatory):

| Metric | Before | After |
|---|---|---|
| Total lines | 1,150 | ~990 |
| Methods with real logic | 5 | 2 (write-samples methods, if Move 4 deferred) |
| SRP violations | 3 | 0 |
| Methods > 20 lines | 4 | 0–1 |

Every method in `OnboardingInterviewCoordinator` becomes a one-liner delegation or a trivial computed property. The coordinator's sole responsibility is maintained: expose the unified interface, delegate everything else.

---

## 8. File Interaction Summary

```
OnboardingInterviewCoordinator
    → container.uiResponseCoordinator.submitValidationResponse(...)   [Move 1]
    → container.uiResponseCoordinator.interruptPendingUITools()        [Move 2]
    → container.dataResetService.resetAllOnboardingData()              [Move 3]
    → container.uiResponseCoordinator.completeWritingSamplesCollection() [Move 4, optional]
    → container.uiResponseCoordinator.skipWritingSamplesCollection()     [Move 4, optional]

UIResponseCoordinator (gains):
    - submitValidationResponse logic (needs toolRouter injection)
    - interruptPendingUITools logic (needs toolRouter + uiToolContinuationManager injection)
    - [optional] writing sample completion methods

OnboardingDataResetService (gains):
    - resetAllOnboardingData #if DEBUG method
```

No new files are needed. No new types. No access-level changes required — all moves stay within the same module (`Sprung`), so `internal` access is sufficient throughout.

**Before committing:** Grep for `resetAllOnboardingData`, `submitValidationResponse`, and `interruptPendingUITools` to confirm zero duplicate implementations remain after the move.
