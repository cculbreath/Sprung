# ExecPlan: Chat UI Auto-scroll and Reasoning Summary Display Fixes

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

**IMPORTANT**: Multiple developers are working on this codebase simultaneously. Make frequent atomic commits with clear messages. If you encounter unexpected changes to files you're working on, pull latest changes and merge carefully. Coordinate through commit messages and avoid large, monolithic changes.

## Purpose / Big Picture

After this change, users will experience a dramatically improved chat interface during assistant responses. The chat will remain stable and readable while the assistant streams tokens (no more jittery scrolling on every word), and reasoning summaries will reliably appear in italics under assistant messages when provided by the model. This creates a calm, professional interaction experience where users can actually read responses as they stream without fighting the scroll position.

## Progress

Use a list with checkboxes to summarize granular steps. Every stopping point must be documented here, even if it requires splitting a partially completed task into two.

- [ ] Set up development environment and verify build
- [ ] Remove per-delta scroll trigger in OnboardingInterviewChatPanel.swift
- [ ] Test scroll behavior with long streaming responses
- [ ] Implement array element reassignment pattern in ChatTranscriptStore.swift for updateAssistantStream
- [ ] Implement array element reassignment pattern for finalizeAssistantStream
- [ ] Implement array element reassignment pattern for updateReasoningSummary
- [ ] Implement array element reassignment pattern for finalizeReasoningSummariesIfNeeded
- [ ] Test reasoning summary display with model responses
- [ ] Create atomic commit for scroll fixes
- [ ] Create atomic commit for reasoning summary fixes
- [ ] Run full acceptance tests
- [ ] Document any merge conflicts encountered

## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during implementation.

- To be filled during implementation

## Decision Log

Record every decision made while working on the plan.

- Decision: Handle scroll and reasoning fixes separately with distinct commits
  Rationale: Allows easier rollback if one fix causes issues, cleaner git history
  Date/Author: 2025-11-01 / Planning Phase

## Outcomes & Retrospective

To be filled at completion.

## Context and Orientation

This plan focuses on two critical UI issues in the onboarding interview chat interface:

1. **Chat Auto-scroll Jitter**: Currently located in `Views/Components/OnboardingInterviewChatPanel.swift`, the chat scrolls on every token delta via `onChange(of: coordinator.messages.last?.text)`. This creates a jittery, unreadable experience during streaming.

2. **Reasoning Summary Display**: Located in `Stores/ChatTranscriptStore.swift`, reasoning summaries are updated by mutating properties directly on array elements (`messages[index].reasoningSummary = ...`). With Swift's Observation framework, this in-place mutation doesn't trigger view updates, so summaries never appear even when logs confirm they arrived.

The chat panel uses SwiftUI's ScrollViewReader for positioning. The transcript store uses the @Observable macro requiring explicit array element reassignment for change detection.

## Plan of Work

### Phase 1: Fix Auto-scroll Behavior

We will modify the scroll triggers in the chat panel to only activate on message completion, not on every token update. The existing `onChange(of: coordinator.messages.count)` hook handles new messages, and `onChange(of: service.isProcessing)` handles completion. We remove the problematic per-delta hook.

### Phase 2: Fix Reasoning Summary Updates

We will refactor all array element mutations in ChatTranscriptStore to use the reassignment pattern. Instead of mutating in place, we copy the element to a local variable, modify it, then reassign it back to the array. This ensures Swift's Observation framework detects the change and triggers view updates.

## Concrete Steps

Working directory: `./Sprung/Onboarding/`

### Step 1: Remove Per-Delta Scroll Trigger

    cd ./Sprung/Onboarding/
    git pull origin main
    git checkout -b fix/chat-scroll-behavior

Edit `Views/Components/OnboardingInterviewChatPanel.swift`:

1. Locate the `messageScrollView` function
2. Find the `onChange` modifier that reads: `onChange(of: coordinator.messages.last?.text ?? "", initial: false)`
3. Delete this entire onChange block
4. Verify the following hooks remain:
   - `onChange(of: coordinator.messages.count)`
   - `onChange(of: service.isProcessing)`

Test by running the app and observing that chat doesn't jump during streaming.

    git add Views/Components/OnboardingInterviewChatPanel.swift
    git commit -m "fix: Remove per-delta auto-scroll to prevent chat jitter during streaming"

### Step 2: Fix Array Element Updates for Observability

Edit `Stores/ChatTranscriptStore.swift`:

1. Locate `updateAssistantStream` method. Change pattern from:

        messages[index].text = updatedText
        messages[index].isStreaming = true

   To:

        var msg = messages[index]
        msg.text = updatedText
        msg.isStreaming = true
        messages[index] = msg

2. Locate `finalizeAssistantStream` method. Apply same pattern for all property updates.

3. Locate `updateReasoningSummary` method. Change from:

        messages[index].reasoningSummary = summary
        messages[index].showReasoningPlaceholder = false

   To:

        var msg = messages[index]
        msg.reasoningSummary = summary
        msg.showReasoningPlaceholder = false
        messages[index] = msg

4. Locate `finalizeReasoningSummariesIfNeeded` method. Apply same reassignment pattern.

Test by triggering responses with reasoning summaries and confirming they appear in the UI.

    git add Stores/ChatTranscriptStore.swift
    git commit -m "fix: Use array element reassignment for Observable updates in ChatTranscriptStore"
    git push origin fix/chat-scroll-behavior

## Validation and Acceptance

No automated tests required. Notify user when code is ready for workflow evaluation.

## Idempotence and Recovery

All changes are safely reversible:

- Removing the onChange hook: Can be re-added if needed, though this would restore the jitter
- Array reassignment pattern: Functionally equivalent to in-place mutation, just triggers Observation
- No data model changes or migrations required
- Can safely pull and merge upstream changes during development

If merge conflicts occur in either file:
1. Stash local changes: `git stash`
2. Pull latest: `git pull origin main`  
3. Reapply changes: `git stash pop`
4. Resolve conflicts preserving both sets of changes
5. Re-test affected functionality

## Artifacts and Notes

Expected console output during testing showing reasoning summary arrival:

    [ChatTranscriptStore] Updating reasoning summary for message 5
    [ChatTranscriptStore] Summary: "Analyzing user request for company information..."
    [SwiftUI] View update triggered for MessageBubbleView

The down-arrow scroll button should remain functional and only appear when user has scrolled away from bottom.

## Interfaces and Dependencies

No external dependencies. Uses existing SwiftUI ScrollViewReader and Swift Observation framework.

Key protocols/types that must remain compatible:
- `ChatMessage` struct with `reasoningSummary: String?` and `showReasoningPlaceholder: Bool`
- `OnboardingChatCoordinator.messages: [ChatMessage]`
- ` service.isProcessing: Bool`

No changes to public APIs or tool interfaces.