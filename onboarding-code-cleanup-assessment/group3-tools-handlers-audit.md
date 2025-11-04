# Onboarding Module Code Cleanup Assessment
## Subfolders: Tools & Handlers

**Assessment Date**: November 4, 2025
**Architecture Reference**: ./planning/pub-sub-single-state-spec.md

---

## Executive Summary

**Total Files Evaluated**: 30 files (22 Tools + 8 Handlers)
**Files Requiring Cleanup**: 4 files
**Critical Issues**: 3 stub implementations requiring completion
**Minor Issues**: 1 availability method requiring event integration

### Overall Status
The Tools and Handlers subfolders show excellent migration to the new event-driven architecture. The majority of files (26 out of 30) are fully implemented and properly integrated with the pub-sub event system. Only 4 files contain stub implementations with TODO comments indicating planned future work.

---

## TOOLS SUBFOLDER ASSESSMENT

### File: ToolProtocol.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated to new architecture. The protocol properly defines the contract for tools with support for continuation tokens and UI requests, which are core to the event-driven model.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. This file is well-structured and serves as an excellent foundation for all tool implementations.

---

### File: ToolRegistry.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Uses thread-safe DispatchQueue for concurrent access and supports dynamic tool availability checking via async methods.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. The registry is properly implemented with thread safety and async support.

---

### File: ToolExecutor.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. The actor-based implementation is perfect for the new architecture, properly managing tool execution and continuation tokens.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. The executor properly normalizes results and handles errors according to the spec.

---

### File: GetUserOptionTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Properly implements continuation-based pattern with UI request emission for choice prompts.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Excellent implementation following the spec's choice prompt pattern (Spec Section 4.7).

---

### File: GetUserUploadTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Implements continuation-based upload flow with proper support for file uploads, URL inputs, and targeted uploads (e.g., basics.image).

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Comprehensive implementation with excellent validation and error handling.

---

### File: GetApplicantProfileTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Simple continuation-based tool that properly delegates to the profile intake flow via UI request.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Clean implementation following the event-driven pattern.

---

### File: GetMacOSContactCardTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Direct integration with macOS Contacts.framework with proper permission handling and artifact record generation.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Well-structured with excellent error handling for permission denied and not found cases.

---

### File: ExtractDocumentTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Properly delegates to DocumentExtractionService with support for various return types and progress reporting.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Clean implementation with proper error handling and result normalization.

---

### File: ValidateApplicantProfileTool.swift
**Status**: Requires Significant Work

#### Commented Code
Line 17: `// TODO: Reimplement using event-driven architecture`

#### Old Architectural Patterns
**CRITICAL**: This tool is a stub implementation that returns a placeholder response. The TODO comment indicates this needs to be reimplemented using the event-driven architecture.

#### Code Duplication
No duplication detected, but functionality is incomplete.

#### Recommendations
1. **PRIORITY HIGH**: Implement the validation logic according to the event-driven pattern
2. Consider whether this tool is still needed given that `SubmitForValidationTool.swift` exists and appears fully implemented
3. If this tool is redundant, remove it from the codebase
4. If it serves a different purpose than SubmitForValidationTool, implement it following the continuation pattern with validation prompt UI request
5. Verify with the team whether this stub should be completed or removed

---

### File: SubmitForValidationTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Implements continuation-based validation flow with support for multiple validation types (applicant_profile, skeleton_timeline, enabled_sections).

#### Code Duplication
**POTENTIAL**: There may be conceptual overlap with ValidateApplicantProfileTool.swift. The team should clarify whether both tools are needed or if ValidateApplicantProfileTool is legacy and should be removed.

#### Recommendations
1. Clarify the distinction between this tool and ValidateApplicantProfileTool
2. If ValidateApplicantProfileTool is redundant, remove it from the registry
3. Otherwise, no changes needed - this implementation is excellent

---

### File: PersistDataTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Properly delegates to InterviewDataStore for persistence operations.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Clean implementation with good error handling.

---

### File: GenerateKnowledgeCardTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Properly uses dependency injection via agentProvider closure and delegates to KnowledgeCardAgent.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Well-structured with proper error handling for agent availability and generation failures.

---

### File: SetObjectiveStatusTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Properly delegates to the coordinator which emits events according to the spec (Section 4.1).

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Clean implementation that properly validates status values and delegates to the state coordinator.

---

### File: NextPhaseTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Properly checks objectives and delegates phase transitions to the coordinator which emits events.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Excellent implementation with proper objective checking and phase progression logic.

---

### File: CreateTimelineCardTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Delegates to coordinator for timeline card creation with event emission.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Clean and simple implementation.

---

### File: UpdateTimelineCardTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Delegates to coordinator for timeline card updates with event emission.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Clean implementation with proper validation.

---

### File: DeleteTimelineCardTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Delegates to coordinator for timeline card deletion with event emission.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Clean implementation.

---

### File: ReorderTimelineCardsTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Delegates to coordinator for timeline card reordering with event emission.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Clean implementation with proper validation.

---

### File: CancelUserUploadTool.swift
**Status**: Needs Minor Cleanup

#### Commented Code
Lines 32-33: `// TODO: Check via event system`
Line 37: `// TODO: Reimplement using event-driven architecture`

#### Old Architectural Patterns
**ISSUE**: The tool has stub implementations:
- `isAvailable()` returns false with a TODO to check via event system
- `execute()` returns a placeholder response with TODO to reimplement

#### Code Duplication
No duplication detected.

#### Recommendations
1. **PRIORITY MEDIUM**: Implement the isAvailable() check to query whether an upload request is currently pending (could check UploadInteractionHandler state via event query or shared state)
2. Implement the execute() method to emit an event that cancels the active upload continuation
3. Consider whether this tool is needed - the upload flow may handle cancellation through other means (timeout, user action, etc.)
4. If the tool is needed, integrate it with UploadInteractionHandler's cancellation flow

---

### File: ListArtifactsTool.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Properly delegates to service for artifact summaries with availability checking.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Clean implementation with proper MainActor usage for service calls.

---

### File: GetArtifactRecordTool.swift
**Status**: Requires Significant Work

#### Commented Code
Line 17: `// TODO: Reimplement using event-driven architecture`

#### Old Architectural Patterns
**CRITICAL**: This tool is a stub implementation that returns a placeholder response.

#### Code Duplication
No duplication detected, but functionality is incomplete.

#### Recommendations
1. **PRIORITY HIGH**: Implement the artifact retrieval logic using event-driven architecture
2. Should likely delegate to ArtifactHandler or directly query OnboardingArtifactStore
3. Define proper parameters schema (currently empty) to accept artifact ID
4. Emit appropriate events when artifacts are retrieved
5. Add proper error handling for artifact not found cases

---

### File: RequestRawArtifactFileTool.swift
**Status**: Requires Significant Work

#### Commented Code
Line 12: `// TODO: Reimplement using event-driven architecture`

#### Old Architectural Patterns
**CRITICAL**: This tool is a stub implementation that returns a placeholder response.

#### Code Duplication
No duplication detected, but functionality is incomplete.

#### Recommendations
1. **PRIORITY HIGH**: Implement the raw file retrieval logic using event-driven architecture
2. Define proper parameters schema (currently empty) to accept artifact ID and possibly format preferences
3. Should delegate to artifact storage system to retrieve raw file data
4. Consider security implications of exposing raw file access
5. Add proper error handling for file not found cases

---

## HANDLERS SUBFOLDER ASSESSMENT

### File: PromptInteractionHandler.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Uses @Observable for reactive SwiftUI integration and properly manages continuation IDs for choice and validation prompts.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Excellent implementation that properly bridges between the event system and SwiftUI's Observable system.

---

### File: SectionToggleHandler.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Clean @Observable implementation for resume section toggle management.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Well-structured with proper state management and JSON payload construction.

---

### File: UploadInteractionHandler.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Comprehensive implementation with proper support for local uploads, remote URLs, targeted uploads (basics.image), and progress reporting.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. This is an exemplary implementation with excellent logging, error handling, and integration with multiple services (UploadFileService, OnboardingUploadStorage, ApplicantProfileStore).

---

### File: ProfileInteractionHandler.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Comprehensive handler supporting multiple profile intake modes (manual, URL, upload, contacts) with proper state machine management.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. Excellent implementation with clear separation between validation flow and intake flow, proper metadata attachment, and comprehensive error handling.

---

### File: ChatboxHandler.swift
**Status**: Clean

#### Commented Code
Line 88: `// TODO: Handle processing state changes for UI feedback`

#### Old Architectural Patterns
Fully migrated to event-driven architecture. The actor-based implementation properly subscribes to LLM and processing events.

#### Code Duplication
No duplication detected.

#### Recommendations
1. **PRIORITY LOW**: Implement the processing state change handler if processing state feedback is needed in the UI
2. The TODO is minor and doesn't block functionality - the core chat streaming functionality is complete
3. Otherwise, no action needed - excellent implementation of Spec Section 4.9

---

### File: LLMReasoningHandler.swift
**Status**: Clean

#### Commented Code
Lines 55-60: Commented out case statements for reasoning events with explanation that OpenAI Responses API doesn't currently expose reasoning in streaming mode

#### Old Architectural Patterns
Fully migrated. The handler is properly structured for future reasoning support when the API becomes available.

#### Code Duplication
No duplication detected.

#### Recommendations
1. **NO ACTION NEEDED**: The commented code is intentional and well-documented as future preparation
2. When OpenAI adds reasoning API support, uncomment lines 56-60 to enable the feature
3. The implementation is ready and waiting for API support - this is good forward-thinking design

---

### File: ToolExecutionCoordinator.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Excellent actor-based implementation following Spec Section 4.6 precisely.

#### Code Duplication
No duplication detected.

#### Recommendations
No action needed. This is an exemplary implementation that properly:
- Validates tools against allowed tools from StateCoordinator
- Manages continuation tokens
- Emits UI request events based on tool needs
- Handles all three ToolResult types (immediate, waiting, error)

---

### File: ArtifactHandler.swift
**Status**: Clean

#### Commented Code
None found.

#### Old Architectural Patterns
Fully migrated. Actor-based implementation following Spec Section 4.8 with proper event subscription and delegation to DocumentExtractionService.

#### Code Duplication
No duplication detected.

#### Recommendations
1. **MINOR**: Consider adding the Artifact.get event handler when GetArtifactRecordTool is implemented
2. The "Public API (called by tools until events are added)" comment on line 77 suggests the extractDocument method is transitional - consider whether this should be event-driven or remain as a public method
3. Otherwise, no action needed - clean implementation

---

## Overall Recommendations

### Critical Priority (Address Immediately)
1. **Complete or Remove ValidateApplicantProfileTool** - This stub needs to be either fully implemented or removed if redundant with SubmitForValidationTool
2. **Implement GetArtifactRecordTool** - This tool is needed for artifact retrieval functionality
3. **Implement RequestRawArtifactFileTool** - Complete this stub or determine if raw file access is needed

### Medium Priority (Address Soon)
4. **Complete CancelUserUploadTool** - Implement isAvailable() and execute() methods to properly integrate with upload cancellation flow
5. **Clarify tool duplication** - Determine if ValidateApplicantProfileTool and SubmitForValidationTool serve distinct purposes or if one should be removed

### Low Priority (Address When Convenient)
6. **Add processing state feedback** - Implement the TODO in ChatboxHandler line 88 if processing state UI feedback is needed
7. **Review ArtifactHandler public API** - Consider whether extractDocument should be fully event-driven

### Architectural Observations
1. **Excellent Event-Driven Migration**: The vast majority of code (26 out of 30 files) shows complete migration to the new pub-sub architecture
2. **Consistent Patterns**: Tools consistently use continuation tokens for user input, handlers properly use @Observable for SwiftUI integration, and actors are used appropriately for thread safety
3. **Stub Implementations Are Well-Marked**: All incomplete implementations have clear TODO comments explaining what needs to be done
4. **No Legacy Code Found**: There are no commented-out old implementations or mixed patterns - the migration was clean
5. **Proper Separation of Concerns**: Tools delegate to services and coordinators, handlers manage UI state and continuation resolution

### Suggestions for Preventing Similar Issues
1. **Definition of Done**: Ensure all tool stubs are completed before marking phase complete, or explicitly flag them as "future enhancements"
2. **Tool Audit**: Run a registry check to ensure all registered tools have complete implementations
3. **Test Coverage**: Add integration tests that exercise all tool code paths to catch stub implementations
4. **Documentation**: Create a tools manifest that lists each tool, its implementation status, and its purpose to prevent duplication

---

## Summary Statistics

### Tools Subfolder (22 files)
- Clean: 18 files (82%)
- Needs Minor Cleanup: 1 file (5%)
- Requires Significant Work: 3 files (13%)

### Handlers Subfolder (8 files)
- Clean: 8 files (100%)
- Needs Minor Cleanup: 0 files
- Requires Significant Work: 0 files

### Combined (30 files)
- Clean: 26 files (87%)
- Needs Minor Cleanup: 1 file (3%)
- Requires Significant Work: 3 files (10%)

### Migration Quality Score: 87%
The Tools and Handlers subfolders demonstrate an excellent migration to the event-driven architecture. The 4 files requiring attention are clearly marked with TODO comments and represent planned future work rather than incomplete migration artifacts. The codebase is production-ready for the implemented tools, with the stub implementations representing known gaps in functionality rather than technical debt.
