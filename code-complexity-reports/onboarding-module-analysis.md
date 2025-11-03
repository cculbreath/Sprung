# Architecture Analysis: Onboarding Module

**Analysis Date**: November 3, 2025
**Subdirectory**: `/Users/cculbreath/devlocal/codebase/Sprung/Sprung/Onboarding`
**Total Swift Files Analyzed**: 88
**Total Lines of Code**: 16,028

---

## Executive Summary

The Onboarding module is a sophisticated but **severely over-engineered** system that suffers from fundamental architectural problems. While the surface-level implementation appears comprehensive, it exhibits multiple critical coupling issues that make it brittle, difficult to test, and prone to emergent bugs.

**Key Findings:**
1. **InterviewOrchestrator and OnboardingInterviewCoordinator are tightly coupled** through a complex callback system that creates bidirectional dependencies
2. **State is scattered across 5+ locations** with no single source of truth (InterviewSession, InterviewState, ChatTranscriptStore, OnboardingInterviewCoordinator, OnboardingToolRouter)
3. **The tool routing system adds an unnecessary abstraction layer** that complicates error handling and continuation management
4. **LLM integration leaks implementation details** throughout the coordinator rather than being encapsulated in the orchestrator
5. **Objective tracking is both over-complicated and fragile**, with circular callbacks and redundant state synchronization

**Complexity Rating**: **EXCESSIVE**

The module demonstrates architectural anti-patterns: god objects (OnboardingInterviewCoordinator at 1500+ lines), deep callback chains, and premature abstraction that doesn't actually provide value. The system works, but at high cognitive cost.

**Recommendation**: **Major refactor keeping some components** (Section B below). A complete rewrite is justified but carries higher risk. A targeted refactor is achievable in 2-3 sprints.

---

## Overall Architecture Assessment

### Architectural Style

The Onboarding module uses an **LLM-orchestrated imperative pattern** with tool-based interactions. The architecture attempts to separate concerns via:

1. **InterviewOrchestrator** (actor): LLM communication and streaming
2. **OnboardingInterviewCoordinator** (@MainActor): State aggregation and callbacks
3. **OnboardingToolRouter**: Tool state dispatch
4. **Tool Handlers** (PromptInteractionHandler, UploadInteractionHandler, etc.): Domain-specific UI interactions
5. **InterviewState** (actor): Session and objective tracking
6. **ChatTranscriptStore**: Message history

This separation is **theoretically sound** but **practically broken** due to tight coupling between layers.

### Strengths

- **Streaming is well-implemented**: The `InterviewOrchestrator.requestResponse()` method correctly handles streaming text and reasoning deltas with proper buffering
- **Tool continuation system is sound**: The `ContinuationToken` pattern allows tools to pause waiting for user input
- **Objective ledger is conceptually clean**: `ObjectiveEntry`, `ObjectiveLedgerSnapshot`, and `ObjectiveCatalog` provide good abstraction
- **Phase progression is explicit**: `InterviewPhase` enum and `InterviewState.advancePhase()` make progression clear
- **Handler delegation pattern works**: PromptInteractionHandler, UploadInteractionHandler, etc. are well-isolated
- **Timeline card system is simple**: TimelineCard, TimelineCardAdapter handle transformations cleanly

### Concerns

1. **InterviewOrchestrator.Callbacks is a code smell**
   - 13 different callback functions bundled into a struct
   - Creates implicit bidirectional dependency between Orchestrator and Coordinator
   - Makes it difficult to understand data flow
   - Changes to callbacks require coordinating updates in two places

2. **OnboardingInterviewCoordinator has excessive responsibilities**
   - 1,576 lines of code
   - Manages chat messages, tool routing, artifacts, objectives, wizard tracking, checkpoints, preferences, phase advancement, streaming status, and extraction progress
   - Functions like `recordObjectiveStatus()` trigger developer messages AND UI updates AND objective status observations
   - Contains both business logic and UI state management

3. **State synchronization is fragile**
   - `objectiveStatuses: [String: ObjectiveStatus]` duplicates data from InterviewState
   - `InterviewSession.objectivesDone: Set<String>` is a separate copy of completed objectives
   - `ObjectiveLedgerSnapshot` is yet another representation
   - Three different places track the same information with no enforcement of consistency

4. **Tool Router adds unnecessary indirection**
   - Routes calls to 4 different handlers (PromptInteractionHandler, UploadInteractionHandler, ProfileInteractionHandler, SectionToggleHandler)
   - Presents status snapshot that duplicates state from handlers
   - Coordinator already delegates to it, creating an extra layer of indirection
   - OnboardingToolRouter→PromptInteractionHandler→... pattern makes tracing data flow difficult

5. **Objective system has circular dependencies**
   - OnboardingInterviewService.recordObjective() calls coordinator.recordObjectiveStatus()
   - recordObjectiveStatus() updates state, fires observers, and enqueues developer messages
   - Observer callbacks flow back to service, triggering workflow outputs
   - profileHandler.lastSubmittedDraft is checked by service for fallback validation
   - This creates implicit coupling that's easy to break

6. **Error handling is inconsistent**
   - Some errors flow through callbacks
   - Some are caught and logged locally
   - Some become tool errors with status payloads
   - No clear error contract between layers

7. **The "developer message" system is a workaround**
   - Developer messages and objectives are being used to communicate state changes to the LLM
   - This suggests the LLM doesn't have reliable access to state, so state changes need to be narrated back
   - 200+ lines of code dedicated to formatting developer messages indicates this is a substantial design choice
   - This should be either: (a) replaced with direct state access, or (b) formalized as a first-class pattern

8. **Streaming logic is scattered**
   - InterviewOrchestrator handles streaming text and reasoning
   - OnboardingInterviewCoordinator manages reasoning summary clearing with a Task
   - ChatTranscriptStore tracks streaming message start times
   - OnboardingInterviewService has its own streaming status logic
   - No unified streaming state machine

### Complexity Rating

**Rating**: **EXCESSIVE**

**Justification**:

- **88 files for a single feature** is a warning sign. Most features could be implemented in 30-40 files
- **16,028 lines of code** suggests systematic over-engineering. A well-designed module of this functionality should be 8,000-10,000 lines
- **7 levels of indirection** from UI action to tool execution: View → Service → Coordinator → Router → Handler → Tool → ToolExecutor
- **Coordinator size (1,576 lines)** violates single responsibility principle
- **5+ state representations** of the same data creates maintenance burden
- **Callback struct with 13 functions** indicates unclear data flow

The complexity is not warranted by actual requirements. A 3-phase onboarding flow with tools, file uploads, and timeline editing should not require this architectural complexity.

---

## File-by-File Analysis

### Core Files (Foundation)

#### InterviewOrchestrator.swift (1,208 lines)

**Purpose**: Orchestrates LLM conversation via OpenAI's Responses API, handles streaming, tool execution, and state persistence

**Complexity**: **High**

**Key Issues**:
- The Callbacks struct defines 13 separate async closures, creating implicit coupling
- Mixing of concerns: LLM streaming, tool result handling, output sanitization, and continuation management
- `requestResponse()` method is 150+ lines with nested state management (StreamBuffer, messageIdByOutputItem, reasoningSummaryBuffers)
- `sanitizeToolOutput()` method contains hardcoded tool names (get_applicant_profile, validate_applicant_profile, submit_for_validation)—should be configurable
- Deprecated `runPhaseOne()` method remains (240+ lines) as a code smell indicating evolving architecture
- `allowedToolsMap` hardcodes phase-to-tool mapping at module level rather than being data-driven

**Specific Problems**:
- Line 826: `callTool()` is a private wrapper that hides synchronous tool execution behind async wrapper—adds complexity without benefit
- Lines 1084-1096: `waitingState()` uses switch on tool name to determine UI state—should be tool metadata
- Lines 1000-1035: `sanitizeToolOutput()` sanitizes email options on applicant profile data—this domain logic should live in the data model

**Observations**:
- Well-structured streaming with proper buffering (lines 627-657)
- Error handling is inconsistent between `handleToolExecutionError()` and generic error cases
- Timeline tool enforcement (line 1200) is a hack to force tool selection after resume extraction

**Recommendations**:
- Extract Callbacks struct into a separate CallbackRegistry protocol
- Break `requestResponse()` into smaller functions: `buildRequestParameters()`, `streamResponse()`, `processStreamEvent()`
- Move tool sanitization logic to tool-specific handlers
- Replace allowedToolsMap with a data-driven approach
- Delete `runPhaseOne()` and any deprecated code

---

#### OnboardingInterviewCoordinator.swift (1,576 lines)

**Purpose**: Central aggregator of onboarding state; bridges orchestrator, tool routing, and SwiftUI

**Complexity**: **Excessive**

**Key Responsibilities** (too many):
1. Chat message management (appendUserMessage, appendAssistantMessage, beginAssistantStream, etc.)
2. Reasoning summary management (updateReasoningSummary, finalizeReasoningSummaries, clearLatestReasoningSummary)
3. Artifact management (storeApplicantProfile, storeSkeletonTimeline, storeArtifactRecord, storeKnowledgeCard, loadPersistedArtifacts)
4. Objective tracking (recordObjectiveStatus, evaluateApplicantProfileObjective, updateObjectiveStatus)
5. Checkpoint management (saveCheckpoint, restoreCheckpoint, hasRestorableCheckpoint)
6. Tool routing (presentChoicePrompt, presentValidationPrompt, presentUploadRequest, etc.)
7. Wizard progress tracking (setWizardStep, syncWizardProgress, applyWizardProgress)
8. Phase advancement (advancePhase, presentPhaseAdvanceRequest, approvePhaseAdvanceRequest, denyPhaseAdvanceRequest)
9. Preference management (setPreferredDefaults, setWritingAnalysisConsent)
10. Interview lifecycle (startInterview, sendMessage, resetInterview)
11. Developer message queuing (recordObjectiveStatus triggers enqueueDeveloperMessage)
12. Model availability handling (onModelAvailabilityIssue callback)

**God Object Anti-Pattern**: This class does 12 distinct things. Single Responsibility Principle suggests 12 different classes.

**Circular Dependencies**:
- Lines 100-115: `recordObjectiveStatus()` updates state, fires observers, and enqueues developer messages
- Lines 430-476: `evaluateApplicantProfileObjective()` reads state and calls recordObjectiveStatus() to update it
- Line 113: Observer callback triggers evaluateApplicantProfileObjective, which can trigger recordObjectiveStatus again
- This creates potential for infinite loops (though guards prevent it in practice)

**State Duplication Issues**:
- Line 53: `objectiveStatuses: [String: ObjectiveStatus]` duplicates InterviewState.objectiveLedger
- Line 1571-1574: `refreshObjectiveStatuses()` synchronizes objectiveStatuses from interviewState—brittle manual sync
- Lines 109-110: `objectiveStatuses[id] = status` happens immediately, while interviewState update happens async in Task

**Specific Problems**:
- Lines 667-693: `storeArtifactRecord()` has complex logic determining when to enforce timeline tools; should be data-driven
- Line 1179: Falls back to coordinator.toolRouter.profileHandler.lastSubmittedDraft—exposes internal handler state
- Lines 818-827: `resolveChoice()` and related methods are simple wrappers around toolRouter calls—add no value
- Lines 1258-1281: State preparation for interview start spans 25 lines with duplicated logic

**Coupling Issues**:
- Takes InterviewState as dependency (line 20) but also creates its own InterviewSession concept
- Creates InterviewOrchestrator via `makeOrchestrator()` (line 1320), which then calls back via callbacks—inverted dependency
- ToolRouter and handlers are created in OnboardingInterviewService constructor (lines 95-110) but passed to Coordinator—confused ownership

**Observations**:
- Good separation between chat store, artifact store, and tool state
- Well-organized into MARK sections despite size
- DeveloperMessageTemplates usage is extensive but indicates over-reliance on narrative state
- Phase advance cache (PhaseAdvanceBlockCache) is smart but localized—more general caching strategy would help

**Recommendations**:
- **Split into 3-4 focused classes**:
  - ChatCoordinator: message management, streaming, reasoning
  - ArtifactCoordinator: artifacts, timeline cards, knowledge cards
  - ObjectiveCoordinator: objective tracking, ledger management
  - PhaseCoordinator: phase advancement, tool enforcement
- Remove InterviewOrchestrator from this file; pass it in as dependency
- Replace circular callbacks with events/notifications
- Establish single source of truth for objective state
- Remove toolRouter delegation; let service coordinate directly with handlers

---

#### OnboardingToolRouter.swift (294 lines)

**Purpose**: Central dispatch for tool-driven interactions; facades into specialized handlers

**Complexity**: **Medium-High** (appropriate for what it does, but what it does is unnecessary)

**Key Issues**:
- Adds a layer of indirection between coordinator and handlers
- OnboardingToolRouter delegates everything to 4 handlers: PromptInteractionHandler, UploadInteractionHandler, ProfileInteractionHandler, SectionToggleHandler
- 85% of its methods are passthroughs: `presentChoicePrompt()` → `promptHandler.presentChoicePrompt()`
- StatusSnapshot (lines 75-82) duplicates state from individual handlers

**Specific Problems**:
- Lines 265-292: Status resolver closures reference unowned self; could cause issues if router deallocates while closures execute
- Lines 278-287: getApplicantProfile status logic has business rules embedded in closure—should be handler responsibility
- No clear separation of concerns; feels like a naming facade rather than a real layer

**Observations**:
- Reasonable pattern in isolation, but unnecessary in context
- Handlers already provide clear interface; router doesn't add abstraction value
- Could be easily inlined into OnboardingInterviewCoordinator

**Recommendations**:
- Consider removing this layer entirely; have coordinator work directly with handlers
- If keeping, move to a more formal adapter pattern with explicit transformation logic
- Move status resolver closures to handlers

---

#### InterviewSession.swift (248 lines)

**Purpose**: Session state and actor-isolated state management

**Complexity**: **Low-Medium**

**Issues**:
- InterviewSession is a value type (struct) with mutable state, but InterviewState (actor) wraps it for mutations
- objectivesDone duplication: Set<String> in session + objectiveLedger dictionaries—two ways to query completed state
- `missingObjectives()` hardcodes required objectives per phase (lines 56-69)—should use ObjectiveCatalog
- `isObjective()` method (line 201) is private but duplicates logic of objectiveStatus()

**Observations**:
- Actor-based approach is correct for thread safety
- Objective ledger management is solid
- makeEntry pattern (ObjectiveDescriptor.makeEntry) is clean
- Session restoration works well

**Recommendations**:
- Use ObjectiveCatalog.objectives(for:) in missingObjectives() instead of hardcoding
- Remove objectivesDone Set; derive from objectiveLedger
- Make isObjective() public or replace with objectiveStatus() calls
- Consider making InterviewSession immutable and InterviewState manage mutations only

---

#### ToolExecutor.swift (97 lines)

**Purpose**: Executes tools and manages continuations

**Complexity**: **Low**

**Observations**:
- Clean, focused implementation
- ContinuationToken storage is appropriate
- Error normalization provides good interface

**Issues**:
- None significant

**Recommendations**:
- None needed; this is well-designed

---

### Tool System Files

#### ToolProtocol.swift / ToolRegistry.swift (referenced but structure examined)

**Purpose**: Defines tool interface and registry

**Observations**:
- Tool protocol should define error contract and continuation behavior
- Registry pattern is standard and appropriate

---

### Handler Files (PromptInteractionHandler, UploadInteractionHandler, ProfileInteractionHandler, SectionToggleHandler)

**Overall Pattern**: @MainActor @Observable handlers with state and payload construction

**Complexity**: **Low-Medium** per handler

**General Issues**:
- Each handler manages continuation IDs locally—should be centralized
- Payload construction is repetitive (JSON boilerplate across all handlers)
- No error propagation; handlers assume everything works

**PromptInteractionHandler.swift (132 lines)**:
- Clean and focused
- Two separate flows: choice prompts and validation prompts
- Continuation ID management is appropriate
- Minor: Could use a generic resumeContinuation pattern

**UploadInteractionHandler.swift (partial view)**:
- Complex due to file handling, extraction progress, and multi-file support
- Good separation of concerns for uploads vs. profile images
- Handles extraction progress callbacks appropriately

**ProfileInteractionHandler.swift (partial view)**:
- Manages 4 intake modes (manual, URL, upload, contacts)
- State machine for intake flow could be more explicit
- lastSubmittedDraft is an anti-pattern; should be immutable

**SectionToggleHandler.swift**:
- Simple request/response pattern
- No identified issues

---

### State Management Files

#### ChatTranscriptStore.swift (104 lines)

**Purpose**: Chat message history management

**Complexity**: **Low**

**Observations**:
- Clean implementation
- Streaming message start time tracking is appropriate
- No significant issues

---

#### InterviewDataStore.swift

**Purpose**: Persists interview data (artifacts, knowledge cards, etc.)

**Complexity**: **Low-Medium**

**Observations**:
- Appropriate for separating persistence logic
- SwiftData integration is clean

---

### UI Integration Files

#### OnboardingInterviewService.swift (1,185 lines)

**Purpose**: Service bridge between coordinator and SwiftUI views

**Complexity**: **High**

**Key Issues**:
- Another aggregator class; adds minimal value between coordinator and UI
- Duplicates many coordinator methods as passthroughs
- Has opinion about objective workflows (lines 1123-1145: handleObjectiveStatusUpdate)
- Photo prompt logic is scattered (lines 899-957)
- Validation retry tracking (lines 1161-1174) is service concern but belongs in coordinator
- Timeline card operations implemented here (lines 977-1092) instead of coordinator

**Specific Problems**:
- Line 77: `applicantProfileJSON` property duplicates coordinator.applicantProfileJSON
- Lines 382-392: recordObjective() method records the same objective that was just recorded by coordinator—double recording
- Lines 1123-1145: Orchestrates objective workflows; but OnboardingInterviewCoordinator has observers for this
- Lines 899-927: enqueuePhotoFollowUp() has complex business logic that should be data-driven

**Observations**:
- Timeline card management is better integrated here than scattered in coordinator
- Model availability handling is appropriate
- Reason testing is thorough (comments at lines 383-385)

**Recommendations**:
- Reduce to a simple @MainActor facade over coordinator
- Move timeline operations to coordinator or separate service
- Remove objective double-recording
- Formalize photo follow-up workflow with data-driven approach

---

## Identified Issues

### 1. Over-Abstraction

**Problem**: The system uses too many layers for a relatively simple flow:
- UI View → Service → Coordinator → Router → Handler → Tool

This creates 6+ hops to execute a tool call.

**Example**:
```
OnboardingInterviewView
→ OnboardingInterviewService.resolveChoice()
→ OnboardingInterviewCoordinator.resolveChoice()
→ OnboardingToolRouter.resolveChoice()
→ PromptInteractionHandler.resolveChoice()
→ returns (continuationId, JSON)
→ Service calls resumeToolContinuation()
→ Coordinator.resumeToolContinuation()
→ Orchestrator.resumeToolContinuation()
→ ToolExecutor.resumeContinuation()
```

**Impact**: Difficult to trace data flow, easy to introduce bugs, hard to test individual layers

---

### 2. State Duplication & Synchronization

**Problem**: Objective state exists in multiple places:
- InterviewSession.objectivesDone: Set<String>
- InterviewState.objectiveLedger: [String: ObjectiveEntry]
- OnboardingInterviewCoordinator.objectiveStatuses: [String: ObjectiveStatus]
- ObjectiveLedgerSnapshot (computed from ledger)

**Example (InterviewSession.swift, lines 240-245)**:
```swift
private func persistLedger() {
    session.objectiveLedger = Array(objectiveLedger.values)
    session.objectivesDone = Set(
        objectiveLedger.values
            .filter { $0.status == .completed }
            .map(\.id)
    )
}
```

And then (OnboardingInterviewCoordinator.swift, lines 1569-1574):
```swift
private func refreshObjectiveStatuses() async {
    let session = await interviewState.currentSession()
    objectiveStatuses = session.objectiveLedger.reduce(into: [:]) { dict, entry in
        dict[entry.id] = entry.status
    }
}
```

**Impact**: Inconsistency bugs, syncing overhead, difficult to debug state issues

---

### 3. Callback Hell

**Problem**: InterviewOrchestrator.Callbacks struct with 13 callback functions creates implicit dependencies

**Example (InterviewOrchestrator.swift, lines 32-52)**:
```swift
struct Callbacks {
    let updateProcessingState: @Sendable (Bool) async -> Void
    let emitAssistantMessage: @Sendable (String, Bool) async -> UUID
    let beginStreamingAssistantMessage: @Sendable (String, Bool) async -> UUID
    let updateStreamingAssistantMessage: @Sendable (UUID, String) async -> Void
    let finalizeStreamingAssistantMessage: @Sendable (UUID, String) async -> Void
    let updateReasoningSummary: @Sendable (UUID, String, Bool) async -> Void
    let finalizeReasoningSummaries: @Sendable ([UUID]) async -> Void
    let updateStreamingStatus: @Sendable (String?) async -> Void
    let handleWaitingState: @Sendable (InterviewSession.Waiting?) async -> Void
    let handleError: @Sendable (String) async -> Void
    let storeApplicantProfile: @Sendable (JSON) async -> Void
    let storeSkeletonTimeline: @Sendable (JSON) async -> Void
    let storeArtifactRecord: @Sendable (JSON) async -> Void
    let storeKnowledgeCard: @Sendable (JSON) async -> Void
    let setExtractionStatus: @Sendable (OnboardingPendingExtraction?) async -> Void
    let updateExtractionProgress: ExtractionProgressHandler
    let persistCheckpoint: @Sendable () async -> Void
    let registerToolWait: @Sendable (UUID, String, String, String?) async -> Void
    let clearToolWait: @Sendable (UUID, String) async -> Void
    let handleInvalidModelId: @Sendable (String) async -> Void
}
```

**Impact**: Difficult to understand what orchestrator actually does vs. what it delegates, hard to test orchestrator in isolation, changes to Callbacks require updates in two files

---

### 4. Developer Message Anti-Pattern

**Problem**: The system narrates state changes back to the LLM via "developer messages" instead of providing direct state access

**Examples (OnboardingInterviewCoordinator.swift)**:
- Line 685: `enqueueDeveloperStatus(from: message)` when artifact is stored
- Lines 1498-1499: Similar for knowledge cards
- Lines 834-839: DeveloperMessageTemplates used extensively

**Problem Statement**: Suggests the LLM doesn't have reliable access to state, so state changes need to be narrated. This indicates either:
1. LLM tool definitions are incomplete (tools don't return current state)
2. Continuation handling doesn't provide context to next turn
3. State snapshots should be part of tool responses

**Impact**: 200+ lines of template code, fragile if narration diverges from actual state, hard to debug LLM understanding of state

---

### 5. Tool Sanitization Anti-Pattern

**Problem**: InterviewOrchestrator.sanitizeToolOutput() contains hardcoded tool names and domain logic

**Code (lines 999-1035)**:
```swift
private func sanitizeToolOutput(for toolName: String?, payload: JSON) -> JSON {
    guard let toolName else { return payload }
    switch toolName {
    case "get_applicant_profile":
        var sanitized = payload
        if sanitized["data"] != .null {
            var data = ApplicantProfileDraft.removeHiddenEmailOptions(from: sanitized["data"])
            let channel = sanitized["mode"].string ?? "intake"
            data = attachValidationMetaIfNeeded(to: data, defaultChannel: channel)
            sanitized["data"] = data
        }
        return sanitized
    case "validate_applicant_profile":
        // Similar logic
    // ... more cases
    }
}
```

**Problem**:
- Orchestrator shouldn't know about specific tool output formats
- Tool-specific logic should live in tool implementation or separate sanitizers
- Adding new tools requires modifying orchestrator

**Impact**: Orchestrator becomes tool-aware, hard to extend, violates open-closed principle

---

### 6. Implicit State Machines

**Problem**: No explicit state machine for wizard, upload, and profile intake flows

**Example** (OnboardingApplicantProfileIntakeState has modes):
```
options → manual/url/upload/contacts → loading → complete
```

But this state machine is encoded in if/else logic rather than an explicit enum

**Impact**: Hard to visualize flow, easy to create invalid state transitions, difficult to test

---

## Recommended Refactoring Approaches

### Approach 1: Facade-Based Refactor (Recommended - Medium Effort)

**Effort**: Medium (3-4 sprints)
**Impact**: Significant improvement in maintainability, testability, enables future improvements
**Risk**: Low (changes are additive, can be done incrementally)

**Strategy**:

1. **Consolidate State Management**
   - Create `OnboardingState` actor that owns all mutable state
   - Single source of truth for objectives, session, artifacts, messages
   - Replaces InterviewState, ChatTranscriptStore, and objectiveStatuses duplication
   - Example interface:
   ```swift
   actor OnboardingState {
       func currentSession() async -> InterviewSession
       func recordObjectiveStatus(id: String, status: ObjectiveStatus, source: String) async
       func appendMessage(role: MessageRole, text: String) async -> UUID
       func storeArtifact(_ artifact: JSON) async
   }
   ```

2. **Extract Service Layer**
   - Create focused services for major domains:
     - `ChatService`: message management, streaming, reasoning
     - `ArtifactService`: artifact storage and retrieval
     - `ObjectiveService`: objective tracking and evaluation
     - `PhaseService`: phase advancement logic
   - Each service has ~200-400 lines
   - Services coordinate through OnboardingState, not through callbacks

3. **Simplify Tool Execution Path**
   - Remove OnboardingToolRouter abstraction
   - Let OnboardingInterviewCoordinator work directly with handlers
   - Create `ToolResponseHandler` protocol for sanitization logic
   - Each tool can optionally implement response handler

4. **Replace Callbacks with Events**
   - Define OnboardingEvent enum:
   ```swift
   enum OnboardingEvent: Sendable {
       case messageAdded(MessageRole, String)
       case streamingStarted(UUID)
       case streamingUpdated(UUID, String)
       case artifactStored(JSON)
       case objectiveCompleted(String)
       case phaseAdvanced(InterviewPhase)
   }
   ```
   - Orchestrator emits events, not callbacks
   - Coordinator subscribes to events
   - Decouples layers

5. **Implementation Steps**:
   - Step 1: Create OnboardingState actor, migrate state gradually
   - Step 2: Extract service layer incrementally
   - Step 3: Replace callbacks with events
   - Step 4: Remove old structures
   - Step 5: Simplify tool routing

**Benefits**:
- Single source of truth for all state
- Clear data flow (events from orchestrator)
- Easier to test (mock event handlers)
- Reduced file size for Coordinator (1500+ → 600-700 lines)
- Easier to add new features (new services, new event types)

**Risks**:
- Potential for bugs during state migration
- Event-based approach might reveal timing issues
- Mitigated by: incremental migration, comprehensive logging, gradual replacement

---

### Approach 2: Complete Rewrite with Clean Architecture

**Effort**: High (5-7 sprints)
**Impact**: Maximum improvement, but high risk
**Risk**: Medium-High (could introduce new bugs, more difficult to debug during transition)

**Key Changes**:
1. Use MVVM pattern with clear ViewModel
2. Separate LLM orchestration from state management completely
3. Use Swift Concurrency primitives (TaskGroup, AsyncSequence) instead of callbacks
4. Data-driven approach for all state machines
5. Dependency injection instead of factory methods

**Not Recommended** unless timeline allows; the facade approach is safer and faster

---

### Approach 3: Minimal Surgical Fixes (Not Recommended)

**Effort**: Low (1 sprint)
**Impact**: Temporary stability, doesn't solve core issues

**Would Address**:
- Remove OnboardingToolRouter indirection
- Consolidate objectiveStatuses with InterviewState
- Extract some methods from Coordinator

**Doesn't Address**:
- Callback coupling
- State duplication
- Orchestrator-Coordinator bidirectional dependency
- Over-abstraction

**Not recommended** because core issues remain

---

## Simpler Alternative Architectures

### Option A: Event-Driven Architecture

**Structure**:
```
User Action
    ↓
LLMOrchestrator (handles API, streaming, tool calls)
    ↓
OnboardingEvent (messageReceived, toolCalled, etc.)
    ↓
OnboardingState (single source of truth, processes events)
    ↓
@Observable Facade (exposes state to UI)
```

**Pros**:
- Clear unidirectional data flow
- Single state source
- Easy to log/replay events
- Testable: emit events, verify state changes

**Cons**:
- Requires rewriting orchestrator to emit events instead of calling callbacks
- Event ordering could be complex with concurrent updates

---

### Option B: Command-Based Architecture

**Structure**:
```
User Action → Command (struct)
    ↓
OnboardingInterpreter (processes commands)
    ↓
LLMOrchestrator or Service Layer (executes)
    ↓
Update OnboardingState
    ↓
Notify UI via @Observable
```

**Pros**:
- Explicit, serializable actions
- Easy to debug (print commands)
- Can build UI that shows command queue
- Natural for testing

**Cons**:
- Requires significant refactoring
- Commands might become complex

---

### Option C: Agent-Based (if reconsidering fundamental approach)

Use a dedicated agent framework that manages state machines, tool calling, and continuations:

**Pros**:
- Off-the-shelf solution for complex flows
- Standardized state machine
- Community support

**Cons**:
- Dependency on external framework
- May not perfectly match Sprung needs

---

## Conclusion & Recommendations

### Summary

The Onboarding module is **salvageable with targeted refactoring** but has fundamental architectural problems that make it fragile despite apparent completeness:

1. **State duplication** across 5+ locations creates sync bugs
2. **Callback coupling** between Orchestrator and Coordinator makes changes risky
3. **Over-abstraction** (7+ layers) makes code hard to trace and debug
4. **God object problem** in OnboardingInterviewCoordinator (1,576 lines)
5. **Developer messages** indicate state visibility issues

### Priority-Ranked Action Plan

**Phase 1 (Sprint 1-2): Foundation**
1. **Create OnboardingState actor** to consolidate state
2. **Migrate objectives** to single source of truth in OnboardingState
3. **Remove objectiveStatuses** from Coordinator; derive from OnboardingState
4. Establish pattern for other state migrations

**Phase 2 (Sprint 2-3): Decoupling**
1. **Replace Callbacks with Events**
   - Define OnboardingEvent enum
   - Have Orchestrator emit events
   - Have Coordinator listen to events
2. **Remove Callback struct** from InterviewOrchestrator
3. **Test new event flow** thoroughly

**Phase 3 (Sprint 3): Simplification**
1. **Extract ChatService** from Coordinator
2. **Extract ArtifactService** from Coordinator
3. **Remove OnboardingToolRouter** indirection
4. **Simplify Coordinator** to orchestrate services, not contain logic

**Phase 4 (Sprint 4): Polish**
1. Update tests
2. Performance review
3. Documentation
4. Deprecation cleanup

### What to Keep

- ✅ Streaming implementation (InterviewOrchestrator streaming logic is solid)
- ✅ Tool continuation pattern (ContinuationToken design is good)
- ✅ Objective ledger concept (clean abstraction)
- ✅ Phase progression (explicit and correct)
- ✅ Handler delegation (PromptInteractionHandler, etc. are well-isolated)
- ✅ Timeline card system (simple and effective)

### What to Replace

- ❌ Callbacks struct → Events
- ❌ ObjectiveStatuses duplication → Single source in OnboardingState
- ❌ OnboardingToolRouter indirection → Direct handler coordination
- ❌ Coordinator god object → Split into services
- ❌ Developer message narration → Direct state queries or better tool definitions

### Success Metrics

After refactoring:
1. Coordinator should be < 800 lines (currently 1,576)
2. No state duplication (single source of truth for objectives)
3. Data flow should be unidirectional (no bidirectional callbacks)
4. Adding a new tool should not require modifying orchestrator
5. New developers should be able to trace a user action to state change in < 5 minutes

### Estimated Timeline

- **Complete refactor**: 4-5 sprints with concurrent work
- **Significant improvement**: 2-3 sprints with targeted fixes (Approach 1)
- **Minimum viable improvements**: 1 sprint (remove duplication, simplify Router)

**Recommendation**: Pursue **Approach 1 (Facade-Based Refactor)** starting with Phase 1 to consolidate state. This is low-risk, high-reward, and enables future improvements.

---

## Appendix: File Organization Reference

```
Onboarding/
├── Core/
│   ├── InterviewOrchestrator.swift (1,208 lines) - LLM orchestration
│   ├── OnboardingInterviewCoordinator.swift (1,576 lines) - State aggregation
│   ├── OnboardingToolRouter.swift (294 lines) - Tool dispatch
│   ├── InterviewSession.swift (248 lines) - Session state
│   ├── ToolExecutor.swift (97 lines) - Tool execution
│   ├── OnboardingInterviewService.swift (1,185 lines) - Service facade
│   └── [Other core files]
├── Handlers/
│   ├── PromptInteractionHandler.swift (132 lines)
│   ├── UploadInteractionHandler.swift
│   ├── ProfileInteractionHandler.swift
│   └── SectionToggleHandler.swift
├── Stores/
│   ├── ChatTranscriptStore.swift (104 lines)
│   ├── InterviewDataStore.swift
│   └── OnboardingArtifactStore.swift
├── Tools/
│   ├── ToolProtocol.swift
│   ├── ToolRegistry.swift
│   └── Implementations/ (17 tool files)
├── Views/ (24 component files + OnboardingInterviewView.swift)
├── ViewModels/
│   └── OnboardingInterviewViewModel.swift
└── [Other support files]

Total: 88 Swift files, 16,028 lines
```

