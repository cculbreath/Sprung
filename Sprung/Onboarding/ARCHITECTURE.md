# Onboarding Interview Architecture

This document describes the refactored architecture for the onboarding interview feature, implemented following the **Coordinator + Router + Handler** pattern.

---

## Overview

The onboarding interview system has been decomposed from a monolithic `OnboardingInterviewService` (≈1,400 lines) into focused, single-responsibility components. The refactor enables:

- **Easier testing**: Each component can be tested in isolation
- **Better maintainability**: Changes are localized to specific domains
- **Clearer responsibilities**: Each file has one clear job
- **Extensibility**: New phases, tools, or handlers can be added without modifying existing code

---

## Architecture Diagram

```
OnboardingInterviewService (facade / environment entry point)
└── OnboardingInterviewCoordinator (@Observable brain)
    ├── ChatTranscriptStore                // conversation stream + reasoning summaries
    ├── OnboardingToolRouter               // central continuation registry & dispatcher
    │   ├── PromptInteractionHandler       // choice & validation prompts
    │   ├── UploadInteractionHandler       // file uploads (incl. targeted uploads)
    │   ├── ProfileInteractionHandler      // applicant profile intake state machine
    │   └── SectionToggleHandler           // resume section enable/disable
    ├── OnboardingDataStoreManager         // applicant profile, timeline, artifacts persistence
    ├── OnboardingCheckpointManager        // checkpoint save/restore/clear
    ├── OnboardingPreferences              // model/backend/user-consent flags
    ├── WizardProgressTracker              // wizard step status for UI
    └── PhaseScriptRegistry                // strategy objects per onboarding phase
        ├── PhaseOneScript                 // Phase 1: Core Facts
        ├── PhaseTwoScript                 // Phase 2: Deep Dive
        └── PhaseThreeScript               // Phase 3: Writing Corpus

InterviewOrchestrator                      // existing LLM interaction component (unchanged interface)
```

---

## Core Components

### 1. **OnboardingInterviewService** (Facade)

**Location**: `Sprung/Onboarding/Core/OnboardingInterviewService.swift`

**Responsibility**: Lightweight facade that:
- Provides SwiftUI environment entry point
- Instantiates and wires dependencies
- Exposes coordinator's public API
- Bridges coordinator to SwiftUI views

**Key Methods**:
```swift
func startInterview(modelId: String, backend: LLMFacade.Backend, resumeExisting: Bool) async
func sendMessage(_ text: String) async
func resetInterview()
```

---

### 2. **OnboardingInterviewCoordinator** (@Observable Brain)

**Location**: `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`

**Responsibility**: Orchestrates interview lifecycle and coordinates all managers/handlers.

**Composed Dependencies**:
- `ChatTranscriptStore`: Message stream management
- `OnboardingToolRouter`: Tool interaction routing
- `OnboardingDataStoreManager`: Artifact persistence
- `OnboardingCheckpointManager`: Checkpoint management
- `OnboardingPreferences`: User preferences
- `WizardProgressTracker`: UI wizard step tracking
- `PhaseScriptRegistry`: Phase-specific behavior
- `InterviewOrchestrator`: LLM communication

**Key Responsibilities**:
- Start/stop interview sessions
- Route tool continuation results to appropriate handlers
- Manage interview state transitions
- Coordinate checkpointing

### Coordinator Lifecycle Flow

The onboarding runtime now runs entirely through the coordinator. The high-level flow is:

1. `OnboardingInterviewService` wires dependencies and hands control to the coordinator when `startInterview` is called. The service retains no business state.
2. The coordinator constructs an `InterviewOrchestrator` with the current session, the phased system prompt built by `PhaseScriptRegistry`, and callback closures that forward tool events back into the coordinator.
3. When the orchestrator issues a tool continuation, the coordinator records the pending request in `OnboardingToolRouter`. The router then exposes handler state (`pendingChoicePrompt`, `pendingApplicantProfileIntake`, uploads, etc.) that SwiftUI observes through the service façade.
4. UI actions call back into the service, which immediately forwards to the coordinator and, when relevant, resumes the orchestrator continuation with the handler-provided payload.
5. After every significant transition the coordinator updates `WizardProgressTracker` and persists checkpoints via `OnboardingCheckpointManager` so the UI and data stores stay in sync.
6. Resetting the interview clears only coordinator-managed state—no additional reset logic lives in the service or views.

`ProfileInteractionHandler` now drives the entire contact import flow through its intake state machine, so there is no longer a separate "contacts permission" surface in the service.

---

### Objective Ledger & Validation Workflow

The coordinator maintains a lightweight *objective ledger* that tracks the status of each phase objective together with provenance metadata:

- `status`: `pending`, `in_progress`, or `completed`
- `source`: `user_manual`, `user_contacts`, `llm_proposed`, etc.
- `updatedAt`: ISO8601 timestamp

Deterministic UI flows (manual or contact-card intake, section toggles, etc.) update the ledger immediately. Subjective goals (e.g., “experience interview complete”) still rely on `set_objective_status` proposals from the LLM, but the coordinator remains the final authority—every proposal is audited before the ledger flips to `completed`.

Ledger updates are surfaced to the LLM by:

1. Embedding short system messages ahead of each `responseCreate` call that summarize the latest objective deltas.
2. Returning structured JSON in tool responses (e.g., `{"status":"approved","objective_state":"completed","objective_id":"contact_validation"}`) so the model can react without waiting for another round trip.

### Validation Metadata & Auto-Approval

Applicant profile drafts originating from deterministic user flows are tagged with validation metadata before storage:

```json
"meta": {
  "validation_state": "user_validated",
  "validated_via": "manual" | "contacts",
  "validated_at": "2024-07-19T22:15:04Z"
}
```

When `submit_for_validation` receives a payload marked `user_validated`, the tool short-circuits with an immediate response:

```json
{
  "status": "approved",
  "message": "Validated data automatically approved.",
  "metadata": {
    "reason": "already_validated",
    "validated_via": "...",
    "validated_at": "..."
  }
}
```

If the LLM submits data without a payload (`data` missing), the tool asks it to retry. After two empty attempts the coordinator falls back to the cached draft to keep the workflow moving, while logging the anomaly for diagnostics.

Resume/URL driven drafts **do not** receive the `user_validated` tag automatically; the validation card still appears so the user can confirm extracted data. Upon approval the ledger records `source = llm_proposed` and the metadata is attached for future submissions.

---

## Message & Streaming Management

### **ChatTranscriptStore**

**Location**: `Sprung/Onboarding/Stores/ChatTranscriptStore.swift`

**Responsibility**: Owns the conversation transcript and streaming state.

**Key Features**:
- Append user/assistant/system messages
- Stream assistant responses with real-time updates
- Track reasoning summaries
- Measure streaming latency

**API**:
```swift
func appendUserMessage(_ text: String)
func appendAssistantMessage(_ text: String) -> UUID
func beginAssistantStream(initialText: String) -> UUID
func updateAssistantStream(id: UUID, text: String)
func finalizeAssistantStream(id: UUID, text: String) -> TimeInterval
func updateReasoningSummary(_ summary: String, for messageId: UUID, isFinal: Bool)
func reset()
```

---

## Tool Interaction Routing

### **OnboardingToolRouter**

**Location**: `Sprung/Onboarding/Core/OnboardingToolRouter.swift`

**Responsibility**: Centralized tool continuation registry and dispatcher.

**Pattern**: Maintains a single registry of all pending tool interactions, then delegates to specialized handlers.

**Registry Structure**:
```swift
private var continuationRegistry: [UUID: HandlerType] = [:]
```

**Benefits**:
- Single source of truth for pending user interactions
- Easy debugging: "What's blocking the interview?"
- Enforces mutual exclusivity (only one prompt active at a time)

---

### **Interaction Handlers**

All handlers follow a consistent pattern:
1. Maintain observable state (pending requests, intake modes, etc.)
2. Return `(continuationId: UUID, payload: JSON)?` tuples
3. Provide `reset()` for interview lifecycle management

---

#### **PromptInteractionHandler**

**Location**: `Sprung/Onboarding/Handlers/PromptInteractionHandler.swift`

**Responsibility**: Choice prompts and validation prompts.

**State**:
- `pendingChoicePrompt: OnboardingChoicePrompt?`
- `pendingValidationPrompt: OnboardingValidationPrompt?`

**API**:
```swift
func presentChoicePrompt(_ prompt: OnboardingChoicePrompt, continuationId: UUID)
func resolveChoice(selectionIds: [String]) -> (UUID, JSON)?
func cancelChoice(reason: String) -> (UUID, JSON)?

func presentValidationPrompt(_ prompt: OnboardingValidationPrompt, continuationId: UUID)
func submitValidation(status: String, updatedData: JSON?, changes: JSON?, notes: String?) -> (UUID, JSON)?
func cancelValidation(reason: String) -> (UUID, JSON)?
```

---

#### **UploadInteractionHandler**

**Location**: `Sprung/Onboarding/Handlers/UploadInteractionHandler.swift`

**Responsibility**: File upload orchestration, targeted uploads (e.g., profile images), remote downloads.

**Dependencies**:
- `UploadFileService`: File validation, remote downloads, cleanup
- `OnboardingUploadStorage`: Storage processing
- `OnboardingDataStoreManager`: For targeted uploads (basics.image)

**State**:
- `pendingUploadRequests: [OnboardingUploadRequest]`
- `uploadedItems: [OnboardingUploadedItem]`

**API**:
```swift
func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID)
func completeUpload(id: UUID, fileURLs: [URL]) async -> (UUID, JSON)?
func completeUpload(id: UUID, link: URL) async -> (UUID, JSON)?
func skipUpload(id: UUID) async -> (UUID, JSON)?
```

**Targeted Uploads**:
- `basics.image`: Profile picture uploads (validated as images, stored in data manager)
- Extensible for future targets (e.g., `basics.resume`, `artifact.document`)

---

#### **ProfileInteractionHandler**

**Location**: `Sprung/Onboarding/Handlers/ProfileInteractionHandler.swift`

**Responsibility**: Applicant profile intake state machine and validation.

**Dependencies**:
- `ContactsImportService`: macOS Contacts integration

**State**:
- `pendingApplicantProfileRequest: OnboardingApplicantProfileRequest?` (validation flow)
- `pendingApplicantProfileIntake: OnboardingApplicantProfileIntakeState?` (intake flow)

**Intake Modes**:
```swift
enum Mode {
    case options               // Show mode picker
    case manual(source)        // Manual entry form
    case urlEntry              // URL paste form
    case loading(String)       // Fetching contacts
}
```

**API**:
```swift
// Validation flow
func presentProfileRequest(_ request: OnboardingApplicantProfileRequest, continuationId: UUID)
func resolveProfile(with draft: ApplicantProfileDraft) -> (UUID, JSON)?
func rejectProfile(reason: String) -> (UUID, JSON)?

// Intake flow
func presentProfileIntake(continuationId: UUID)
func beginManualEntry()
func beginURLEntry()
func beginUpload() -> OnboardingUploadRequest?
func beginContactsFetch()
func submitURL(_ urlString: String) -> (UUID, JSON)?
func completeDraft(_ draft: ApplicantProfileDraft, source: Source) -> (UUID, JSON)?
func cancelIntake(reason: String) -> (UUID, JSON)?
```

---

#### **SectionToggleHandler**

**Location**: `Sprung/Onboarding/Handlers/SectionToggleHandler.swift`

**Responsibility**: Resume section enable/disable logic.

**State**:
- `pendingSectionToggleRequest: OnboardingSectionToggleRequest?`

**API**:
```swift
func presentToggleRequest(_ request: OnboardingSectionToggleRequest, continuationId: UUID)
func resolveToggle(enabled: [String]) -> (UUID, JSON)?
func rejectToggle(reason: String) -> (UUID, JSON)?
```

---

## Data Persistence

### **OnboardingDataStoreManager**

**Location**: `Sprung/Onboarding/Managers/OnboardingDataStoreManager.swift`

**Responsibility**: Centralized artifact storage and retrieval.

**Dependencies**:
- `ApplicantProfileStore`: SwiftData store for profiles
- `InterviewDataStore`: File-based interview data

**Managed Artifacts**:
- `applicantProfileJSON`: JSON representation
- `skeletonTimelineJSON`: Timeline data
- `artifacts.artifactRecords`: Uploaded files
- `artifacts.knowledgeCards`: Generated cards
- `artifacts.enabledSections`: Selected resume sections

**API**:
```swift
func storeApplicantProfile(_ json: JSON)
func storeApplicantProfileImage(data: Data, mimeType: String?)
func storeSkeletonTimeline(_ json: JSON)
func storeArtifactRecord(_ artifact: JSON)
func storeKnowledgeCard(_ card: JSON)
func loadPersistedArtifacts() async
func clearArtifacts()
```

**Deduplication**:
- Artifact records deduplicated by SHA256
- Knowledge cards deduplicated by ID

---

### **OnboardingCheckpointManager**

**Location**: `Sprung/Onboarding/Managers/OnboardingCheckpointManager.swift`

**Responsibility**: Checkpoint persistence and restoration.

**Dependencies**:
- `Checkpoints`: Actor-based checkpoint storage
- `InterviewState`: Interview session state

**API**:
```swift
func hasRestorableCheckpoint() async -> Bool
func restoreLatest() async -> CheckpointSnapshot?
func save(applicantProfile: JSON?, skeletonTimeline: JSON?, enabledSections: [String]?) async
func clear() async
```

**CheckpointSnapshot**:
```swift
typealias CheckpointSnapshot = (
    session: InterviewSession,
    applicantProfile: JSON?,
    skeletonTimeline: JSON?,
    enabledSections: [String]?,
    ledger: [ObjectiveEntry]
)
```

---

## Phase Management

### **PhaseScript Protocol**

**Location**: `Sprung/Onboarding/Phase/PhaseScript.swift`

**Purpose**: Defines behavior for each interview phase using the Strategy pattern.

```swift
protocol PhaseScript {
    var phase: InterviewPhase { get }
    var systemPromptFragment: String { get }
    var requiredObjectives: [String] { get }

    func canAdvance(session: InterviewSession) -> Bool
    func missingObjectives(session: InterviewSession) -> [String]
}
```

---

### **Phase Implementations**

#### **PhaseOneScript** (Core Facts)

**Location**: `Sprung/Onboarding/Phase/PhaseOneScript.swift`

**Objectives**:
- `applicant_profile`: Contact information
- `skeleton_timeline`: Career timeline
- `enabled_sections`: Resume section selection

**Tools**: `get_applicant_profile`, `extract_document`, `submit_for_validation`, `persist_data`, `set_objective_status`, `next_phase`

---

#### **PhaseTwoScript** (Deep Dive)

**Location**: `Sprung/Onboarding/Phase/PhaseTwoScript.swift`

**Objectives**:
- `interviewed_one_experience`: Detailed interview
- `one_card_generated`: Knowledge card creation

**Tools**: `get_user_option`, `generate_knowledge_card`, `submit_for_validation`, `persist_data`, `set_objective_status`, `next_phase`

---

#### **PhaseThreeScript** (Writing Corpus)

**Location**: `Sprung/Onboarding/Phase/PhaseThreeScript.swift`

**Objectives**:
- `one_writing_sample`: Collect writing samples
- `dossier_complete`: Finalize candidate dossier

**Tools**: `get_user_upload`, `extract_document`, `submit_for_validation`, `persist_data`, `set_objective_status`, `next_phase`

---

### **PhaseScriptRegistry**

**Location**: `Sprung/Onboarding/Phase/PhaseScriptRegistry.swift`

**Responsibility**: Manages phase scripts and builds system prompts.

**API**:
```swift
func script(for phase: InterviewPhase) -> PhaseScript?
func currentScript(for session: InterviewSession) -> PhaseScript?
func buildSystemPrompt(for session: InterviewSession) -> String
```

**System Prompt Composition**:
```
Base System Prompt (universal guidelines)
+
Current Phase Script Fragment (phase-specific instructions)
```

**Benefits**:
- Open/Closed Principle: Add Phase 4 without modifying existing code
- Testable: Can unit test each phase script independently
- Clear separation: Base instructions vs. phase-specific behavior

---

## UI Progress Tracking

### **WizardProgressTracker**

**Location**: `Sprung/Onboarding/Managers/WizardProgressTracker.swift`

**Responsibility**: Maps interview phases/objectives to UI wizard steps.

**Wizard Steps**:
1. **Introduction**: Initial greeting
2. **Résumé Intake**: Collect contact info and timeline (Phase 1)
3. **Artifact Discovery**: Deep interviews and cards (Phase 2)
4. **Writing Corpus**: Collect samples and finalize (Phase 3)
5. **Wrap Up**: Interview complete

**State**:
- `currentStep: OnboardingWizardStep`
- `completedSteps: Set<OnboardingWizardStep>`
- `stepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus]`

**API**:
```swift
func setStep(_ step: OnboardingWizardStep)
func updateWaitingState(_ waiting: InterviewSession.Waiting?)
func syncProgress(from session: InterviewSession)
func reset()
```

**Synchronization Logic**:
- Phase 1 (CoreFacts) → Résumé Intake or Artifact Discovery
- Phase 2 (DeepDive) → Artifact Discovery
- Phase 3 (WritingCorpus) → Writing Corpus
- Complete → Wrap Up

---

## Supporting Services

### **UploadFileService**

**Location**: `Sprung/Onboarding/Services/UploadFileService.swift`

**Responsibility**: File utilities for upload handler.

**API**:
```swift
func downloadRemoteFile(from url: URL) async throws -> URL
func validateImageData(data: Data, fileExtension: String) throws
func cleanupTemporaryFile(at url: URL)
```

---

### **ContactsImportService**

**Location**: `Sprung/Onboarding/Services/ContactsImportService.swift`

**Responsibility**: macOS Contacts integration.

**API**:
```swift
func fetchMeCardAsDraft() async throws -> ApplicantProfileDraft
```

**Permissions**: Requests Contacts access, handles denial gracefully.

**Error Handling**:
```swift
enum ContactFetchError: Error {
    case permissionDenied
    case notFound
    case system(String)
}
```

---

## Key Design Patterns

### 1. **Coordinator Pattern**
- Coordinator owns business logic and coordinates components
- Service is just a facade for SwiftUI

### 2. **Router + Handler Pattern**
- Router maintains continuation registry
- Handlers provide domain-specific logic
- Keeps router thin, handlers focused

### 3. **Strategy Pattern (Phase Scripts)**
- Each phase is a first-class entity with its own behavior
- Open/Closed Principle: Add phases without modifying existing code

### 4. **Observable Segmentation**
- Only coordinator and specific stores are `@Observable`
- Clear data flow: Views → Coordinator → Handlers

### 5. **Continuation Payload Pattern**
- Handlers return `(UUID, JSON)?` tuples
- Coordinator resumes continuations with orchestrator
- Handlers don't know about orchestrator

---

## File Organization

```
Sprung/Onboarding/
├── Core/
│   ├── OnboardingInterviewService.swift       (facade)
│   ├── OnboardingInterviewCoordinator.swift   (coordinator)
│   ├── OnboardingToolRouter.swift             (router)
│   ├── InterviewOrchestrator.swift            (LLM integration)
│   ├── InterviewSession.swift                 (session state)
│   └── CheckpointActor.swift                  (checkpoint storage)
├── Handlers/
│   ├── PromptInteractionHandler.swift
│   ├── UploadInteractionHandler.swift
│   ├── ProfileInteractionHandler.swift
│   └── SectionToggleHandler.swift
├── Managers/
│   ├── OnboardingDataStoreManager.swift
│   ├── OnboardingCheckpointManager.swift
│   └── WizardProgressTracker.swift
├── Phase/
│   ├── PhaseScript.swift                      (protocol)
│   ├── PhaseOneScript.swift
│   ├── PhaseTwoScript.swift
│   ├── PhaseThreeScript.swift
│   └── PhaseScriptRegistry.swift
├── Services/
│   ├── UploadFileService.swift
│   └── ContactsImportService.swift
├── Stores/
│   └── ChatTranscriptStore.swift
└── Models/
    └── (existing models...)
```

---

## Migration from Monolithic Service

### Before
```swift
// 1,400 lines in one file
class OnboardingInterviewService {
    // Messages, uploads, profile, checkpoints, phases, wizard, etc.
    // All mixed together
}
```

### After
```swift
// Facade (~200 lines)
class OnboardingInterviewService {
    private let coordinator: OnboardingInterviewCoordinator

    // Delegates to coordinator
}

// Coordinator (~400 lines)
class OnboardingInterviewCoordinator {
    private let chatTranscriptStore: ChatTranscriptStore
    private let toolRouter: OnboardingToolRouter
    private let dataStoreManager: OnboardingDataStoreManager
    // ...

    // Orchestrates components
}

// Handlers (~200-300 lines each)
// Managers (~100-200 lines each)
// Phase Scripts (~100 lines each)
```

---

## Testing Strategy

### Unit Tests
- **Handlers**: Test tool interaction logic in isolation
- **Phase Scripts**: Test objective validation and advancement
- **WizardProgressTracker**: Test wizard step synchronization
- **DataStoreManager**: Test artifact storage and deduplication

### Integration Tests
- **Coordinator**: Test component coordination
- **ToolRouter**: Test continuation routing
- **Checkpoint Flow**: Test save/restore cycles

### UI Tests
- **Interview Flow**: Test complete user journeys
- **Upload Flows**: Test file upload scenarios
- **Profile Intake**: Test all intake modes

---

## Future Extensibility

### Adding a New Phase
1. Create `PhaseFourScript: PhaseScript`
2. Define objectives and system prompt
3. Register in `PhaseScriptRegistry`
4. Update `InterviewPhase` enum
5. Update `WizardProgressTracker` mapping

### Adding a New Tool Interaction
1. Create handler (e.g., `VideoUploadHandler`)
2. Implement `presentRequest()` and `resolveRequest()`
3. Register in `OnboardingToolRouter`
4. Wire into coordinator

### Adding New Artifact Types
1. Add property to `OnboardingArtifacts`
2. Add storage method in `OnboardingDataStoreManager`
3. Update checkpoint serialization if needed

---

## Key Takeaways

✅ **Single Responsibility**: Each component has one clear job
✅ **Testability**: Components can be tested in isolation
✅ **Discoverability**: Clear file names and organization
✅ **Maintainability**: Changes localized to specific domains
✅ **Extensibility**: New features fit into existing patterns
✅ **Reduced Cognitive Load**: ~200 lines per file vs. 1,400

---

_Last updated: Developer B workstream completion_
