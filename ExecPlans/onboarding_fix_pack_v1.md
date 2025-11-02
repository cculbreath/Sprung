# Onboarding Fix Pack (v1) Implementation

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

Plan maintained per `Plans.md` (repository root).

## Purpose / Big Picture

The onboarding interview currently exposes reliability gaps: the left pane spinner disappears while the LLM is still working, chat autoscroll sometimes jumps upward, reasoning summaries vanish whenever the assistant responds via tools only, legacy model identifiers linger and cause silent 400 errors, and the objective ledger marks the applicant profile complete long before the intake card actually finishes. This plan hardens the onboarding experience so a new user always sees accurate loading state, can read reasoning summaries even when no transcript is emitted, is guided to a valid model, and can dismiss the intake card only after every prerequisite (profile persisted, photo handled, validations satisfied) is met. When finished, you can launch an interview with an invalid saved model id and immediately get a banner directing you to Settings, watch the left pane spinner appear whenever extraction or streaming holds the pane idle, see a persistent reasoning status bar for tool-only turns, and observe the intake card close exactly when the ledger reaches a completed or skipped profile state.

## Progress

- [x] (2025-11-02T03:01Z) Kickoff: ExecPlan authored; implementation and verification not yet started.
- [x] (2025-11-02T06:12Z) Chat autoscroll guard added in `OnboardingInterviewChatPanel` so scrolling only occurs when `state.shouldAutoScroll` is true; prep for glow stability validation.
- [x] (2025-11-02T06:40Z) Added reasoning status bar plumbing (coordinator state, orchestrator callbacks, status bar view) so reasoning-only turns surface in the chat panel footer with auto-fade behavior.

## Surprises & Discoveries

No surprises yet. This section will collect unexpected behaviors or optimizations discovered during implementation, accompanied by logs or transcripts for evidence.

## Decision Log

No decisions recorded yet. Any design trade-offs or scope adjustments will be logged here with rationale and author/timestamp.

## Outcomes & Retrospective

Pending. Will summarize achieved outcomes, remaining gaps, and lessons learned once the fix pack ships.

## Context and Orientation

The onboarding UI lives in `Sprung/Onboarding/Views`, with the tool pane defined in `Views/Components/OnboardingInterviewToolPane.swift` and the chat surface in `Views/Components/OnboardingInterviewChatPanel.swift`. The parent container is `Views/Components/OnboardingInterviewInteractiveCard.swift`, while app-level scaffolding is `Views/OnboardingInterviewView.swift`. Observable state comes from `OnboardingInterviewService` and `OnboardingInterviewCoordinator` (`Sprung/Onboarding/Core`), backed by the `InterviewState` actor and ledger types in `Core/InterviewSession.swift` and `Core/ObjectiveLedger.swift`. Reasoning summaries flow through `InterviewOrchestrator.swift` via callbacks into the coordinator and `ChatTranscriptStore` (`Sprung/Onboarding/Stores`). Model defaults are coordinated by `OnboardingInterviewViewModel.swift` and surfaced in `App/Views/SettingsView.swift`, while PDF extraction uses `Onboarding/Services/DocumentExtractionService.swift` and the shared OpenRouter executor `Shared/AI/Models/Services/LLMRequestExecutor.swift`. Tool definitions, including `SetObjectiveStatusTool`, are under `Onboarding/Tools`. Prompt guidance for objectives lives in `Onboarding/Phase/PhaseOneScript.swift` (and related phase scripts). Logger utilities reside at `Sprung/Shared/Utilities/Logger.swift`.

## Plan of Work

Begin with spinner stability. Expose a shared `paneOccupied` computation so both `OnboardingInterviewToolPane` and its parent (`OnboardingInterviewInteractiveCard`) stay in sync; the binding must always reflect whether uploads, intake cards, validations, or extractions own the pane. Adjust `showSpinner` to follow the FixList formula—`pendingExtraction` always wins, otherwise show when the pane is idle but the LLM is active—and ensure overlay logic and animations respect that boolean.

Next, confirm the autoscroll and glow behavior. Audit `OnboardingInterviewChatPanel` to guarantee `handleMessageCountChange` only scrolls when a new message arrives and `state.shouldAutoScroll` is true, and that the `.onChange` for `service.isProcessing` only triggers on `true → false`. Update `lastMessageCount` initialization if needed so first render does not jump, and keep `ConditionalIntelligenceGlow` independent from scroll anchoring.

Introduce the reasoning status bar. Extend `OnboardingInterviewCoordinator` (and, if needed, `OnboardingInterviewService`) with `@Published var latestReasoningSummary: String?`, helper methods to store/clear trimmed text, and a cancellable Task to clear after a short timeout. Wire the orchestrator callbacks: whenever a reasoning summary arrives, update both the transcript and `latestReasoningSummary`; when streaming finishes and a message carries its own summary, or the timeout fires, clear it. Add a `ReasoningStatusBar` view (footnote italic text with a spinner) and inject it above the composer in `OnboardingInterviewChatPanel`, with an opacity/slide transition and `withAnimation` to fade when the summary disappears.

Harden model id validation. Create a small validator (either within `OnboardingInterviewViewModel` or a helper) that reconciles stored defaults against the current OpenAI model list; coerce invalid IDs to the default or the first available and persist the cleaned value back to `@AppStorage`. Update `SettingsView` pickers and the `OnboardingInterviewView.updateServiceDefaults()` call to always pass a vetted ID. In `OnboardingInterviewCoordinator.setPreferredDefaults`, verify the candidate id exists in the latest known list; if not, fall back and surface a user-visible error banner on the chat panel (reusing the “Change in Settings…” affordance). Extend `LLMError` with `.invalidModelId(String)` and update `LLMRequestExecutor` to map HTTP 400 responses containing `"is not a valid model ID"` to that error, skipping retries. Ensure `OnboardingInterviewCoordinator` and orchestrator error handlers detect the new error and set a banner message that the chat UI can display. Mirror the same validation for the PDF extraction path: `DocumentExtractionService` should rely on the sanitized preference instead of the hard-coded Gemini fallback, and propagate `LLMError.invalidModelId` so the spinner/banner path alerts the user.

Overhaul the objective ledger. Add `skipped` to `ObjectiveStatus`, extend `ObjectiveEntry` with `notes`, and augment `InterviewState` with `beginObjective`, `completeObjective`, `skipObjective`, and `isObjective(_:inState:)`. Maintain `session.objectivesDone` by deriving from entries marked `completed`. Refactor `OnboardingInterviewCoordinator.recordObjectiveStatus` to delegate to the new helpers and to stamp `updatedAt`, `source`, and optional `notes`. Remove the automatic completion when `storeApplicantProfile` persists data; instead introduce an `evaluateApplicantProfileObjective()` helper that runs whenever the profile saves, a contact photo is completed or skipped, or validations finish. This helper should only mark `applicant_profile` completed when the profile JSON is persisted, the photo objective is `completed` or `skipped`, and validation (if required) is satisfied. Update `OnboardingInterviewService.storeApplicantProfileImage`, any photo skip affordance, and tool-driven status updates to call the new helpers. Extend `SetObjectiveStatusTool` schema to accept `pending`, `in_progress`, `completed`, and `skipped`, handling skips (with optional reason) without forcing the user back into the intake loop. Add a “Skip photo for now” action to the intake card (or adjacent UI) that records `contact_photo_collected` as skipped via the service. Finally, revise the phase prompt scripts (Phase One and any shared prompt text) to embed the Objective Ledger rules block from the FixList.

With objective states authoritative, adjust view gating. Update `OnboardingInterviewToolPane` so summary cards only show when `coordinator.isObjective("applicant_profile", inState: .completed)` or `.skipped`; otherwise keep the intake card visible. Ensure photo follow-up logic consults the ledger before enqueuing new uploads.

## Concrete Steps

1. While iterating on plan-only artifacts, no commands are required. During implementation, keep `git status` focused on files touched by this plan and stage incrementally.  
2. After major type-signature or ledger changes, run a targeted compile:  
   `xcodebuild -project Sprung.xcodeproj -scheme Sprung build | grep -E "(error:|warning:|failed)" | head -20`  
   (Working directory: repository root.)  
3. Use `swiftlint` or formatting tools only if the repository already expects them; otherwise conform to existing style manually.  
4. Before final handoff, rerun the quick compile command and capture the 20-line filtered output for Artifacts.

## Validation and Acceptance

Follow the FixList quick test plan end-to-end:  
- Seed an invalid onboarding model id in defaults, launch the interview, and verify the banner appears with a working Settings link and no lingering retries.  
- Run the résumé upload path, confirming the left spinner shows “Extracting PDF…” while the pane is otherwise empty and that streaming finishes with a single snap to the latest message.  
- Trigger a tool-only reasoning turn (no assistant text) and verify the new status bar displays the summary until replaced or timed out.  
- Upload a photo and confirm `contact_photo_collected` transitions, the ledger reevaluates, and the intake card dismisses once the profile persists.  
- Use the Skip photo action and ensure the ledger records `skipped`, the intake card closes appropriately, and later turns respect the skipped state.

## Idempotence and Recovery

Ledger migrations and preference sanitization should be idempotent: calling the new helpers multiple times yields the same state. If a migration or compilation fails, revert the specific file changes (do not reset unrelated files) and rerun the command. The spinner and status bar changes are UI-only and safe to reapply; banner state clears when preferences are valid again.

## Artifacts and Notes

Capture the filtered `xcodebuild` output after the final build, along with any relevant log excerpts demonstrating ledger transitions (e.g., `Logger.info` lines for objective updates) and screenshots or transcript snippets from manual validation. Store short snippets inline in the final report; no large attachments needed.

## Interfaces and Dependencies

- `ObjectiveStatus` (ObjectiveLedger.swift) gains `.skipped`.  
- `ObjectiveEntry` adds `notes` and may expose mutable `status/source/updatedAt/notes`.  
- `InterviewState` new APIs:  
    - `func beginObjective(_ id: String)`  
    - `func completeObjective(_ id: String, source: String?, notes: String?)`  
    - `func skipObjective(_ id: String, reason: String?)`  
    - `func isObjective(_ id: String, inState state: ObjectiveStatus) -> Bool`  
- `OnboardingInterviewCoordinator` publishes `latestReasoningSummary`, exposes `evaluateApplicantProfileObjective()`, and updates `setPreferredDefaults` to validate ids.  
- `OnboardingInterviewService` forwards reasoning summaries, exposes banner text, and provides helpers for photo skip/completion.  
- `SetObjectiveStatusTool` schema enumerates `pending`, `in_progress`, `completed`, `skipped`.  
- `LLMError` adds `.invalidModelId(String)`; `LLMRequestExecutor` detects 400 invalid-id responses.  
- `DocumentExtractionService` reads sanitized PDF model id and surfaces the new error.  
- Prompt scripts (`PhaseOneScript.swift` et al.) include the Objective Ledger rules snippet.  
- UI components (`OnboardingInterviewChatPanel`, `OnboardingInterviewToolPane`, `OnboardingInterviewInteractiveCard`, `ApplicantProfileIntakeCard`) consume the new state and render spinner/status bar/skip affordance accordingly.
