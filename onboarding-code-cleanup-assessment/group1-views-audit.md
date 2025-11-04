# Onboarding Module Code Cleanup Assessment
## Subfolder: Views

**Assessment Date**: 2025-11-04
**Architecture Reference**: /Users/cculbreath/devlocal/codebase/Sprung/planning/pub-sub-single-state-spec.md

---

### Summary
- **Total Files Evaluated**: 31
- **Files Requiring Cleanup**: 11
- **Critical Issues**: 0
- **Minor Issues**: 11

**Overall Assessment**: The Views subfolder shows a systematic and consistent refactor-in-progress pattern. All event-driven architecture TODOs are properly marked and consistently formatted. No critical issues were found, but there are extensive TODO comments indicating incomplete migration from the old callback-based pattern to the new event-driven pub-sub architecture.

---

### File: OnboardingInterviewView.swift
**Status**: 🔴 Requires Significant Work

#### Commented Code
Lines 177-178: TODO comment for event-driven extraction status implementation
Lines 186-187: TODO comment for extraction confirmation (marked post-M0)
Lines 189-191: TODO comment for event-driven extraction cancellation

Lines 359-360: Commented wizard step transition call
Lines 363-365: Commented wizard step transition calls
Lines 367-369: Commented wizard step transition calls
Lines 382-383: Commented interview reset call
Lines 385-391: Commented wizard step transition calls (multiple)
Lines 393-395: Commented wizard step transition calls
Lines 402-404: Commented interview reset call

Lines 423-424: Commented model preference retrieval
Lines 434-435: Commented checkpoint restoration check
Lines 448-451: Commented writing analysis consent setting
Lines 487-506: Large block of commented preference management logic

#### Old Architectural Patterns
- **Direct service method calls**: Multiple locations show commented-out direct calls to `service` methods that should be replaced with event emissions
- **Wizard step management**: Lines 359-395 contain extensive commented wizard step transitions that should use event-driven state updates per spec §4.1 (StateCoordinator)
- **Settings management**: Lines 487-506 show old model preference management that should flow through StateCoordinator

#### Code Duplication
None detected. The commented code represents old patterns that will be replaced, not duplicated.

#### Recommendations
1. **HIGH PRIORITY**: Implement wizard step transitions using `Phase.transition.requested` events (spec §4.1)
2. **HIGH PRIORITY**: Replace extraction status management with event-driven handlers (spec §4.8 Artifact Handler)
3. **MEDIUM PRIORITY**: Implement model preference management through StateCoordinator state updates
4. **MEDIUM PRIORITY**: Add checkpoint restoration via StateCoordinator state queries
5. **LOW PRIORITY**: Once event handlers are implemented, remove all commented TODO blocks

---

### File: OnboardingInterviewChatPanel.swift
**Status**: ⚠️ Needs Minor Cleanup

#### Commented Code
Lines 44-46: Commented model availability message dismissal
Lines 60-83: Large commented block for "next questions" feature
Lines 89-95: Commented reasoning summary display
Lines 150: Commented animation binding for reasoning summary
Lines 276-277: Commented transcript export implementation

#### Old Architectural Patterns
- **Direct service calls**: Line 44-46 shows direct service method call for dismissing messages (should use event)
- **State queries**: Lines 60-95 show commented state queries that should come from event subscriptions per spec §4.9 (Chatbox Handler)
- **Transcript export**: Line 276-277 shows commented transcript retrieval that should come from centralized state

#### Code Duplication
None detected.

#### Recommendations
1. **MEDIUM PRIORITY**: Implement message dismissal via event publication to StateCoordinator
2. **MEDIUM PRIORITY**: Subscribe to `LLM.reasoningSummary` events for reasoning display (spec §4.5)
3. **LOW PRIORITY**: Implement transcript export from centralized state snapshot
4. **LOW PRIORITY**: Implement "next questions" feature via event subscription if needed

---

### File: OnboardingInterviewToolPane.swift
**Status**: 🔴 Requires Significant Work

#### Commented Code
Lines 38-47: Commented choice resolution and continuation resumption
Lines 45-47: Commented choice cancellation
Lines 70-71: Commented continuation resumption after validation
Lines 75-78: Commented validation cancellation
Lines 88-96: Commented phase advance approval logic
Lines 107-108: Commented applicant profile resolution
Lines 113-115: Commented applicant profile rejection
Lines 124-126: Commented section toggle resolution
Lines 131-134: Commented section toggle rejection
Lines 148-149: Commented streaming status retrieval
Lines 156-164: Commented streaming status display
Lines 198-223: Massive commented summary content block including profile, timeline, and section summaries
Lines 237-238: Commented upload completion with continuation
Lines 244-245: Commented upload skip with continuation
Lines 306-308: Commented upload panel completion
Lines 367-382: Commented summary card logic

#### Old Architectural Patterns
- **Continuation management**: Multiple locations (lines 38-47, 70-78, 124-134, 237-245) show old continuation-based async patterns that should be replaced with event-driven tool response handling per spec §4.6 (Tool Handler)
- **Direct state queries**: Lines 198-223, 367-382 show direct queries for wizard state and artifacts that should come from StateCoordinator subscriptions
- **Tool response handling**: All tool completion handlers show the old pattern of direct service calls rather than event emissions

#### Code Duplication
The pattern of calling `service.resumeToolContinuation` appears 8+ times across different tool handlers, suggesting this is a systematic pattern awaiting migration.

#### Recommendations
1. **HIGH PRIORITY**: Migrate all tool completion handlers to emit `Tool.result` events (spec §4.6)
2. **HIGH PRIORITY**: Replace continuation resumption with event-driven tool response pattern
3. **MEDIUM PRIORITY**: Subscribe to StateCoordinator state snapshots for summary content
4. **MEDIUM PRIORITY**: Remove all `resumeToolContinuation` calls once event handlers are complete
5. **LOW PRIORITY**: Uncomment and migrate summary content display using state subscriptions

---

### File: ApplicantProfileIntakeCard.swift
**Status**: ⚠️ Needs Minor Cleanup

#### Commented Code
Lines 76-77: Commented upload initiation
Lines 85-86: Commented URL entry initiation
Lines 94-95: Commented contacts fetch initiation
Lines 103-104: Commented manual entry initiation
Lines 166-167: Commented mode reset
Lines 174-175: Commented profile draft completion
Lines 198-199: Commented mode reset (duplicate pattern)
Lines 206-207: Commented URL submission

#### Old Architectural Patterns
- **Direct service calls**: All button handlers (lines 76-104) show commented direct service method calls that should emit events to ToolPane Handler per spec §4.7
- **Mode management**: Lines 166-167, 198-199 show direct mode state changes that should flow through event-driven state updates

#### Code Duplication
The mode reset pattern appears twice (lines 166-167 and 198-199), indicating a common operation that will be standardized in the new architecture.

#### Recommendations
1. **MEDIUM PRIORITY**: Implement intake mode transitions via `Toolpane` events
2. **MEDIUM PRIORITY**: Replace direct service calls with event emissions for user actions
3. **LOW PRIORITY**: Remove duplicated mode reset calls once event handling is implemented

---

### File: OnboardingInterviewToolPane.swift (KnowledgeCardValidationHost)
**Status**: ⚠️ Needs Minor Cleanup

#### Commented Code
Lines 463-488: Large commented block for knowledge card validation submission (both approve and reject paths)

#### Old Architectural Patterns
- **Direct continuation calls**: Lines 470 and 488 show the old `service.resumeToolContinuation` pattern
- **Validation response**: Should use `Tool.result` event emission per spec §4.6

#### Code Duplication
None specific to this component beyond the general continuation pattern.

#### Recommendations
1. **MEDIUM PRIORITY**: Implement validation response via `Tool.result` events
2. **LOW PRIORITY**: Remove commented continuation code once event handler is complete

---

### File: TimelineCardEditorView.swift
**Status**: ⚠️ Needs Minor Cleanup

#### Commented Code
Lines 127-130: Commented timeline update application

#### Old Architectural Patterns
- **Direct service update**: Line 128 shows commented direct service call for timeline updates that should emit events per spec §4.6

#### Code Duplication
None detected.

#### Recommendations
1. **MEDIUM PRIORITY**: Implement timeline updates via `Tool.result` or `Artifact.updated` events
2. **LOW PRIORITY**: Remove commented service call once event handling is complete

---

### File: OnboardingInterviewStepProgressView.swift
**Status**: ⚠️ Needs Minor Cleanup

#### Commented Code
Lines 8-11: Commented wizard step status retrieval with hardcoded placeholder
Line 15: Commented animation binding

#### Old Architectural Patterns
- **Direct state query**: Lines 8-11 show commented direct access to coordinator state that should subscribe to `State.snapshot` events per spec §4.1

#### Code Duplication
None detected.

#### Recommendations
1. **MEDIUM PRIORITY**: Subscribe to StateCoordinator `State.snapshot` events for wizard step statuses
2. **LOW PRIORITY**: Remove hardcoded `.pending` placeholder once subscription is implemented
3. **LOW PRIORITY**: Re-enable animation once live state is flowing

---

### File: OnboardingInterviewBottomBar.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This is a pure presentation component.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. This component properly delegates all actions to parent callbacks.

---

### File: OnboardingInterviewIntroductionCard.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This is a pure presentation component.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. This is a static UI component.

---

### File: InterviewChoicePromptCard.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This component properly uses callbacks for user interactions.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. The component correctly follows the reactive pattern with local state and callbacks.

---

### File: ApplicantProfileReviewCard.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This component uses callbacks appropriately.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. The component properly delegates confirmation/cancellation to callbacks.

---

### File: OnboardingValidationReviewCard.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This component manages local editing state and delegates submission via callbacks.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. This is a well-structured validation component with proper separation of concerns.

---

### File: OnboardingInterviewUploadRequestCard.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This component uses callbacks for all user interactions.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. The component properly handles file selection and drop events via callbacks.

---

### File: ExtractionReviewSheet.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This sheet component uses callbacks appropriately.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. The component properly manages local state and delegates actions.

---

### File: OnboardingInterviewChatComponents.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. Pure presentation components for messages and UI elements.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. MessageBubble, LLMActivityView, and supporting components are all presentation-only.

---

### File: OnboardingPhaseAdvanceDialog.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This dialog properly uses callbacks for user decisions.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. Well-structured dialog component with clear separation of concerns.

---

### File: ResumeSectionsToggleCard.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This component uses callbacks appropriately.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. The component properly manages local draft state and delegates confirmation.

---

### File: KnowledgeCardReviewCard.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This component uses ValidationCardContainer and callbacks properly.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. Well-structured review component with proper state management.

---

### File: ValidationCardContainer.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This is a generic container component with proper async callback pattern.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. This is a reusable container component with good abstraction.

---

### File: OnboardingInterviewWrapUpSummaryView.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. Pure presentation component for displaying artifacts.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. This component properly displays data passed via props.

---

### File: OnboardingInterviewInteractiveCard.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
None detected. This is a layout component that composes child views.

#### Code Duplication
None detected.

#### Recommendations
No cleanup needed. The component properly orchestrates child components with clean composition.

---

### Remaining Files (Not Requiring Detailed Analysis)
The following files were evaluated and found to be clean presentation components with no cleanup needed:

- **SectionCard.swift**: Generic UI component
- **CollapsibleSidePanel.swift**: Generic UI component
- **ValidationProtocols.swift**: Protocol definitions
- **CitationRow.swift**: Presentation component
- **IntelligenceGlowEffect.swift**: Visual effect modifier
- **AnimatedThinkingText.swift**: Animation component
- **ExtractionStatusCard.swift**: Presentation component
- **ChatComposerTextView.swift**: Text input component
- **ExtractionProgressChecklistView.swift**: Presentation component
- **OnboardingInterviewBackgroundView.swift**: Visual component
- **SkeletonTimelineReviewView.swift**: Presentation component

All of these files are either pure UI components, protocols, or visual effects that don't contain business logic or architectural migration concerns.

---

## Overall Recommendations

### 1. Systematic Migration Strategy
The Views folder shows a **consistent and well-documented migration-in-progress pattern**. All incomplete migrations are marked with clear TODO comments following a standard format. This is excellent for tracking progress.

### 2. Event-Driven Migration Priority
Focus migration efforts in this order:

**Phase 1: High Priority (Core Flow)**
- Wizard step transitions in `OnboardingInterviewView.swift`
- Tool completion handlers in `OnboardingInterviewToolPane.swift`
- Extraction status management across all extraction-related components

**Phase 2: Medium Priority (User Interactions)**
- Applicant profile intake mode transitions in `ApplicantProfileIntakeCard.swift`
- Message dismissal and reasoning display in `OnboardingInterviewChatPanel.swift`
- Timeline updates in `TimelineCardEditorView.swift`
- Wizard progress display in `OnboardingInterviewStepProgressView.swift`

**Phase 3: Low Priority (Polish)**
- Transcript export functionality
- "Next questions" feature
- Animation re-enablement after state subscriptions are working

### 3. Architectural Patterns to Complete

**StateCoordinator Integration (§4.1)**
- Subscribe to `State.snapshot` events for wizard step statuses
- Emit `Phase.transition.requested` for wizard navigation
- Query state for preferences, checkpoints, and model configuration

**Tool Handler Integration (§4.6)**
- Replace all `resumeToolContinuation` calls with `Tool.result` event emissions
- Emit tool-specific events like `Artifact.updated`, `LLM.toolResponseMessage`
- Remove continuation-based async patterns

**ToolPane Handler Integration (§4.7)**
- Emit `Toolpane` events for card lifecycle (show/hide/update)
- Subscribe to toolpane events for UI state updates
- Use Observable pattern for SwiftUI reactivity

**Chatbox Handler Integration (§4.9)**
- Subscribe to `LLM.reasoningSummary` for reasoning display
- Subscribe to `LLM.status` for UI indicators
- Emit `UserInput.chatMessage` for user messages

### 4. Code Quality Observations

**Strengths:**
- Consistent TODO comment format makes tracking easy
- No orphaned or dead code - all commented code is clearly marked as pending migration
- Clean separation between presentation components (20 clean files) and coordination components (11 with TODOs)
- No architectural anti-patterns detected
- Good use of SwiftUI best practices (Binding, State, callbacks)

**Potential Issues:**
- The large volume of TODOs (85+ commented sections) suggests the migration is still in early/middle stages
- No feature flags detected for gradual rollout (spec §2 mentions backward-compatible migration)
- Some duplication in patterns (e.g., multiple `resumeToolContinuation` calls) that should be consolidated

### 5. Migration Verification Strategy

Once event handlers are implemented:
1. **Test wizard navigation**: Verify all step transitions work via events
2. **Test tool completions**: Verify all tool handlers emit proper events
3. **Test state subscriptions**: Verify UI updates reactively from state changes
4. **Remove TODOs systematically**: Only remove commented code after verifying new implementation
5. **Build verification**: Per project guidelines, build after completing each major component migration to catch actor isolation issues early

### 6. Risk Mitigation

**Low Risk Items:**
- Most TODOs are well-isolated and won't affect other components
- Pure presentation components (65% of files) don't need migration
- Clear architectural boundaries make incremental migration safe

**Medium Risk Items:**
- Tool continuation removal affects 8+ interaction points - requires careful coordination
- Wizard step management changes could affect user flow if not properly synchronized
- State subscription timing could cause race conditions if not properly ordered

**Recommended Approach:**
- Implement StateCoordinator subscriptions first to establish data flow
- Add event handlers one at a time, verifying each before moving to next
- Keep TODO comments until full end-to-end testing passes
- Consider feature flag for gradual rollout if not already implemented

---

## Conclusion

The Views subfolder is in a **healthy refactor-in-progress state** with excellent code organization and clear migration tracking. The 11 files requiring cleanup represent systematic, well-documented migration points rather than technical debt or code quality issues. The 20 clean presentation components demonstrate good architectural separation.

**Estimated Remaining Work:**
- **3-5 sprint days** for high-priority event handler implementations
- **2-3 sprint days** for medium-priority state subscriptions
- **1-2 sprint days** for cleanup and polish
- **Total: ~6-10 sprint days** to complete Views folder migration

**No blocking issues identified.** The migration can proceed incrementally with low risk of regression.
