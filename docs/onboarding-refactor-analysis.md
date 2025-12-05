# Onboarding Module Refactoring Analysis

**Base Commit**: `3c4d0b61d41e7243eeb5c571fc55e9da22865f24`
**Analysis Date**: November 27, 2025
**Status**: Issues identified - potential rollback candidate

---

## Executive Summary

The refactoring since commit `3c4d0b61` introduced significant architectural changes to the onboarding module. While the stated goals (decomposition, SRP, cleaner event flow) are sound, **the implementation has critical bugs** and introduces unnecessary complexity in some areas.

**Critical Bug Found**: Event subscription ordering in `InterviewLifecycleController.startInterview()` causes the initial LLM call to never execute. The `StateCoordinator` subscribes to events *after* the orchestrator sends the initial message, causing the message queue to never be processed.

---

## Change Statistics

- **Files Changed**: 129 files
- **Lines Added**: ~1,805
- **Lines Removed**: ~5,769
- **Net Change**: -3,964 lines (significant reduction)
- **New Files**: 13
- **Deleted Files**: 2

---

## Architectural Goals & Implementation

### 1. Coordinator Decomposition

**Goal**: Break up the monolithic `OnboardingInterviewCoordinator` (~1,500 lines) into smaller, focused components.

**Implementation**:
- Created `CoordinatorEventRouter` - routes events to appropriate handlers
- Created `UIResponseCoordinator` - handles user action → LLM message logic
- Created `ToolInteractionCoordinator` - manages tool UI presentation/resolution
- Created `OnboardingToolRegistrar` - centralizes tool registration
- Created `OnboardingUIState` - observable state container for SwiftUI

**Assessment**: ✅ Good decomposition in principle, but:
- Creates many small files that now need careful coordination
- Event subscription timing is critical and was broken in the refactor
- Some components have weak references (`weak var coordinator`) creating potential for bugs

### 2. UI State Extraction

**Goal**: Separate observable UI state from business logic.

**Implementation**:
- New `OnboardingUIState` class marked with `@Observable`
- Holds: `isProcessing`, `messages`, `skeletonTimeline`, `wizardStep`, etc.
- Accessed via `coordinator.ui.*` throughout views

**Assessment**: ✅ Clean separation, but:
- Removed `nonisolated(unsafe)` sync caches from `StateCoordinator` (lines deleted suggest removal)
- Views now access `coordinator.ui.isActive` instead of `coordinator.isActiveSync`
- Need to verify all UI bindings work correctly after this change

### 3. Phase 2 "Evidence Flow" Enhancement

**Goal**: Change Phase 2 from synchronous interviews to asynchronous evidence collection.

**Implementation**:
- New `EvidenceRequirement` model with statuses: requested, fulfilled, skipped
- New `request_evidence` tool for LLM to request specific documents
- New `IngestionCoordinator` service to process evidence uploads in background
- New `DraftKnowledgeStore` for managing draft knowledge cards
- New `EvidenceRequestView` and `DraftKnowledgeListView` UI components
- Changed Phase 2 objectives from interview-based to evidence-based:
  - OLD: `interviewed_one_experience`, `one_card_generated`
  - NEW: `evidence_audit_completed`, `cards_generated`
- Changed LLM role from "Interviewer" to "Lead Investigator"

**Assessment**: ⚠️ Significant workflow change:
- Completely rewrites the Phase 2 interaction model
- User uploads evidence → system generates cards automatically
- Less conversational, more document-processing focused
- May or may not match the product vision

### 4. Event System Cleanup

**Goal**: Streamline event handling and reduce callback complexity.

**Implementation**:
- Added new events: `draftKnowledgeCardProduced`, `draftKnowledgeCardUpdated`, `draftKnowledgeCardRemoved`
- Added evidence events: `evidenceRequirementAdded`, `evidenceRequirementUpdated`, `evidenceRequirementRemoved`
- Removed many blank lines and comments (cosmetic cleanup)

**Assessment**: ✅ Reasonable additions for new features

### 5. Model ID Updates

**Goal**: Update default model references.

**Implementation**:
- Changed `gpt-5` → `gpt-5.1` throughout
- Changed `openai/gpt-5` → `openai/gpt-5.1`

**Assessment**: ✅ Minor version update

---

## Critical Issues

### Issue 1: Event Subscription Race Condition (BLOCKING)

**Location**: `InterviewLifecycleController.swift:49-78`

**Problem**: When `startInterview()` is called:
1. `orchestrator.startInterview()` sends initial message (emits `.llmSendUserMessage`)
2. `LLMMessenger` receives event, emits `.llmEnqueueUserMessage`
3. **BUT** `StateCoordinator.startEventSubscriptions()` hasn't been called yet
4. No one processes the queue → no `.llmExecuteUserMessage` emitted
5. LLM call never happens, app hangs with spinner

**Fix Applied**: Moved event subscriptions BEFORE `orchestrator.startInterview()`

```swift
// BEFORE (broken):
try await orchestrator.startInterview(isResuming: isResuming)
await state.startEventSubscriptions()

// AFTER (fixed):
await state.startEventSubscriptions()
try await orchestrator.startInterview(isResuming: isResuming)
```

### Issue 2: OpenAI Service Mutability

**Location**: `OnboardingInterviewCoordinator.swift:19`

**Change**: `private let openAIService: OpenAIService?` is now immutable (`let` not `var`)

**Problem**: The old code had `updateOpenAIService()` which could update the service at runtime. The new code still has the method but it creates a new `KnowledgeCardAgent` without updating the coordinator's internal reference properly. This may cause issues if the API key changes during a session.

### Issue 3: Potential Memory Issues

**Locations**: Various coordinators use `weak var coordinator` pattern

**Concern**: Multiple coordinators hold weak references to the parent. If any are retained beyond the parent's lifecycle, callbacks will silently fail (nil guard returns).

### Issue 4: Event Handler Redundancy

**Location**: `CoordinatorEventRouter.swift:73-121`

**Problem**: The switch statement handles many events but then immediately `break`s. This creates maintenance burden and potential for bugs if a case is accidentally commented out.

---

## New Components Summary

| Component | Purpose | Lines |
|-----------|---------|-------|
| `OnboardingUIState` | Observable UI state container | 67 |
| `UIResponseCoordinator` | User action → LLM message handling | 265 |
| `CoordinatorEventRouter` | Event subscription and routing | 128 |
| `ToolInteractionCoordinator` | Tool UI presentation/resolution | 132 |
| `OnboardingToolRegistrar` | Centralized tool registration | 74 |
| `ProfilePersistenceHandler` | Profile save/load handling | 71 |
| `IngestionCoordinator` | Background evidence processing | 131 |
| `DraftKnowledgeStore` | Draft card management | 70 |
| `EvidenceRequirement` | Evidence request model | 41 |
| `RequestEvidenceTool` | LLM tool for requesting evidence | 69 |
| `DraftKnowledgeListView` | UI for draft cards | 86 |
| `EvidenceRequestView` | UI for evidence requests | 118 |

---

## Recommendations for Rewrite

If rolling back and reimplementing, prioritize these goals:

### Must Have

1. **Fix event subscription ordering** - Ensure all event handlers are subscribed before any events are emitted
2. **Preserve sync cache pattern** - The `nonisolated(unsafe)` caches were useful for SwiftUI; if removing, ensure replacement works
3. **Test interview startup flow** - The "Start Interview" → LLM greeting → first tool call flow is critical
4. **Maintain service updatability** - OpenAI service may need updating mid-session (API key changes)

### Should Have

1. **Simpler coordinator decomposition** - Consider fewer, larger components rather than many small ones
2. **Event handler consolidation** - Route events through fewer intermediaries
3. **Clearer ownership model** - Reduce `weak var` coordinator patterns

### Nice to Have

1. **Phase 2 evidence flow** - The async evidence model is interesting but may need product validation
2. **Draft knowledge cards** - Background processing is useful but adds complexity
3. **Code style cleanup** - Removing blank lines is fine but should be a separate commit

---

## Files to Review in Detail

If reimplementing, study these files carefully:

1. `InterviewLifecycleController.swift` - Orchestrates startup/shutdown
2. `LLMMessenger.swift` - Handles all LLM communication
3. `StateCoordinator.swift` - Central state management (stream queue is here)
4. `OnboardingInterviewCoordinator.swift` - Main coordinator (now much smaller)
5. `PhaseTwoScript.swift` - Defines Phase 2 behavior (heavily changed)

---

## Testing Checklist for Any Rewrite

- [ ] Click "Start Interview" → Greeting appears → First tool call executes
- [ ] User types in chatbox → Message sent to LLM → Response received
- [ ] Resume interview from checkpoint → Conversation context restored
- [ ] Phase transitions work correctly
- [ ] All tool UI cards (choice, upload, validation) display and resolve properly
- [ ] Background document extraction works
- [ ] Checkpoint save/restore includes conversation state

---

*Analysis by Claude Code - November 27, 2025*
