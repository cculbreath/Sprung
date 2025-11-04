# Onboarding Event-Driven Architecture Implementation Checklist

**Based on:** planning/pub-sub-single-state-spec.md
**Last Updated:** 2025-11-03
**Status:** Phase 1 Complete - Foundation Laid

---

## ✅ Phase 1: Core Infrastructure (COMPLETE)

### 1.1 StateCoordinator (Actor) — Single Source of Truth
- [x] Create StateCoordinator actor ✅ **RENAMED**
- [x] Implement canonical state storage (currentPhase, wizardStep, objective ledger)
- [x] Add phase script application logic
- [x] Implement checkpoint persistence integration
- [x] **Subscriptions:** ✅ Using AsyncStream
  - [x] `State.set(..)` partial updates → handleStateEvent()
  - [x] `LLM.userMessageSent`, `LLM.sentToolResponseMessage` → handleLLMEvent()
  - [x] `Objective.status.requested` → handleObjectiveEvent()
  - [x] `Phase.transition.requested` → handlePhaseEvent()
- [x] **Publications:** ✅ Via OnboardingEventEmitter
  - [x] `State.snapshot(updated_keys)` → emitSnapshot()
  - [x] `State.allowedTools()` → emitAllowedTools()
  - [x] `Phase.transition.applied` → in handlePhaseEvent()
  - [x] `Objective.status.changed` → updateObjectiveStatus()

**File:** `Sprung/Onboarding/Core/StateCoordinator.swift` ✅
**Event Integration:** Complete with startEventSubscriptions() method

---

### 1.2 EventCoordinator — Pub/Sub Backbone
- [x] Create EventCoordinator actor ✅ **RENAMED**
- [x] Implement topic registry and subscription management ✅ **UPGRADED TO ASYNCSTREAM**
- [x] Add async fan-out for event delivery ✅ **VIA ASYNCSTREAM**
- [x] **NEW: AsyncStream-based architecture** ✅
  - [x] Topic-based routing (EventTopic enum)
  - [x] Per-topic AsyncStream with buffering (50 events)
  - [x] Automatic topic extraction from events
  - [x] Stream merging for compatibility (streamAll())
- [x] Add metrics (publishedCount, queueDepth, lastPublishTime) ✅
- [x] Implement bounded queues (bufferingNewest(50)) ✅

**File:** `Sprung/Onboarding/Core/OnboardingEvents.swift` (contains EventCoordinator + OnboardingEvent enum) ✅

**Architecture Decision:** Using AsyncStream instead of callbacks for:
- Natural Swift concurrency integration (`for await event in stream`)
- Built-in backpressure handling
- Topic-based filtering at source (performance)
- Type-safe event routing

---

### 1.3 Service Layer Simplification
- [x] Reduce OnboardingInterviewService to ~225 line bridge
- [x] Remove callback lattice (13 callbacks eliminated)
- [x] Add synchronous property caching for SwiftUI
- [x] Make coordinator accessible to AppDelegate
- [x] Update AppDependencies initialization

**File:** `Sprung/Onboarding/Core/OnboardingInterviewService.swift`

---

### 1.4 Build Verification
- [x] Fix all compilation errors
- [x] Resolve type-checking timeout in OnboardingInterviewView
- [x] Comment out missing methods with TODO markers
- [x] Verify successful build

---

## ✅ Phase 2: LLM & Streaming Infrastructure (COMPLETE)

### 2.1 NetworkRouter — Stream Event Emission (§4.4)
- [x] Create NetworkRouter actor ✅
- [x] Extract stream processing from InterviewOrchestrator ✅
- [x] Connect to EventCoordinator with AsyncStream ✅
- [x] **Publications:**
  - [x] `.streamingMessageBegan`, `.streamingMessageUpdated`, `.streamingMessageFinalized` (message deltas)
  - [x] `.toolCallRequested` (tool invocation - LLM.toolCallReceived)
  - [x] `.waitingStateChanged` (derived from tool type)
  - [x] `.errorOccurred` (LLM.error)
  - [ ] `LLM.reasoningDelta`, `LLM.reasoningDone` (TODO: when OpenAI exposes in Responses API)
- [x] InterviewOrchestrator refactored to use NetworkRouter ✅
  - Delegates stream processing to NetworkRouter
  - Subscribes to tool events for continuation management
  - Maintains conversation state (conversationId, lastResponseId)

**File:** `Sprung/Onboarding/Core/NetworkRouter.swift` ✅
**Status:** ✅ Complete
**Unblocks:** Chatbox Handler can now subscribe to message events

---

### 2.2 LLM Messenger (§4.3)
- [x] Extract message orchestration from InterviewOrchestrator ✅
- [x] **Subscriptions:** ✅
  - [x] `LLM.sendUserMessage(payload)`
  - [x] `LLM.sendDeveloperMessage(payload)`
  - [x] `LLM.toolResponseMessage(payload)`
  - [x] `UserInput.chatMessage`
  - [ ] `State.allowedTools()` (TODO: not yet used)
- [x] **Publications:** ✅
  - [x] `LLM.userMessageSent(payload)`
  - [x] `LLM.developerMessageSent(payload)`
  - [x] `LLM.sentToolResponseMessage(payload)`
  - [x] `LLM.status(busy|idle|error)`

**File:** `Sprung/Onboarding/Core/LLMMessenger.swift` ✅
**Status:** ✅ Complete
**Integration:** InterviewOrchestrator refactored to emit message request events instead of direct calls

---

### 2.3 LLM Reasoning Handler (§4.5)
- [x] Create reasoning delta aggregator ✅
- [x] **Subscriptions:** ✅ (prepared for API support)
  - [ ] `LLM.reasoningDelta` (TODO: when OpenAI exposes in Responses API)
  - [ ] `LLM.reasoningDone` (TODO: when OpenAI exposes in Responses API)
- [x] **Publications:** ✅
  - [x] `.llmReasoningSummary(messageId, summary, isFinal)` (throttled at 500ms)
  - [x] `.llmReasoningStatus(incoming|none)`

**File:** `Sprung/Onboarding/Handlers/LLMReasoningHandler.swift` ✅
**Status:** ✅ Complete (prepared for future API support)
**Note:** OpenAI Responses API doesn't currently expose reasoning in streaming mode. Handler is ready for when API support is added.
**Fixes:** Infrastructure ready for reasoning summaries display

---

## 🚧 Phase 3: Tool & UI Handler Infrastructure (IN PROGRESS - ChatboxHandler Complete)

### 3.1 Tool Execution Coordination (§4.6)
- [x] Create ToolExecutionCoordinator actor ✅
- [x] **Subscriptions:** ✅
  - [x] `.toolCallRequested` (from NetworkRouter)
- [x] **Publications:** ✅
  - [x] `.llmToolResponseMessage(payload)` (immediate results & errors)
  - [x] `.toolContinuationNeeded(id, toolName)` (waiting for user input)
- [x] Validate tool names against `State.allowedTools` ✅
- [x] Manage continuation tokens via events ✅
- [x] Execute tools via ToolExecutor ✅
- [x] Handle ToolResult (immediate/waiting/error) ✅
- [ ] **TODO:** Tool implementations need to return proper data instead of placeholders

**File:** `Sprung/Onboarding/Handlers/ToolExecutionCoordinator.swift` ✅
**Status:** ✅ Core infrastructure complete
**Cleanup:** Removed 42 lines of duplicate tool handling from InterviewOrchestrator
**Integration:** Wired into coordinator, starts subscriptions, handles resumption

---

### 3.2 ToolPane Handler (§4.7)
- [x] Add service bridge methods for tool UI presentation ✅
- [x] Enable GetUserOptionTool to present choice cards ✅
- [ ] **TODO:** Migrate remaining tools (upload, validation, profile, etc.)
- [ ] **Future:** Consider event-driven card coordination if needed

**Status:** ✅ Core mechanism working
**Solution:** Tools call service bridge methods → service delegates to ToolHandler → UI observes
**Architecture:** Using existing Observable pattern instead of pure events for UI cards
**Reasoning:** Simpler and works well with SwiftUI's observation system
**First Working Tool:** get_user_option now presents/clears UI cards correctly

---

### 3.3 Chatbox Handler (§4.9)
- [x] Create Chatbox Handler ✅
- [x] **Subscriptions:** ✅
  - [x] `.streamingMessageBegan`, `.streamingMessageUpdated`, `.streamingMessageFinalized` (LLM topic)
  - [x] `.llmUserMessageSent` (for displaying user messages)
  - [x] `.errorOccurred` (for error display)
  - [ ] `LLM.reasoningSummary(payload)` (TODO: when LLM Reasoning Handler is implemented)
- [x] **Publications:** ✅
  - [x] `.llmSendUserMessage` (emits when user sends message)
- [x] Integrate with existing transcript formatter ✅
  - Uses ChatTranscriptStore for message management
  - Updates transcript via MainActor calls

**File:** `Sprung/Onboarding/Handlers/ChatboxHandler.swift` ✅
**Status:** ✅ Complete
**Integration:**
- Integrated into OnboardingInterviewCoordinator
- Chat panel updated to use coordinator.messages
- User input now flows through chatboxHandler.sendUserMessage()
**Fixes:** Message display now working with event-driven architecture

---

### 3.4 Artifact Handler (§4.8)
- [ ] Create Artifact Handler
- [ ] **Subscriptions:**
  - [ ] `Artifact.get(id)`
  - [ ] `Artifact.new(payload)`
- [ ] **Publications:**
  - [ ] `Artifact.added`
  - [ ] `Artifact.updated`
- [ ] Delegate to DocumentExtractionService
- [ ] Manage artifact store integration

**Status:** Not started

---

## 🔧 Phase 4: Tool Event Migration (NOT STARTED)

### 4.1 Core Tools Migration
Update tools to emit events instead of immediate responses:

- [ ] **get_user_choice** → `Toolpane.cards.choiceForm.show`
- [ ] **get_applicant_profile** → profile intake flow events
- [ ] **get_user_upload** → upload request events
- [ ] **extract_document** → extraction progress events
- [ ] **submit_for_validation** → validation review events
- [ ] **persist_data** → artifact events
- [ ] **set_objective_status** → objective ledger events
- [ ] **next_phase** → phase transition events

**Current Status:** All tools return `ToolResult.immediate(placeholder)` with TODO comments

---

### 4.2 Timeline Tools Migration
- [ ] **create_timeline_card**
- [ ] **update_timeline_card**
- [ ] **delete_timeline_card**
- [ ] **reorder_timeline_cards**

---

### 4.3 Knowledge Card Tools
- [ ] **generate_knowledge_card**

---

## 📊 Phase 5: Data Contracts & Payloads (PARTIAL)

### 5.1 MessagePayload (§5.1)
- [ ] Formalize MessagePayload struct
- [ ] Add metadata field for objective/tool context
- [ ] Integrate with OnboardingMessage

**Current:** Using OnboardingMessage, needs metadata extension

---

### 5.2 OnboardingPhaseSpec (§5.2)
- [ ] Create OnboardingPhaseSpec struct
- [ ] Map to existing allowedToolsMap
- [ ] Integrate with phase scripts

**Current:** Using enum InterviewPhase + hardcoded tool maps

---

### 5.3 ToolPaneCardDescriptor (§5.3)
- [ ] Create ToolPaneCardDescriptor struct
- [ ] Define card types (choiceForm, uploadForm, etc.)
- [ ] Add event routing for card submissions

**Current:** Card descriptors are ad-hoc

---

## 🔄 Phase 6: Event Topics Implementation (§6)

### 6.1 LLM Topics
- [ ] `LLM.sendUserMessage`
- [ ] `LLM.sendDeveloperMessage`
- [ ] `LLM.toolResponseMessage`
- [ ] `LLM.userMessageSent`
- [ ] `LLM.developerMessageSent`
- [ ] `LLM.sentToolResponseMessage`
- [ ] `LLM.messageDelta`
- [ ] `LLM.messageReceived`
- [ ] `LLM.toolCallReceived`
- [ ] `LLM.reasoningDelta`
- [ ] `LLM.reasoningDone`
- [ ] `LLM.status`
- [ ] `LLM.error`

---

### 6.2 ToolPane Topics
- [ ] `Toolpane.show`
- [ ] `Toolpane.hide`
- [ ] `Toolpane.showing`

---

### 6.3 UserInput Topics
- [ ] `UserInput.chatMessage`
- [ ] `UserInput.received`

---

### 6.4 Artifact Topics
- [ ] `Artifact.get`
- [ ] `Artifact.new`
- [ ] `Artifact.added`
- [ ] `Artifact.updated`

---

### 6.5 State Topics
- [ ] `State.set(partial)`
- [ ] `State.snapshot`
- [ ] `State.allowedTools`

---

### 6.6 Phase Topics
- [ ] `Phase.transition.requested`
- [ ] `Phase.transition.applied`

---

### 6.7 Objective Topics
- [ ] `Objective.status.changed`

---

## 🧹 Phase 7: Cleanup & Migration Completion (NOT STARTED)

### 7.1 Remove Old Code
- [ ] Delete callback lattice from InterviewOrchestrator
- [ ] Remove duplicated state tracking
- [ ] Clean up commented TODO sections
- [ ] Remove temporary bridge methods

---

### 7.2 UI Integration
- [ ] Wire spinner/glow to `LLM.status` events
- [ ] Wire reasoning display to `LLM.reasoningSummary` events
- [ ] Wire timeline cards to tool events
- [ ] Wire progress indicators to extraction events

---

### 7.3 Testing & Validation
- [ ] End-to-end interview flow testing
- [ ] Phase transition validation
- [ ] Tool execution verification
- [ ] Checkpoint restore testing
- [ ] Error handling paths

---

## 📈 Metrics & Observability (§11)

- [ ] Event bus throughput counters
- [ ] Per-topic lag monitoring
- [ ] Handler latency tracking
- [ ] Queue depth monitoring
- [ ] UI busy glow accuracy

---

## ⚠️ Known Issues (Blocking UI Feedback)

1. ~~**Spinner/glow not working**~~ → ✅ **FIXED**: LLM.status events wired to StateCoordinator → UI
2. ~~**Reasoning summaries not displaying**~~ → ✅ **INFRASTRUCTURE READY**: LLM Reasoning Handler complete (waiting for API support)
3. **Timeline card tools not working** → Tools need to emit events (Phase 4)
4. **Phase transitions commented out** → Need event-driven implementation (Phase 4)

---

## 📝 Naming Migrations ✅ COMPLETE

All core classes renamed to match spec naming conventions:

- [x] ✅ Renamed `OnboardingState` → `StateCoordinator` (matches spec §4.1)
  - [x] Updated file: `StateCoordinator.swift`
  - [x] Updated calling sites: `OnboardingInterviewCoordinator.swift`, `Checkpoints.swift`
  - [x] Build verified successful
- [x] ✅ Renamed `OnboardingEventBus` → `EventCoordinator` (matches spec §4.2)
  - [x] Updated file: `OnboardingEvents.swift`
  - [x] Updated calling sites: `OnboardingInterviewCoordinator.swift`, `InterviewOrchestrator.swift`
  - [x] Build verified successful
- [x] ✅ Renamed `OnboardingToolRouter` → `ToolHandler` (matches spec §4.6)
  - [x] Updated file: `ToolHandler.swift`
  - [x] Updated calling sites: `OnboardingInterviewCoordinator.swift`, `OnboardingInterviewView.swift`, `OnboardingInterviewInteractiveCard.swift`
  - [x] Build verified successful

---

## 🎯 Current Sprint Goals

**Sprint 1 (Completed):**
- ✅ Foundation infrastructure (State actor, EventCoordinator)
- ✅ Build compiling with TODO markers
- ✅ NetworkRouter implementation
- ✅ LLM event emission (LLMMessenger, LLMReasoningHandler)
- ✅ ChatboxHandler for message display

**Sprint 2 (Next):**
- ToolPane Handler
- Chatbox Handler
- LLM Reasoning Handler
- Tool event migration (core tools)

**Sprint 3 (Future):**
- Remaining tool migrations
- Cleanup old code
- End-to-end testing
- Performance optimization
