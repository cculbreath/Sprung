# Onboarding Module Cleanup Checklist

**Created**: 2025-11-04
**Status**: In Progress
**Estimated Total Effort**: 10-17 days
**Current Health**: 72% compliant with event-driven architecture

---

## Phase 1: Critical Legacy Code Removal (High Priority, 2-3 days)

### 1.1 Remove Deprecated Methods from InterviewOrchestrator.swift
**Status**: ⏳ Pending
**Estimated**: 2-3 hours
**Files**: `Sprung/Onboarding/Core/InterviewOrchestrator.swift`

- [ ] Delete `resumeToolContinuation` method (lines 96-100)
- [ ] Remove `nextToolChoiceOverride` property (lines 25-26)
- [ ] Delete `ToolChoiceOverride` struct (lines 119-125)
- [ ] Remove `forceTimelineTools()` method (lines 106-117)
- [ ] Remove `resetToolChoice()` method
- [ ] Remove TODOs at lines 66, 104
- [ ] Build verification
- [ ] Grep verification (no references remain)

**Impact**: High - Prevents confusion and incorrect usage patterns

---

### 1.2 Remove Legacy Support Section from OnboardingInterviewCoordinator.swift
**Status**: ⏳ Pending
**Estimated**: 2-3 hours
**Files**: `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`

- [ ] Delete "Legacy Support" section (lines 982-1021)
  - [ ] Remove `objectiveStatuses` property (lines 984-992)
  - [ ] Remove Task.value extension placeholder (lines 1016-1021)
  - [ ] Remove WizardProgressTracker bridge code (lines 1000-1013)
- [ ] Fix dependent UI code if any
- [ ] Build verification
- [ ] Runtime testing

**Impact**: High - Code marked "Phase 2 removal" but still present

---

## Phase 2: Replace Polling Anti-Patterns (High Priority, 2-3 days)

### 2.1 Convert OnboardingInterviewCoordinator State Observation to Events
**Status**: ⏳ Pending
**Estimated**: 4-6 hours
**Files**: `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`

- [ ] Remove polling while-loop (lines 356-371)
- [ ] Subscribe to `.processingStateChanged` events
- [ ] Subscribe to artifact/extraction events for pendingExtraction
- [ ] Subscribe to LLM events for streamingStatus
- [ ] Update synchronous properties from event handlers (MainActor)
- [ ] Remove `startStateObservation()` method
- [ ] Build verification
- [ ] Runtime testing (verify state updates work)

**Current Problem**: Polling every 100ms - inefficient
**Benefit**: Eliminates wasteful 10x/second polling

---

### 2.2 Convert OnboardingInterviewService Polling to Events
**Status**: ⏳ Pending
**Estimated**: 3-4 hours
**Files**: `Sprung/Onboarding/Core/OnboardingInterviewService.swift`

- [ ] Remove Timer-based polling (lines 101-109)
- [ ] Subscribe to state events from EventCoordinator
- [ ] Update @Published properties from event handlers
- [ ] Remove `subscribeToStateUpdates()` method
- [ ] Remove `syncStateFromCoordinator()` method
- [ ] Build verification
- [ ] Runtime testing

**Note**: Consider deprecation path for this bridge layer

---

## Phase 3: Complete Stub Tool Implementations (Medium Priority, 2-4 days)

### 3.1 Complete or Remove ValidateApplicantProfileTool.swift
**Status**: ⏳ Pending
**Estimated**: 4-6 hours
**Files**: `Sprung/Onboarding/Tools/Implementations/ValidateApplicantProfileTool.swift`

**Decision Required**: ⚠️ Implement or Remove?

If Implementing:
- [ ] Add profile validation logic
- [ ] Integrate with ApplicantProfileStore
- [ ] Return proper validation results
- [ ] Add tests

If Removing:
- [ ] Verify no LLM prompts reference this tool
- [ ] Remove from ToolRegistry
- [ ] Document why validation moved elsewhere
- [ ] Update spec if needed

---

### 3.2 Complete GetArtifactRecordTool.swift
**Status**: ⏳ Pending
**Estimated**: 3-4 hours
**Files**: `Sprung/Onboarding/Tools/Implementations/GetArtifactRecordTool.swift`

- [ ] Integrate with OnboardingArtifactStore
- [ ] Implement artifact retrieval by ID
- [ ] Return proper artifact metadata
- [ ] Handle not found cases
- [ ] Build verification
- [ ] Integration testing

**Pattern**: Use ArtifactHandler approach

---

### 3.3 Complete RequestRawArtifactFileTool.swift
**Status**: ⏳ Pending
**Estimated**: 3-4 hours
**Files**: `Sprung/Onboarding/Tools/Implementations/RequestRawArtifactFileTool.swift`

- [ ] Implement raw file access from artifact storage
- [ ] Add proper file URL handling
- [ ] Return file metadata
- [ ] Handle errors (file not found, permission denied)
- [ ] Build verification
- [ ] Integration testing

**Integration**: Coordinate with OnboardingArtifactStore

---

### 3.4 Complete CancelUserUploadTool.swift Event Integration
**Status**: ⏳ Pending
**Estimated**: 1-2 hours
**Files**: `Sprung/Onboarding/Tools/Implementations/CancelUserUploadTool.swift`

- [ ] Review `isAvailable()` stub at line 18
- [ ] Integrate with upload cancellation events
- [ ] Ensure proper cleanup on cancellation
- [ ] Build verification
- [ ] Test cancellation flow

**Impact**: Low - Functional but has stub methods

---

## Phase 4: Complete Core TODOs (Medium Priority, 1-2 days)

### 4.1 Complete LLMMessenger.swift TODOs
**Status**: ⏳ Pending
**Estimated**: 3-4 hours
**Files**: `Sprung/Onboarding/Core/LLMMessenger.swift`

- [ ] Line 95: Wire up `UserInput.chatMessage` subscription
- [ ] Line 141: Implement developer message sending
- [ ] Lines 179-181: Complete request building (remove placeholder)
- [ ] Line 200: Get tools from StateCoordinator (not empty array)
- [ ] Build verification
- [ ] Test message flow

**Benefit**: Completes LLM message handling

---

### 4.2 Complete or Document OnboardingInterviewCoordinator TODOs
**Status**: ⏳ Pending
**Estimated**: 2-3 hours
**Files**: `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`

- [ ] Lines 565-566, 883-884: SwiftData conversion - decide implementation or deferral
- [ ] Lines 906-923: Complete artifact loading or remove
- [ ] Line 678: Complete extraction type checking
- [ ] Create tickets for deferred work
- [ ] Document decisions in code comments

**Decision**: If deferring SwiftData, create tickets and document

---

### 4.3 Address StateCoordinator.swift TODOs
**Status**: ⏳ Pending
**Estimated**: 2-3 hours
**Files**: `Sprung/Onboarding/Core/StateCoordinator.swift`

- [ ] Line 779: Implement `applyPartialUpdate` or remove `.stateSet` event
- [ ] Line 798: Consider extracting phase configuration
- [ ] Document architectural decisions
- [ ] Build verification

**Priority**: Low - current implementation works

---

## Phase 5: Views Migration (Lower Priority, 6-10 days)

### 5.1 Migrate OnboardingInterviewView.swift
**Status**: ⏳ Deferred
**Estimated**: 3-5 days
**Files**: `Sprung/Onboarding/Views/OnboardingInterviewView.swift`

**85+ TODO comments** - Requires focused sprint

- [ ] Wizard step transitions → Phase.transition.requested events
- [ ] Extraction management → event subscriptions
- [ ] Preference handling → event-driven updates
- [ ] Remove direct coordinator access
- [ ] Build verification
- [ ] Full UI testing

---

### 5.2 Migrate OnboardingInterviewToolPane.swift
**Status**: ⏳ Deferred
**Estimated**: 3-5 days
**Files**: `Sprung/Onboarding/Views/Components/OnboardingInterviewToolPane.swift`

**Tool continuation pattern removal**

- [ ] Replace resumeToolContinuation calls with Tool.result events
- [ ] Update completion handlers to use events
- [ ] Remove legacy tool handling
- [ ] Build verification
- [ ] Integration testing

---

## Progress Tracking

### Week 1: Critical Cleanup
- **Day 1**: Phase 1.1 (InterviewOrchestrator cleanup)
- **Day 2**: Phase 1.2 (Legacy support removal)
- **Day 3-4**: Phase 2.1 (Coordinator polling → events)
- **Day 5**: Phase 2.2 (Service polling → events)

### Week 2: Completions
- **Day 6-8**: Phase 3 (Stub tools completion)
- **Day 9-10**: Phase 4 (Core TODOs)

---

## Success Criteria

- [ ] Build: No compilation errors or warnings
- [ ] Architecture Compliance: 85%+ files fully event-driven
- [ ] No Polling: All timer-based polling replaced with events
- [ ] No Deprecated Code: All "marked for removal" code deleted
- [ ] Documentation: All TODOs completed or ticketed
- [ ] Testing: All workflows function correctly

---

## Testing Strategy

After each phase:
1. Build verification: `xcodebuild -scheme Sprung build`
2. Grep verification: Check for removed patterns
3. Runtime testing: Start interview, test affected workflows
4. Event flow validation: Verify events emitted and handled

---

## Notes

- Audit conducted by onboarding-refactor-auditor agent
- Full reports in `./onboarding-code-cleanup-assessment/`
- Current module health: 72% compliant
- Models, Services, Phase, Utilities, Stores, ViewModels, Managers: 100% compliant (reference implementations)
