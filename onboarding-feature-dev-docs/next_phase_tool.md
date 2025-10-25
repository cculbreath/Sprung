# Onboarding Feature — Phase Advancement via `next_phase` Tool

**Status:** Approved for immediate use  
**Audience:** Orchestrator/Tooling developers  
**Compatibility:** Tool Specification (v2), Workflow Narrative (v2), State Machine Spec

---

## 1) Scope
This addendum introduces a single tool, `next_phase`, that enables the interviewer LLM to request advancing the onboarding phase. The tool supports both normal advancement (no override) and a user-approved override path when required objectives are not yet marked complete.

- The LLM **never** mutates phase directly.  
- The **actor** remains the code path that mutates phase — but it is *no longer the only decision-maker*: the user can approve an override via a gated dialog.  
- No provider/model details are exposed to the LLM.

---

## 2) Tool: `next_phase`

**Name:** `next_phase`  
**Purpose:** Request advancing to the next phase, optionally proposing overrides for unmet objectives.  
**Visibility:** Exposed in all phases; the app still controls which tools are passed to the model at each turn.

### Parameters (JSON Schema)
```json
{
  "type": "object",
  "required": ["overrides"],
  "properties": {
    "overrides": {
      "type": "array",
      "description": "List of unmet objectives the LLM proposes to bypass",
      "items": { "type": "string" },
      "default": []
    },
    "reason": {
      "type": "string",
      "description": "Justification for advancing, especially when proposing overrides"
    }
  }
}
```

### Responses
```json
{ "status": "approved", "advanced_to": "phase_2" }
{ "status": "blocked", "missing_objectives": ["skeleton_timeline"] }
{ "status": "awaiting_user_approval", "missing_objectives": ["skeleton_timeline","education_history"], "reason": "user verbally confirmed completeness" }
{ "status": "denied", "message": "User declined to advance" }
{ "status": "denied_with_feedback", "feedback": "Please finish entering education history." }
```

---

## 3) Behavior

### A) Normal Case (no overrides)
1. LLM calls `next_phase(overrides=[], reason=null)`.
2. Actor evaluates `shouldAdvancePhase()`:
   - If all required objectives are met → advance phase, return `approved`.
   - Otherwise → return `blocked` with `missing_objectives`.

### B) Override Proposal (one or more reasons)
1. LLM retries with `next_phase(overrides=[...], reason="...")` listing all unmet objectives it proposes to bypass.
2. App opens a user dialog (see §4). The actor pauses advancement and returns `awaiting_user_approval` to the LLM.
3. User decision determines outcome:
   - **Approve:** actor advances and logs override details.
   - **Deny:** actor remains in current phase, returns `denied`.
   - **Deny & Tell:** same as deny, plus `denied_with_feedback` with user message for the LLM.

### C) User-Initiated Advance
If the user explicitly requests advancing, the UI can directly call `next_phase(overrides=[...], reason="user requested")` following the same approval flow (the dialog can be skipped if the user is the initiator).

---

## 4) User Dialog (UI Text)
> **Move to next phase?**  
> The interviewer would like to proceed despite the following not being marked complete:  
> • {missing_objectives.join(", ")}  
> Reason: “{reason}”  
>  
> **Do you approve advancing to {next_phase}?**  
> [Approve] [Deny] [Deny & Tell Interviewer What To Do Next]

- **Approve:** advance immediately.  
- **Deny:** stay in the current phase.  
- **Deny & Tell:** stay in the current phase and send a structured feedback message to the LLM.

---

## 5) Prompt Guidance (System)
Add to the interviewer’s system message:

- You may call `next_phase` when you believe the user is ready to proceed.  
- If any required objectives are incomplete, list them in `overrides` and provide a concise `reason`.  
- The app will confirm with the user before advancing when objectives are incomplete.  
- You may retry after receiving feedback.

---

## 6) Actor Responsibilities (Code)
- Evaluate `shouldAdvancePhase()` for normal (no-override) calls.
- For override proposals, compute `missing_objectives` and open the user dialog.
- Mutate `phase` only after explicit approval (either because criteria are met, or the user approved overrides).
- Return structured outcomes to the LLM (`approved`, `blocked`, `awaiting_user_approval`, `denied`, `denied_with_feedback`).

The actor remains the sole mutator of `phase`, but not the sole *decider*: user approval can authorize bypassing unmet objectives.

---

## 7) Logging (Audit Trail)
Append a record on each invocation:

```json
{
  "event": "phase_advance_attempt",
  "timestamp": "ISO-8601",
  "phase": "phase_1",
  "overrides": ["skeleton_timeline"],
  "reason": "user verbally confirmed",
  "objectivesRemaining": ["skeleton_timeline"],
  "userDecision": "approved | denied | denied_with_feedback",
  "advancedTo": "phase_2 | null"
}
```

---

## 8) Integration Notes
- Keep phase-allowed tool gating: only pass allowed tools to the model each turn.  
- No provider/model identifiers are ever included in tool surfaces or prompts.  
- The `extract_document` tool remains the universal entrypoint for PDFs/DOCX; this addendum does not change extraction behavior.

---

## 9) Edge Cases
- **No objectives defined for phase:** `shouldAdvancePhase()` returns true → advance.  
- **LLM spams `next_phase`:** rate-limit and surface the last `blocked` response until state changes.  
- **Conflicting overrides:** always show the user the exact `missing_objectives` the actor computed; do not rely on the LLM’s list.

---

## 10) Test Cases (Minimum)
1. All objectives met → `next_phase([])` returns `approved` and phase increments.  
2. One unmet objective → `blocked` includes the exact objective.  
3. Multi-override → `awaiting_user_approval` then each of the three user decisions produces the expected result and log entries.  
4. Double-submit guard → repeated calls without state change return the last known outcome.  
5. User-initiated advance → bypass dialog and advance immediately (log `by_user=true`).

---

## 11) Backward Compatibility
- No changes required to existing objective schemas.  
- No changes to `extract_document` or validation flows.  
- This addendum adds only one new tool and one UI dialog.

