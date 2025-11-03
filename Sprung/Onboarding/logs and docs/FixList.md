# Onboarding Fix Pack — Combined Changes & Patches (v1)

This document consolidates all fixes we discussed into one actionable pack. It’s organized by problem area and includes rationale, precise code edits/diffs, and acceptance checks. Everything here is additive and safe to apply incrementally.

---

## Contents
1. Two tiny changes (spinner + occupancy)
2. Autoscroll + glow stability patch
3. Reasoning summaries → dedicated Status Bar (always visible)
4. SettingsView ↔ model id sync + hard error for invalid ids
5. Intake card dismissal: Objective Ledger overhaul (and prompt contract updates)
6. Quick test plan (10 minutes)

---

## 1) Two tiny changes (spinner + occupancy)

**Goal**
- Make the left pane show a spinner whenever *either* the LLM is streaming *or* a deterministic job (e.g., PDF extraction) is running **and** no other card is occupying the pane.
- Fix the “pane occupied” signal so the spinner isn’t accidentally suppressed.

**Edits**
1. **OnboardingInterviewToolPane.swift**
   - Treat the pane as occupied when any of the following are true: upload requests present, an intake/choice/validation card is active.
   - Consider the LLM “active” when `service.isProcessing` **or** `coordinator.pendingStreamingStatus` is non‑nil.
   - Show spinner when `(pendingExtraction != nil) || (!paneOccupied && isLLMActive)`.

```diff
 let paneOccupied = isPaneOccupied(service: service, coordinator: coordinator)
 let isLLMActive = service.isProcessing || coordinator.pendingStreamingStatus != nil
 let showSpinner = service.pendingExtraction != nil || (!paneOccupied && isLLMActive)
```

2. **Interactive host** that owns the tool pane:
   - Ensure the `isOccupied` binding you pass into `OnboardingInterviewToolPane` reflects `isPaneOccupied(...)` to keep the rest of the view tree consistent.

**Acceptance**
- While extraction runs or the model streams (with no card visible), a centered spinner appears with a 1‑line status.
- Spinner disappears immediately when a card appears or work ends.

---

## 2) Autoscroll + glow stability patch

**Problems fixed**
- Chat jumped upward when the glow became active.
- Autoscroll didn’t consistently snap to the latest message on completion.

**Design**
- Only auto‑scroll when **(a)** a new message is appended, or **(b)** streaming flips from true → false.
- Track a `shouldAutoScroll` boolean driven by “near bottom” detection; if the user has scrolled up, we don’t auto‑scroll and show a floating “down arrow”.
- Keep the glow (visual affordance) independent of scroll state.

**Edits**
1. **Scroll offset observer**
   - Keep the existing `ScrollViewOffsetObserver`. Use a small near‑bottom threshold (e.g., 32pt) to drive `state.shouldAutoScroll`.

```swift
let nearBottom = max(maxOffset - offset, 0) < 32
if state.shouldAutoScroll != nearBottom {
  state.shouldAutoScroll = nearBottom
}
updateScrollToLatestVisibility(isNearBottom: nearBottom)
```

2. **Scroll triggers**
   - On `messages.count` increase → `scrollToLatestMessage()` if `state.shouldAutoScroll`.
   - On `service.isProcessing` change to `false` → `scrollToLatestMessage()`.

**Acceptance**
- During long replies, the view does **not** jump per token; it snaps once when the message completes.
- Manually scrolling up shows the “down arrow”; tapping it restores auto‑scroll.

---

## 3) Reasoning summaries → dedicated Status Bar (always visible)

**Goal**
- Show reasoning summaries even when the assistant returns **no** textual message for that turn.

**Design**
- Introduce a small **Reasoning Status Bar** pinned to the bottom of the chat panel, above the composer.
- It displays the latest non‑empty reasoning summary (fades after a few seconds, or when replaced).
- Keep the existing italic summary **inside message bubbles** when an assistant message is present; the Status Bar is a backstop when there isn’t one.

**State**
- Add `@Published var latestReasoningSummary: String?` to the coordinator/store layer.
- Update it from the orchestrator callback whenever a reasoning summary item arrives (even if no assistant message arrives in that turn).
- Clear it when streaming ends and the next assistant message includes its own summary (message‑scoped rendering takes precedence), or after a timeout.

**UI**
- New `ReasoningStatusBar` view:

```swift
struct ReasoningStatusBar: View {
  let text: String
  var body: some View {
    HStack(spacing: 8) {
      ProgressView().controlSize(.small)
      Text(text).font(.footnote).italic().foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
```

- Insert it just above the composer:

```swift
if let text = coordinator.latestReasoningSummary, !text.isEmpty {
  ReasoningStatusBar(text: text)
    .transition(.opacity.combined(with: .move(edge: .bottom)))
    .padding(.horizontal, horizontalPadding)
}
```

**Acceptance**
- If a turn has only reasoning (no assistant text), the Status Bar shows the summary.
- If a later turn includes assistant text **with** summary, the inline italic line shows under that bubble and the Status Bar hides.

---

## 4) SettingsView ↔ model id sync + hard error for invalid ids

**Problems fixed**
- Stale “built‑in” fallback ids can stick around and yield silent 400s.
- The picker is populated from OpenRouter but the active id may not be reconciled.

**Changes**
1. **Validation on startup + selection**
   - After fetching `availableModelIds`, ensure the **selected** id is either:
     1) in `availableModelIds`, or
     2) replaced by the default, else
     3) replaced by the first available entry.
   - Never keep a string that is not in `availableModelIds`.

2. **Service preference setter**
   - When `setPreferredDefaults(modelId:backend:...)` is called, guard that `modelId` exists in the latest list; if not, coerce to default + emit a user‑visible error banner.

3. **400 mapping → UI**
   - In `LLMRequestExecutor`, map HTTP 400 with message `"<id> is not a valid model ID"` to a non‑retryable `invalidModelId(id)` error.
   - Bubble this through the service to the chat panel as a banner: “Your selected model is no longer available. Pick a model in Settings.” with a **Change in Settings…** action.

4. **PDF extraction model id**
   - Ensure the document extraction service also references the same validated model id (or its own independent picker that uses the same validation flow). Do not keep a hard‑coded fallback string.

**Acceptance**
- If a removed id is selected, users immediately see a banner and the app coerces to a valid model.
- No more silent infinite retries for 400s.

---

## 5) Intake card dismissal: Objective Ledger overhaul

**Problems fixed**
- `applicant_profile` being marked complete too early (e.g., as soon as profile is persisted or Contacts import finishes), leaving the intake card stranded.
- `contact_photo_collected` never transitions because the photo write path doesn’t record its objective state.

**Design**
- Introduce a **single source of truth** for objective transitions in the `InterviewState` actor.
- Tools **request** transitions; the coordinator arbitrates and records them.
- UI visibility derives solely from ledger state (not ad‑hoc flags sprinkled in multiple places).

**State additions**
- Extend `ObjectiveEntry` with:
  - `status: pending|in_progress|completed|skipped` (no auto‑complete on persistence alone)
  - `updatedAt`, `source` (e.g., contacts, upload, manual)
  - `notes` (freeform, optional)
- Add helper methods on the actor:
  - `beginObjective(_ id:)`
  - `completeObjective(_ id:, source:, notes:)`
  - `skipObjective(_ id:, reason:)`
  - `isObjective(_ id:, inState:)`

**Transitions**
- **Applicant Profile**
  - Begin on first intake open.
  - Complete only when **all** of:
    - profile persisted **and**
    - either `contact_photo_collected` is `completed` **or** `skipped` (user explicitly chooses to skip) **and**
    - validation either not required **or** marked `user_validated`.
- **Contact Photo Collected**
  - Complete when `storeApplicantProfileImage(bytes:)` succeeds.
  - Skip path exposed via the intake card (“Skip photo for now”).

**UI rules**
- Intake card **remains visible** until `applicant_profile` is `completed|skipped`.
- When `contact_photo_collected` transitions to `completed` or `skipped`, immediately evaluate `applicant_profile` for completion and dismiss the card.

**Tooling / prompt contract**
- `set_objective_status` stays, but the system prompt clarifies:
  - The LLM **proposes** status with `set_objective_status`.
  - The coordinator will finalize and may override; the LLM should not loop on re‑assertions.
- Add explicit tool `skip_objective(id, reason)` for photo opt‑out, or map it to `set_objective_status(id, status:"skipped")`.

**Minimal prompt snippet to append**
```
### Objective Ledger Rules
- Propose status via `set_objective_status` when you believe an objective or sub‑objective is finished.
- Do **not** re‑open or re‑mark an objective the coordinator has finalized.
- For the photo: call `set_objective_status(id:"contact_photo_collected", status:"completed")` when a photo is successfully saved, or `status:"skipped"` if the user declines. Only when photo is `completed|skipped` and the profile data is persisted should you propose `applicant_profile → completed`.
```

**Acceptance**
- Intake card dismisses immediately after profile + (photo **completed|skipped**) + (any required validation met).
- No early completion after Contacts import alone.

---

## 6) Quick test plan (≈10 min)

1. **Model id guardrails**
   - Set a bogus model id in defaults; launch app → banner appears, Settings link works; requests do not retry.
2. **Resume path**
   - Open intake, choose *Upload resume*, pick a PDF:
     - Left spinner shows “Extracting PDF…” while pane is otherwise empty.
     - Chat does not jump while streaming; snaps to end when finished.
3. **Reasoning‑only turn**
   - Trigger a tool‑only turn that yields reasoning without assistant text:
     - Status Bar shows the italic summary; disappears on next assistant message with inline summary.
4. **Photo collected**
   - Upload a photo → `contact_photo_collected` → intake card re‑evaluates and dismisses once profile is persisted.
5. **Skip photo**
   - Use Skip → ledger records `skipped` → intake card dismisses after profile persist.

---

## Appendix — Example diffs

> Note: Paths/names match your current tree; adapt import lines if you’ve refactored modules.

### A. Coordinator/store state (reasoning summary)
```diff
 // OnboardingInterviewCoordinator.swift (or ChatTranscriptStore)
 @Published var latestReasoningSummary: String?

 func updateReasoningSummary(_ text: String) {
   latestReasoningSummary = text.trimmingCharacters(in: .whitespacesAndNewlines)
 }

 func clearReasoningSummary() {
   latestReasoningSummary = nil
 }
```

Hook from orchestrator:
```diff
 callbacks.updateReasoningSummary = { [weak self] text in
   await MainActor.run { self?.updateReasoningSummary(text) }
 }
 callbacks.finalizeAssistantStream = { [weak self] in
   await MainActor.run { self?.clearReasoningSummary() }
 }
```

### B. Chat panel insertion (status bar)
```diff
 // OnboardingInterviewChatPanel.swift
 if let text = coordinator.latestReasoningSummary, !text.isEmpty {
   ReasoningStatusBar(text: text)
     .padding(.horizontal, horizontalPadding)
 }
```

### C. LLMRequestExecutor invalid‑model mapping
```diff
 if response.statusCode == 400,
    let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
    body.error.message.contains("is not a valid model ID") {
   throw APIError.invalidModelId(selectedId)
 }
```

### D. InterviewState ledger helpers
```diff
 mutating func beginObjective(_ id: String) { /* … */ }
 mutating func completeObjective(_ id: String, source: String?, notes: String?) { /* … */ }
 mutating func skipObjective(_ id: String, reason: String?) { /* … */ }
 func isObjective(_ id: String, inState state: Status) -> Bool { /* … */ }
```

### E. Photo save path → objective status
```diff
 func storeApplicantProfileImage(_ data: Data) async throws {
   try await imageStore.save(data)
   await interviewState.completeObjective("contact_photo_collected", source: "upload", notes: nil)
 }
```

---

**End of v1**

