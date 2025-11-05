# Testing Event-First Architecture

This document describes how to verify that the event-first architecture is working correctly for applicant profile, skeleton timeline, enabled sections, and waiting state management.

## Architecture Overview

All state mutations for applicant profile, timeline, sections, and waiting state now happen via events reduced by `StateCoordinator`. The `OnboardingInterviewCoordinator` no longer directly calls state mutators.

### Event Flow

1. **Event Publication**: Components publish events like `.applicantProfileStored(profile)` to the event bus
2. **Event Routing**: EventCoordinator routes events to appropriate topic streams
3. **Event Reduction**: StateCoordinator subscribes to events and applies state mutations
4. **Side Effects**: OnboardingInterviewCoordinator handles side effects (e.g., SwiftData persistence, checkpointing)

## Events Tested

### 1. Applicant Profile Storage

**Event**: `.applicantProfileStored(JSON)`
**Topic**: `.state`
**Handler**: `StateCoordinator.handleStateEvent()`
**Expected Behavior**:
- StateCoordinator receives event and calls `setApplicantProfile()`
- `applicant_profile` objective is marked as completed
- Log message: "👤 Applicant profile stored via event"
- OnboardingInterviewCoordinator persists to SwiftData as a side effect

**How to Test**:
```swift
// Publish event
await eventBus.publish(.applicantProfileStored(profileJSON))

// Verify state was updated
let profile = await stateCoordinator.artifacts.applicantProfile
assert(profile != nil)

// Verify objective was completed
let status = await stateCoordinator.getObjectiveStatus("applicant_profile")
assert(status == .completed)
```

### 2. Skeleton Timeline Storage

**Event**: `.skeletonTimelineStored(JSON)`
**Topic**: `.state`
**Handler**: `StateCoordinator.handleStateEvent()`
**Expected Behavior**:
- StateCoordinator receives event and calls `setSkeletonTimeline()`
- `skeleton_timeline` objective is marked as completed
- Log message: "📅 Skeleton timeline stored via event"

**How to Test**:
```swift
// Publish event
await eventBus.publish(.skeletonTimelineStored(timelineJSON))

// Verify state was updated
let timeline = await stateCoordinator.artifacts.skeletonTimeline
assert(timeline != nil)

// Verify objective was completed
let status = await stateCoordinator.getObjectiveStatus("skeleton_timeline")
assert(status == .completed)
```

### 3. Enabled Sections Update

**Event**: `.enabledSectionsUpdated(Set<String>)`
**Topic**: `.state`
**Handler**: `StateCoordinator.handleStateEvent()`
**Expected Behavior**:
- StateCoordinator receives event and calls `setEnabledSections()`
- `enabled_sections` objective is marked as completed if sections are not empty
- Log message: "📑 Enabled sections updated via event (N sections)"

**How to Test**:
```swift
// Publish event
let sections: Set<String> = ["summary", "experience", "education"]
await eventBus.publish(.enabledSectionsUpdated(sections))

// Verify state was updated
let enabledSections = await stateCoordinator.artifacts.enabledSections
assert(enabledSections == sections)

// Verify objective was completed
let status = await stateCoordinator.getObjectiveStatus("enabled_sections")
assert(status == .completed)
```

### 4. Waiting State Changes with Tool Gating

**Event**: `.waitingStateChanged(String?)`
**Topic**: `.processing`
**Handler**: `StateCoordinator.handleProcessingEvent()`
**Expected Behavior**:

#### Setting Waiting State
- StateCoordinator receives event and converts string to `WaitingState` enum
- `waitingState` is updated
- Restricted tool set is emitted (empty set during waiting)
- Log message: "🚫 Waiting state set to [state] - tools restricted"
- `.stateAllowedToolsUpdated(tools: [])` event is published

#### Clearing Waiting State
- StateCoordinator receives event with `nil` waiting state
- `waitingState` is set to `nil`
- Normal allowed tools are emitted based on current phase
- Log message: "✅ Waiting state cleared - tools restored"
- `.stateAllowedToolsUpdated(tools: allowedToolsForPhase)` event is published

**How to Test**:
```swift
// Test setting waiting state
await eventBus.publish(.waitingStateChanged("upload"))

// Verify state was updated
let waitingState = await stateCoordinator.waitingState
assert(waitingState == .upload)

// Verify tools were restricted (subscribe to .stateAllowedToolsUpdated event)
// Expected: empty set

// Test clearing waiting state
await eventBus.publish(.waitingStateChanged(nil))

// Verify state was cleared
let clearedState = await stateCoordinator.waitingState
assert(clearedState == nil)

// Verify tools were restored
// Expected: phase-appropriate tool set
```

## Event Sequence Logging

The following log messages indicate correct event flow:

1. **Before State Change**: Event publication is logged by EventCoordinator
2. **During State Change**: StateCoordinator logs the mutation
3. **After State Change**: Side effects (checkpointing, persistence) are logged

### Example Log Sequence for Applicant Profile

```
[Event] Profile stored                                 // EventCoordinator
👤 Applicant profile stored via event                  // StateCoordinator
✅ Objective applicant_profile: pending → completed    // StateCoordinator
💾 Applicant profile persisted to SwiftData           // OnboardingInterviewCoordinator
💾 Checkpoint saved                                    // OnboardingInterviewCoordinator
```

## Manual Verification Steps

1. **Enable Debug Logging**: Set logging level to `.debug` to see all event flows

2. **Trigger Profile Storage**:
   - Run the onboarding interview
   - Complete the applicant profile intake
   - Check logs for event sequence

3. **Trigger Timeline Storage**:
   - Create or update timeline cards
   - Verify events are published and reduced

4. **Trigger Section Toggle**:
   - Use section toggle UI
   - Verify enabled sections are updated via events

5. **Trigger Waiting States**:
   - Trigger file upload flow (should set waiting state to "upload")
   - Verify tools are restricted (check `.stateAllowedToolsUpdated` event)
   - Complete or cancel upload
   - Verify tools are restored

## Acceptance Criteria

✅ No coordinator function directly calls StateCoordinator mutators for these domains
✅ All state changes flow through events and are observable in event logs
✅ Allowed/restricted tool sets update automatically when waiting state changes
✅ Publishing `.enabledSectionsUpdated` updates `StateCoordinator.artifacts.enabledSections`
✅ Log output shows event sequence before mutation

## Known Consumers

These events may be published by:
- Tool implementations (after tool execution completes)
- Handlers (ProfileInteractionHandler, SectionToggleHandler)
- InterviewOrchestrator (during conversation flow)
- Manual test code

Note: If events are not currently being published from tools/handlers, you will need to add event publications at the appropriate points where state changes are intended.
