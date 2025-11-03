# Onboarding Applicant Profile Persistence & Guidance
This ExecPlan is a living document. Keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` updated as work advances. Follow the rules in `Plans.md`.

## Purpose / Big Picture

Users should experience a smooth onboarding intake where once their contact data is confirmed it is:
1. Persisted exactly once (no redundant writes or log spam),
2. Communicated back to GPT-5 with clear “already validated” status so the model advances without re-validating,
3. Followed by a reliable photo prompt workflow driven by ledger updates rather than scattered service logic.

After implementing this plan, starting an interview, importing contacts, and approving them should log one persistence event, immediately notify the LLM that data is authoritative, and automatically queue the profile-photo follow-up if needed.

## Progress

- [x] (2025-10-30 03:05Z) Draft plan capturing persistence, validation, prompt, and reasoning updates.
- [x] (2025-10-30 03:45Z) Implemented observer-driven photo prompts, persistence dedupe, schema relaxation, prompt refresh, and reasoning effort alignment with user settings.
- [x] (2025-10-30 04:20Z) Updated tool pane occupancy handling to drop the spinner whenever a card is visible and expanded the applicant summary card to show formatted addresses.
- [ ] Surface photo upload card automatically when the coordinator issues the profile photo follow-up.
- [ ] Validate manually by exercising the onboarding interview start → contact intake → auto-approval flow observing tool queue messages.
- [ ] Capture findings in Outcomes & Retrospective.

## Surprises & Discoveries

_None yet._

## Decision Log

- Pending decisions will be captured here with rationale, author, and timestamp.

## Outcomes & Retrospective

Filled in after implementation and validation.

## Context and Orientation

Key moving pieces:

- `OnboardingInterviewCoordinator.recordObjectiveStatus` emits developer messages and now supports observers for objective updates. Completion of `contact_data_validated` should centrally queue photo prompts instead of scattering logic.
- `OnboardingInterviewService.persistApplicantProfile` currently stores JSON every time it is called, even if unchanged, creating redundant logs and potential model confusion.
- Validation tools (`submit_for_validation`, `validate_applicant_profile`) inject metadata that should help the LLM skip unnecessary confirmation, but schema strictness and descriptions need tightening to prevent API errors and model misuse.
- Prompting remains partially stale (still references `capabilities_describe`). We must align system/phase instructions with the new developer-message contract and possibly increase reasoning effort to “low” after the welcome turn so GPT-5 stops re-validating.

## Requirements

1. **Single persistence per confirmed payload**: If confirmed applicant profile data hasn’t changed, skip `storeApplicantProfile` while still logging that the coordinator acknowledged the request.
2. **Ledger-driven photo prompt**: Photo follow-up should be triggered once, when `contact_data_validated` is marked complete—no earlier or duplicate triggers.
3. **Schema + tooling clarity**: JSON schemas must be accepted by the Responses API (no strict mode, no union-with-null), and tool descriptions must warn the LLM away from validated data.
4. **Prompt alignment**: Base system prompt, Phase 1 script, and developer messages must emphasize that “already persisted/validated” == move on. Raise reasoning effort to `low` after the greeting.
5. **Logging hygiene**: Console logs must show developer messages (with payloads when present) and make it obvious when data is skipped vs. stored.
6. **Manual validation**: Demonstrate behavior by running the macOS app, performing the contact import workflow, confirming persistence happens once, and verifying the photo prompt surfaces.

## Implementation Steps

1. **Objective observer infrastructure**
   - Extend `OnboardingInterviewCoordinator` with a lightweight observer struct to broadcast objective updates.
   - Register the observer in `OnboardingInterviewService` during init.
   - Route photo follow-up logic (`enqueuePhotoFollowUp`) through the observer callback and remove duplicate calls in intake completion functions.

2. **Deduplicate persistence and logging**
   - Teach `persistApplicantProfile(_:)` to compare incoming JSON against the stored snapshot; if identical, skip storage, log an info-level skip message, and still persist checkpoints if needed.
   - Ensure developer messages communicating “persisted” vs. “skipped” are explicit so GPT-5 understands no action is required.

3. **Tool schema & description tuning**
   - Update `ValidateApplicantProfileTool` schema (disable strict, allow optional fields) and reinforce description that validated payloads should bypass the tool.
   - Revisit `SubmitForValidationTool` description if needed to stress automatic approval when `meta.validation_state == "user_validated"` and mention no resubmission is required.
   - Mirror documentation updates under onboarding docs to keep schema guidance in sync.

4. **Prompt and reasoning adjustments**
   - Refresh base system prompt and Phase 1 script to remove obsolete guidance, spotlight developer messages, and emphasize “do not re-validate or re-persist already-approved data.”
   - Introduce logic in `InterviewOrchestrator` to set `reasoning.effort = "low"` after the greeting turn (the welcome can stay minimal effort).

5. **Developer message clarity & logging**
   - Standardize developer messages to include payload JSON (sanitized) and human-readable summaries.
   - Ensure messages announcing objective completions explicitly say “Photo follow-up ready” when appropriate.

6. **Validation & documentation**
   - Run the onboarding workflow: start interview → contacts import → approve data.
   - Capture console log excerpts showing single persistence, developer messages, and photo prompt.
   - Update `ExecPlans/onboarding-tool-coordination.md` progress and add summary in this plan’s `Outcomes & Retrospective`.

## Validation and Acceptance

- Launch Sprung, run the onboarding interview, choose the Contacts intake path.
- After confirming details, expect:
  - Console log shows one “persisted” (or skipped) message and matching developer status output.
  - Developer messages to GPT-5 announce contact data validated and photo follow-up instructions.
  - UI surfaces the photo prompt without overlay spinner conflicts.
- Confirm no redundant `storeApplicantProfile` invocations via logs or breakpoints.

## Idempotence and Recovery

- Persistence skip logic is safe to re-run; changes are additive and bail out cleanly if observer already registered.
- If schema changes cause build failures, revert the specific tool file and reapply carefully.
- Prompt updates remain text-only; revert via git if behavior regresses.

## Artifacts and Notes

- Record console log snippets showing photo prompt trigger and persisted/skip message.
- Optional: capture screenshot or transcript demonstrating LLM acknowledgement.

## Interfaces and Dependencies

- `OnboardingInterviewCoordinator.ObjectiveStatusUpdate` (new struct) with fields `id`, `status`, `source`, `details`.
- `OnboardingInterviewService` must implement `handleObjectiveStatusUpdate` hooking into photo follow-up.
- `persistApplicantProfile(_:)` returns early when payload unchanged; consider factoring comparison helper in `OnboardingDataStoreManager`.
- `InterviewOrchestrator.requestResponse` sets `Reasoning(effort: "low")` after the first assistant greeting.
