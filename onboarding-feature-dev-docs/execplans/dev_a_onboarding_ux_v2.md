# ExecPlan: Onboarding UX polish (dev_a) — scroll, reasoning summary, spinner

**Status:** Proposed  
**Owner:** dev_a  
**Scope:** Chat transcript readability, reasoning summary surfacing, left-pane spinner/progress.  
**Out of scope:** Tool steering, prompt contract (see dev_c, dev_d).

---

## Purpose / Big Picture
Deliver a smooth chat experience while the assistant streams:
1) Auto‑scroll **only** when an assistant message finishes (no per‑token jumps).  
2) Show the italic reasoning summary line when available; remove the placeholder once the message completes.  
3) Render the Sprung spinner with short status text while the LLM or deterministic jobs (e.g., PDF extraction) are in progress and no other card occupies the left pane.

---

## Changes

### A. Auto‑scroll only at message completion
- **Remove** per‑delta scroll in the chat panel (the `onChange` that watches `messages.last?.text`).
- **Keep** existing hooks:
  - `onChange(messages.count)` – when a new message is appended.
  - `onChange(service.isProcessing)` – final snap to bottom when streaming ends.
- **Retain** the “jump to latest” button when the user has scrolled away.

**Files**
- `Sprung/Onboarding/Views/Components/OnboardingInterviewChatPanel.swift`

**Acceptance**
- During long assistant replies, the view does **not** jump until the message completes.  
- If the user scrolls up, the “down arrow” affordance appears and restores the view to the bottom on tap.

---

### B. Reasoning summaries render reliably
- **Change array-element mutation to reassignment** in the store: copy the message to a local var, mutate `reasoningSummary` and flags, then write back with `messages[index] = msg`. This guarantees Observation/SwiftUI publishes updates.
- Apply this pattern in:
  - `updateAssistantStream`, `finalizeAssistantStream`
  - `updateReasoningSummary`, `finalizeReasoningSummariesIfNeeded`

**Files**
- `Sprung/Onboarding/Stores and Services/ChatTranscriptStore.swift`

**Acceptance**
- When logs indicate a reasoning summary was received, the chat shows a single italic line beneath the assistant message.  
- The shimmering placeholder never outlives the final message completion.

---

### C. Spinner + status in the left pane
- The tool pane already computes `showSpinner`; **render it** when `true` and no other card occupies the pane.
- Layout:
  - `AnimatedThinkingText()` centered.
  - Optional `Text(coordinator.pendingStreamingStatus)` beneath (footnote, secondary).
- The spinner appears during resume extraction, artifact save, or active streaming with an empty pane.

**Files**
- `Sprung/Onboarding/Views/Components/OnboardingInterviewToolPane.swift`
- (uses existing) `Sprung/Onboarding/Views/Components/AnimatedThinkingText.swift`

**Acceptance**
- After saving Applicant Profile (or any card dismissal) and while the model is working, the spinner is visible with brief status lines (“Extracting PDF…”, “Saving artifact…”).  
- Spinner disappears as soon as a new card loads or processing ends.

---

## Risks & Mitigations
- **Risk:** Removing per‑delta scroll hides partial content for very fast responses.  
  **Mitigation:** Users can tap the “jump to latest” button; end‑of‑message snap keeps the transcript readable.

---

## Validation Plan
1. Send a prompt that yields streaming tokens; confirm no jitter until completion.  
2. Trigger a response known to produce a reasoning summary; confirm italic line appears.  
3. Run the resume-upload flow: observe spinner + status until the first card appears.

---

## Rollback
Re-enable the per‑delta `onChange` in ChatPanel and revert the store to in‑place mutation (not recommended).

---

## Progress Checklist
- [ ] Remove per‑delta auto‑scroll; keep completion hooks
- [ ] Reassign array elements on summary/stream updates
- [ ] Render spinner + status when `showSpinner` is true
