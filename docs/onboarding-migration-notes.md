# Onboarding Interview Migration Notes

These notes summarize the public API changes introduced by the coordinator/router refactor of the onboarding interview feature. Use this guide when updating legacy code or writing new integrations.

---

## What Changed

- `OnboardingInterviewService` is now a thin SwiftUI façade. It wires dependencies and forwards every state mutation to the coordinator.
- All interactive state (choice prompts, uploads, applicant profile intake, etc.) flows through `OnboardingToolRouter` and its handlers.
- Wizard progress and system prompt construction are delegated to new collaborators so views and tools no longer poke at legacy service fields.
- Contacts import is handled entirely by the applicant profile intake state machine; there is no separate contacts permission request API.
- Objective ledger tracks fine-grained milestones (contact source selection, validation, etc.) so the coordinator can push canonical status updates back to the LLM.
- Phase scripts now declare per-objective workflows (starting with Phase 1) that emit follow-up developer messages and tool instructions, replacing scattered hard-coded strings in the service layer.

---

## Public API Reference

### `OnboardingInterviewCoordinator`

- `@Observable` entry point for lifecycle control.
- Provides read-only access to router state (`pendingChoicePrompt`, `pendingApplicantProfileIntake`, uploads, toggles).
- Exposes chat helpers for logging transcript updates without touching `ChatTranscriptStore` directly.
- Offers async utilities for checkpointing (`hasRestorableCheckpoint`, `restoreCheckpoint`, `saveCheckpoint`, `clearCheckpoints`).
- Surfaces wizard state (`wizardStep`, `wizardStepStatuses`) sourced from `WizardProgressTracker`.

**Usage Tip:** SwiftUI views should continue observing `OnboardingInterviewService`; the service forwards to the coordinator so no additional environment wiring is required.

### `WizardProgressTracker`

- Centralizes step computation so views do not implement their own phase-to-step mapping.
- API highlights:
  - `setStep(_:)` – force the UI to a specific wizard step.
  - `updateWaitingState(_:)` – sync current waiting reason with the interview session.
  - `syncProgress(from:)` – rebuilds step state after restoring checkpoints.
  - `reset()` – clears to introduction state.

**Usage Tip:** Call `updateWaitingState` whenever the coordinator receives an `InterviewSession.Waiting` update so the primary CTA disables appropriately.

### `PhaseScriptRegistry`

- Builds the system prompt handed to `InterviewOrchestrator`.
- Provides `script(for:)` and `currentScript(for:)` helpers for phase-specific behavior.
- Keeps base prompt text separate from phase fragments, making it straightforward to add future phases without changing existing scripts.

**Usage Tip:** Whenever you introduce a new interview phase, add a `PhaseScript` implementation and register it in the registry. The coordinator will automatically produce the correct prompt.

---

## Integration Checklist

1. Remove references to deprecated service state such as `pendingContactsRequest` or `pendingSectionEntryRequests`.
2. Route UI actions through `OnboardingInterviewActionHandler`; the service now handles resuming tool continuations internally.
3. Use `coordinator.wizardTracker` (through the service façade) for all wizard UI bindings—do not replicate step logic in views.
4. When persisting new artifacts, go through `OnboardingDataStoreManager` so checkpoint snapshots stay consistent.
5. Add or update objective workflows inside the appropriate `PhaseScript` implementation when introducing new milestones so follow-up prompts stay centralized.
6. Document new tool status fields or modal flows in `docs/` alongside this file to keep collaborators aligned.

---

## Resources

- `Sprung/Onboarding/ARCHITECTURE.md` – detailed architecture diagrams and component responsibilities.
