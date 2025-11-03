# ExecPlan: Tool/Runtime Control (dev_c) — enforced timeline creation & de‑dup validation

**Status:** Proposed  
**Owner:** dev_c  
**Scope:** Responses API parameters, allowed tools per turn, tool implementations.  
**Dependencies:** dev_d (prompt/allowlist cleanups).

---

## Purpose / Big Picture
Make the resume→timeline step deterministic and prevent redundant validations:
1) **Force** the first model reply after resume extraction to call timeline card tools.  
2) **Revert** to normal auto tool choice after that first turn.  
3) **Auto‑approve** validation for data already marked `user_validated` (ApplicantProfile + Timeline).

---

## Changes

### A. One‑shot `tool_choice: required` for timeline creation
- In the orchestrator layer that builds Responses API calls, add:
  ```swift
  struct ToolChoiceOverride {
      enum Mode { case require(tools: [String]), case auto }
      let mode: Mode
  }
  private var nextToolChoiceOverride: ToolChoiceOverride?
  ```
- After resume extraction succeeds and you enqueue the artifact + developer message, set:
  ```swift
  nextToolChoiceOverride = .init(mode: .require(
      tools: ["create_timeline_card", "update_timeline_card", "reorder_timeline_cards", "delete_timeline_card"]
  ))
  ```
- In the call builder: if `nextToolChoiceOverride` is present, emit `tool_choice: required` and restrict `available_tools` to the list **for that one call**, then clear the override. Otherwise use `auto` with the normal phase allowlist.

**Acceptance**
- The first LLM turn after extraction produces timeline card tool calls (no section selector yet).  
- Subsequent turns use `auto` again.

---

### B. No duplicate validation for already validated data
- In `SubmitForValidationTool.execute`, add an **early‑exit** branch for:
  - `dataType ∈ { "applicant_profile", "skeleton_timeline", "experience", "education" }`
  - AND `data.meta.validation_state == "user_validated"`
- Return `{ status: "approved", approvedAt: now }` **without** opening UI.  
- Keep the existing applicant‑profile short‑circuit; extend it to the timeline types.

**Acceptance**
- If the user just saved the profile or timeline, any stray validation call is auto‑approved, no duplicate UI.

---

### C. Allowed tools hygiene (during timeline step)
- For the **one forced turn**, restrict `available_tools` to the 4 timeline tools (above).  
- For normal turns, rely on the phase allowlist **after** dev_d removes `validate_applicant_profile` from Phase‑1 exposure.

**Acceptance**
- LLM cannot “discover” a second validation path during timeline creation.

---

## Risks & Mitigations
- **Risk:** Forcing a tool when resume text is empty/garbage.  
  **Mitigation:** Set the override **only** when extraction returns usable text; otherwise ask for another file or proceed with manual entry.

---

## Validation Plan
1. Upload a resume with 2–3 roles → observe timeline cards created on the very next turn.  
2. Make timeline edits → save → stray `submit_for_validation(skeleton_timeline)` returns approved without UI.  
3. Profile intake → save → stray `submit_for_validation(applicant_profile)` returns approved without UI.

---

## Progress Checklist
- [ ] One‑shot `tool_choice: required` override after extraction  
- [ ] Early‑exit auto‑approve in SubmitForValidationTool for validated timeline types  
- [ ] Restrict available tools during the forced turn; revert to auto
