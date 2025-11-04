# Event-Driven Architecture Patterns

**Created**: 2025-11-04
**Purpose**: Define clear boundaries for when direct calls vs events are appropriate

---

## Core Principle: Event-First Design

**Default Rule**: All component interactions should flow through events unless there's a specific justification for direct coupling.

---

## When Direct Calls Are Acceptable

### 1. Tightly Coupled Processing Pipelines
**Pattern**: Component A owns data/stream, Component B is a pure transformer/processor

**Example**: LLMMessenger → NetworkRouter
- LLMMessenger owns the API stream
- NetworkRouter is stateless processor (stream events → domain events)
- NetworkRouter has no other purpose than serving LLMMessenger
- **Key**: NetworkRouter still emits to event bus for downstream consumers

**Justification**: They form a single logical unit with no state mutation

---

### 2. Read-Only State Queries
**Pattern**: Component queries StateCoordinator for read-only data

**Example**: Coordinator.getArtifact(id) → StateCoordinator.artifacts
```swift
// OK - Read-only query through coordinator
let artifact = await coordinator.getArtifact(id: artifactId)

// NOT OK - Direct state access
let artifacts = await stateCoordinator.artifacts
```

**Rules**:
- Must go through coordinator layer (not direct to StateCoordinator)
- Cannot mutate state
- Used for synchronous responses to tools/UI
- StateCoordinator remains single source of truth

**Justification**: Some operations need immediate synchronous data without round-trip through events

---

## When Events Are Required

### 1. State Mutations (Always)
**Pattern**: All state changes must flow through events

**Example**: Update objective status
```swift
// CORRECT - Emit event
await coordinator.updateObjectiveStatus(objectiveId: id, status: status)
  → emits .objectiveStatusUpdateRequested
  → StateCoordinator subscribes and handles
  → emits .objectiveStatusChanged confirmation

// WRONG - Direct mutation
await stateCoordinator.setObjectiveStatus(id, status: .completed)
```

**Why**: Enables event logging, undo/redo, state synchronization, debugging

---

### 2. Cross-Component Communication (Always)
**Pattern**: Components that don't have tight processing relationship

**Example**: Tool execution → UI updates
```swift
// CORRECT
Tool returns .waiting(uiRequest: .choicePrompt(...))
  → ToolExecutionCoordinator emits .choicePromptRequested
  → ToolHandler subscribes and displays UI

// WRONG
tool.execute() → service.presentChoicePrompt()
```

**Why**: Decouples components, enables multiple subscribers, improves testability

---

### 3. Async Workflows (Always)
**Pattern**: Operations that involve async processing, user input, or long-running tasks

**Example**: Phase transitions
```swift
// CORRECT
await coordinator.requestPhaseTransition(from: phase, to: nextPhase)
  → emits .phaseTransitionRequested
  → StateCoordinator validates and applies
  → emits .phaseTransitionApplied

// WRONG
await coordinator.setPhase(nextPhase)
```

**Why**: Allows validation, cancellation, progress tracking, error handling

---

### 4. Fan-Out Notifications (Always)
**Pattern**: One event needs to notify multiple subscribers

**Example**: LLM status changes
```swift
// CORRECT - Event allows multiple subscribers
await emit(.llmStatus(status: .busy))
  → StateCoordinator updates processing flag
  → UI updates spinner
  → Metrics collector tracks duration

// WRONG - Direct calls require calling each subscriber
coordinator.setProcessing(true)
ui.showSpinner()
metrics.startTracking()
```

**Why**: Loose coupling, extensibility, unknown number of interested parties

---

## Anti-Patterns to Avoid

### ❌ Service Layer Bypass
```swift
// WRONG - Tool directly accessing state
let artifacts = await service.coordinator.state.artifacts

// RIGHT - Tool queries through coordinator
let artifact = await service.coordinator.getArtifact(id: id)
```

### ❌ Event Bus Direct Access from Tools
```swift
// WRONG - Tool accessing event bus directly
await service.coordinator.eventBus.publish(.someEvent)

// RIGHT - Tool calls coordinator method
await service.coordinator.doSomething()
  → coordinator emits event internally
```

### ❌ Callback Lattice
```swift
// WRONG - Callback chains
tool.execute { result in
    service.handleResult(result) { processed in
        coordinator.complete(processed)
    }
}

// RIGHT - Event-driven flow
tool returns .immediate(result)
  → ToolExecutionCoordinator emits .toolCompleted
  → Subscribers handle as needed
```

### ❌ Polling Instead of Events
```swift
// WRONG - Timer-based polling
Timer.scheduledTimer(withTimeInterval: 0.1) {
    if await coordinator.isProcessing { ... }
}

// RIGHT - Event subscription
for await event in eventBus.stream(topic: .processing) {
    if case .processingStateChanged(let processing) = event { ... }
}
```

---

## Decision Tree

When connecting two components, ask:

```
1. Is this a state mutation?
   YES → Use events (always)
   NO → Continue

2. Are these components tightly coupled in a processing pipeline?
   YES → Direct call acceptable IF:
         - No state mutation
         - Receiving component is stateless processor
         - Receiving component still emits to event bus
   NO → Continue

3. Is this a read-only query for synchronous response?
   YES → Direct call through coordinator acceptable
   NO → Use events

4. Does this involve async workflow, user input, or multiple subscribers?
   YES → Use events (always)
```

---

## Architecture Layers

```
┌─────────────────────────────────────────┐
│              Tools Layer                 │
│  (Call coordinator methods only)         │
└──────────────────┬──────────────────────┘
                   │
┌──────────────────▼──────────────────────┐
│         Coordinator Layer                │
│  - Provides query methods (read-only)    │
│  - Emits events for state changes        │
│  - Never exposes eventBus directly       │
│  - Never exposes StateCoordinator        │
└──────────────────┬──────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
┌───────▼────────┐   ┌────────▼─────────┐
│  Event Bus      │   │ StateCoordinator │
│  (pub/sub)      │   │ (single source)  │
└───────┬────────┘   └────────▲─────────┘
        │                     │
        │    ┌────────────────┘
        │    │
┌───────▼────▼────────────────────────────┐
│           Handlers Layer                 │
│  - Subscribe to events                   │
│  - Process and emit new events           │
│  - May query StateCoordinator (read)     │
│  - Update state via events only          │
└─────────────────────────────────────────┘
```

---

## Examples from Codebase

### ✅ Correct Patterns

**Objective Status Update (State Mutation)**
```swift
// SetObjectiveStatusTool.swift
let result = try await service.coordinator.updateObjectiveStatus(
    objectiveId: objectiveId,
    status: status
)
// → Coordinator emits .objectiveStatusUpdateRequested
// → StateCoordinator subscribes, updates, emits .objectiveStatusChanged
```

**Artifact Query (Read-Only)**
```swift
// GetArtifactRecordTool.swift
if let artifact = await service.coordinator.getArtifact(id: artifactId) {
    return .immediate(artifact)
}
// → Coordinator queries StateCoordinator.artifacts directly (read-only)
```

**Timeline Card Creation (State Mutation)**
```swift
// CreateTimelineCardTool.swift
let result = await service.coordinator.createTimelineCard(fields: fields)
// → Coordinator emits .timelineCardCreated
// → StateCoordinator subscribes and updates artifacts.skeletonTimeline
```

**LLM Stream Processing (Tight Pipeline)**
```swift
// LLMMessenger.swift
let stream = try await service.responseCreateStream(request)
for try await streamEvent in stream {
    await networkRouter.handleResponseEvent(streamEvent)  // Direct call OK
    // → NetworkRouter emits .streamingMessageUpdated, .toolCallRequested, etc.
}
```

---

## Testing Implications

**Benefits of Event-Driven Design:**
1. **Testability**: Subscribe to events and verify emissions
2. **Isolation**: Test components without dependencies
3. **Observability**: Event log shows entire system behavior
4. **Debugging**: Trace events to find issues
5. **Extensibility**: Add subscribers without modifying publishers

**Testing Pattern:**
```swift
// Test tool event emission
let events: [OnboardingEvent] = []
for await event in eventBus.stream(topic: .objective) {
    events.append(event)
    if case .objectiveStatusChanged = event { break }
}

// Verify correct event emitted
XCTAssertEqual(events.count, 1)
XCTAssertCase(events[0], .objectiveStatusChanged(id: "test", status: "completed"))
```

---

## Code Review Checklist

When reviewing PRs, verify:

- [ ] State mutations go through events (not direct calls)
- [ ] Tools only access coordinator methods (not eventBus, not StateCoordinator)
- [ ] Coordinator methods emit events for mutations, query for reads
- [ ] No timer-based polling (use event subscriptions)
- [ ] No callback chains (use event flows)
- [ ] Components communicate through events (not direct coupling)
- [ ] Direct calls justified with comment explaining tight coupling

---

## Migration Notes

**If you find direct coupling:**

1. Identify if it's a state mutation → Must use events
2. Identify if it's cross-component communication → Must use events
3. If neither, check if it fits tight pipeline or read query pattern
4. Document justification in code comment
5. Consider future extensibility needs

**Red Flags:**
- `eventBus` accessed from Tools
- `StateCoordinator` accessed directly (bypass coordinator)
- Timer-based polling instead of subscriptions
- Callback parameters in method signatures
- Direct service method calls from UI
