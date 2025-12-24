# Onboarding Module Refactoring Plan

## Overview

This plan addresses issues identified in the Onboarding module analysis and quality assessment. The refactoring emphasizes **complete implementation** with no stubs, placeholders, or backwards compatibility shims.

**Guiding Principle:** If adopting a new paradigm, fully implement it. Delete old code completely. No data migration is required.

---

## Work Streams (Parallelizable)

The refactoring is organized into **5 independent work streams** that can be executed in parallel by AI subagents. Each stream has clear boundaries and minimal dependencies on other streams.

### Work Stream 1: Type Safety & Codable Migration

**Scope:** Replace SwiftyJSON with native Swift Codable types throughout the onboarding module.

**Files Affected:**
- `Sprung/Onboarding/Models/*.swift`
- `Sprung/Onboarding/Tools/Implementations/*.swift`
- `Sprung/Onboarding/Core/*.swift`

**Tasks:**

1. **Create Codable structs for all internal data types**
   - `TimelineEntry` struct with full Codable conformance
   - `KnowledgeCard` struct with full Codable conformance
   - `ApplicantProfileData` struct (distinct from the SwiftData model)
   - `ToolResponse` generic wrapper for typed responses

2. **Migrate Tool implementations to use Codable**
   - Replace `JSON(params["fields"].dictionary!)` patterns with proper decoding
   - Use `JSONDecoder` at tool boundary, pass typed structs internally
   - Remove all force unwrapping after helper checks

3. **Delete `TimelineEntryDraft.swift`**
   - Consolidate to `TimelineCard` struct and `TimelineCardViewModel`
   - Update `TimelineCardAdapter` to remove conversion boilerplate
   - Update `TimelineCardEditorView` to use consolidated types

4. **Fix force unwrapping in tool execution**
   - `CreateTimelineCardTool.swift`: Bind `requireObject` result directly
   - Apply same pattern to all tools using `ToolResultHelpers`

**Commit Cadence:** Commit after each major type migration (one commit per model type, one commit per tool file updated).

---

### Work Stream 2: Event Bus Segmentation

**Scope:** Refactor the monolithic `OnboardingEvent` enum into domain-specific event channels.

**Files Affected:**
- `Sprung/Onboarding/Core/Events/OnboardingEvent.swift`
- `Sprung/Onboarding/Core/Events/EventCoordinator.swift`
- `Sprung/Onboarding/Core/Coordinators/CoordinatorEventRouter.swift`
- All event subscribers

**Tasks:**

1. **Define segmented event enums**
   ```swift
   enum LLMStreamEvent { case chunkReceived, streamComplete, streamError }
   enum UIEvent { case sheetPresented, sheetDismissed, viewTransition }
   enum DataEvent { case artifactCreated, artifactUpdated, profileMerged }
   enum ToolEvent { case toolStarted, toolCompleted, toolFailed }
   enum PhaseEvent { case phaseStarted, phaseCompleted, objectiveUpdated }
   ```

2. **Create typed event bus channels**
   - `LLMEventChannel` for streaming events
   - `UIEventChannel` for view state changes
   - `DataEventChannel` for data mutations
   - `ToolEventChannel` for tool lifecycle
   - `PhaseEventChannel` for interview phase transitions

3. **Migrate subscribers to appropriate channels**
   - Update `CoordinatorEventRouter` to handle segmented events
   - Remove the massive switch statement, replace with focused handlers
   - Delete `stripHeavyPayloads` debug function entirely

4. **Use typed enum values instead of strings**
   - Replace `if id == "applicant_profile"` with `if id == OnboardingObjectiveId.applicantProfile`
   - Apply throughout `CoordinatorEventRouter`

**Commit Cadence:** Commit after defining each event enum, commit after migrating each subscriber group.

---

### Work Stream 3: UI Component Extraction & State Consolidation

**Scope:** Extract massive view bodies into focused components, consolidate UI state management.

**Files Affected:**
- `Sprung/Onboarding/Views/Components/OnboardingInterviewChatPanel.swift`
- `Sprung/Onboarding/Views/OnboardingInterviewView.swift`
- `Sprung/Onboarding/Views/OnboardingCompletionReviewSheet.swift`
- `Sprung/Onboarding/Core/OnboardingUIState.swift`
- `Sprung/Onboarding/Core/SessionUIState.swift`

**Tasks:**

1. **Extract chat panel components**
   - Create `ComposerView.swift` - input field and send button
   - Create `BannerView.swift` - status banners and notifications
   - Create `MessageListView.swift` - scrolling message container
   - Update `OnboardingInterviewChatPanel` to compose these components

2. **Create focused ViewModels for sub-views**
   - `DocumentCollectionViewModel` - document management state
   - `TimelineViewModel` - timeline editing state
   - `ChatPanelViewModel` - message input and display state
   - Each ViewModel exposes only what its view needs

3. **Consolidate `OnboardingUIState` and `SessionUIState`**
   - Audit both classes for overlapping responsibilities
   - Create single `OnboardingSessionState` with clear sections:
     - UI visibility state (sheets, alerts)
     - Processing state (loading, busy)
     - Permission state (tool gating)

4. **Implement ExtractionReviewSheet confirmation**
   - Delete stub: `Logger.debug("Extraction confirmation is not implemented...")`
   - Implement merge logic for extraction JSON into ApplicantProfile
   - Or remove the sheet entirely if handled by `DocumentArtifactHandler`

5. **Remove developer meta-commentary**
   - Delete `OnboardingCompletionReviewSheet.swift` placeholder text
   - Implement proper completion review UI or simplify

**Commit Cadence:** Commit after each extracted component, commit after ViewModel creation, commit after state consolidation.

---

### Work Stream 4: Configuration Externalization

**Scope:** Move hardcoded values, prompts, and schemas to external configuration.

**Files Affected:**
- `Sprung/Onboarding/Tools/Implementations/NextPhaseTool.swift`
- `Sprung/Onboarding/Scripts/*.swift`
- `Sprung/Onboarding/Services/DocumentExtractionService.swift`
- `Sprung/Onboarding/Core/SessionUIState.swift`

**Tasks:**

1. **Externalize phase transition logic**
   - Move `switch currentPhase` from `NextPhaseTool` to `PhaseScriptRegistry`
   - `NextPhaseTool` becomes generic trigger calling `registry.nextPhase(after:)`
   - Delete all hardcoded phase transitions in tool implementations

2. **Centralize model configuration**
   - Create `OnboardingModelConfig.swift` (or extend existing)
   - Move `defaultModelId = "gemini-2.0-flash"` to config
   - Move all `UserDefaults` model ID lookups to config
   - Delete hardcoded model IDs from `DocumentExtractionService`

3. **Create unified `PromptLibrary`**
   - Move prompts from `PhaseOneScript`, `KCAgentPrompts`, `DocumentExtractionPrompts`, `AgentReadyTool`
   - Organize by domain: interview prompts, extraction prompts, agent prompts
   - Use resource files (`.txt` or `.json`) for large prompts

4. **Centralize tool groupings**
   - Move `ToolGating.timelineTools` Set to `OnboardingToolName.timelineTools`
   - Reuse in `PhaseScript` definitions
   - Delete duplicate tool set definitions

5. **Create `DocumentTypePolicy` struct**
   - Consolidate extension sets from:
     - `DropZoneHandler.acceptedExtensions`
     - `DocumentArtifactMessenger.extractableExtensions`
     - `DocumentArtifactHandler.extractableExtensions`
     - `DocumentExtractionService` extension checks
   - Single source of truth for accepted/extractable/image extensions

**Commit Cadence:** Commit after each configuration externalization (prompts, models, tool groups, document types).

---

### Work Stream 5: Actor Isolation & Concurrency Fixes

**Scope:** Fix race conditions and actor isolation issues, remove unsafe patterns.

**Files Affected:**
- `Sprung/Onboarding/Core/ArtifactRepository.swift`
- `Sprung/Onboarding/Core/AgentActivityTracker.swift`
- Various coordinator files

**Tasks:**

1. **Remove `nonisolated(unsafe)` from ArtifactRepository**
   - Delete `nonisolated(unsafe) private(set) var artifactRecordsSync`
   - Use `@MainActor` on `OnboardingUIState` for view-safe data
   - Implement async event emission for UI state updates
   - Ensure actor boundaries are respected

2. **Audit and fix all actor isolation warnings**
   - Review all `@MainActor` annotations
   - Ensure services that don't need UI thread access don't have `@MainActor`
   - Use `Task { @MainActor in }` for callback assignments

3. **Fix unused/misused properties in AgentActivityTracker**
   - Clarify `cachedTokens` vs `totalTokens` semantics
   - Either factor cached tokens into total or remove the property
   - Update UI display to reflect accurate token accounting

4. **Fix Git agent author filter logic**
   - `AgentPrompts.authorFilter` currently locks to first contributor
   - Implement proper author selection or remove filter if not needed

**Commit Cadence:** Commit after each actor isolation fix, commit after tracker cleanup.

---

## Sequential Dependencies

While work streams are mostly parallel, observe these dependencies:

1. **Stream 1 (Codable) should complete before Stream 2 (Events)** can fully migrate event payloads to typed data
2. **Stream 3 (UI)** can start immediately but final state consolidation should wait for **Stream 2** event refactoring
3. **Stream 4 (Config)** is fully independent
4. **Stream 5 (Concurrency)** is fully independent

**Recommended execution order:**
- Start immediately: Streams 1, 3 (component extraction only), 4, 5
- After Stream 1 completes: Stream 2, Stream 3 (state consolidation)

---

## Deleted Items Checklist

The following MUST be deleted (not commented out, not deprecated—deleted):

- [ ] `TimelineEntryDraft.swift` - entire file
- [ ] `Logger.debug("Extraction confirmation is not implemented in milestone M0.")` - stub
- [ ] `Text("This screen is a first pass...")` - placeholder UI text
- [ ] `nonisolated(unsafe)` declarations
- [ ] `stripHeavyPayloads` debug function
- [ ] Hardcoded phase transitions in `NextPhaseTool`
- [ ] Hardcoded model IDs in services
- [ ] Duplicate extension sets across files
- [ ] `OnboardingToolName.getUserOption` if unused

---

## Verification Criteria

After refactoring, verify:

1. **No SwiftyJSON in business logic** - only at API boundaries
2. **No force unwraps** after helper validation calls
3. **No massive switch statements** - event routing is segmented
4. **No duplicate type definitions** - one source of truth per model
5. **No UI stubs or placeholders** - all features implemented or removed
6. **No `nonisolated(unsafe)`** - proper actor isolation
7. **No hardcoded configuration** - all externalized
8. **Build succeeds** with no warnings related to actor isolation
