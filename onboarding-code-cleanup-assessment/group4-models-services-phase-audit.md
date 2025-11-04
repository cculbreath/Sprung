# Onboarding Module Code Cleanup Assessment
## Subfolders: Models, Services, and Phase

**Assessment Date**: 2025-11-04
**Architecture Reference**: ./planning/pub-sub-single-state-spec.md

---

## Executive Summary

This audit evaluated 16 Swift files across three critical subdirectories of the Onboarding module:
- **Models**: 7 files - Data structures and domain models
- **Services**: 4 files - Business logic and external integrations
- **Phase**: 5 files - Interview phase configuration and workflow orchestration

### Key Findings

- **Total Files Evaluated**: 16
- **Files Requiring Cleanup**: 0
- **Critical Issues**: 0
- **Minor Issues**: 1 (non-blocking observation)

### Overall Assessment

The Models, Services, and Phase subdirectories exhibit **excellent post-refactor hygiene**. These directories contain pure data models, service layer logic, and phase configuration that are intentionally decoupled from the event-driven architecture. This architectural separation is by design and represents a clean implementation.

---

## MODELS SUBDIRECTORY (7 files)

### File: OnboardingArtifactRecord.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. This file defines a SwiftData model for persisting artifact records - it correctly has no event handling logic as persistence models should remain pure data structures.

#### Code Duplication
No duplication detected.

#### Recommendations
None. This file represents a clean, focused SwiftData model with appropriate use of the @Model macro.

---

### File: OnboardingPreferences.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Simple value struct for preferences - appropriately stateless and architecture-agnostic.

#### Code Duplication
No duplication detected.

#### Recommendations
None. This is a minimal, well-defined preferences model.

---

### File: KnowledgeCardDraft.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Contains pure data models (KnowledgeCardDraft, Achievement, EvidenceItem, ArtifactRecord, ExperienceContext) with JSON serialization. No event handling or state management - appropriately pure domain models.

#### Code Duplication
No duplication detected. Note: `ArtifactRecord` exists here as a lightweight value type separate from the persisted `OnboardingArtifactRecord` SwiftData model. This is intentional separation of concerns.

#### Recommendations
None. The dual `ArtifactRecord` types (one here as a value struct, one as a SwiftData model) serve different purposes and represent good architectural separation.

---

### File: ExtractionProgress.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Defines extraction progress stages and state models with a progress handler typealias. The `@Sendable` annotation on the handler is appropriate for the new async/await architecture.

#### Code Duplication
No duplication detected.

#### Recommendations
None. Clean enumeration-based state machine for extraction progress.

---

### File: TimelineCard.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Pure data model with JSON serialization and error types. No event handling logic present.

#### Code Duplication
No duplication detected.

#### Recommendations
None. Well-structured timeline card model with appropriate validation and transformation methods.

---

### File: OnboardingPlaceholders.swift
**Status**: Clean

#### Commented Code
File header indicates this was created for "M0 skeleton milestone" with note "These will be expanded in later milestones" (lines 5-6). However, these models are actively used throughout the codebase and are not placeholders in practice.

#### Old Architectural Patterns
Fully migrated to new architecture. Contains comprehensive data models for messages, choices, wizard steps, uploads, artifacts, and UI state. All models are pure value types with no event handling logic.

#### Code Duplication
No duplication detected.

#### Recommendations
- **Optional/Low Priority**: Consider renaming file from `OnboardingPlaceholders.swift` to `OnboardingModels.swift` or `OnboardingDataStructures.swift` to reflect that these are production models, not placeholders. The file header comment suggests these were temporary but they've evolved into permanent domain models.

---

### File: InterviewPhase.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Defines core enums (InterviewPhase, ObjectiveStatus) that are referenced throughout the event-driven system but remain pure domain types.

#### Code Duplication
No duplication detected.

#### Recommendations
None. Clean enumeration definitions with appropriate metadata.

---

## SERVICES SUBDIRECTORY (4 files)

### File: UploadFileService.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Service class marked @MainActor for UI-related file operations (file dialogs, image validation). Uses modern async/await patterns. No event handling in this layer - appropriately delegates to callers.

#### Code Duplication
No duplication detected.

#### Recommendations
None. Clean service implementation with clear separation of concerns.

---

### File: ContactsImportService.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Service class marked @MainActor for Contacts framework integration. Uses modern async/await patterns with proper error handling via custom error enum.

#### Code Duplication
No duplication detected.

#### Recommendations
None. Well-structured service with appropriate use of async/await and error propagation.

---

### File: KnowledgeCardAgent.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Service class for LLM-based knowledge card generation. Uses async/await throughout, no callbacks or old patterns detected.

#### Code Duplication
No duplication detected.

#### Recommendations
None. Clean implementation with proper error handling and validation logic.

---

### File: DocumentExtractionService.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Actor-based service with async/await patterns throughout. The `@escaping` handler on line 87 (`setInvalidModelHandler`) is for error callback delegation and is an appropriate use case, not a legacy pattern.

**Note on Progress Handler**: Line 52 defines `ExtractionProgressHandler` as `@Sendable (ExtractionProgressUpdate) async -> Void`. This is a modern async callback pattern that allows the extraction service to report progress without direct event bus coupling. The service remains decoupled from EventCoordinator - callers can bridge to events if needed.

#### Code Duplication
No duplication detected.

#### Recommendations
None. The actor isolation and progress handler pattern represent good architectural choices that maintain service independence while enabling progress reporting.

---

## PHASE SUBDIRECTORY (5 files)

### File: PhaseThreeScript.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Implements PhaseScript protocol with declarative objective workflows. The workflow outputs use `.developerMessage` pattern which aligns with the event-driven coordinator design.

#### Code Duplication
No duplication detected.

#### Recommendations
None. Clean phase script with comprehensive documentation in the system prompt fragment.

---

### File: PhaseTwoScript.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Implements PhaseScript protocol consistently with Phase 3. Uses declarative workflow pattern with objective dependencies.

#### Code Duplication
No duplication detected. Structural similarity to Phase 3 is expected and appropriate - these follow the same protocol pattern.

#### Recommendations
None. Well-structured phase script with clear workflow definitions.

---

### File: PhaseOneScript.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Most comprehensive phase script with detailed objective workflows and extensive system prompt documentation. Uses modern workflow pattern with objective dependencies.

#### Code Duplication
No duplication detected.

#### Recommendations
None. Excellent documentation and clear workflow definitions make this an exemplar file.

---

### File: PhaseScriptRegistry.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Registry pattern marked @MainActor for safe access from UI context. Provides centralized access to phase scripts and system prompt building.

#### Recommendations
None. Clean registry implementation with appropriate actor isolation.

---

### File: PhaseScript.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. Protocol definition with associated types for workflow context and outputs. The enum-based output types (`.developerMessage`, `.triggerPhotoFollowUp`) are well-designed for event-driven coordination.

#### Code Duplication
No duplication detected.

#### Recommendations
None. Excellent protocol design with clear separation between phase logic and workflow orchestration.

---

## CROSS-CUTTING OBSERVATIONS

### Architectural Alignment

All three subdirectories demonstrate **excellent alignment** with the event-driven architecture specification:

1. **Models Directory**: Contains pure value types and data structures with no event handling logic. This is exactly as intended - models should be architecture-agnostic.

2. **Services Directory**: Services use modern async/await patterns and remain decoupled from EventCoordinator. They expose async APIs that can be called from handlers or other coordinators without direct event bus coupling. Progress reporting via async callbacks (DocumentExtractionService) is a clean pattern that preserves service independence.

3. **Phase Directory**: Phase scripts use declarative workflow patterns that output structured actions rather than directly publishing events. This allows the coordinator layer to interpret and route these outputs appropriately.

### Integration with Event Architecture

Based on the specification in `pub-sub-single-state-spec.md`, the integration points should be:

- **Models**: Consumed by handlers and coordinators, never produce events themselves (Verified: Correct)
- **Services**: Called by Tool Handlers and other handlers, report results via return values or async callbacks (Verified: Correct)
- **Phase Scripts**: Provide configuration and workflow logic consumed by StateCoordinator (Verified: Correct)

### No Evidence of Incomplete Migration

The audit found **no evidence** of:
- Commented-out code from refactoring
- Old callback patterns (except appropriate use cases)
- Direct event publishing from models or services
- Duplicated logic between old and new patterns
- Orphaned imports or dependencies
- TODO/FIXME markers indicating incomplete work

---

## OVERALL RECOMMENDATIONS

### 1. No Critical Action Items
All files in these three subdirectories are production-ready and require no immediate cleanup or refactoring.

### 2. Optional Enhancement
- Consider renaming `OnboardingPlaceholders.swift` to better reflect its role as a production data model file. This is purely cosmetic and non-blocking.

### 3. Documentation Alignment
- The file header in `OnboardingPlaceholders.swift` suggests these models are temporary ("skeleton milestone"), but they're actually core domain models. Update the header comment to reflect their permanent status.

### 4. Architectural Validation
- These directories serve as excellent examples of clean architecture:
  - Models are pure and reusable
  - Services are focused and testable
  - Phase scripts are declarative and maintainable
- Use these as reference implementations when refactoring other parts of the codebase.

### 5. No Build Required
No structural changes or cleanups are needed. No build verification is necessary for these directories.

---

## CONCLUSION

The Models, Services, and Phase subdirectories represent a **clean, well-architected foundation** for the event-driven onboarding system. The refactor has been completed successfully in these areas, with clear separation of concerns and appropriate use of modern Swift patterns.

These directories demonstrate that the architectural principles from the specification have been properly applied:
- Single responsibility principle (each file has a clear, focused purpose)
- Loose coupling (no direct event bus dependencies in models/services)
- Testability (services use dependency injection, models are pure)
- Maintainability (clear structure, comprehensive documentation)

**Recommendation**: Mark these three subdirectories as **COMPLETE** with respect to the event-driven architecture migration. They require no cleanup and can serve as reference implementations for other modules.

---

## APPENDIX: File Inventory

### Models (7 files)
1. OnboardingArtifactRecord.swift - SwiftData persistence model
2. OnboardingPreferences.swift - Preferences value struct
3. KnowledgeCardDraft.swift - Knowledge card domain models
4. ExtractionProgress.swift - Progress tracking models
5. TimelineCard.swift - Timeline card domain model
6. OnboardingPlaceholders.swift - Core UI and workflow models
7. InterviewPhase.swift - Phase and status enumerations

### Services (4 files)
1. UploadFileService.swift - File upload utilities
2. ContactsImportService.swift - macOS Contacts integration
3. KnowledgeCardAgent.swift - LLM-based card generation
4. DocumentExtractionService.swift - Document parsing and enrichment

### Phase (5 files)
1. PhaseThreeScript.swift - Phase 3 configuration
2. PhaseTwoScript.swift - Phase 2 configuration
3. PhaseOneScript.swift - Phase 1 configuration
4. PhaseScriptRegistry.swift - Phase script registry
5. PhaseScript.swift - Phase script protocol definition

**Total**: 16 files, all clean and production-ready
