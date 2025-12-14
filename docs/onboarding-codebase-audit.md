# Onboarding Module Codebase Audit

**Date:** December 13, 2025
**Scope:** `Sprung/Onboarding` module (178 files)

## Executive Summary

The Onboarding module has transitioned from a monolithic coordinator pattern to an event-driven architecture (Event Bus + StateCoordinator). However, this transition is incomplete, resulting in significant duplication, "God Objects", and vestigial code paths.

### Key Issues

1.  **Dual Persistence Systems**: The system persists data to both JSON files (`InterviewDataStore`, `TranscriptPersistenceHandler`) and SwiftData (`OnboardingSessionStore`, `SwiftDataSessionPersistenceHandler`). The JSON file persistence appears to be legacy but is still active.
2.  **"God Object" Coordinators**: `OnboardingInterviewCoordinator` (700+ lines) and `StateCoordinator` (600+ lines) have overlapping responsibilities. `StateCoordinator` was intended to be the "thin" orchestrator but has grown to handle too many event types.
3.  **Duplicated Artifact Processing**: File uploads are processed by `UploadInteractionHandler` (legacy tool-driven) and `DocumentArtifactHandler` (event-driven). Logic for file handling, extraction, and artifact creation is scattered between these handlers and `DocumentProcessingService`.
4.  **Orphaned UI Components**: Several UI cards and tools (`RequestEvidenceTool`, `ApplicantProfileReviewCard`) are dead code, left behind after refactoring to generic validation systems.
5.  **Event Bus Bloat**: `OnboardingEvents` contains a massive enum of events, some of which appear unused or redundant.
6.  **Hardcoded Logic**: Tool bundles (`ToolBundlePolicy`), prompts (`KCAgentPrompts`, `PhaseScripts`), and model IDs are hardcoded in code.

## Detailed File Audit

### Constants
| File | Status | Findings |
| :--- | :--- | :--- |
| `OnboardingConstants.swift` | **Active** | Shared constants. |

### Core
| File | Status | Findings |
| :--- | :--- | :--- |
| `ToolBundlePolicy.swift` | **Refactor** | Hardcoded tool lists per subphase. Logic for `inferSubphase` duplicates state tracking found in `PhaseTransitionController`. |
| `TokenUsageTracker.swift` | **Active** | Tracks token usage. Seems well-isolated but relies on correct event emissions. |
| `TokenBudgetPolicy.swift` | **Active** | Defines budget thresholds. Good separation of concerns. |
| `StateCoordinator.swift` | **Refactor** | Massive file. Handles too many event types. Violates SRP. Overlaps with `OnboardingInterviewCoordinator`. |
| `OnboardingUIState.swift` | **Active** | View state container. Leaks business logic flags like `hasBatchUploadInProgress`. |
| `OnboardingToolRegistrar.swift` | **Active** | Registers tools. Good separation, but manual dependency injection is verbose. |
| `OnboardingInterviewCoordinator.swift` | **Legacy/Refactor** | "God Object". Acts as a facade but retains too much logic. Should devolve more to `StateCoordinator` and Services. |
| `OnboardingEvents.swift` | **Refactor** | Massive enum. Needs splitting or categorization. |
| `OnboardingDependencyContainer.swift` | **Active** | Manual DI container. Functional but verbose. |
| `ObjectiveStore.swift` | **Active** | Manages objectives. Contains hardcoded "script" metadata that duplicates `PhaseScript` logic. |
| `NetworkRouter.swift` | **Active** | Network request handling. |
| `LLMStateManager.swift` | **Active** | Manages LLM context. Crucial for the "Codex paradigm". |
| `LLMMessenger.swift` | **Active** | Interfaces with `OpenAIService`. |
| `InterviewOrchestrator.swift` | **Refactor** | Name suggests overlap with `OnboardingInterviewCoordinator`. Potential duplicate. |
| `Coordinators/UIStateUpdateHandler.swift` | **Active** | Updates UI state from events. |
| `Coordinators/UIResponseCoordinator.swift` | **Active** | Helper for sending UI-driven messages to LLM. |
| `Coordinators/CoordinatorEventRouter.swift` | **Active** | Routes events. Part of the complexity of `StateCoordinator`. |
| `ConversationLogStore.swift` | **Active** | In-memory log. |
| `ArtifactRepository.swift` | **Active** | Manages in-memory artifact state. |
| `AgentActivityTracker.swift` | **Active** | Tracks parallel agents. Good. |
| `CandidateDossierTracker.swift` | **Active** | Tracks opportunistic dossier collection. |
| `ChatTranscriptStore.swift` | **Active** | Manages chat history. |
| `ConversationContextAssembler.swift` | **Active** | Prepares context for LLM. |
| `Coordinators/ArtifactQueryCoordinator.swift` | **Active** | Handles `get_artifact` etc. |
| `Coordinators/InterviewSessionCoordinator.swift` | **Active** | Manages session start/stop/resume. |
| `Coordinators/ToolInteractionCoordinator.swift` | **Active** | Handles UI-based tools (upload, choice). |
| `Handlers/ProfilePersistenceHandler.swift` | **Active** | Persists profile updates. |
| `InterviewLifecycleController.swift` | **Active** | Manages overall lifecycle. |
| `ModelProvider.swift` | **Active** | Provides models. |
| `ObjectiveWorkflowEngine.swift` | **Active** | Executes workflows defined in `PhaseScript`. |
| `PhaseTransitionController.swift` | **Active** | Manages phase changes. |
| `SessionUIState.swift` | **Active** | Session-specific UI state. |
| `StreamQueueManager.swift` | **Active** | Manages LLM streaming queue. |
| `ToolHandler.swift` | **Active** | Routes tool calls. Contains vestigial methods for `presentApplicantProfileRequest`. |

### Handlers
| File | Status | Findings |
| :--- | :--- | :--- |
| `ChatboxHandler.swift` | **Active** | Handles user input. Cancels pending tools (questionable UX). |
| `UploadInteractionHandler.swift` | **Refactor** | Handles uploads. Logic overlaps significantly with `DocumentArtifactHandler`. |
| `ProfileInteractionHandler.swift` | **Refactor** | Manages profile intake UI state. Contains unused `pendingApplicantProfileRequest` state. |
| `DocumentArtifactMessenger.swift` | **Active** | Batches artifact messages. Logic duplicates `ArtifactRepository` presentation. |
| `DocumentArtifactHandler.swift` | **Active** | Processes documents via events. The "modern" way vs `UploadInteractionHandler`. |
| `PromptInteractionHandler.swift` | **Active** | Simple state container. |
| `SectionToggleHandler.swift` | **Active** | Simple state container. |
| `SwiftDataSessionPersistenceHandler.swift` | **Active** | Persists to SwiftData. Duplicates state logic from `StateCoordinator`. |
| `ToolExecutionCoordinator.swift` | **Active** | Executes tools. Checks waiting states. |
| `TranscriptPersistenceHandler.swift` | **Legacy/Delete** | Persists transcript to JSON files. Redundant with SwiftData persistence. |

### Managers
| File | Status | Findings |
| :--- | :--- | :--- |
| `WizardProgressTracker.swift` | **Active** | Tracks UI wizard steps. Simple state machine. |

### Models
| File | Status | Findings |
| :--- | :--- | :--- |
| `OnboardingArtifacts.swift` | **Active** | Data structure. |
| `KnowledgeCardDraft.swift` | **Active** | Model for drafts. |
| `DocumentSummary.swift` | **Active** | Model for summaries. |
| `EvidenceRequirement.swift` | **Active** | Model. |
| `Extensions/JSONViewHelpers.swift` | **Active** | Helpers. |
| `ExtractionProgress.swift` | **Active** | Model. |
| `InterviewPhase.swift` | **Active** | Enum. |
| `OnboardingPlaceholders.swift` | **Active** | Constants. |
| `OnboardingPreferences.swift` | **Active** | Settings. |
| `OnboardingSessionModels.swift` | **Active** | SwiftData models. |
| `TimelineCard.swift` | **Active** | Model. |

### Phase
| File | Status | Findings |
| :--- | :--- | :--- |
| `PhaseScript.swift` | **Active** | Protocol definition. |
| `PhaseScriptRegistry.swift` | **Active** | Registry. |
| `PhaseOneScript.swift` | **Active** | Phase 1 logic. Hardcoded prompts. |
| `PhaseTwoScript.swift` | **Active** | Phase 2 logic. Hardcoded prompts. |
| `PhaseThreeScript.swift` | **Active** | Phase 3 logic. Hardcoded prompts. |

### Services
| File | Status | Findings |
| :--- | :--- | :--- |
| `SubAgentToolExecutor.swift` | **Active** | Restricted executor for agents. Hardcoded tool list. |
| `KnowledgeCardAgentService.swift` | **Active** | Spawns KC agents. |
| `KCAgentPrompts.swift` | **Active** | Prompts for KC agents. Hardcoded. |
| `GitIngestionKernel.swift` | **Active** | Git analysis logic. |
| `GitAgent/GitAnalysisAgent.swift` | **Active** | Agent logic. |
| `ExtractionManagementService.swift` | **Active** | Manages extraction UI state. |
| `DocumentProcessingService.swift` | **Active** | Business logic for docs. Hardcoded model IDs. |
| `DocumentExtractionService.swift` | **Active** | Low-level extraction. Splits PDF/Text logic. |
| `DocumentExtractionPrompts.swift` | **Active** | Prompts. |
| `ArtifactIngestionCoordinator.swift` | **Active** | Unifies ingestion. |
| `AgentRunner.swift` | **Active** | Generic agent runner. |
| `ArtifactIngestionProtocol.swift` | **Active** | Protocol. |
| `ContactsImportService.swift` | **Active** | Imports from Contacts. |
| `DataPersistenceService.swift` | **Active** | Handles `persist_data` tool. |
| `DocumentIngestionKernel.swift` | **Active** | Wrapper for doc processing. |
| `GitAgent/AgentPrompts.swift` | **Active** | Git agent prompts. |
| `GitAgent/CompleteAnalysisTool.swift` | **Active** | Tool definition. |
| `GitAgent/FileSystemTools.swift` | **Active** | File system tools. |
| `TimelineManagementService.swift` | **Active** | Manages timeline data. |
| `UploadFileService.swift` | **Active** | Low-level file handling. |

### Stores
| File | Status | Findings |
| :--- | :--- | :--- |
| `InterviewDataStore.swift` | **Legacy** | Persists to JSON files. Redundant. |
| `OnboardingSessionStore.swift` | **Active** | SwiftData store. The source of truth for persistence. |

### Tools
| File | Status | Findings |
| :--- | :--- | :--- |
| `ToolRegistry.swift` | **Active** | Thread-safe registry. |
| `ToolExecutor.swift` | **Active** | Executes tools. |
| `ToolProtocol.swift` | **Active** | Protocol. |
| `Schemas/*.swift` | **Active** | JSON Schemas for tools (7 files). Generally sound. |
| `Implementations/AgentReadyTool.swift` | **Active** | Signals agent readiness. Critical bootstrap. |
| `Implementations/CancelUserUploadTool.swift` | **Active** | UI interaction tool. |
| `Implementations/ConfigureEnabledSectionsTool.swift` | **Active** | UI interaction tool. |
| `Implementations/CreateTimelineCardTool.swift` | **Active** | CRUD tool. |
| `Implementations/DeleteTimelineCardTool.swift` | **Active** | CRUD tool. |
| `Implementations/DisplayKnowledgeCardPlanTool.swift` | **Active** | UI tool. Updates default view state. |
| `Implementations/DisplayTimelineForReviewTool.swift` | **Active** | UI tool. Triggers editor. |
| `Implementations/DispatchKCAgentsTool.swift` | **Active** | Triggers agent service. |
| `Implementations/GetApplicantProfileTool.swift` | **Active** | UI interaction tool. |
| `Implementations/GetArtifactRecordTool.swift` | **Active** | Data retrieval. |
| `Implementations/GetContextPackTool.swift` | **Active** | Optimization tool. Useful. |
| `Implementations/GetTimelineEntriesTool.swift` | **Active** | Data retrieval. |
| `Implementations/GetUserOptionTool.swift` | **Active** | UI interaction tool. |
| `Implementations/GetUserUploadTool.swift` | **Active** | UI interaction tool. |
| `Implementations/GetValidatedApplicantProfileTool.swift` | **Active** | Data retrieval. |
| `Implementations/IngestWritingSampleTool.swift` | **Active** | Data ingestion. |
| `Implementations/ListArtifactsTool.swift` | **Active** | Data retrieval. |
| `Implementations/NextPhaseTool.swift` | **Active** | Phase transition. |
| `Implementations/OpenDocumentCollectionTool.swift` | **Active** | UI tool. |
| `Implementations/PersistDataTool.swift` | **Active/Refactor** | Uses `InterviewDataStore` (Legacy). Should use SwiftData. |
| `Implementations/ProposeCardAssignmentsTool.swift` | **Active** | Logic tool. |
| `Implementations/ReorderTimelineCardsTool.swift` | **Active** | CRUD tool. |
| `Implementations/RequestEvidenceTool.swift` | **Legacy/Delete** | Not in any tool bundle or allowed list. Dead code. |
| `Implementations/RequestRawArtifactFileTool.swift` | **Active** | Data retrieval. |
| `Implementations/ScanGitRepoTool.swift` | **Active** | Triggers Git ingestion. |
| `Implementations/SetCurrentKnowledgeCardTool.swift` | **Active** | State management. |
| `Implementations/SetObjectiveStatusTool.swift` | **Active** | State management. |
| `Implementations/StartPhaseThreeTool.swift` | **Active** | Phase bootstrap. |
| `Implementations/StartPhaseTwoTool.swift` | **Active** | Phase bootstrap. |
| `Implementations/SubmitCandidateDossierTool.swift` | **Active** | Final submission. |
| `Implementations/SubmitExperienceDefaultsTool.swift` | **Active** | Final submission. |
| `Implementations/SubmitForValidationTool.swift` | **Active** | UI interaction tool. |
| `Implementations/SubmitKnowledgeCardTool.swift` | **Active/Refactor** | Complex business logic. Should move logic to Service. |
| `Implementations/UpdateArtifactMetadataTool.swift` | **Active** | CRUD tool. |
| `Implementations/UpdateTimelineCardTool.swift` | **Active** | CRUD tool. |
| `Implementations/ValidateApplicantProfileTool.swift` | **Active** | UI interaction tool. Uses generic validation prompt. |

### Utilities
| File | Status | Findings |
| :--- | :--- | :--- |
| `ChatTranscriptFormatter.swift` | **Active** | Formatter. |
| `ExperienceDefaultsDraft+Onboarding.swift` | **Active** | Extension. |
| `ExperienceSectionKey+Onboarding.swift` | **Active** | Extension. |
| `OnboardingUploadStorage.swift` | **Active** | Manages temp files. |
| `TimelineCardAdapter.swift` | **Active** | Adapter. |
| `TimelineDiff.swift` | **Active** | Diffing logic. |

### ViewModels
| File | Status | Findings |
| :--- | :--- | :--- |
| `OnboardingInterviewViewModel.swift` | **Active** | Main ViewModel. Likely bloated if it mirrors the Coordinator complexity. |

### Views
| File | Status | Findings |
| :--- | :--- | :--- |
| `OnboardingInterviewView.swift` | **Active** | Main view. |
| `EventDumpView.swift` | **Debug** | Debug view. |
| `Components/OnboardingInterviewToolPane.swift` | **Active** | Main container for tools. Contains view switch logic. |
| `Components/ApplicantProfileReviewCard.swift` | **Orphaned/Delete** | Triggered by `pendingApplicantProfileRequest` which is never set. Replaced by `OnboardingValidationReviewCard`. |
| `Components/ApplicantProfileIntakeCard.swift` | **Active** | Used by `GetApplicantProfileTool`. |
| `Components/TimelineCardEditorView.swift` | **Active** | Used by `DisplayTimelineForReviewTool` and validation. |
| `Components/KnowledgeCardCollectionView.swift` | **Active** | Used by `DisplayKnowledgeCardPlanTool`. |
| `Components/DocumentCollectionView.swift` | **Active** | Used by `OpenDocumentCollectionTool`. |
| `Components/OnboardingValidationReviewCard.swift` | **Active** | Generic validation view. |
| `Components/UploadRequestCard.swift` | **Active** | Used by `GetUserUploadTool`. |
| `Components/InterviewChoicePromptCard.swift` | **Active** | Used by `GetUserOptionTool`. |
| `Components/ResumeSectionsToggleCard.swift` | **Active** | Used by `ConfigureEnabledSectionsTool`. |

## Recommendations

1.  **Eliminate Legacy Persistence**: Remove `TranscriptPersistenceHandler` and `InterviewDataStore`. Rely entirely on `SwiftDataSessionPersistenceHandler` and `OnboardingSessionStore`.
2.  **Delete Orphaned Code**:
    *   Delete `RequestEvidenceTool`.
    *   Delete `ApplicantProfileReviewCard`.
    *   Remove unused `pendingApplicantProfileRequest` state from `ProfileInteractionHandler` and `ToolHandler`.
3.  **Unify Artifact Processing**: Deprecate the logic in `UploadInteractionHandler` that performs file processing. Route all uploads through `ArtifactIngestionCoordinator` -> `DocumentIngestionKernel` -> `DocumentProcessingService`. `UploadInteractionHandler` should only handle the UI interaction.
4.  **Refactor Coordinators**: Break down `StateCoordinator` and `OnboardingInterviewCoordinator`. Move specific event handling logic into dedicated subscribers/managers (e.g., a `TimelineCoordinator`, a `ProfileCoordinator`).
5.  **Consolidate Events**: Audit `OnboardingEvents` and remove unused cases. Group related events into sub-enums or distinct event buses if necessary.
6.  **Configuration Externalization**: Move prompts and model configurations out of Swift code and into a configuration file or a dedicated `ConfigurationService` that can be updated dynamically.
7.  **Fix Subphase Logic**: Unify `ToolBundlePolicy` and `PhaseScript`. The allowed tools should be strictly defined by the `PhaseScript`, and `ToolBundlePolicy` should just read from it.