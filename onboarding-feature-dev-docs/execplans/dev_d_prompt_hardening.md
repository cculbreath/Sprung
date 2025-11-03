# ExecPlan: Prompt & Tool Contract Hardening (dev_d) — single validation surface, liberal approval

**Status:** Proposed  
**Owner:** dev_d  
**Scope:** System/developer prompts, tool docs, sanitizer behavior, phase allowlist.  
**Dependencies:** None; complements dev_a/dev_b/dev_c.

---

## Purpose / Big Picture
Eliminate contradictory guidance and duplicate approval surfaces:
- **Single validation door:** `submit_for_validation` is the only user‑facing confirmation UI.  
- **Liberal approval:** user actions in editors (ApplicantProfile intake; Timeline editor) count as validation—no duplicate modals.  
- **Clear hand‑off:** cards capture facts; the modal is used only when facts haven’t been user‑touched or bulk AI edits need confirmation.

---

## Changes

### A. Phase‑1 tool allowlist
- **Remove** `validate_applicant_profile` from the Phase‑1 allowlist (do not register it for Phase‑1).  
- Keep the file in the repo but unregistered so the model never sees it in `available_tools`.

**Files**
- `Sprung/Onboarding/Core/OnboardingInterviewService.swift` (Phase‑1 allowed tools map)  
- `Sprung/Onboarding/Tools/ToolRegistry.swift` (ensure `ValidateApplicantProfileTool` is not registered for Phase‑1)

**Acceptance**
- Tool schema advertised to the model no longer includes `validate_applicant_profile` in Phase‑1.

---

### B. SubmitForValidationTool documentation
- Update schema/description to **explicitly** mention:  
  - `dataType` supports `"applicant_profile"` and `"skeleton_timeline"` (plus `"experience"`, `"education"`).  
  - **Auto‑approve** rule applies to `applicant_profile` when `meta.validation_state == "user_validated"`.  
  - Timeline types open the modal **unless** `user_validated` is already present (see dev_c early‑exit).

**Files**
- `Sprung/Onboarding/Tools/Implementations/SubmitForValidationTool.swift` (description strings)

**Acceptance**
- The exposed schema text aligns with runtime behavior and examples used elsewhere.

---

### C. Sanitizer narrowing
- In `InterviewOrchestrator.sanitizeToolOutput(...)`, **do not** inject `meta.validation_state = "user_validated"` for the `submit_for_validation` path.  
- Keep sanitizer behavior for profile **intake** and other safe enrichments (e.g., email scrubbing).

**Files**
- `Sprung/Onboarding/Core/InterviewOrchestrator.swift`

**Acceptance**
- Validation state for timeline data is only set by user editors or by the tool result—never pre‑set by the sanitizer.

---

### D. Phase‑1 system prompt hand‑off text
Add explicit lines to the system fragment (Phase‑1):
- *“Use timeline **cards** to capture/refine facts. When the set is stable, call `submit_for_validation(dataType: "skeleton_timeline")` **once** to open the review modal. Do **not** rely on chat acknowledgments for final confirmation.”*
- *“If you receive a developer status indicating **Timeline cards updated by the user** (or Applicant profile intake complete) with `meta.validation_state = "user_validated"`, **do not** call `submit_for_validation` again for that data. Acknowledge and proceed.”*

**Files**
- `Sprung/Onboarding/Phase/PhaseOneScript.swift`

**Acceptance**
- In traces, the model stops re‑requesting validation after user‑driven edits/saves.

---

### E. Developer messages
- **After ApplicantProfile intake Save:**  
  “Coordinator has already persisted the applicant profile. If you present profile validation it will auto‑approve. **Do not** re‑persist the profile. Proceed to skeleton timeline.”
- **After Timeline editor Save:**  
  “Timeline cards updated by the user. Treat the attached payload as **user_validated**; proceed to `enabled_sections`. Do not call `submit_for_validation` unless introducing new, unreviewed facts.”

**Files**
- `Sprung/Onboarding/Core/DeveloperMessageTemplates.swift`

**Acceptance**
- The first assistant turn after these messages never re‑asks for approval of the same payload.

---

## Risks & Mitigations
- **Risk:** Hiding the second approval could miss conflicts.  
  **Mitigation:** Keep explicit validation for LLM‑originated bulk changes or conflict resolution; prompts and dev messages state this exception.

---

## Validation Plan
1. Contacts/manual intake → Save → assistant proceeds without modal; stray validations are ignored/auto‑approved.  
2. Resume→timeline→user edits → Save → assistant proceeds; no duplicate modal.  
3. LLM bulk‑edit proposal → `submit_for_validation` opens the modal once.

---

## Progress Checklist
- [ ] Remove `validate_applicant_profile` from Phase‑1 allowlist/registry  
- [ ] Update SubmitForValidationTool docs (`applicant_profile`, `skeleton_timeline`)  
- [ ] Narrow sanitizer (no pre‑set validation on submit_for_validation)  
- [ ] Add system hand‑off lines to Phase‑1 script  
- [ ] Update developer message templates for profile/timeline
