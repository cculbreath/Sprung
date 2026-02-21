# UIResponseCoordinator Refactoring Analysis

File: `Sprung/Onboarding/Core/Coordinators/UIResponseCoordinator.swift`
Lines: 857
Functions: 27 (public + private)

---

## 1. Primary Responsibility / Purpose

`UIResponseCoordinator` is the single point of contact between UI-driven user actions and the LLM message pipeline. When a user interacts with any onboarding UI element — submitting a choice, uploading a file, confirming a profile, editing their timeline — the coordinator translates that raw UI event into a structured `UIToolCompletionResult` (which resumes an async continuation that the LLM is suspended on) and/or emits events onto the event bus.

Its stated purpose matches that narrow description. The problem is that "UI action → LLM result" is actually six entirely separate domains stacked inside one class.

---

## 2. Distinct Logical Sections

| MARK section | Lines | Methods | What it actually does |
|---|---|---|---|
| Choice Selection | 39–122 | 4 | Resolves `getUserOption` and `askUserSkipToNextPhase` tool continuations; forces phase transitions on skip approval |
| Forced Phase Transition | 124–152 | 1 (private) | Idempotency-guarded phase advance via event bus |
| Upload Handling | 153–197 | 2 | Completes/skips `getUserUpload` tool continuations |
| Validation Handling | 198–324 | 4 + 1 private | Resolves `submitForValidation`; manages timeline editor state; manages section cards state; forces phase transition on section cards done |
| Applicant Profile Handling | 347–527 | 4 | Resolves `validateApplicantProfile` / `getApplicantProfile`; fires objective chain; builds LLM result with URL hints |
| Section Toggle Handling | 528–589 | 2 | Resolves `configureEnabledSections`; sets `shouldGenerateTitleSets` flag; fires objective |
| Chat & Control | 590–636 | 2 | Sends chatbox messages; drains queue; dismisses prompts; cancels LLM |
| Direct File Upload | 638–685 | 1 | Processes drop-zone uploads via `OnboardingUploadStorage`; emits artifact event |
| Writing Sample Upload | 687–731 | 1 | Identical storage pipeline as direct upload with different metadata/requestKind |
| Timeline Handling | 733–771 | 2 (1 private) | Applies user-driven timeline edits; enqueues LLM notification |
| UI Tool Continuation / Helpers | 773–856 | 3 private | `completeUITool`, `buildCompletionResult`, `dismissPendingUIPrompts` |

---

## 3. Single Responsibility Principle Assessment

**UIResponseCoordinator violates SRP.** It has at minimum six distinct reasons to change:

1. **Choice prompt UX changes** — The format of option results, skip-phase approval logic, or how cancellation is signaled to the LLM.
2. **File upload pipeline changes** — How `OnboardingUploadStorage` works, what metadata fields are passed, what requestKind strings mean.
3. **Applicant profile workflow changes** — Objective chain order, what URL hints are embedded in tool results, photo upload next-step instructions.
4. **Validation / timeline editor lifecycle changes** — When `submit_for_validation` is ungated, what the "Done with Timeline" message says, timeline card summary format.
5. **Section toggle / section cards workflow changes** — Phase transition timing, `shouldGenerateTitleSets` flag logic.
6. **Chat / queue infrastructure changes** — How chatbox messages clear waiting state, how prompts are dismissed, drain gate interaction.

The shared helpers (`completeUITool`, `buildCompletionResult`, `dismissPendingUIPrompts`) are genuine shared infrastructure, but they are not the binding force that makes splitting impossible — they are two-liners that belong in a shared base or protocol extension.

---

## 4. Length Justification

857 lines is **not justified** by logical cohesion. The file is large because six independent workflow domains were accumulated into one place for convenience. Each domain is internally coherent, but the domains have no meaningful coupling to each other. A change to applicant profile objective ordering has zero impact on upload handling; a change to chatbox queue draining has zero impact on section toggle logic.

The length creates real maintenance friction: finding the validation methods requires scanning past 200+ lines of profile handling; understanding the upload pipeline requires reading around timeline code.

**Verdict: split.**

---

## 5. Refactoring Plan

### Guiding Principle

Extract each domain into its own `@MainActor final class`. The shared helpers (`completeUITool`, `buildCompletionResult`) become a tiny shared `UIToolCompletionBuilder` value type, or can simply be duplicated (they are two lines each) — but a shared type is cleaner. `dismissPendingUIPrompts` belongs with the chat/queue domain since it is only called from `sendChatMessage`.

`UIResponseCoordinator` itself survives as a thin facade that owns instances of the sub-coordinators and delegates every public method. `OnboardingDependencyContainer` and `OnboardingInterviewCoordinator` do not need changes at all — they continue calling `uiResponseCoordinator.someMethod()` and the facade forwards the call.

---

### New Files

All paths are relative to the project root `Sprung/`.

---

#### A. `Sprung/Onboarding/Core/Coordinators/UIToolResultBuilder.swift`

**Purpose:** Shared factory for building `UIToolCompletionResult` and completing UI tool continuations. Currently these are private methods on `UIResponseCoordinator` that every sub-coordinator needs. Extracting them eliminates duplication without introducing a heavyweight protocol.

**Contents (from current file):**

- Lines 781–793: `completeUITool(toolName:result:)` and `buildCompletionResult(status:message:data:)`

**Type:**

```swift
@MainActor
struct UIToolResultBuilder {
    private let continuationManager: UIToolContinuationManager

    init(continuationManager: UIToolContinuationManager) {
        self.continuationManager = continuationManager
    }

    func complete(toolName: String, result: UIToolCompletionResult) { ... }
    func buildResult(status: String, message: String, data: JSON? = nil) -> UIToolCompletionResult { ... }
}
```

**Access:** `internal` (same module). No `public` needed — this is an app target.

---

#### B. `Sprung/Onboarding/Core/Coordinators/ChoiceResponseHandler.swift`

**Purpose:** Handles all user actions on choice/option prompts, including the skip-phase approval special case and forced phase transitions triggered from a user choice.

**Contents (from current file):**

- Lines 38–122: `submitChoiceSelection`, `submitChoiceSelectionWithOther`, `cancelChoiceSelection`, `submitChoiceSelectionInternal` (private, becomes internal to this class)
- Lines 124–152: `forcePhaseTransition` (private — keep here since the only public caller of the private version is `completeSectionCardsAndAdvancePhase` in the Validation domain; see note below)

**Note on `forcePhaseTransition`:** This private method is currently called from two places: `submitChoiceSelectionInternal` (line 94) and `completeSectionCardsAndAdvancePhase` (line 342). If extracted, either (a) it becomes an `internal` method on `ChoiceResponseHandler` that `ValidationResponseHandler` calls, or (b) it is extracted into its own tiny `PhaseAdvanceService`. Option (a) is simpler. `ValidationResponseHandler` takes a reference to `ChoiceResponseHandler` (or just to a `PhaseAdvanceService`).

**Dependencies:** `EventCoordinator`, `ToolHandler`, `StateCoordinator`, `UIToolContinuationManager`, `UIToolResultBuilder`

---

#### C. `Sprung/Onboarding/Core/Coordinators/UploadResponseHandler.swift`

**Purpose:** Handles UI responses to LLM-initiated upload requests (`getUserUpload` tool) — completing or skipping pending upload continuations.

**Contents (from current file):**

- Lines 153–197: `completeUploadAndResume`, `skipUploadAndResume`

**Dependencies:** `UIToolResultBuilder`, `UIToolContinuationManager`, `OnboardingInterviewCoordinator` (passed per-call as already done — no structural change needed)

---

#### D. `Sprung/Onboarding/Core/Coordinators/ValidationResponseHandler.swift`

**Purpose:** Handles user responses to the `submitForValidation` tool prompt and manages the lifecycle of the timeline editor and section cards editor (both gated behind validation tooling).

**Contents (from current file):**

- Lines 198–345: `submitValidationAndResume`, `clearValidationPromptAndNotifyLLM`, `buildTimelineCardSummary` (private, stays private here), `completeTimelineEditingAndRequestValidation`, `completeSectionCardsAndAdvancePhase`

**Note:** `completeSectionCardsAndAdvancePhase` calls `forcePhaseTransition`. With the extraction to `ChoiceResponseHandler`, this method needs a reference to wherever `forcePhaseTransition` lives. The cleanest resolution is to make `forcePhaseTransition` a standalone internal function in a `PhaseAdvanceService` (see option below) or to pass `ChoiceResponseHandler` as a dependency. Since `forcePhaseTransition` only touches `EventCoordinator` and `StateCoordinator`, extracting it into a tiny internal helper that both handlers share is cleaner.

**Alternative:** Add a `PhaseAdvanceService` (see below) as a shared dependency instead of creating a cross-handler dependency.

**Dependencies:** `EventCoordinator`, `ToolHandler`, `StateCoordinator`, `OnboardingUIState`, `SessionUIState`, `UIToolResultBuilder`

---

#### E. `Sprung/Onboarding/Core/Coordinators/ProfileResponseHandler.swift`

**Purpose:** Handles all user interactions with applicant profile tooling — confirming, rejecting, submitting drafts, and submitting profile URLs.

**Contents (from current file):**

- Lines 347–527: `confirmApplicantProfile`, `rejectApplicantProfile`, `submitProfileDraft`, `submitProfileURL`

**Dependencies:** `EventCoordinator`, `ToolHandler`, `StateCoordinator`, `OnboardingUIState`, `UIToolResultBuilder`

---

#### F. `Sprung/Onboarding/Core/Coordinators/SectionToggleResponseHandler.swift`

**Purpose:** Handles user confirmation or rejection of the `configureEnabledSections` tool prompt.

**Contents (from current file):**

- Lines 528–589: `confirmSectionToggle`, `rejectSectionToggle`

**Dependencies:** `EventCoordinator`, `ToolHandler`, `StateCoordinator`, `OnboardingUIState`, `UIToolResultBuilder`

---

#### G. `Sprung/Onboarding/Core/Coordinators/ChatResponseHandler.swift`

**Purpose:** Handles chatbox message submission and LLM cancellation. Includes dismissal of pending UI prompts (which is a side effect that only `sendChatMessage` needs).

**Contents (from current file):**

- Lines 590–636: `sendChatMessage`, `requestCancelLLM`
- Lines 796–856: `dismissPendingUIPrompts` (private, stays private here — only called from `sendChatMessage`)

**Dependencies:** `EventCoordinator`, `ToolHandler`, `StateCoordinator`, `OnboardingUIState`, `SessionUIState`, `UIToolContinuationManager`, `UserActionQueue`, `DrainGate`, `QueueDrainCoordinator`, `UIToolResultBuilder`

---

#### H. `Sprung/Onboarding/Core/Coordinators/DirectUploadHandler.swift`

**Purpose:** Handles file uploads initiated by the user outside of a pending LLM upload request — drag-and-drop zone uploads and writing sample uploads.

**Contents (from current file):**

- Lines 638–731: `uploadFilesDirectly`, `uploadWritingSamples`

**Dependencies:** `EventCoordinator`

**Note:** These two methods share an identical `OnboardingUploadStorage` pipeline differing only in metadata and `requestKind`. After extraction, consider consolidating them into one method with a parameter — but that is a separate cleanup decision.

---

#### I. `Sprung/Onboarding/Core/Coordinators/TimelineResponseHandler.swift`

**Purpose:** Handles user-driven edits to the timeline data model and notifies the LLM.

**Contents (from current file):**

- Lines 733–771: `applyUserTimelineUpdate`, `buildTimelineCardSummarySync` (private, stays here)

**Dependencies:** `EventCoordinator`

---

### Optional: `PhaseAdvanceService`

If the shared `forcePhaseTransition` logic crossing `ChoiceResponseHandler` → `ValidationResponseHandler` feels awkward as a cross-handler call, extract it:

**File:** `Sprung/Onboarding/Core/Coordinators/PhaseAdvanceService.swift`

**Contents:** Just the 24 lines of `forcePhaseTransition` (lines 130–152), renamed to `advancePhase(to:reason:)`.

**Dependencies:** `EventCoordinator`, `StateCoordinator`

Both `ChoiceResponseHandler` and `ValidationResponseHandler` take `PhaseAdvanceService` as a constructor dependency.

---

### Revised `UIResponseCoordinator.swift`

After extraction, `UIResponseCoordinator` becomes a ~70-line facade:

```swift
@MainActor
final class UIResponseCoordinator {
    private let choiceHandler: ChoiceResponseHandler
    private let uploadHandler: UploadResponseHandler
    private let validationHandler: ValidationResponseHandler
    private let profileHandler: ProfileResponseHandler
    private let sectionToggleHandler: SectionToggleResponseHandler
    private let chatHandler: ChatResponseHandler
    private let directUploadHandler: DirectUploadHandler
    private let timelineHandler: TimelineResponseHandler

    init(...) { ... }

    // MARK: - Choice Selection
    func submitChoiceSelection(_ selectionIds: [String]) async {
        await choiceHandler.submitChoiceSelection(selectionIds)
    }
    // ... one-line delegates for every public method
}
```

No call sites in `OnboardingInterviewCoordinator` change. No changes to `OnboardingDependencyContainer` beyond constructing the additional handler types (or constructing `UIResponseCoordinator` with handler instances).

---

### Dependency Wiring in `OnboardingDependencyContainer`

`UIToolResultBuilder` is constructed once and injected into each handler. All handlers are constructed lazily (consistent with existing container pattern) and stored as `let` properties on the container, or are constructed inline inside `UIResponseCoordinator`'s `init` if they require no container-level lifetime management beyond the coordinator.

---

## 6. Summary Table

| New File | Lines (approx.) | Moved From |
|---|---|---|
| `UIToolResultBuilder.swift` | ~30 | Lines 781–793 |
| `ChoiceResponseHandler.swift` | ~110 | Lines 38–152 |
| `UploadResponseHandler.swift` | ~50 | Lines 153–197 |
| `ValidationResponseHandler.swift` | ~130 | Lines 198–345 |
| `ProfileResponseHandler.swift` | ~175 | Lines 347–527 |
| `SectionToggleResponseHandler.swift` | ~65 | Lines 528–589 |
| `ChatResponseHandler.swift` | ~115 | Lines 590–636, 796–856 |
| `DirectUploadHandler.swift` | ~100 | Lines 638–731 |
| `TimelineResponseHandler.swift` | ~45 | Lines 733–771 |
| `PhaseAdvanceService.swift` (optional) | ~30 | Lines 124–152 |
| `UIResponseCoordinator.swift` (revised) | ~70 | Facade only |

**Total lines preserved:** 857 (same code, reorganized). No logic changes required.

---

## 7. Implementation Order

1. Create `UIToolResultBuilder.swift` — no dependencies on other new files.
2. Create `PhaseAdvanceService.swift` (if chosen) — depends only on `EventCoordinator`, `StateCoordinator`.
3. Create `ChoiceResponseHandler.swift` — depends on `UIToolResultBuilder`, optionally `PhaseAdvanceService`.
4. Create `ValidationResponseHandler.swift` — depends on `UIToolResultBuilder`, optionally `PhaseAdvanceService`.
5. Create remaining handlers (`UploadResponseHandler`, `ProfileResponseHandler`, `SectionToggleResponseHandler`, `ChatResponseHandler`, `DirectUploadHandler`, `TimelineResponseHandler`) in any order — each is independent.
6. Rewrite `UIResponseCoordinator.swift` as facade.
7. Build. Fix any access-level or import issues.
