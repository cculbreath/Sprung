# Periphery Unused Code Cleanup Plan

**Scan Date**: November 27, 2025
**Total Warnings**: 235
**Post-Refactor Status**: Many unused items are artifacts of the recent onboarding module decomposition

---

## Summary by Category

### High-Impact Files (>10 warnings)
| File | Warnings | Notes |
|------|----------|-------|
| OnboardingInterviewCoordinator.swift | 21 | Coordinator facade with many delegating methods |
| StateCoordinator.swift | 16 | Central state with many accessor methods |
| DocumentExtractionService.swift | 15 | Many unused model properties |
| OnboardingPlaceholders.swift | 14 | Legacy placeholder structs |
| ToolHandler.swift | 13 | Tool UI management with unused methods |
| ChatTranscriptStore.swift | 12 | Message store with unused accessors |

### Categories of Unused Code

1. **Redundant Facade Methods** (~40 warnings)
   - `OnboardingInterviewCoordinator` has many methods that simply delegate to child coordinators
   - These were likely created during decomposition as convenience wrappers
   - Many are now unused because callers access child coordinators directly

2. **Unused "Sync" Properties** (~15 warnings)
   - Pattern: `nonisolated(unsafe) var fooSync: T`
   - These were SwiftUI synchronous accessors for actor-isolated properties
   - Many were removed from use during the refactor but left in place

3. **Orphaned Stop/Cleanup Methods** (~4 warnings)
   - `stop()` methods on services that are never cleaned up
   - May indicate missing lifecycle management

4. **Unused Model Properties** (~30 warnings)
   - Properties defined in DTOs but never accessed
   - Common in `DocumentExtractionService`, `OnboardingPlaceholders`

5. **Dead Protocol Conformances** (~3 warnings)
   - `ExperienceDefaultsProviding` - protocol never used as existential
   - `OnboardingEventHandler` - redundant conformance

6. **Entire Unused Types** (~5 warnings)
   - `DeveloperMessageTemplates` struct
   - `HighlightListEditor` struct
   - `OnboardingQuestion` struct
   - `UploadUserResponse` struct
   - `TimelineCardError` enum

---

## Verification Strategy

Before removing any code, verify it's truly unused by:

1. **Check for dynamic usage**: Some methods may be called via reflection or string-based lookup
2. **Check for protocol requirements**: Method may be required by a protocol even if not directly called
3. **Check for future use**: Review recent commits to see if code was intentionally preserved
4. **Check for test usage**: Periphery scans production code only

---

## Cleanup Plan (Prioritized)

### Phase 1: Safe Removals (Low Risk)
These are clearly dead code with no side effects:

```
Priority: HIGH
Risk: LOW
Estimated Time: 2-3 hours
```

#### 1.1 Remove Entire Unused Types
- [ ] `DeveloperMessageTemplates` (Onboarding/Core/)
- [ ] `HighlightListEditor` (Experience/Views/)
- [ ] `OnboardingQuestion` (Onboarding/Models/)
- [ ] `UploadUserResponse` (Onboarding/Tools/)
- [ ] `TimelineCardError` (Onboarding/Models/)

#### 1.2 Remove Dead Protocol
- [ ] `ExperienceDefaultsProviding` protocol and conformance

#### 1.3 Remove Unused Properties in Models
- [ ] `Applicant.swift`: `label`, `summary`, `pictureDataURL`, `picture`, `profileDataURL`
- [ ] `OnboardingPlaceholders.swift`: Multiple unused properties
- [ ] `ValidationProtocols.swift`: `isEditing`, `beginEditing`, `toggleEditing`

### Phase 2: Facade Method Cleanup (Medium Risk)
These delegate methods may be intentionally preserved for API consistency:

```
Priority: MEDIUM
Risk: MEDIUM
Estimated Time: 4-6 hours
```

#### 2.1 OnboardingInterviewCoordinator Cleanup
Verify and remove unused facade methods:
- [ ] `eventStream(for:)`
- [ ] `advancePhase()`
- [ ] `getCompletedObjectiveIds()`
- [ ] `listArtifactRecords()`
- [ ] `getArtifact(id:)`
- [ ] `nextPhase()`
- [ ] `updateExtractionProgress(with:)`
- [ ] `setStreamingStatus(_:)`
- [ ] `synchronizeWizardTracker(currentStep:completedSteps:)`
- [ ] `presentChoicePrompt(_:)`
- [ ] `submitChoice(optionId:)`
- [ ] `presentValidationPrompt(_:)`
- [ ] `completeUploadAndResume(id:link:)`
- [ ] `notifyInvalidModel(id:)`
- [ ] `buildSystemPrompt(for:)`

#### 2.2 StateCoordinator Cleanup
- [ ] `advanceToNextPhase()`
- [ ] `canAdvancePhase()`
- [ ] `getLastResponseId()`
- [ ] `backfillObjectiveStatuses(snapshot:)`
- [ ] `setToolPaneCard(_:)`
- [ ] `getCurrentToolPaneCard()`
- [ ] `appendUserMessage(_:isSystemGenerated:)`
- [ ] `appendAssistantMessage(_:)`
- [ ] `beginStreamingMessage(initialText:reasoningExpected:)`
- [ ] `updateStreamingMessage(id:delta:)`
- [ ] `finalizeStreamingMessage(id:finalText:toolCalls:)`

#### 2.3 PhaseTransitionController Cleanup
- [ ] `advancePhase()`
- [ ] `nextPhase()`
- [ ] `getCompletedObjectiveIds()`
- [ ] `buildSystemPrompt(for:)`

### Phase 3: Service Method Cleanup (Higher Risk)
These may be intentionally preserved for future use:

```
Priority: LOW
Risk: HIGHER
Estimated Time: 3-4 hours
```

#### 3.1 ChatTranscriptStore
- [ ] `appendAssistantMessage(_:)`
- [ ] `getMessageCount()`
- [ ] `beginStreamingMessage(initialText:reasoningExpected:)`
- [ ] `getStreamingMessage()`
- [ ] `clearReasoningSummary()`
- [ ] `getLatestReasoningSummary()`
- [ ] `getCurrentReasoningSummary()`
- [ ] `getIsReasoningActive()`

#### 3.2 ArtifactRepository
- [ ] `addArtifactRecord(_:)`
- [ ] `addExperienceCard(_:)`
- [ ] `addWritingSample(_:)`
- [ ] `scratchpadSummary()`

#### 3.3 ConversationContextAssembler
- [ ] `buildForUserMessage(text:)`
- [ ] `buildForDeveloperMessage(text:)`
- [ ] `buildStateCues()`
- [ ] `buildConversationHistory()`
- [ ] `buildScratchpadSummary()`

### Phase 4: Sync Property Cleanup (Careful Review Required)
These were part of SwiftUI integration pattern:

```
Priority: LOW
Risk: MEDIUM
Estimated Time: 2-3 hours
```

- [ ] Review all `*Sync` properties
- [ ] Determine if still needed for SwiftUI bindings
- [ ] Remove if truly unused

---

## Recommended Approach

1. **Start with Phase 1** - These are safe deletions that reduce noise
2. **Build after each removal** - Verify no compilation errors
3. **Test critical flows** - Especially onboarding interview startup
4. **Commit incrementally** - One logical group per commit
5. **Re-run Periphery** - After each phase to track progress

---

## Commands

```bash
# Re-run scan after cleanup
periphery scan

# Quick count of remaining warnings
periphery scan 2>&1 | grep "warning:" | wc -l

# Filter to specific module
periphery scan 2>&1 | grep "Onboarding"
```

---

## Notes

- Many warnings are artifacts of the coordinator decomposition
- Some "unused" methods may be protocol requirements
- The `*Sync` pattern was intentional for SwiftUI but may now be obsolete
- Consider whether to remove vs. mark as `// periphery:ignore`
