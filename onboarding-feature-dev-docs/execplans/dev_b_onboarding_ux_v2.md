# ExecPlan: Coordinator & Persistence UX (dev_b) — implicit validation and statuses

**Status:** Proposed  
**Owner:** dev_b  
**Scope:** Coordinator/state updates, persistence semantics, status strings.  
**Out of scope:** Tool steering internals (see dev_c), prompt contract (see dev_d).

---

## Purpose / Big Picture
Adopt **liberal approval**: user interaction in editors counts as validation, avoiding duplicate modals. Provide clear progress/status during deterministic jobs.

---

## Changes

### A. Treat **ApplicantProfile** intake as validated
- On successful intake Save (Contacts or Manual), ensure the persisted payload contains:
  - `meta.validation_state = "user_validated"`
  - `meta.validated_via = "contacts" | "manual"`
  - `meta.validated_at = ISO8601 timestamp`
- Do **not** surface a subsequent approval step for the same profile. Proceed directly to timeline.

**Files**
- Intake save path (handler/service): `Sprung/Onboarding/Handlers/ProfileInteractionHandler.swift` and/or the service it calls.

**Acceptance**
- After Save, the chat advances; no validation modal for profile appears in the same session.  
- If a stray `submit_for_validation(applicant_profile)` occurs, it is auto‑approved (tool behavior; see dev_c).

---

### B. Treat **Timeline editor** saves as validated
- When the user edits/saves timeline cards, enrich the stored skeleton timeline with:
  - `meta.validation_state = "user_validated"`
  - `meta.validated_via = "timeline_editor"`
  - `meta.validated_at = ISO8601 timestamp`
- Mark the `skeleton_timeline` objective **completed** at persist time (if not already).  
- Emit a developer status like “Timeline cards updated by the user” with the final payload.

**Files**
- Timeline update path: `Sprung/Onboarding/.../OnboardingInterviewService.applyUserTimelineUpdate(...)` (or equivalent)  
- Objective marking: wherever `storeSkeletonTimeline(...)` records objective status.

**Acceptance**
- After user edits, the flow proceeds without a second validation step for the same content.  
- The assistant treats the payload as authoritative and moves to `enabled_sections`.

---

### C. Status plumbing for spinner
- Ensure deterministic steps (PDF detection/extraction/save) set short `pendingStreamingStatus` strings (“Extracting PDF…”, “Saving artifact…”, “Sending to assistant…”).  
- Clear when work completes.

**Files**
- `Sprung/Onboarding/Managers/DocumentExtractionService.swift`  
- `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`

**Acceptance**
- The left pane shows timely, human‑readable progress beneath the spinner (see dev_a).

---

## Risks & Mitigations
- **Risk:** Marking validation on editor save might mask needed reviews.  
  **Mitigation:** Only treat **user**-initiated saves as validated; LLM-originated bulk edits should still go through explicit validation (guarded in dev_c/dev_d).

---

## Validation Plan
1. Contacts intake → Save: profile marked validated; no duplicate review.  
2. Timeline edits → Save: meta added, objective completed, flow continues.  
3. Resume upload: status lines appear during extraction/save.

---

## Progress Checklist
- [ ] ApplicantProfile meta on save (contacts/manual)  
- [ ] Timeline meta on user save; objective completed  
- [ ] Developer status emission after timeline save  
- [ ] Status strings wired for spinner
