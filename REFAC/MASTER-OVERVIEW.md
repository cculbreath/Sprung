# Onboarding Module Refactoring Plan - Master Overview

**Version:** 1.0  
**Date:** January 8, 2026  
**Total Estimated Duration:** 5-6 days (parallel execution)  
**Team Size:** 3 developers working independently

---

## Executive Summary

This document coordinates three parallel refactoring workstreams to address technical debt in the Sprung Onboarding module before open-sourcing. The smell reports identified 4 critical, 18 high, and 48 medium severity issues across 209 files. This plan addresses all critical and high-priority issues plus selected medium-priority improvements.

### Report Verification Status

All critical issues have been verified against the actual codebase:

| Issue | File | Line | Verified |
|-------|------|------|----------|
| Force unwrap crash risk | ToolPaneTabsView.swift | 121 | ✅ Confirmed |
| @unchecked Sendable bypass | ArtifactRecord.swift | 307 | ✅ Confirmed |
| Singleton violates DI | FileSystemToolWrappers.swift | 22 | ✅ Confirmed |
| God object (1318 lines) | OnboardingInterviewCoordinator.swift | - | ✅ Confirmed (57KB) |
| God object (1104 lines) | FileSystemTools.swift | - | ✅ Confirmed (35KB) |
| God object (1096 lines) | OnboardingCompletionReviewSheet.swift | - | ✅ Confirmed (38KB) |

---

## Workstream Summary

| Workstream | Owner | Focus Area | Duration | Priority |
|------------|-------|------------|----------|----------|
| **1: Core Infrastructure** | Developer A | OnboardingInterviewCoordinator, Threading, Events | 5-6 days | Critical |
| **2: Services & Data** | Developer B | FileSystemTools, Singleton, Models | 4-5 days | Critical |
| **3: UI & Handlers** | Developer C | View splitting, Animations, Handlers | 3-4 days | High |

### Parallel Execution Diagram

```
Week 1
┌─────────────────────────────────────────────────────────────────┐
│ Day 1       │ Day 2       │ Day 3       │ Day 4       │ Day 5   │
├─────────────┼─────────────┼─────────────┼─────────────┼─────────┤
│ WS1: Thread │ WS1: Extract│ WS1: Extract│ WS1: Events │ WS1:    │
│ Safety Fix  │ DataReset   │ Archive Mgr │ Grouping    │ Review  │
├─────────────┼─────────────┼─────────────┼─────────────┼─────────┤
│ WS2: Remove │ WS2: Split  │ WS2: Split  │ WS2: Std    │ WS2:    │
│ Singleton   │ FSTools     │ Models      │ Progress    │ Review  │
├─────────────┼─────────────┼─────────────┼─────────────┼─────────┤
│ WS3: Force  │ WS3: Split  │ WS3: Anim   │ WS3: Drop   │ WS3:    │
│ Unwrap Fix  │ ReviewSheet │ Constants   │ Zone Logic  │ Review  │
└─────────────┴─────────────┴─────────────┴─────────────┴─────────┘
                          ↓ Sync Points ↓
                    Day 2 Standup   Day 4 Integration
```

---

## Critical Path Items

These items MUST be completed before any open-source release:

### Day 1 Deliverables (All Workstreams)

| Workstream | Task | Impact |
|------------|------|--------|
| WS1 | Remove @unchecked Sendable from ArtifactRecord | Thread safety |
| WS1 | Replace unowned with weak in stores | Crash prevention |
| WS2 | Remove ArtifactFilesystemContext.shared singleton | DI compliance |
| WS3 | Fix force unwrap in ToolPaneTabsView | Crash prevention |

### Day 2-3 Deliverables

| Workstream | Task | Impact |
|------------|------|--------|
| WS1 | Extract OnboardingDataResetService | God object reduction |
| WS1 | Extract ArtifactArchiveManager | God object reduction |
| WS2 | Split FileSystemTools.swift into 7 files | Maintainability |
| WS3 | Split OnboardingCompletionReviewSheet | Maintainability |

---

## Dependency Matrix

Most tasks are independent, but these require coordination:

```
                    WS1           WS2           WS3
                 ┌─────────┐   ┌─────────┐   ┌─────────┐
Event Changes    │ Source  │──▶│ Notify  │──▶│ Update  │
(OnboardingEvents│         │   │         │   │ Handlers│
 grouping)       └─────────┘   └─────────┘   └─────────┘

                    WS2           WS3
                 ┌─────────┐   ┌─────────┐
Model Moves      │ Source  │──▶│ Update  │
(Placeholders    │         │   │ Imports │
 split)          └─────────┘   └─────────┘

                    WS1           WS2
                 ┌─────────┐   ┌─────────┐
Schema Utils     │ Notify  │◀──│ Source  │
(buildJSONSchema │         │   │         │
 extraction)     └─────────┘   └─────────┘
```

### Coordination Protocol

1. **Event Changes (WS1 → WS2/WS3):**
   - WS1 creates grouped enum structure with deprecated forwarding
   - WS2/WS3 update handler switch statements
   - WS1 removes deprecated cases after WS2/WS3 confirm

2. **Model Moves (WS2 → WS3):**
   - WS2 announces new file locations
   - WS3 updates import statements
   - Both verify builds

3. **Schema Utils (WS2 → WS1):**
   - WS2 extracts to `AgentSchemaUtilities`
   - WS1 updates agent files to use shared utility

---

## File Ownership

To prevent merge conflicts, each file is owned by one workstream:

### Workstream 1 Owns
```
Core/OnboardingInterviewCoordinator.swift
Core/StateCoordinator.swift
Core/OnboardingEvents.swift
Core/LLMMessenger.swift
Core/AnthropicRequestBuilder.swift
Core/OnboardingDependencyContainer.swift
Core/InterviewLifecycleController.swift
Models/ArtifactRecord.swift
Stores/ArtifactRecordStore.swift
Stores/OnboardingSessionStore.swift
```

### Workstream 2 Owns
```
Services/GitAgent/FileSystemTools.swift (splitting)
Services/CardMergeAgent/MergeCardsTool.swift
Tools/Implementations/FileSystemToolWrappers.swift
Models/OnboardingSessionModels.swift
Constants/OnboardingConstants.swift
Handlers/DocumentArtifactHandler.swift
```

### Workstream 3 Owns
```
Views/OnboardingCompletionReviewSheet.swift
Views/OnboardingInterviewView.swift
Views/Components/ToolPaneTabsView.swift
Views/Components/OnboardingInterviewChatComponents.swift
Views/Components/PersistentUploadDropZone.swift
Views/Components/OnboardingInterviewUploadRequestCard.swift
Models/OnboardingPlaceholders.swift
Handlers/ChatboxHandler.swift
```

### Shared (Coordinate Changes)
```
Handlers/SwiftDataSessionPersistenceHandler.swift  # WS2 primary, WS1 event coordination
```

---

## Git Workflow

### Branch Strategy
```
main
 └── refactor/onboarding-cleanup
      ├── refactor/ws1-core-infrastructure
      │    ├── ws1-thread-safety
      │    ├── ws1-coordinator-extraction
      │    └── ws1-event-grouping
      ├── refactor/ws2-services-data
      │    ├── ws2-singleton-removal
      │    ├── ws2-filesystem-split
      │    └── ws2-model-cleanup
      └── refactor/ws3-ui-handlers
           ├── ws3-critical-fixes
           ├── ws3-view-splitting
           └── ws3-animation-constants
```

### PR Guidelines

1. **Atomic PRs:** One task per PR when possible
2. **Naming:** `[WSn] Brief description of change`
3. **Review:** Cross-workstream review for shared concerns
4. **Merge Order:** 
   - Day 1 critical fixes first
   - Then by dependency order
   - Integration branch merges daily

### Merge Schedule
- **Day 1 EOD:** All critical fixes merged to integration branch
- **Day 3 EOD:** Core extractions and splits complete
- **Day 5 EOD:** All workstreams complete, final integration
- **Day 6:** Integration testing and release prep

---

## Risk Mitigation

### Risk 1: Coordinator Extraction Breaks Functionality
**Mitigation:** 
- Create extracted services with tests first
- Use facade pattern to maintain existing API
- Feature flag new implementations:
  ```swift
  let useExtractedServices = UserDefaults.standard.bool(forKey: "useExtractedServices")
  ```

### Risk 2: Event System Changes Break Handlers
**Mitigation:**
- Use deprecated forwarding during transition:
  ```swift
  @available(*, deprecated, message: "Use .artifact(.created) instead")
  case artifactCreated(ArtifactRecord)
  // Forwards to new structure internally
  ```

### Risk 3: Model Splits Cause Import Errors
**Mitigation:**
- Create type aliases in original location:
  ```swift
  // OnboardingPlaceholders.swift (after split)
  @available(*, deprecated, renamed: "OnboardingMessage")
  typealias OldOnboardingMessage = OnboardingMessage
  ```

### Risk 4: Animation Changes Break UI Feel
**Mitigation:**
- Extract constants first without changing values
- Visual QA before and after
- Keep old values as fallback

---

## Testing Strategy

### Unit Tests
| Workstream | Test Focus |
|------------|------------|
| WS1 | Thread safety (actor isolation), service extraction |
| WS2 | Tool execution without singleton, model serialization |
| WS3 | View snapshot tests, animation timing |

### Integration Tests
- Full interview flow with extracted services
- Document processing with split tools
- UI automation for view changes

### Manual QA Checklist
- [ ] Complete onboarding flow
- [ ] Document upload and extraction
- [ ] Knowledge card creation and editing
- [ ] Timeline editing
- [ ] Phase transitions
- [ ] Session resume

---

## Success Criteria

### Quantitative Metrics
| Metric | Before | Target |
|--------|--------|--------|
| Critical issues | 4 | 0 |
| Files > 1000 lines | 3 | 0 |
| Files > 500 lines | 10 | 5 |
| Singleton usages | 1 | 0 |
| Force unwraps | 1 | 0 |
| @unchecked Sendable | 1 | 0 |

### Qualitative Criteria
- [ ] Code builds with `-strict-concurrency=complete`
- [ ] All existing tests pass
- [ ] No visual regressions
- [ ] Architecture follows stated DI principles
- [ ] Ready for external code review

---

## Post-Refactoring Actions

1. **Update CLAUDE.md:** Document new file locations and patterns
2. **Update Architecture Diagrams:** Reflect service extractions
3. **Create Migration Guide:** For any API changes
4. **Update CHANGELOG:** Document all structural changes
5. **Schedule Code Review:** External review for open-source readiness

---

## Appendix: Quick Reference

### New Files Created

**Workstream 1:**
- `Core/Services/OnboardingDataResetService.swift`
- `Core/Services/ArtifactArchiveManager.swift`
- `Core/Debug/DebugRegenerationService.swift`
- `Core/Config/OnboardingLLMConfig.swift`

**Workstream 2:**
- `Services/GitAgent/AgentToolProtocol.swift`
- `Services/GitAgent/GitToolError.swift`
- `Services/GitAgent/GitToolUtilities.swift`
- `Services/GitAgent/Tools/ReadFileTool.swift` (and 5 more)
- `Services/Shared/AgentSchemaUtilities.swift`
- `Services/Shared/ExtractionProgress.swift`
- `Models/SessionModels/OnboardingSession.swift` (and 4 more)

**Workstream 3:**
- `Views/CompletionReview/CompletionKnowledgeCardsTab.swift` (and 2 more)
- `Views/Shared/OnboardingAnimations.swift`
- `Views/Shared/DropZoneConfiguration.swift`
- `Views/Shared/DropZoneView.swift`
- `Views/Shared/ToastView.swift`
- `Models/UIModels/OnboardingMessage.swift` (and 3 more)

### Files to Delete (After Migration)
- Legacy objective ID cases in `OnboardingConstants.swift`
- `OnboardingMessageRecord` (after migration to `ConversationEntryRecord`)
- Original `FileSystemTools.swift` (after split)

---

*Document prepared for Sprung Onboarding Module refactoring initiative*
