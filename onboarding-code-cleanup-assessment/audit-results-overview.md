# Onboarding Module Audit Results Overview

**Audit Date**: 2025-11-04
**Module**: Sprung/Onboarding
**Architecture Spec**: ./planning/pub-sub-single-state-spec.md

## Executive Summary

A comprehensive audit of the entire onboarding module (14,817 LOC across 71 files) was conducted to assess the state of the event-driven architecture refactor. The module was divided into 5 logical groups based on folder structure and lines of code.

**Overall Health Score: 72% Clean**

- **Clean Files**: 51 (72%)
- **Minor Issues**: 15 (21%)
- **Significant Issues**: 5 (7%)

## Audit Groups

### Group 1: Views (5,037 LOC)
**Status**: 🟡 Refactor In Progress
**Files**: 31
**Report**: [group1-views-audit.md](./group1-views-audit.md)

#### Summary
- **Clean**: 20 files (65%) - Pure presentation components
- **Needs Cleanup**: 11 files (35%) - Systematic migration TODOs
- **TODO Comments**: 85+ marking incomplete event-driven migrations

#### Key Issues
1. **Tool Continuation Pattern**: 8+ locations still using old `resumeToolContinuation` → needs `Tool.result` events
2. **Wizard Step Management**: Multiple commented transitions → needs `Phase.transition.requested` events
3. **State Queries**: Direct coordinator access → needs StateCoordinator subscriptions
4. **Service Method Calls**: Direct service calls → needs event emissions

#### Files Requiring Significant Work
- `OnboardingInterviewView.swift` - Wizard step transitions, extraction management, preference handling
- `OnboardingInterviewToolPane.swift` - Tool completion handlers, continuation pattern removal

#### Estimated Work
**6-10 sprint days** to complete Views folder migration

---

### Group 2: Core (3,843 LOC)
**Status**: 🟡 Needs Cleanup
**Files**: 11
**Report**: [group2-core-audit.md](./group2-core-audit.md)

#### Summary
- **Clean**: 6 files (55%)
- **Minor Cleanup**: 3 files (27%)
- **Significant Work**: 2 files (18%)

#### Critical Issues
1. **Deprecated Code Not Removed**: `InterviewOrchestrator.swift` has deprecated `resumeToolContinuation` method
2. **Legacy Support Code**: `OnboardingInterviewCoordinator.swift` contains 40+ lines of legacy code marked for "Phase 2" removal
3. **Polling Anti-Patterns**: Two files use timer-based polling instead of event subscriptions
4. **Old Architectural Patterns**: Tool choice override logic doesn't align with StateCoordinator approach

#### Files Requiring Attention
- `OnboardingInterviewCoordinator.swift` - Large legacy support section, polling-based state observation
- `InterviewOrchestrator.swift` - Deprecated method, old tool choice override logic
- `OnboardingInterviewService.swift` - Polling anti-pattern instead of events
- `LLMMessenger.swift` - Incomplete feature TODOs
- `StateCoordinator.swift` - Minor TODOs for partial state updates

---

### Group 3: Tools + Handlers (3,199 LOC)
**Status**: 🟢 Excellent (87% Clean)
**Files**: 30 (22 Tools + 8 Handlers)
**Report**: [group3-tools-handlers-audit.md](./group3-tools-handlers-audit.md)

#### Summary
- **Clean**: 26 files (87%)
- **Minor Issues**: 1 file (3%)
- **Significant Issues**: 3 files (10%)

#### Outstanding Issues
1. **ValidateApplicantProfileTool.swift** - Stub implementation, needs completion or removal
2. **GetArtifactRecordTool.swift** - Stub implementation, needs artifact retrieval functionality
3. **RequestRawArtifactFileTool.swift** - Stub implementation, needs raw file access implementation
4. **CancelUserUploadTool.swift** - Minor stub methods need event integration

#### Positive Observations
- **All 8 Handlers are 100% clean** and properly implemented
- Excellent migration quality in completed tools
- No legacy code or mixed patterns
- Consistent use of continuation tokens and event patterns
- Well-documented gaps with clear TODO comments

---

### Group 4: Models + Services + Phase (2,101 LOC)
**Status**: 🟢 Pristine
**Files**: 16 (7 Models + 4 Services + 5 Phase)
**Report**: [group4-models-services-phase-audit.md](./group4-models-services-phase-audit.md)

#### Summary
- **Clean**: 16 files (100%)
- **Issues**: 0
- **Cosmetic Suggestions**: 1 (optional file rename)

#### Highlights
- **Zero cleanup required** - all files in excellent condition
- Pure data structures with no event handling logic (Models)
- Modern async/await patterns, properly decoupled from EventCoordinator (Services)
- Declarative workflow patterns (Phase Scripts)
- **Serves as reference implementation** for other modules

#### Optional Improvement
- Consider renaming `OnboardingPlaceholders.swift` to `OnboardingModels.swift` (cosmetic only)

---

### Group 5: Utilities + Stores + ViewModels + Managers (837 LOC)
**Status**: 🟢 Pristine
**Files**: 13 (6 Utilities + 3 Stores + 1 ViewModel + 1 Manager)
**Report**: [group5-utilities-stores-viewmodels-managers-audit.md](./group5-utilities-stores-viewmodels-managers-audit.md)

#### Summary
- **Clean**: 13 files (100%)
- **Issues**: 0

#### Highlights
- **Zero cleanup required** - all files in excellent condition
- Excellent architecture compliance across all components
- Proper component design with clear separation of concerns
- Actor-based persistence patterns (Stores)
- Pure transformation functions (Utilities)
- Clean service layer interaction (ViewModels)
- **Represents target state** for entire codebase

---

## Priority Recommendations

### High Priority (Complete First)
1. **Remove Legacy Code in Core** - Delete deprecated methods and legacy support sections in `InterviewOrchestrator.swift` and `OnboardingInterviewCoordinator.swift`
2. **Replace Polling with Events** - Convert timer-based polling to event subscriptions in Core files
3. **Complete Critical Stubs** - Finish or remove `ValidateApplicantProfileTool`, `GetArtifactRecordTool`, and `RequestRawArtifactFileTool`

### Medium Priority (Next Sprint)
4. **Migrate Views Core Flows** - Complete event-driven migration for `OnboardingInterviewView.swift` and `OnboardingInterviewToolPane.swift`
5. **Tool Continuation Pattern** - Replace old `resumeToolContinuation` pattern with `Tool.result` events across Views

### Low Priority (Ongoing)
6. **Complete Minor TODOs** - Address remaining TODO comments in `LLMMessenger.swift`, `StateCoordinator.swift`, and minor Views components
7. **Wizard Step Transitions** - Migrate commented wizard transitions to `Phase.transition.requested` events

---

## Architecture Compliance Assessment

### ✅ Strengths
- **72% of files fully compliant** with event-driven architecture
- **Excellent separation of concerns** in Models, Services, Phase, Utilities, Stores, ViewModels, and Managers
- **No anti-patterns detected** in compliant files
- **Well-documented migration gaps** with TODO comments
- **Consistent patterns** in completed migrations

### ⚠️ Areas for Improvement
- **Legacy code removal** - Some deprecated methods and support sections remain
- **Polling anti-patterns** - Timer-based state observation in 2 files
- **Incomplete tool implementations** - 3 stub tools need completion
- **Views migration** - 11 files still have migration TODOs

### 🎯 Target State Achieved In
- Models (100%)
- Services (100%)
- Phase (100%)
- Utilities (100%)
- Stores (100%)
- ViewModels (100%)
- Managers (100%)
- Handlers (100%)

---

## Estimated Completion Timeline

| Work Category | Estimated Effort |
|---------------|------------------|
| Core cleanup (legacy removal, polling fix) | 2-3 days |
| Complete stub tool implementations | 2-4 days |
| Views core flow migration | 3-5 days |
| Views remaining TODOs | 3-5 days |
| **Total** | **10-17 days** |

---

## Conclusion

The onboarding module demonstrates a **successful event-driven architecture refactor** with the majority of code (72%) fully compliant. The remaining work is well-documented and concentrated in two primary areas: **Core** (legacy cleanup) and **Views** (migration completion).

The **Models, Services, Phase, Utilities, Stores, ViewModels, and Managers** subdirectories represent exemplary implementations and should be used as reference patterns for future development.

With focused effort on the priority recommendations, the onboarding module can achieve 100% architecture compliance within 2-3 sprints.

---

## Report Files

1. [group1-views-audit.md](./group1-views-audit.md) - Views subfolder (31 files, 5,037 LOC)
2. [group2-core-audit.md](./group2-core-audit.md) - Core subfolder (11 files, 3,843 LOC)
3. [group3-tools-handlers-audit.md](./group3-tools-handlers-audit.md) - Tools + Handlers (30 files, 3,199 LOC)
4. [group4-models-services-phase-audit.md](./group4-models-services-phase-audit.md) - Models + Services + Phase (16 files, 2,101 LOC)
5. [group5-utilities-stores-viewmodels-managers-audit.md](./group5-utilities-stores-viewmodels-managers-audit.md) - Utilities + Stores + ViewModels + Managers (13 files, 837 LOC)
