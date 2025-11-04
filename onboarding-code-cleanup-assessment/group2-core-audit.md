# Onboarding Module Code Cleanup Assessment
## Subfolder: Core

**Assessment Date**: November 4, 2025
**Architecture Reference**: ./planning/pub-sub-single-state-spec.md

---

### Summary
- **Total Files Evaluated**: 11
- **Files Requiring Cleanup**: 5
- **Critical Issues**: 2
- **Minor Issues**: 3

---

### File: ModelProvider.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. This file provides model configuration and is architecture-agnostic.

#### Code Duplication
No duplication detected.

#### Recommendations
No cleanup needed. This file is clean and properly scoped.

---

### File: DeveloperMessageTemplates.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. This file provides message templates and is architecture-agnostic.

#### Code Duplication
No duplication detected.

#### Recommendations
No cleanup needed. Well-structured helper module for developer message generation.

---

### File: Checkpoints.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. This file properly integrates with StateCoordinator (line 15) and uses the new StateSnapshot type.

#### Code Duplication
No duplication detected.

#### Recommendations
No cleanup needed. Properly migrated to work with the centralized StateCoordinator.

---

### File: NetworkRouter.swift
**Status**: ✅ Clean

#### Commented Code
None found - only a proper TODO comment at lines 154-162 for future reasoning support implementation.

#### Old Architectural Patterns
Fully migrated to new architecture. Properly implements Spec §4.4:
- Emits events via OnboardingEventEmitter protocol (line 19)
- Uses EventCoordinator for pub/sub (line 22)
- Emits proper event types: streamingMessageBegan, streamingMessageUpdated, streamingMessageFinalized, toolCallRequested (lines 98, 115, 122, 149)

#### Code Duplication
No duplication detected.

#### Recommendations
No cleanup needed. This is a well-implemented component following the spec. The TODO comment at line 154 is intentional and documents future work.

---

### File: LLMMessenger.swift
**Status**: ⚠️ Needs Minor Cleanup

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Properly implements Spec §4.3:
- Uses event-driven subscriptions (lines 54-74)
- Emits appropriate events (lines 108, 117, 134, etc.)
- No callback dependencies

#### Code Duplication
No duplication detected.

#### Recommendations
1. **TODO Comments** (lines 95, 141, 179-181, 200): These indicate incomplete implementation:
   - Line 95: UserInput.chatMessage wiring needs completion
   - Line 141: Developer message sending not implemented
   - Lines 179-181: Request building is marked as placeholder
   - Line 200: Tools need to come from StateCoordinator

   **Priority**: Medium - Core functionality works but these gaps should be addressed before Phase 5.

2. **Build Verification**: After implementing the TODOs, run a targeted build to ensure proper integration with StateCoordinator for tool retrieval.

---

### File: InterviewOrchestrator.swift
**Status**: 🔴 Requires Significant Work

#### Commented Code
None found.

#### Old Architectural Patterns
**Critical Issues**:
1. **Deprecated Method Not Removed** (lines 96-100): `resumeToolContinuation` method is marked as deprecated with a warning but still exists. This creates confusion and should be removed entirely since tool continuations are handled by ToolExecutionCoordinator.

2. **Orphaned Tool Choice Logic** (lines 106-117): The `forceTimelineTools()` and `resetToolChoice()` methods manipulate `nextToolChoiceOverride` (line 26), but this pattern doesn't align with the event-driven architecture. According to the spec, tool choice should be managed by StateCoordinator/LLMMessenger.

3. **TODO Comments Indicating Incomplete Migration** (line 104): "Move tool choice override and available tools logic to StateCoordinator/LLMMessenger"

#### Code Duplication
No duplication detected.

#### Recommendations
1. **Remove Deprecated Code** (lines 96-100): Delete the `resumeToolContinuation` method entirely. Tool continuations are fully handled by ToolExecutionCoordinator.

2. **Remove Old Tool Choice Pattern** (lines 25-26, 106-125):
   - Delete `nextToolChoiceOverride` property
   - Delete `ToolChoiceOverride` struct (lines 119-125)
   - Delete `forceTimelineTools()` and `resetToolChoice()` methods
   - If timeline tool forcing is still needed, implement it through StateCoordinator's allowed tools system

3. **Remove TODOs**: Lines 66, 104 contain TODOs that should either be completed or removed if functionality is now elsewhere.

4. **Priority**: High - These are remnants of the old callback-based architecture that create confusion and should be removed to complete the migration.

---

### File: ToolHandler.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture:
- Properly implements event-driven UI presentation (lines 80-121)
- Subscribes to toolpane events (line 87)
- Observable pattern for SwiftUI integration (line 50)
- Delegates to specialized handlers

#### Code Duplication
No duplication detected.

#### Recommendations
No cleanup needed. This is a well-designed adapter between the event-driven architecture and SwiftUI's Observable system, exactly as described in Spec §4.7.

---

### File: OnboardingInterviewService.swift
**Status**: ⚠️ Needs Minor Cleanup

#### Commented Code
None found.

#### Old Architectural Patterns
This is a bridge/facade layer, which is acceptable during migration, but there are concerns:

1. **Polling-based State Sync** (lines 101-109): Uses a timer-based polling mechanism to sync state from coordinator. The comment acknowledges this is "temporary" but it's an anti-pattern in an event-driven architecture.

2. **Empty Stub Properties** (lines 61-68): Multiple properties return empty/nil values, suggesting incomplete implementation.

#### Code Duplication
No duplication detected within this file, but this entire file appears to duplicate responsibilities that should belong to the coordinator or be event-driven.

#### Recommendations
1. **Replace Polling with Events** (lines 101-118): Instead of polling coordinator state every 100ms, subscribe to relevant events from EventCoordinator. This would be more efficient and align with the architecture.

2. **Complete or Remove Stubs** (lines 61-68): Either implement these properties properly or document why they're intentionally unimplemented during the migration.

3. **Consider Deprecation Path**: This bridge layer should have a clear deprecation plan. Add documentation about when/how this will be replaced by direct event-driven UI bindings.

4. **Priority**: Medium - The polling is wasteful but functional. Should be addressed in Phase 5 when refactoring UI bindings.

---

### File: OnboardingEvents.swift
**Status**: ✅ Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. This is a core piece of the new event-driven system:
- Comprehensive event enum (lines 13-91)
- AsyncStream-based EventCoordinator (lines 114-389)
- Proper topic routing (lines 100-111, 213-259)
- OnboardingEventEmitter protocol (lines 392-401)

#### Code Duplication
No duplication detected.

#### Recommendations
No cleanup needed. This is the backbone of the new architecture and is well-implemented according to Spec §4.2 and §6.

---

### File: StateCoordinator.swift
**Status**: ⚠️ Needs Minor Cleanup

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. This is the "single source of truth" implementation as described in Spec §4.1. Excellent architecture implementation.

#### Code Duplication
No duplication detected.

#### Recommendations
1. **TODO Comment** (line 779): "TODO: Implement partial state updates based on JSON" in `applyPartialUpdate`. This should either be implemented or the event type should be removed if not needed.

2. **TODO Comment** (line 798): "Get from phase configuration" in `getAllowedToolsForCurrentPhase`. The current switch-based implementation works but could be more data-driven.

3. **Consider Extracting Phase Configuration**: Lines 131-156 and 797-810 define phase-specific logic. Consider moving this to a PhaseConfiguration type for better separation of concerns.

4. **Priority**: Low - These are minor improvements. The core architecture is solid.

---

### File: OnboardingInterviewCoordinator.swift
**Status**: 🔴 Requires Significant Work

#### Commented Code
None found, but extensive inline TODOs.

#### Old Architectural Patterns
This file shows signs of being in mid-migration:

1. **Legacy Support Code** (lines 982-1021): Large section marked "Legacy Support (will be removed in Phase 2)" containing:
   - `objectiveStatuses` property (lines 984-992)
   - Extension with placeholder Task.value implementation (lines 1016-1021)
   - WizardProgressTracker bridge code (lines 1000-1013)

2. **Incomplete TODOs** scattered throughout:
   - Line 565-566: "Convert JSON to ApplicantProfile model for SwiftData storage"
   - Line 678: Extraction type checking commented out with TODO
   - Line 883-884: Same SwiftData conversion TODO
   - Line 906-923: Incomplete artifact loading implementation
   - Line 1005-1011: Wizard tracker integration notes about private properties

3. **Synchronous Property Workarounds** (lines 109-120): Properties like `_isProcessingSync` exist to bridge async actor state to synchronous SwiftUI. This is a code smell indicating incomplete UI refactoring.

4. **Polling-based State Observation** (lines 356-371): Similar to OnboardingInterviewService, uses a while-loop with sleep to poll state changes instead of event-driven updates.

#### Code Duplication
Minor duplication in state synchronization logic between this file and OnboardingInterviewService.

#### Recommendations
1. **Remove Legacy Support Section** (lines 982-1021):
   - Priority: High
   - These should have been removed in "Phase 2" but still exist
   - Remove the entire "Legacy Support" section
   - Fix any UI code that depends on these deprecated APIs

2. **Complete or Remove TODOs**:
   - Lines 565-566, 883-884: Either implement SwiftData conversion or document why it's deferred
   - Lines 906-923: Complete artifact loading or remove if not needed
   - Line 678: Complete extraction type checking
   - Priority: Medium

3. **Replace Polling with Events** (lines 356-371):
   - Replace while-loop polling with event subscriptions
   - Subscribe to processing state events, extraction events, and streaming status events
   - Priority: High - This is inefficient and goes against the event-driven architecture

4. **Eliminate Synchronous State Bridges** (lines 109-120):
   - Work with UI layer to properly handle async state
   - Consider using @Published properties that update from event handlers
   - Priority: Medium

5. **Document Migration Status**:
   - Add file-level comment explaining this is a bridge during migration
   - Document what still needs to be refactored
   - Priority: Low but helpful for team clarity

---

### Overall Recommendations

#### By Priority

**Critical (Address Immediately)**:
1. **InterviewOrchestrator.swift**: Remove deprecated `resumeToolContinuation` method and old tool choice override logic (lines 25-26, 96-117)
2. **OnboardingInterviewCoordinator.swift**: Remove "Legacy Support" section (lines 982-1021) that should have been deleted in Phase 2

**High Priority (Address in Next Sprint)**:
3. **OnboardingInterviewCoordinator.swift**: Replace polling-based state observation (lines 356-371) with event subscriptions
4. **OnboardingInterviewService.swift**: Replace timer-based polling (lines 101-109) with event subscriptions
5. **InterviewOrchestrator.swift**: Complete migration of tool choice logic to StateCoordinator/LLMMessenger

**Medium Priority (Address in Phase 5)**:
6. **LLMMessenger.swift**: Complete TODOs for UserInput wiring, developer messages, and StateCoordinator integration (lines 95, 141, 179-181, 200)
7. **OnboardingInterviewCoordinator.swift**: Complete or document all TODO items for SwiftData conversion and artifact loading
8. **OnboardingInterviewService.swift**: Develop deprecation plan for this bridge layer

**Low Priority (Future Improvements)**:
9. **StateCoordinator.swift**: Implement or remove partial state update functionality (line 779)
10. **StateCoordinator.swift**: Consider extracting phase configuration to separate type

#### General Patterns Observed

1. **Incomplete Migration**: Several files contain deprecated code, legacy support sections, and TODOs indicating the refactor is not complete. The most critical issues are in InterviewOrchestrator.swift and OnboardingInterviewCoordinator.swift.

2. **Polling Anti-pattern**: Both OnboardingInterviewService.swift and OnboardingInterviewCoordinator.swift use timer-based polling to sync state, which contradicts the event-driven architecture goals. These should be replaced with event subscriptions.

3. **Bridge Layers**: OnboardingInterviewService.swift appears to be a transitional facade. Consider whether this layer can be removed entirely once UI is fully refactored to work with events.

4. **Excellent New Components**: NetworkRouter.swift, OnboardingEvents.swift, StateCoordinator.swift, and ToolHandler.swift are well-implemented and follow the spec correctly. These demonstrate the target architecture pattern.

5. **TODO Discipline**: The codebase has numerous TODO comments. Establish a policy: either complete them in the current phase, create tickets for future work, or remove them if no longer applicable.

#### Suggestions for Preventing Similar Issues

1. **Define "Done" for Refactor Phases**: Establish clear exit criteria for each phase, including "no deprecated code remains" and "all TODOs addressed or ticketed."

2. **Code Review Checklist**: Create a checklist for reviewing migrated code:
   - No callback patterns remain
   - Event emission follows spec topics
   - No polling/timer-based state sync
   - Legacy code removed (not just marked for removal)

3. **Architectural Decision Records**: Document why bridge layers like OnboardingInterviewService exist and when they'll be removed.

4. **Build Verification Strategy**: Group related cleanup tasks and verify after each logical group:
   - Group 1: Remove deprecated methods from InterviewOrchestrator
   - Group 2: Replace polling with events in both coordinator files
   - Group 3: Complete LLMMessenger TODOs
