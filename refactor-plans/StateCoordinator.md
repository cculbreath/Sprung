# StateCoordinator.swift — Refactor Assessment

File: `Sprung/Onboarding/Core/StateCoordinator.swift`
Lines: 947
Date assessed: 2026-02-18

---

## 1. Primary Responsibility / Purpose

`StateCoordinator` is an `actor` that serves as the **authoritative runtime state container for the onboarding interview session**. It is the single object that aggregates access to every domain service and exposes a unified async API to the rest of the system.

Its declared self-description ("thin orchestrator") is aspirationally accurate: it delegates nearly all domain logic to injected services. But the file still has two concrete residual responsibilities of its own that are not fully delegated:

1. **Tool response batch coordination** — it owns `collectedToolResponsePayloads` and the logic that decides when all ConversationLog slots are filled and a batch is ready to enqueue (lines 392–433).
2. **Wizard progress computation** — it owns `WizardStep`, `currentWizardStep`, `completedWizardSteps`, and the `updateWizardProgress()` method that queries `ObjectiveStore` and computes which wizard steps are complete (lines 54–241).

Everything else in the file is either:
- **Pure delegation** — a method that forwards its arguments to an injected service with no added logic (the majority of lines 626–946).
- **Event routing** — `handleXxxEvent` methods that match on event cases and call service methods.
- **Retry logic** — the exponential backoff `retryToolResponses` method (lines 583–605).

---

## 2. Distinct Logical Sections

| Section | Lines | What it does |
|---|---|---|
| Type / property declarations | 1–70 | `PhasePolicy` struct; all stored properties |
| Initialization | 71–100 | Wires injected services; creates `StreamQueueManager` and `LLMStateManager` internally |
| Agent activity tracking | 102–149 | `setAgentActivityTracker`, `getRunningAgentStatus`, `getRunningAgentCount`, `getRecentlyCompletedAgents` |
| Phase management | 151–190 | `setPhase`, `restorePhase`, `setUserApprovedKCSkip` |
| Wizard progress computation | 192–241 | `updateWizardProgress` — queries ObjectiveStore, maps objectives to wizard steps, owns `WizardStep` enum |
| Event subscription setup | 242–297 | `startEventSubscriptions` — creates `Task` with `withTaskGroup` subscribing to 8 event topics |
| Event handlers | 298–582 | `handleStateEvent`, `handleProcessingEvent`, `handleLLMEvent`, `handleObjectiveEvent`, `handlePhaseEvent`, `handleTimelineEvent`, `handleArtifactEvent`, `handleToolpaneEvent` |
| Retry logic | 583–605 | `retryToolResponses` with exponential backoff |
| Stream queue delegation | 607–625 | `markStreamCompleted`, `getHasStreamedFirstResponse`, `restoreStreamingState` |
| LLM state delegation | 626–660 | `setModelId`, `getCurrentModelId`, `getUseFlexProcessing`, etc. |
| Pending tool responses | 652–660 | `setPendingToolResponses`, `clearPendingToolResponses` |
| Completed tool results | 662–678 | `addCompletedToolResult` |
| Reset | 681–698 | `reset` — calls reset on all services |
| ConversationLog access | 700–710 | `getConversationLog`, `getOperationTracker` |
| ToolPane card delegation | 711–714 | `getCurrentToolPaneCard` |
| Objective delegation | 716–756 | `getObjectiveStatus`, `getAllObjectives`, `getMissingObjectives`, `restoreObjectiveStatus`, etc. |
| Artifact delegation | 758–843 | `restoreArtifacts`, `getArtifactRecord`, `artifacts` computed property, etc. |
| Chat / message delegation | 844–874 | `messages` computed property, `appendUserMessage`, `appendAssistantMessage` |
| UI state delegation | 875–903 | `setActiveState`, `publishAllowedToolsNow`, `checkToolAvailability`, `excludeTool`, `includeTool` |
| Dossier tracking | 905–935 | `buildDossierPrompt`, `setDossierNotes`, `getDossierNotes` |
| UI state computed props | 936–946 | `isActive`, `pendingExtraction` |

---

## 3. Single Responsibility Principle Assessment

`StateCoordinator` has **three distinct responsibilities** today, not one:

### Responsibility A — Unified Facade (intended responsibility)
Expose a consolidated async API over all the underlying actor services so callers (e.g., `ConversationContextAssembler`, `WorkingMemoryBuilder`, `AnthropicRequestBuilder`, tool implementations) only depend on one actor boundary. This is well-justified by the actor isolation model: every crossing of an actor boundary is an `await`, so consolidating access behind a single actor cuts async hops for callers that need multiple pieces of state together.

### Responsibility B — Wizard Progress Computation (unextracted)
`StateCoordinator` owns the `WizardStep` enum and all logic for computing which wizard steps are complete by querying `ObjectiveStore`. This logic is **already duplicated in a different form** in `UIStateUpdateHandler.syncWizardProgressFromState()` and `WizardProgressTracker`. The `WizardStep` enum inside `StateCoordinator` has the same cases as `OnboardingWizardStep` in `OnboardingWizardStep.swift`, which already exists as a standalone type. `OnboardingUIState` references `StateCoordinator.WizardStep` directly (line 79–80 of `OnboardingUIState.swift`), creating a dependency from the UI model back into the actor.

### Responsibility C — Tool Response Batch Coordination (unextracted)
The logic at lines 392–433 (`collectedToolResponsePayloads`, tool batch counting, ConversationLog slot-filling detection, and the decision to enqueue single vs. batched responses) is non-trivial orchestration logic that lives inside `handleLLMEvent`. It is stateful (owns a mutable array across multiple event invocations), decision-making, and largely independent from the other state properties. This is the most structurally complex behavior in the file, and it is buried inside a large event handler switch statement.

### Summary
The file is **not a pure SRP violation** — most of its length comes from legitimate delegation shims that must exist to provide a unified actor boundary. However, it contains two genuine SRP violations:
1. Wizard progress computation belongs in its own object.
2. Tool response batch coordination logic belongs in its own object.

---

## 4. Is the Length Justified?

**Partially.** The raw line count (947) is inflated primarily by:

- ~200 lines of single-line delegation wrappers (`func foo() async { await service.foo() }`) that are structurally necessary but verbose
- ~200 lines of event handler switch statements, mostly one-liner case bodies
- Excessive inline `Logger` calls that could be consolidated

The delegation wrappers are justified by the actor isolation model: without them every caller would need direct references to each sub-actor, multiplying actor hops. The event routing is justified because something must dispatch events to the right services.

What is **not** justified:
1. The `WizardStep` enum and `updateWizardProgress` computation — this is domain logic that should live elsewhere.
2. The tool response batch state and dispatch logic — this is a coherent stateful sub-system that is currently invisible inside a giant switch case.

---

## 5. Refactoring Recommendation

The file should be **partially refactored**. The delegation wrappers and event routing should stay. Two extractions are warranted:

---

### Extraction 1: `WizardStep` enum — Move to `OnboardingWizardStep.swift`

**Problem:** `StateCoordinator.WizardStep` is a redundant near-duplicate of `OnboardingWizardStep`. `OnboardingUIState` already imports the former via `StateCoordinator.WizardStep` (lines 79–80 of `OnboardingUIState.swift`). `UIStateUpdateHandler.syncWizardProgressFromState()` has to bridge between the two types with `OnboardingWizardStep(rawValue: step.rawValue)`.

**Action:**
- Delete `WizardStep` from `StateCoordinator` (lines 54–59).
- `StateCoordinator.currentWizardStep` and `StateCoordinator.completedWizardSteps` should be retyped to use `OnboardingWizardStep` (already exists at `Sprung/Onboarding/Models/UIModels/OnboardingWizardStep.swift`).
- Update `OnboardingUIState` properties on lines 79–80 to use `OnboardingWizardStep` directly (removing the `StateCoordinator.` prefix).
- Update `UIStateUpdateHandler.syncWizardProgressFromState()` to remove the `rawValue`-based bridging conversion — it becomes a direct assignment.
- Update `UIStateUpdateHandler.initialStateSync()` similarly.
- Grep for `StateCoordinator.WizardStep` and `\.wizardStep` to catch all remaining references.

**Files changed:**
- `Sprung/Onboarding/Core/StateCoordinator.swift` — delete enum, retype two properties
- `Sprung/Onboarding/Core/OnboardingUIState.swift` — change type of `wizardStep` and `completedWizardSteps`
- `Sprung/Onboarding/Core/Coordinators/UIStateUpdateHandler.swift` — remove bridging conversion in `syncWizardProgressFromState`

No new files needed. This is a cleanup, not a structural change.

---

### Extraction 2: Tool Response Batch Coordinator

**Problem:** The `collectedToolResponsePayloads` array and the logic that decides when to release batched tool responses (lines 392–433 in `handleLLMEvent`, plus the `toolResultFilled` case at lines 419–434) is a self-contained stateful sub-system with its own internal state, preconditions, and dispatch decisions. It is currently invisible inside `handleLLMEvent`'s switch statement. This logic is the most error-prone part of the file because mistakes in batch counting can deadlock the LLM response loop.

**New file:**

```
Sprung/Onboarding/Core/ToolResponseBatchCoordinator.swift
```

**Purpose:** Collect tool response payloads as they arrive, track when all ConversationLog slots are filled, and enqueue a single or batched tool response to `StreamQueueManager` when ready.

**Proposed type:**

```swift
/// Coordinates tool response batching: collects payloads from individual
/// .enqueueToolResponse events and releases them as a single batch once all
/// ConversationLog slots are filled.
actor ToolResponseBatchCoordinator {
    private let conversationLog: ConversationLog
    private let streamQueueManager: StreamQueueManager
    private var collectedPayloads: [JSON] = []

    init(conversationLog: ConversationLog, streamQueueManager: StreamQueueManager) { ... }

    func batchStarted(expectedCount: Int, callIds: [String]) { ... }
    func payloadReceived(_ payload: JSON) async { ... }  // called for .enqueueToolResponse
    func slotFilled(callId: String) async { ... }         // called for .toolResultFilled
    func reset() { ... }

    private func releaseIfReady() async { ... }
}
```

**What moves from `StateCoordinator`:**
- Line 65: `private var collectedToolResponsePayloads: [JSON] = []` — moves to `ToolResponseBatchCoordinator.collectedPayloads`
- Lines 392–433: The `toolCallBatchStarted`, `enqueueToolResponse`, and `toolResultFilled` case bodies inside `handleLLMEvent` — move to `ToolResponseBatchCoordinator.batchStarted`, `payloadReceived`, and `slotFilled`.
- Lines 687 in `reset()`: `collectedToolResponsePayloads = []` — moves to `ToolResponseBatchCoordinator.reset()`.

**What stays in `StateCoordinator`:**
- A stored property: `private let toolResponseBatchCoordinator: ToolResponseBatchCoordinator`
- Delegation calls in `handleLLMEvent` replace the inline logic:
  ```swift
  case .llm(.toolCallBatchStarted(let expectedCount, let callIds)):
      await toolResponseBatchCoordinator.batchStarted(expectedCount: expectedCount, callIds: callIds)
  case .llm(.enqueueToolResponse(let payload)):
      await toolResponseBatchCoordinator.payloadReceived(payload)
  case .llm(.toolResultFilled(let callId, _)):
      await toolResponseBatchCoordinator.slotFilled(callId: callId)
  ```
- `reset()` adds: `await toolResponseBatchCoordinator.reset()`

**Initialization:** `ToolResponseBatchCoordinator` is constructed in `StateCoordinator.init()` using the already-injected `conversationLog` and the internally-constructed `streamQueueManager`. No new injection points at the `OnboardingDependencyContainer` level are needed.

**Access control:** `ToolResponseBatchCoordinator` should be `internal` (no modifier needed). No protocol needed — it is only used by `StateCoordinator`.

---

### What Should NOT Be Extracted

- The event handler methods (`handleStateEvent`, `handleProcessingEvent`, etc.) — these are already thin routing stubs. Extracting them into separate files would scatter logically related routing code.
- The delegation wrapper methods (objective accessors, artifact accessors, etc.) — these are justified by the unified actor boundary pattern. Removing them would force callers to take direct references to each sub-actor.
- `retryToolResponses` — tightly coupled to `LLMStateManager.getPendingToolResponsesForRetry()` and would be a one-method extraction with no clarity gain.
- Agent activity tracking methods — these are simple read-forwarding wrappers over `AgentActivityTracker`. The async context complexity (bridging `@MainActor` isolation) is the only reason they live here at all.

---

## 6. Priority

| Extraction | Effort | Value |
|---|---|---|
| Move `WizardStep` enum to `OnboardingWizardStep.swift` | Low (30 min) | High — eliminates type duplication and `rawValue` bridging in `UIStateUpdateHandler` |
| Extract `ToolResponseBatchCoordinator` | Medium (2–3 hr) | High — makes the most complex stateful logic in the file visible, testable, and named |

Both should be done. The enum move should come first because it has no new files and is pure cleanup. The batch coordinator extraction should follow.

---

## 7. Interaction Map After Refactoring

```
OnboardingDependencyContainer
  └─ creates StateCoordinator (injecting conversationLog, streamQueueManager, etc.)
       └─ creates ToolResponseBatchCoordinator (internal to StateCoordinator.init)

StateCoordinator.handleLLMEvent
  └─ delegates toolCallBatchStarted / enqueueToolResponse / toolResultFilled
       └─ ToolResponseBatchCoordinator
            └─ reads conversationLog.hasPendingToolCalls
            └─ calls streamQueueManager.enqueue(...)

UIStateUpdateHandler.syncWizardProgressFromState
  └─ reads state.currentWizardStep → OnboardingWizardStep (no bridging needed)
  └─ reads state.completedWizardSteps → Set<OnboardingWizardStep> (no bridging needed)
  └─ calls wizardTracker.synchronize(currentStep:completedSteps:)

OnboardingUIState
  └─ wizardStep: OnboardingWizardStep (was StateCoordinator.WizardStep)
  └─ completedWizardSteps: Set<OnboardingWizardStep> (was Set<StateCoordinator.WizardStep>)
```
