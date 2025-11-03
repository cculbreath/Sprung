```
# Onboarding Objective Workflow Framework
This ExecPlan is a living document. Maintain `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` as work proceeds. Comply with Plans.md at every step.

## Purpose / Big Picture
Centralize the onboarding interview workflow so each objective knows:
1. Which prompts and tools initiate it,
2. What follow-up instructions fire when it completes,
3. Which objective(s) come next.

After implementation we want to edit one place—per phase—to update the flow from Welcome through wrap-up, eliminating scattered hard-coded developer messages while keeping the existing architecture.

## Progress
- [x] (2025-10-30 04:45Z) Draft plan describing objectives → prompts/tool sequencing consolidation.
- [x] (2025-10-30 04:55Z) Added initial Phase 1 workflow entry for contact validation → photo follow-up and wired outputs into service.
- [x] (2025-10-30 05:05Z) Expanded Phase 1 workflow definitions (source selection, data collection, applicant profile completion, timeline/sections hand-offs) and updated migration notes.
- [ ] Consolidate developer message helpers into reusable templates so Phase scripts emit consistent instructions.
- [ ] Migrate service/coordinator to consult workflow registry for developer messages and tool payloads.
- [ ] Extend structure to later phases and remove obsolete hard-coded prompts.
- [ ] Document registry usage and validate end-to-end flow.

## Surprises & Discoveries
- None yet (plan-only stage).

## Decision Log
- Pending.

## Outcomes & Retrospective
- To be filled once design implemented.

## Context and Orientation
Existing flow control is distributed:
- Phase scripts describe steps in prose (`PhaseOneScript`), but have no structured metadata.
- `OnboardingInterviewService` emits developer messages and tool payloads (e.g., photo follow-up) ad hoc.
- `ObjectiveLedger` records status but doesn’t drive follow-up actions.
- `InterviewOrchestrator` and tools operate fine once directed, but they depend on instructions coming from scattered code.

The aim is to consolidate this into structured objective definitions per phase while reusing existing components (Service, Coordinator, ToolRouter, etc.) instead of adding new layers.

## Requirements
1. **Single authoritative map** per phase: objective ID → dependencies, default prompts, tool envelopes, completion follow-ups, next objective(s).
2. **Runtime-aware**: workflow entries must accept context (e.g., applicant profile JSON) to build payloads dynamically.
3. **Minimal new nouns**: extend PhaseScript (or similarly scoped layer) rather than introducing a brand-new orchestrator.
4. **Backward compatibility**: existing behavior should remain during migration; registry should fall back gracefully.
5. **Declarative developer messages**: all `sendDeveloperStatus` calls should originate from workflow definitions.
6. **Objective gating**: dependencies (e.g., `contact_photo_collected` depends on `contact_data_validated`) enforced centrally.
7. **Tool association**: specify default tool payloads (e.g., `get_user_upload` JSON) so service no longer hardcodes them.
8. **Logging**: continue logging developer messages at info level.

## Implementation Steps
1. **Define workflow data structures**
   - Add `ObjectiveWorkflow` struct (id, dependsOn, entryPrompt, completionAction, defaultToolPayloads, nextObjectiveIds).
   - Extend `PhaseScript` protocol to expose `objectiveWorkflows` along with helper lookups.

2. **Phase 1 migration (pilot)**
   - Encode welcome sequence, contact intake (manual/contacts/upload/url), validation, photo prompt, and skeleton timeline transition.
   - Provide runtime closures for dynamic payloads (e.g., applicant profile JSON).

3. **Coordinator/service integration**
   - When objectives start or complete, consult the workflow entry:
     * Send structured developer messages via existing queue.
     * Emit tool payload instructions (e.g., `get_user_upload`) from workflow data.
   - Remove duplicate hard-coded logic from `OnboardingInterviewService`.

4. **Dependency enforcement**
   - Refuse to queue/execute objectives whose prerequisites aren’t complete.
   - Update ledger updates to consider workflow dependencies when suggesting next steps.

5. **Tool usage hints**
   - Provide default payload builders within workflow entries so the LLM receives consistent instructions.
   - Optionally surface human-readable hints to UI/logs for debugging.

6. **Validation & docs**
   - Run onboarding flow confirming each objective transition logs the workflow-driven messages.
   - Update developer docs explaining how to edit `objectiveWorkflows`.

## Validation and Acceptance
- Manual run from fresh interview: confirm welcome → contact intake → auto-validation → photo prompt → timeline run entirely from workflow definitions.
- Verify developer log entries and queued tool payloads match registry data.
- Confirm the model never repeats completed objectives unless the workflow allows resets.

## Idempotence and Recovery
- Workflow definitions are declarative; reverting a change restores prior behavior.
- For migration, keep fallback logic until workflow covers all steps; wrap new behavior behind feature toggle if needed.

## Artifacts and Notes
- Capture console log snippet showing workflow-driven developer messages.
- Document example `ObjectiveWorkflow` entry for Phase 1 in repo docs.

## Interfaces and Dependencies
- Updated `PhaseScript` protocol (`objectiveWorkflows` plus helper functions).
- `OnboardingInterviewService`/`Coordinator` use workflow entries when recording objective status.
- Existing components (ToolExecutor, Router, handlers) remain untouched aside from receiving cleaner instructions.
```
