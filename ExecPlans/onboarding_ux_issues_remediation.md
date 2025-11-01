# Onboarding UX Issues Remediation Plan

## Executive Summary

This plan addresses 8 critical UX issues identified during onboarding workflow testing on 10/31/25. Issues range from minor polish items to critical regressions that break core functionality. The plan provides detailed root cause analysis, implementation strategy, and acceptance criteria for each issue.

## Issues Overview

| Priority | Issue | Category | Impact |
|----------|-------|----------|---------|
| P0 | Resume upload form not appearing | Critical Regression | Blocks workflow |
| P0 | Experience editor cards not displaying | Critical Regression | Blocks workflow |
| P1 | Resume dialog after full reset | Incorrect State | Poor UX |
| P1 | Thinking spinner not showing | Missing Feature | Reduced feedback |
| P2 | Auto-scroll behavior issues | Polish | Minor annoyance |
| P2 | Sections enable view styling | Visual Bug | Poor aesthetics |
| P3 | Missing photo existence check | Missing Logic | Redundant prompts |
| P3 | Upload form title generic | Polish | Minor UX issue |

---

## P0: Critical Regressions

### Issue 1: Resume Upload Form Not Appearing

**Symptoms:**
- LLM says "surfacing the resume upload now" in chat
- No upload form card appears in left pane
- User cannot proceed with workflow

**Root Cause Analysis:**
Based on console log analysis, the LLM is responding with text but NOT calling the `get_user_upload` tool. The issue appears to be that:
1. The LLM believes it has "surfaced" the upload by saying so in text
2. The tool is not being called when it should be
3. This suggests a prompting issue where the LLM doesn't understand it must call the tool

**Evidence:**
- Console log shows text output: "Thanks for the heads up—surfacing the resume upload now."
- No corresponding `get_user_upload` function_call in the response
- User feedback: "No resume upload form is shown"

**Implementation Strategy:**

1. **Update Phase 1 system prompt** (Sprung/Onboarding/Phases/Phase1Script.swift or equivalent):
   - Add explicit instruction: "NEVER claim to surface a form or card without calling the corresponding tool"
   - Add example: "Incorrect: 'I'll show you the upload form now.' Correct: [calls get_user_upload tool]"
   - Emphasize: "UI elements only appear when you call the corresponding tool"

2. **Add developer status message after user says "No resume upload form is shown"**:
   - Detect user complaints about missing UI
   - Send developer message: "Developer status: User reports upload form is not visible. You must call get_user_upload tool immediately. Do not describe the form in text—call the tool."

3. **Add tool call verification in coordinator**:
   - After LLM mentions "upload" or "form" without calling tool, inject warning
   - Track tools mentioned in text vs. tools actually called

**Files to Modify:**
- `Sprung/Onboarding/Phases/Phase1Script.swift` - Update system prompt
- `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift` - Add response analysis

**Acceptance Criteria:**
- [ ] LLM calls `get_user_upload` when user reports missing form
- [ ] Upload card appears in left pane within 2 seconds of tool call
- [ ] No text-only responses claiming to "surface" forms
- [ ] Full workflow completion with resume upload

**Testing:**
1. Start interview
2. Complete profile intake
3. When prompted for resume, say "No upload form shown"
4. Verify LLM calls tool and form appears

---

### Issue 2: Experience Editor Cards Not Displaying

**Symptoms:**
- LLM extracts timeline from resume
- Says "Please review the card to the left"
- NO EXPERIENCE EDITOR CARDS DISPLAYED in tool pane

**Root Cause Analysis:**
Based on code inspection, console log evidence, and git history:

**Timeline Tools Exist (commit 9cd6544):**
- `CreateTimelineCardTool`, `UpdateTimelineCardTool`, `ReorderTimelineCardsTool`, `DeleteTimelineCardTool`
- `TimelineCardEditorView` - fully implemented with drag-drop, inline editing
- `TimelineCardAdapter`, `TimelineDiff` - supporting infrastructure
- All properly registered in `OnboardingInterviewService.swift:158-161`

**The Problem:**
According to dev_b_chat_conversation_cards.md plan, the LLM should be using timeline card tools to build the timeline interactively. However, console logs show:
1. LLM calls `submit_for_validation` with complete timeline data (old approach)
2. LLM does NOT call `create_timeline_card` to build cards individually (new approach)
3. The view expects `skeletonTimelineJSON` to be set for TimelineCardEditorView to render
4. But this isn't happening because the validation data isn't being stored

**Two Possible Causes:**
A) **Prompt Issue**: Phase 1 system prompt may not instruct LLM to use card tools
B) **Data Flow Issue**: When LLM does call validation, the JSON isn't stored in `coordinator.skeletonTimelineJSON`

**Evidence:**
- Console shows: `submit_for_validation` called with skeleton_timeline data
- Screenshot shows: No cards visible, just section selector
- OnboardingInterviewToolPane checks: `coordinator.wizardStep == .artifactDiscovery` AND `service.skeletonTimelineJSON != nil`
- User note: "experience cards were basically implemented correctly, but were haphazardly removed to address a build error" (though git history shows only minor styling fixes, not removal of core logic)

**Implementation Strategy:**

**Option A: Fix Data Flow (Quick Fix - Recommended)**

1. **Store timeline JSON when validation is submitted**:
   ```swift
   // In OnboardingInterviewCoordinator or ValidationInteractionHandler
   func handleValidationRequest(dataType: String, payload: JSON) {
       if dataType == "skeleton_timeline" {
           skeletonTimelineJSON = payload
           Logger.info("📝 Stored skeleton timeline JSON for editor view", category: .ai)
       }
       // ... rest of validation logic
   }
   ```

2. **Add debugging to understand current flow**:
   ```swift
   // In OnboardingInterviewToolPane supportingContent()
   Logger.debug("🔍 Tool pane: step=\(coordinator.wizardStep), hasTimeline=\(service.skeletonTimelineJSON != nil)", category: .ui)
   ```

3. **Verify TimelineCardEditorView receives data**:
   - Add logging in TimelineCardEditorView.onAppear
   - Confirm `TimelineCardAdapter.cards(from: timeline)` works

**Option B: Switch to Card Tools Approach (Aligns with dev_b plan)**

1. **Update Phase 1 system prompt** to prefer card tools:
   ```
   After extracting timeline from resume:
   1. Call create_timeline_card for each position
   2. DO NOT call submit_for_validation with complete timeline
   3. Cards appear as you create them
   4. User can drag-reorder and edit inline
   ```

2. **Remove/deprecate skeleton_timeline validation**:
   - Timeline is built through cards, not validated as whole
   - User interacts with cards directly
   - Save when user clicks "Save Timeline" button

3. **Update tool pane to show cards as they're created**:
   - Render individual cards from `service.artifacts.timelineCards`
   - Don't wait for full validation

**Recommendation: Try Option A first (2 hours), fall back to Option B if needed (1 day)**

**Files to Modify:**
- `Sprung/Onboarding/Handlers/ValidationInteractionHandler.swift` - Store timeline on validation
- `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift` - Pass through to skeletonTimelineJSON
- `Sprung/Onboarding/Views/Components/OnboardingInterviewToolPane.swift` - Add logging
- `Sprung/Onboarding/Phases/Phase1Script.swift` - (Option B only) Update prompts

**Acceptance Criteria:**
- [ ] Timeline cards appear after resume extraction
- [ ] Each card shows: title, organization, location, dates
- [ ] Cards are editable inline
- [ ] Cards are drag-reorderable
- [ ] Save/Discard buttons work correctly

**Testing:**
1. Upload resume with work history
2. Verify LLM extracts timeline
3. Confirm cards appear in left pane
4. Edit a card's title
5. Drag to reorder
6. Save changes

---

## P1: High Priority Fixes

### Issue 3: Resume Dialog After Full Datastore Reset

**Symptoms:**
- User performs full reset of datastore
- Clicks "Begin Interview"
- Resume/Start Over dialog appears even though there's nothing to resume

**Root Cause:**
The checkpoint system (`hasRestorableCheckpoint()`) returns true even after full reset. This suggests checkpoints aren't being cleared during the reset operation.

**Files Involved:**
- `Sprung/App/Services/DataResetService.swift` - Reset logic
- `Sprung/Onboarding/Core/Checkpoints.swift` - Checkpoint management
- `Sprung/Onboarding/Views/OnboardingInterviewView.swift:405-408` - Dialog trigger

**Implementation Strategy:**

1. **Update DataResetService** to clear checkpoints:
   ```swift
   func resetOnboardingData() async {
       // Existing code...
       await Checkpoints().clearAll()
       Logger.info("🗑️ Cleared onboarding checkpoints", category: .data)
   }
   ```

2. **Add checkpoint clearing to interview reset**:
   ```swift
   func resetInterview() {
       coordinator.resetInterview()
       Task { await checkpoints.clearAll() }
       resetLocalTransientState()
   }
   ```

3. **Add verification logging**:
   ```swift
   func hasRestorableCheckpoint() async -> Bool {
       let result = await checkpoints.hasRestorable()
       Logger.debug("🔍 Checkpoint check: \(result)", category: .ai)
       return result
   }
   ```

**Acceptance Criteria:**
- [ ] Full reset clears all checkpoints
- [ ] Resume dialog never appears after full reset
- [ ] Resume dialog DOES appear when interrupting a real session
- [ ] Checkpoint restoration works correctly when resuming

---

### Issue 4: Thinking Spinner Not Showing

**Symptoms:**
- During long inference waits, no feedback shown
- User doesn't know if app is working or frozen
- Reasoning summaries are available but not displayed

**Root Cause:**
Based on console log analysis and git history (commit 3a078ab), the problem is multi-layered:

1. **API IS Providing Reasoning Summaries** - Console log shows:
   ```json
   "reasoning": {
       "summary": [
           {
               "text": "**Creating timeline cards**\n\nI need to parse...",
               "type": "summary_text"
           }
       ],
       "type": "reasoning"
   }
   ```

2. **Reasoning Placeholder System Exists** - But was disabled in commit 3a078ab:
   ```swift
   // Changed from true to false:
   messages[index].showReasoningPlaceholder = false
   Logger.info("ℹ️ Reasoning summary unavailable for message \(id.uuidString)", category: .ai)
   ```

3. **Why It Was Disabled** - Commit message: "Stop showing indefinite reasoning placeholder"
   - Placeholders were showing indefinitely (stuck)
   - Reasoning summaries were not arriving at messages
   - Placeholder never cleared, so it was disabled

4. **The Real Problem** - Reasoning summaries from API aren't being:
   - Extracted from streaming response
   - Stored in message objects
   - Delivered to ChatTranscriptStore
   - Cleared from "awaiting" state

**Evidence:**
- Console shows API providing summaries
- Code shows placeholder was disabled due to indefinite display
- No ReasoningStreamView connected to onboarding
- Messages stuck in `isAwaitingReasoningSummary` state

**Implementation Strategy:**

**Step 1: Fix Reasoning Summary Extraction (Core Issue)**

1. **Update InterviewOrchestrator or StreamingExecutor** to extract reasoning:
   ```swift
   // When processing streaming response:
   if let reasoning = chunk.reasoning,
      let summaries = reasoning.summary {
       let text = summaries.map { $0.text }.joined(separator: "\n\n")
       // Store for later delivery to message
       currentMessageReasoningSummary = text
   }

   // When message completes:
   if let summary = currentMessageReasoningSummary {
       coordinator.attachReasoningSummary(messageId: messageId, summary: summary)
       currentMessageReasoningSummary = nil
   }
   ```

2. **Update ChatTranscriptStore to receive summaries**:
   ```swift
   func attachReasoningSummary(messageId: UUID, summary: String) {
       guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
       messages[index].reasoningSummary = summary
       messages[index].isAwaitingReasoningSummary = false
       messages[index].showReasoningPlaceholder = false
       Logger.info("✅ Attached reasoning summary to message", category: .ai)
   }
   ```

3. **Re-enable reasoning placeholder** (now that summaries will arrive):
   ```swift
   // Revert commit 3a078ab partially:
   messages[index].showReasoningPlaceholder = true // Was set to false
   ```

**Step 2: Add Visual Reasoning Display**

4. **Add ReasoningStreamManager to OnboardingInterviewView**:
   ```swift
   @State private var reasoningManager = ReasoningStreamManager()
   ```

5. **Add ReasoningStreamView overlay**:
   ```swift
   .overlay {
       ReasoningStreamView(
           isVisible: $reasoningManager.isVisible,
           reasoningText: $reasoningManager.reasoningText,
           isStreaming: $reasoningManager.isStreaming,
           modelName: modelStatusDescription(service: service)
       )
   }
   ```

6. **Update reasoning manager on streaming events**:
   ```swift
   // When reasoning starts:
   reasoningManager.startReasoning(modelName: "GPT-5")

   // When summaries arrive:
   reasoningManager.appendText(summaryText)

   // When message completes:
   reasoningManager.stopStream()
   ```

**Files to Modify:**
- `Sprung/Shared/AI/Models/Services/StreamingExecutor.swift` - Extract reasoning from responses
- `Sprung/Onboarding/Core/InterviewOrchestrator.swift` - Store and deliver summaries
- `Sprung/Onboarding/Stores/ChatTranscriptStore.swift` - Receive and attach summaries, re-enable placeholder
- `Sprung/Onboarding/Views/OnboardingInterviewView.swift` - Add ReasoningStreamView
- `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift` - Wire events

**Acceptance Criteria:**
- [ ] Reasoning modal appears during long inferences
- [ ] Real-time reasoning text streams as it arrives
- [ ] Modal auto-shows when reasoning starts
- [ ] Modal persists until response completes
- [ ] User can dismiss modal without interrupting inference

---

## P2: Polish & Improvements

### Issue 5: Auto-Scroll Behavior Issues

**Symptoms:**
- Chat scrolls to top when assistant message ends
- Chat scrolls on every word during streaming
- Cannot read earlier messages during output

**Root Cause:**
Multiple scroll triggers in OnboardingInterviewChatPanel.swift:
- Line 156-165: Triggers on message count change
- Line 159-160: Triggers on message text change during streaming
- Line 162-164: Triggers when processing ends

**Implementation Strategy:**

1. **Only scroll at message completion, not during streaming**:
   ```swift
   .onChange(of: coordinator.messages.last?.text ?? "", initial: false) { _, _ in
       // Remove this - causes scroll on every delta
   }
   ```

2. **Add debouncing to scroll during streaming**:
   ```swift
   private var scrollDebounceTask: Task<Void, Never>?

   func scrollWithDebounce(_ proxy: ScrollViewProxy) {
       scrollDebounceTask?.cancel()
       scrollDebounceTask = Task { @MainActor in
           try? await Task.sleep(for: .milliseconds(100))
           scrollToLatestMessage(proxy)
       }
   }
   ```

3. **Only auto-scroll when user is already at bottom**:
   - Keep existing `shouldAutoScroll` logic
   - Don't override user's manual scroll position

**Files to Modify:**
- `Sprung/Onboarding/Views/Components/OnboardingInterviewChatPanel.swift:156-165`

**Acceptance Criteria:**
- [ ] Chat stays put during assistant output
- [ ] Chat scrolls to bottom when message completes
- [ ] Manual scroll-up persists during streaming
- [ ] Scroll-to-bottom button appears when scrolled up

---

### Issue 6: Sections Enable View Styling

**Symptoms:**
- Background too dark
- Too tall, clipped by overlay
- Not scrollable properly
- Poor visual hierarchy

**Files:**
- `Sprung/Onboarding/Views/Components/ResumeSectionsToggleCard.swift`

**Implementation Strategy:**

1. **Reduce overall height**:
   ```swift
   .frame(maxHeight: 240) // Was 280
   ```

2. **Improve background color**:
   ```swift
   .background(
       RoundedRectangle(cornerRadius: 18, style: .continuous)
           .fill(Color(nsColor: .controlBackgroundColor)) // Lighter
   )
   ```

3. **Better grid layout**:
   ```swift
   private let columns = [
       GridItem(.flexible(minimum: 140), spacing: 12),
       GridItem(.flexible(minimum: 140), spacing: 12)
   ]
   ```

4. **Ensure proper scrolling**:
   ```swift
   ScrollView(.vertical, showsIndicators: true) {
       ResumeSectionToggleGrid(draft: $draft, recommended: recommendedSections)
           .padding(.horizontal, 8)
           .padding(.vertical, 8)
   }
   .frame(maxHeight: 200)
   ```

**Acceptance Criteria:**
- [ ] Card fits within overlay without clipping
- [ ] Background is lighter and more readable
- [ ] Smooth vertical scrolling works
- [ ] Checkboxes aligned and clearly labeled

---

## P3: Minor Improvements

### Issue 7: Photo Existence Check

**Implementation:**
Add check before photo workflow to avoid redundant prompts when user already has a photo.

**Files:**
- `Sprung/Onboarding/Tools/GetUserUploadTool.swift` or prompt logic

**Strategy:**
```swift
// Before prompting for photo:
if let existingPhoto = applicantProfileStore.currentProfile().pictureData {
    // Send developer message
    coordinator.addDeveloperStatus("Applicant already has a profile photo on file. Ask if they want to replace it or keep the current one.")
}
```

---

### Issue 8: Upload Form Title

**Implementation:**
Customize upload card titles based on target_key or upload_type.

**Files:**
- `Sprung/Onboarding/Views/Components/UploadRequestCard.swift`

**Strategy:**
```swift
private var cardTitle: String {
    if request.metadata.targetKey == "basics.image" {
        return "Upload Photo"
    }
    switch request.kind {
    case .resume: return "Upload Resume"
    case .portfolio: return "Upload Portfolio"
    case .generic: return "Upload File"
    default: return "Upload"
    }
}
```

---

## Implementation Priorities & Sequencing

### Phase 1: Critical Fixes (Days 1-2)
1. Fix resume upload form regression (Issue 1)
2. Fix experience cards regression (Issue 2)

### Phase 2: High Priority (Days 3-4)
3. Fix resume dialog after reset (Issue 3)
4. Add thinking spinner display (Issue 4)

### Phase 3: Polish (Day 5)
5. Fix auto-scroll behavior (Issue 5)
6. Improve sections view styling (Issue 6)

### Phase 4: Nice-to-Have (Day 6)
7. Add photo existence check (Issue 7)
8. Improve upload form titles (Issue 8)

---

## Testing & Validation

### Integration Test Scenarios

**Scenario A: Full Workflow Happy Path**
1. Start interview from clean state
2. Complete profile with resume upload
3. Verify timeline cards appear and are editable
4. Select resume sections
5. Complete workflow

**Scenario B: Resume After Reset**
1. Complete partial interview
2. Perform full data reset
3. Start new interview
4. Verify no resume dialog appears

**Scenario C: Reasoning Display**
1. Start interview
2. Upload complex resume
3. Verify reasoning modal appears
4. Verify reasoning text streams
5. Verify modal dismisses correctly

---

## Risk Mitigation

### Rollback Plan
- All changes feature-flagged where possible
- Each fix in separate commit for easy revert
- Console logging added for debugging
- Checkpoint before starting: `onboarding-ux-issues-baseline`

### Testing Requirements
- Manual test of all 8 issues before merge
- Console log review for warnings
- Memory leak check with Instruments
- Performance profiling for scroll changes

---

## Success Metrics

- [ ] All P0 issues resolved
- [ ] No regressions in existing functionality
- [ ] Console logs show clean execution
- [ ] User can complete full workflow without errors
- [ ] Reasoning summaries display correctly
- [ ] All automated tests pass

---

## Notes

- Console log analysis confirms API is providing reasoning summaries
- Both critical regressions appear to be logic/coordination issues, not UI bugs
- Most issues have clear root causes and straightforward fixes
- Estimated total effort: 6 developer-days
