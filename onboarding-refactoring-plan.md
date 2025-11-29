# Onboarding Module Refactoring Plan

**Version**: 1.1
**Date**: November 28, 2025
**Total Estimated Effort**: 12-14 developer days

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Design Decision: JSON as Internal Format](#design-decision-json-as-internal-format)
3. [Phase 1: OnboardingInterviewCoordinator Decomposition](#phase-1-onboardinginterviewcoordinator-decomposition)
4. [Phase 2: StateCoordinator Decomposition](#phase-2-statecoordinator-decomposition)
5. [Phase 3: Magic String Centralization](#phase-3-magic-string-centralization)
6. [Phase 4: Targeted Type Safety Improvements](#phase-4-targeted-type-safety-improvements)
7. [Implementation Order and Dependencies](#implementation-order-and-dependencies)
8. [Risk Mitigation](#risk-mitigation)

---

## Executive Summary

This plan addresses the major technical debt items identified in the code audits, prioritized by actual impact:

| Initiative | Current State | Target State | Effort | Priority |
|------------|--------------|--------------|--------|----------|
| Coordinator Decomposition | 2 god objects (809 + 820 LOC) | 8-10 focused components | 5 days | **1 (Highest)** |
| StateCoordinator Split | Monolithic event handler | Domain-specific actors | 5 days | **2** |
| Magic String Centralization | Scattered string literals | Centralized enums | 2 days | **3** |
| Targeted Type Safety | Verbose JSON in views | Typed wrappers where needed | 1-2 days | **4** |

**Key Principle**: Each refactoring phase is designed to be independently shippable with no regressions.

---

## Design Decision: JSON as Internal Format

### Why We're Keeping JSON

The onboarding module communicates with an LLM via the OpenAI API. JSON is the native format at both boundaries:
- **Inbound**: Tool parameters arrive as JSON from the LLM
- **Outbound**: Tool results return as JSON to the LLM
- **Persistence**: `InterviewDataStore` serializes JSON directly

Given this architecture, **converting to typed models internally would require**:
1. JSON → Codable decoding at entry
2. Typed processing
3. Codable → JSON encoding at exit

This adds complexity and potential failure points with minimal benefit.

### When JSON Is Actually Problematic

| Scenario | JSON Works Fine | Typed Models Help |
|----------|-----------------|-------------------|
| LLM tool params → execute | ✅ Schema enforces structure | Marginal benefit |
| Tool result → LLM | ✅ LLM parses anything | Marginal benefit |
| Internal service → service | ✅ Structure is stable | Marginal benefit |
| Persistence → restore | ✅ Same format in/out | Marginal benefit |
| **SwiftUI View binding** | ⚠️ Verbose `json["field"]` | ✅ Clean property access |
| **Complex nested access** | ⚠️ No autocomplete | ✅ IDE support |

### Conclusion

We will **keep JSON as the primary internal format** and only add typed wrappers in Phase 4 for specific pain points (view layer, frequently accessed nested structures).

This reduces the original Phase 3 estimate from **6 days to 1-2 days**.

---

## Phase 1: OnboardingInterviewCoordinator Decomposition

### 1.1 Current State Analysis

`OnboardingInterviewCoordinator.swift` (809 LOC) currently handles:
- **Initialization**: ~200 lines of dependency wiring (lines 93-294)
- **Service Updates**: OpenAI service lifecycle (lines 296-315)
- **Event Routing**: State update subscriptions (lines 316-431)
- **Interview Lifecycle**: Start/end/restore (lines 432-491)
- **Phase Management**: Advance, objectives (lines 496-527)
- **Timeline Operations**: CRUD facade (lines 528-564)
- **Artifact Queries**: Read-only accessors (lines 565-590)
- **Tool Interaction**: UI tool facades (lines 618-728)
- **Data Persistence**: Load/clear/reset (lines 731-742)
- **Debug Utilities**: Event diagnostics (lines 758-807)

### 1.2 Proposed Decomposition

```
┌─────────────────────────────────────────────────────────────────┐
│            OnboardingInterviewCoordinator (Facade)              │
│                        ~150 LOC (target)                        │
│  - Public API surface only                                      │
│  - Delegates to specialized coordinators                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │
    ┌───────────────────────┼───────────────────────────────────┐
    │                       │                                   │
    ▼                       ▼                                   ▼
┌─────────────┐    ┌─────────────────┐    ┌──────────────────────┐
│ Interview   │    │ Artifact        │    │ Tool                 │
│ Session     │    │ Query           │    │ Interaction          │
│ Coordinator │    │ Coordinator     │    │ Coordinator          │
│ ~150 LOC    │    │ ~80 LOC         │    │ (exists: 145 LOC)    │
└─────────────┘    └─────────────────┘    └──────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────┐
│                   DependencyContainer                           │
│  - Owns all service instances                                   │
│  - Wiring extracted from coordinator init                       │
│  ~200 LOC                                                       │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 Detailed Tasks

#### Task 1.3.1: Extract DependencyContainer
**Effort**: 1 day
**Risk**: Low

Extract the 200-line initialization block into a dedicated dependency container:

```swift
// New file: Core/DependencyContainer.swift
@MainActor
final class OnboardingDependencyContainer {
    // MARK: - Core Services
    let eventBus: EventCoordinator
    let state: StateCoordinator
    let toolRegistry: ToolRegistry
    let phaseRegistry: PhaseScriptRegistry

    // MARK: - Handlers
    let toolRouter: ToolHandler
    let chatboxHandler: ChatboxHandler
    let toolExecutionCoordinator: ToolExecutionCoordinator

    // MARK: - Controllers
    let lifecycleController: InterviewLifecycleController
    let checkpointManager: CheckpointManager
    let phaseTransitionController: PhaseTransitionController

    // MARK: - Services
    let extractionManagementService: ExtractionManagementService
    let timelineManagementService: TimelineManagementService
    let dataPersistenceService: DataPersistenceService
    let ingestionCoordinator: IngestionCoordinator

    // ... factory methods

    init(
        openAIService: OpenAIService?,
        documentExtractionService: DocumentExtractionService,
        applicantProfileStore: ApplicantProfileStore,
        dataStore: InterviewDataStore,
        checkpoints: Checkpoints,
        preferences: OnboardingPreferences
    ) {
        // Move initialization logic here
    }
}
```

**Files to modify**:
- Create: `Core/DependencyContainer.swift`
- Modify: `OnboardingInterviewCoordinator.swift` (remove init logic, inject container)

---

#### Task 1.3.2: Extract InterviewSessionCoordinator
**Effort**: 0.5 days
**Risk**: Low

Move interview lifecycle methods (start/end/restore):

```swift
// New file: Core/Coordinators/InterviewSessionCoordinator.swift
@MainActor
final class InterviewSessionCoordinator {
    private let lifecycleController: InterviewLifecycleController
    private let checkpointManager: CheckpointManager
    private let state: StateCoordinator
    private let dataPersistenceService: DataPersistenceService

    func startInterview(resumeExisting: Bool) async -> Bool { ... }
    func endInterview() async { ... }
    func restoreFromCheckpoint(_ checkpoint: OnboardingCheckpoint) async { ... }
}
```

**Methods to extract** (from OnboardingInterviewCoordinator):
- `startInterview(resumeExisting:)` (lines 433-477)
- `endInterview()` (lines 478-482)
- `restoreFromSpecificCheckpoint(_:)` (lines 483-491)
- `loadPersistedArtifacts()` (lines 732-734)
- `clearArtifacts()` (lines 735-739)
- `resetStore()` (lines 740-742)

---

#### Task 1.3.3: Extract ArtifactQueryCoordinator
**Effort**: 0.5 days
**Risk**: Low

Consolidate artifact read operations:

```swift
// New file: Core/Coordinators/ArtifactQueryCoordinator.swift
@MainActor
final class ArtifactQueryCoordinator {
    private let state: StateCoordinator

    func listArtifactSummaries() async -> [JSON] { ... }
    func listArtifactRecords() async -> [JSON] { ... }
    func getArtifactRecord(id: String) async -> JSON? { ... }
    func getArtifact(id: String) async -> JSON? { ... }
}
```

**Methods to extract**:
- `listArtifactSummaries()` (line 566-568)
- `listArtifactRecords()` (line 569-571)
- `getArtifactRecord(id:)` (line 572-574)
- `getArtifact(id:)` (lines 578-587)
- `requestArtifactMetadataUpdate(artifactId:updates:)` (lines 575-577)

---

#### Task 1.3.4: Consolidate Event Handlers
**Effort**: 1 day
**Risk**: Medium

The `CoordinatorEventRouter` already exists but event handling is split. Consolidate:

```swift
// Modify: Core/Coordinators/CoordinatorEventRouter.swift
// Move these handler methods from OnboardingInterviewCoordinator:
// - handleProcessingEvent(_:) (lines 341-366)
// - handleArtifactEvent(_:) (lines 367-376)
// - handleLLMEvent(_:) (lines 377-403)
// - handleStateSyncEvent(_:) (lines 404-413)
// - syncWizardProgressFromState() (lines 414-426)
// - initialStateSync() (lines 427-431)
```

---

#### Task 1.3.5: Slim Down Main Coordinator
**Effort**: 0.5 days
**Risk**: Low

After extractions, `OnboardingInterviewCoordinator` becomes a thin facade:

```swift
@MainActor
@Observable
final class OnboardingInterviewCoordinator {
    // MARK: - Public Dependencies (for View access)
    let ui: OnboardingUIState
    let wizardTracker: WizardProgressTracker
    let checkpoints: Checkpoints

    // MARK: - Internal Coordinators
    private let container: OnboardingDependencyContainer
    private let sessionCoordinator: InterviewSessionCoordinator
    private let artifactCoordinator: ArtifactQueryCoordinator
    private let toolInteractionCoordinator: ToolInteractionCoordinator

    // MARK: - Facade Methods (delegate to sub-coordinators)
    func startInterview(resumeExisting: Bool) async -> Bool {
        await sessionCoordinator.startInterview(resumeExisting: resumeExisting)
    }

    // ... remaining ~30-40 facade methods
}
```

---

### 1.4 Phase 1 Effort Summary

| Task | Effort | Dependencies |
|------|--------|--------------|
| 1.3.1 DependencyContainer | 1 day | None |
| 1.3.2 InterviewSessionCoordinator | 0.5 days | 1.3.1 |
| 1.3.3 ArtifactQueryCoordinator | 0.5 days | 1.3.1 |
| 1.3.4 Consolidate Event Handlers | 1 day | 1.3.1 |
| 1.3.5 Slim Down Coordinator | 0.5 days | All above |
| Testing & Integration | 1.5 days | All above |
| **Phase 1 Total** | **5 days** | |

---

## Phase 2: StateCoordinator Decomposition

### 2.1 Current State Analysis

`StateCoordinator.swift` (820 LOC) handles:
- **Event Subscriptions**: 8 topic handlers (lines 150-200)
- **Event Processing**: Switch statements spanning lines 202-419
- **Stream Queue Management**: Complex serial streaming logic (lines 420-530)
- **LLM State**: Tool names, response IDs, model config (lines 535-557)
- **Snapshot Management**: Checkpoint serialization (lines 558-665)
- **Delegation Methods**: 40+ pass-through methods (lines 686-820)

### 2.2 Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    StateCoordinator (Orchestrator)              │
│                          ~300 LOC (target)                      │
│  - Event routing only                                           │
│  - Delegates to domain-specific actors                          │
└───────────────────────────┬─────────────────────────────────────┘
                            │
    ┌───────────────┬───────┴───────┬───────────────┐
    │               │               │               │
    ▼               ▼               ▼               ▼
┌─────────┐  ┌───────────┐  ┌───────────┐  ┌───────────────┐
│ Stream  │  │ LLM State │  │ Objective │  │ Artifact      │
│ Queue   │  │ Manager   │  │ Store     │  │ Repository    │
│ Manager │  │ (NEW)     │  │ (exists)  │  │ (exists)      │
│ ~150 LOC│  │ ~80 LOC   │  │ 327 LOC   │  │ 294 LOC       │
└─────────┘  └───────────┘  └───────────┘  └───────────────┘
```

### 2.3 Detailed Tasks

#### Task 2.3.1: Extract StreamQueueManager
**Effort**: 1.5 days
**Risk**: High (complex state machine)

Extract the serial streaming queue logic:

```swift
// New file: Core/StreamQueueManager.swift
actor StreamQueueManager {
    enum StreamRequestType {
        case userMessage(payload: JSON, isSystemGenerated: Bool)
        case toolResponse(payload: JSON)
        case batchedToolResponses(payloads: [JSON])
        case developerMessage(payload: JSON)
    }

    private var isStreaming = false
    private var streamQueue: [StreamRequestType] = []
    private var expectedToolResponseCount: Int = 0
    private var expectedToolCallIds: Set<String> = []
    private var collectedToolResponses: [JSON] = []

    func enqueue(_ request: StreamRequestType) { ... }
    func markStreamCompleted() { ... }
    func processQueue() async { ... }
}
```

**Methods to extract** (from StateCoordinator):
- `enqueueStreamRequest(_:)` (lines 422-430)
- `enqueueBatchedToolResponses(_:)` (lines 432-440)
- `processStreamQueue()` (lines 443-486)
- `hasPendingToolResponse()` (lines 488-494)
- `emitStreamRequest(_:)` (lines 496-507)
- `markStreamCompleted()` (lines 510-514)
- `handleStreamCompleted()` (lines 516-530)

**Risk Mitigation**: This is the most complex extraction. Add comprehensive logging and create a state machine diagram before refactoring.

---

#### Task 2.3.2: Extract LLMStateManager
**Effort**: 0.5 days
**Risk**: Low

Consolidate LLM configuration state:

```swift
// New file: Core/LLMStateManager.swift
actor LLMStateManager {
    private var allowedToolNames: Set<String> = []
    private var lastResponseId: String?
    private var currentModelId: String = "gpt-5.1"
    private var hasStreamedFirstResponse = false

    func setAllowedTools(_ tools: Set<String>) { ... }
    func getAllowedTools() -> Set<String> { ... }
    func updateConversationState(responseId: String) { ... }
    func getLastResponseId() -> String? { ... }
    func setModelId(_ id: String) { ... }
    func getCurrentModelId() -> String { ... }
}
```

---

#### Task 2.3.3: Simplify Event Handlers
**Effort**: 1 day
**Risk**: Medium

Reduce handler complexity by delegating to existing services:

**Before** (StateCoordinator):
```swift
private func handleLLMEvent(_ event: OnboardingEvent) async {
    switch event {
    case .llmEnqueueUserMessage(let payload, let isSystemGenerated):
        enqueueStreamRequest(.userMessage(payload: payload, isSystemGenerated: isSystemGenerated))
    // ... 20+ more cases
    }
}
```

**After** (StateCoordinator delegates):
```swift
private func handleLLMEvent(_ event: OnboardingEvent) async {
    switch event {
    case .llmEnqueueUserMessage(let payload, let isSystemGenerated):
        await streamQueueManager.enqueue(.userMessage(payload: payload, isSystemGenerated: isSystemGenerated))
    case .llmToolCallBatchStarted(let expectedCount, let callIds):
        await streamQueueManager.startBatch(expectedCount: expectedCount, callIds: callIds)
    // Simpler delegation
    }
}
```

---

#### Task 2.3.4: Remove Redundant Delegation Methods
**Effort**: 0.5 days
**Risk**: Low

StateCoordinator has ~40 delegation methods that simply forward to injected services. Many can be removed by having callers access services directly:

**Current** (unnecessary indirection):
```swift
// StateCoordinator
func getObjectiveStatus(_ id: String) async -> ObjectiveStatus? {
    await objectiveStore.getObjectiveStatus(id)
}

// Caller
let status = await state.getObjectiveStatus("applicant_profile")
```

**After** (direct access):
```swift
// Caller accesses ObjectiveStore directly via DependencyContainer
let status = await container.objectiveStore.getObjectiveStatus("applicant_profile")
```

**Candidates for removal** (lines 686-820):
- Objective delegation: 6 methods
- Artifact delegation: 8 methods
- Chat delegation: 10 methods
- UI State delegation: 8 methods

**Note**: Some delegation may be intentional for encapsulation. Review each case.

---

### 2.4 Phase 2 Effort Summary

| Task | Effort | Dependencies |
|------|--------|--------------|
| 2.3.1 StreamQueueManager | 1.5 days | None |
| 2.3.2 LLMStateManager | 0.5 days | None |
| 2.3.3 Simplify Event Handlers | 1 day | 2.3.1, 2.3.2 |
| 2.3.4 Remove Redundant Methods | 0.5 days | Phase 1 complete |
| Testing & Integration | 1.5 days | All above |
| **Phase 2 Total** | **5 days** | |

---

## Phase 3: Magic String Centralization

### 3.1 Current Issues

String literals scattered throughout:
- Tool names: `"create_timeline_card"`, `"get_user_upload"`, etc.
- Objective IDs: `"applicant_profile"`, `"skeleton_timeline"`, etc.
- Event topics: Referenced by raw strings in some places
- Data types: `"applicant_profile"`, `"artifact_record"`, etc.

### 3.2 Solution

```swift
// New file: Constants/OnboardingConstants.swift

enum OnboardingToolName: String, CaseIterable {
    case agentReady = "agent_ready"
    case getUserOption = "get_user_option"
    case getApplicantProfile = "get_applicant_profile"
    case getUserUpload = "get_user_upload"
    case cancelUserUpload = "cancel_user_upload"
    case createTimelineCard = "create_timeline_card"
    case updateTimelineCard = "update_timeline_card"
    case deleteTimelineCard = "delete_timeline_card"
    case reorderTimelineCards = "reorder_timeline_cards"
    case displayTimelineEntriesForReview = "display_timeline_entries_for_review"
    case submitForValidation = "submit_for_validation"
    case validateApplicantProfile = "validate_applicant_profile"
    case validatedApplicantProfileData = "validated_applicant_profile_data"
    case configureEnabledSections = "configure_enabled_sections"
    case listArtifacts = "list_artifacts"
    case getArtifact = "get_artifact"
    case requestRawFile = "request_raw_file"
    case nextPhase = "next_phase"
}

enum OnboardingObjectiveId: String, CaseIterable {
    // Phase 1
    case applicantProfile = "applicant_profile"
    case applicantProfileContactIntake = "applicant_profile.contact_intake"
    case applicantProfileContactIntakeActivateCard = "applicant_profile.contact_intake.activate_card"
    case applicantProfileContactIntakePersisted = "applicant_profile.contact_intake.persisted"
    case applicantProfileProfilePhoto = "applicant_profile.profile_photo"
    case skeletonTimeline = "skeleton_timeline"
    case enabledSections = "enabled_sections"
    case dossierSeed = "dossier_seed"
    case contactSourceSelected = "contact_source_selected"
    case contactDataCollected = "contact_data_collected"
    case contactDataValidated = "contact_data_validated"
    case contactPhotoCollected = "contact_photo_collected"

    // Phase 2
    case interviewedOneExperience = "interviewed_one_experience"
    case oneCardGenerated = "one_card_generated"
    case evidenceAuditCompleted = "evidence_audit_completed"
    case cardsGenerated = "cards_generated"

    // Phase 3
    case oneWritingSample = "one_writing_sample"
    case dossierComplete = "dossier_complete"
}

enum OnboardingDataType: String {
    case applicantProfile = "applicant_profile"
    case skeletonTimeline = "skeleton_timeline"
    case artifactRecord = "artifact_record"
    case knowledgeCard = "knowledge_card"
}
```

### 3.3 Usage Updates

**Before**:
```swift
// PhaseOneScript.swift
let requiredObjectives: [String] = [
    "applicant_profile",
    "skeleton_timeline",
    "enabled_sections"
]
```

**After**:
```swift
let requiredObjectives: [OnboardingObjectiveId] = [
    .applicantProfile,
    .skeletonTimeline,
    .enabledSections
]

// Convert to strings only at boundaries
var requiredObjectiveStrings: [String] {
    requiredObjectives.map { $0.rawValue }
}
```

### 3.4 Phase 3 Effort Summary

| Task | Effort |
|------|--------|
| Create OnboardingConstants.swift | 0.5 days |
| Update PhaseScripts | 0.25 days |
| Update ToolRegistry references | 0.25 days |
| Update ObjectiveStore references | 0.25 days |
| Update StateCoordinator references | 0.25 days |
| Testing & Integration | 0.5 days |
| **Phase 3 Total** | **2 days** |

---

## Phase 4: Targeted Type Safety Improvements

### 4.1 Rationale

Rather than wholesale JSON→Codable conversion (which adds complexity at boundaries), we target specific pain points where typed models provide clear value.

### 4.2 Targeted Improvements

#### 4.2.1 Add Codable to TimelineCard
**Effort**: 0.25 days

`TimelineCard` already exists as a typed struct. Add `Codable` for potential future use:

```swift
// Modify: Models/TimelineCard.swift
extension TimelineCard: Codable {}
```

This is free since all properties are already Codable-compatible.

---

#### 4.2.2 View Helper Extensions
**Effort**: 0.5 days

Add computed properties to reduce verbose JSON access in views:

```swift
// New file: Models/Extensions/JSONViewHelpers.swift

extension JSON {
    /// Formatted location string for display
    var formattedLocation: String? {
        let city = self["location"]["city"].string
        let region = self["location"]["region"].string
        return [city, region].compactMap { $0 }.joined(separator: ", ").nilIfEmpty
    }

    /// Display name with fallback
    var displayName: String {
        self["name"].string ?? self["title"].string ?? "Unknown"
    }

    /// Safe date string formatting
    var formattedDateRange: String? {
        guard let start = self["start"].string else { return nil }
        let end = self["end"].string ?? "Present"
        return "\(start) - \(end)"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
```

This keeps JSON as the data format but provides cleaner view code.

---

#### 4.2.3 Type-Safe Event Payloads (Optional)
**Effort**: 0.5 days

For frequently-used event payloads, create typed wrappers:

```swift
// Models/EventPayloads.swift

struct TimelineCardEventPayload {
    let id: String
    let fields: JSON

    init?(from json: JSON) {
        guard let id = json["id"].string else { return nil }
        self.id = id
        self.fields = json["fields"]
    }
}
```

This is optional - only implement if event handling becomes error-prone.

---

### 4.3 Phase 4 Effort Summary

| Task | Effort |
|------|--------|
| 4.2.1 TimelineCard Codable | 0.25 days |
| 4.2.2 View Helper Extensions | 0.5 days |
| 4.2.3 Event Payloads (optional) | 0.5 days |
| Testing | 0.25 days |
| **Phase 4 Total** | **1-1.5 days** |

---

## Implementation Order and Dependencies

```
Week 1:
┌─────────────────────────────────────────────────────────────────┐
│  Phase 1: Coordinator Decomposition (5 days)                    │
│  - Start with DependencyContainer extraction                    │
│  - Highest impact refactoring                                   │
└─────────────────────────────────────────────────────────────────┘

Week 2:
┌─────────────────────────────────────────────────────────────────┐
│  Phase 2: StateCoordinator Decomposition (5 days)               │
│  - Depends on Phase 1 DependencyContainer                       │
│  - StreamQueueManager is highest risk                           │
└─────────────────────────────────────────────────────────────────┘

Week 3:
┌─────────────────────────────────────────────────────────────────┐
│  Phase 3: Magic Strings (2 days)                                │
│  Phase 4: Targeted Type Safety (1-1.5 days)                     │
│  - Lower priority, can be done opportunistically                │
└─────────────────────────────────────────────────────────────────┘
```

### Recommended Order

1. **Phase 1 (Coordinator Decomposition)** - Highest impact, foundation for Phase 2
2. **Phase 2 (StateCoordinator Decomposition)** - Depends on Phase 1
3. **Phase 3 (Magic Strings)** - Can be done anytime, adds safety for other refactoring
4. **Phase 4 (Targeted Type Safety)** - Opportunistic, low priority

---

## Risk Mitigation

### High-Risk Areas

| Risk | Mitigation |
|------|------------|
| StreamQueueManager extraction breaks streaming | Create comprehensive tests before extraction; add state machine logging |
| Event handler changes cause missed events | Add event counting/audit logging; verify counts match before/after |
| Coordinator decomposition breaks View bindings | Keep facade API identical; Views shouldn't need changes |

### Testing Strategy

1. **Before each phase**: Capture current behavior via manual testing
2. **During refactoring**: Keep dual implementations where possible
3. **After each task**: Verify no regressions via build + manual smoke test
4. **End of each phase**: Full regression test of affected workflows

### Rollback Plan

Each phase is designed to be independently revertable:
- Phase 1: Keep old coordinator code commented until phase complete
- Phase 2: StreamQueueManager can delegate back to original methods
- Phase 3: Enums have `rawValue` for string interop
- Phase 4: Helper extensions are additive, no breaking changes

---

## Summary

| Phase | Effort | Risk | Priority |
|-------|--------|------|----------|
| Phase 1: Coordinator Decomposition | 5 days | Medium | **1 (Highest)** |
| Phase 2: StateCoordinator Decomposition | 5 days | High | **2** |
| Phase 3: Magic Strings | 2 days | Low | **3** |
| Phase 4: Targeted Type Safety | 1-1.5 days | Low | **4** |
| **Total** | **13-14 days** | | |

**Outcome**: After completion, the onboarding module will have:
- No coordinator file over 300 LOC
- Extracted StreamQueueManager for testability
- Centralized string constants
- Cleaner view code via helper extensions
- Clear separation of concerns
