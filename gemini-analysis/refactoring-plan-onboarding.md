# Onboarding Module Refactoring Plan (Parallelized)

Based on architectural review (Grade: B+, AI Slop Index: 3/10)

## Phase 1: Critical Fixes (3 Parallel Agents)

| Agent | Task | Files | Dependencies |
|-------|------|-------|--------------|
| **Agent A** | Fix synchronous file I/O on Main Actor | `UploadInteractionHandler.swift` | None |
| **Agent B** | Fix unsafe force unwrapping of file paths | `OnboardingUploadStorage.swift`, `InterviewDataStore.swift` | None |
| **Agent C** | Fix blocking Git process + Add retry limits | `GitIngestionKernel.swift`, `StateCoordinator.swift` | None |

**Status:** ✅ All 3 can run in parallel

---

## Phase 2: Infrastructure Improvements (2 Parallel Agents)

| Agent | Task | Files | Dependencies |
|-------|------|-------|--------------|
| **Agent D** | Reduce event history size + strip heavy payloads | `OnboardingEvents.swift` | None |
| **Agent E** | Centralize tool gating logic into pure function | `SessionUIState.swift`, `LLMStateManager.swift` | None |

**Status:** ✅ Both can run in parallel

---

## Phase 3: Tool Architecture Refactor (Sequential then Parallel)

**Step 1: Create shared infrastructure (1 Agent, blocking)**

| Agent | Task | Files |
|-------|------|-------|
| **Agent F** | Create `ToolResult` enum and `TimelineToolSchema` shared types | New: `Tools/Shared/ToolResult.swift`, `Tools/Shared/TimelineToolSchema.swift` |

**Step 2: Refactor tools (3 Parallel Agents) - after Step 1 completes**

| Agent | Task | Files | Dependencies |
|-------|------|-------|--------------|
| **Agent G** | Refactor Timeline tools to use shared schema + return `ToolResult` | `CreateTimelineCardTool.swift`, `UpdateTimelineCardTool.swift`, `DeleteTimelineCardTool.swift` | Agent F |
| **Agent H** | Refactor Knowledge Card tools to return `ToolResult` | `SubmitKnowledgeCardTool.swift`, `UpdateKnowledgeCardTool.swift` | Agent F |
| **Agent I** | Refactor remaining tools to return `ToolResult` | All other `Tools/Implementations/*.swift` | Agent F |

---

## Phase 4: Type Safety (2 Parallel Agents)

| Agent | Task | Files | Dependencies |
|-------|------|-------|--------------|
| **Agent J** | Replace string objective IDs with typed enums | `OnboardingConstants.swift`, `PhaseScript` files, `ObjectiveWorkflowEngine.swift` | None |
| **Agent K** | Implement Codable → JSONSchema generator | New: `Tools/Shared/SchemaGenerator.swift`, update tool schemas | None |

**Status:** ✅ Both can run in parallel

---

## Phase 5: Extract Resources (2 Parallel Agents)

| Agent | Task | Files | Dependencies |
|-------|------|-------|--------------|
| **Agent L** | Extract prompts to resource files | `Phase/*Script.swift`, `KCAgentPrompts.swift`, `GitAgentPrompts.swift` → new `.txt` files | None |
| **Agent M** | Consolidate validation views into generic `ReviewCard<Content>` | `KnowledgeCardReviewCard.swift`, `ApplicantProfileReviewCard.swift` | None |

**Status:** ✅ Both can run in parallel

---

## Phase 6: Coordinator Refactor (Sequential)

⚠️ **Must complete after Phases 3-5** - depends on tools being decoupled

| Agent | Task | Files |
|-------|------|-------|
| **Agent N** | Audit `.arch-spec`, then refactor `OnboardingInterviewCoordinator` to expose sub-services | `OnboardingInterviewCoordinator.swift`, `.arch-spec` |

---

## Phase 7: Dead Code Cleanup (1 Agent)

| Agent | Task | Files |
|-------|------|-------|
| **Agent O** | Remove unused enum cases, constants, and misplaced types | `ToolHandler.swift`, `OnboardingConstants.swift`, `PersistentUploadDropZone.swift` |

---

## Execution Flow Diagram

```
Phase 1: ──┬── Agent A (file I/O)
           ├── Agent B (force unwrap)
           └── Agent C (git + retry)
                    │
Phase 2: ──┬── Agent D (event history)
           └── Agent E (tool gating)
                    │
Phase 3: ──── Agent F (shared infra) ──┬── Agent G (timeline tools)
                                       ├── Agent H (KC tools)
                                       └── Agent I (other tools)
                    │
Phase 4: ──┬── Agent J (typed enums)
           └── Agent K (schema generator)
                    │
Phase 5: ──┬── Agent L (extract prompts)
           └── Agent M (generic ReviewCard)
                    │
Phase 6: ──── Agent N (coordinator refactor)
                    │
Phase 7: ──── Agent O (dead code cleanup)
```

## Issue Details

### Critical Issues

**1.1. Synchronous File I/O on Main Actor**
- **File:** `Sprung/Onboarding/Handlers/UploadInteractionHandler.swift`
- **Problem:** `Data(contentsOf:)` called on `@MainActor` class freezes UI for large files
- **Fix:** Move to `Task.detached` before returning to MainActor

**1.2. Unsafe Force Unwrapping of File Paths**
- **Files:** `OnboardingUploadStorage.swift`, `InterviewDataStore.swift`
- **Problem:** `FileManager.urls(...)[0]` crashes if array empty
- **Fix:** Use `guard let first = urls.first else { throw ... }`

**1.3. Potential Infinite Loop in Tool Recovery**
- **File:** `StateCoordinator.swift`
- **Problem:** Stream error retry can loop indefinitely with 2s sleep
- **Fix:** Implement exponential backoff (2s → 4s → 8s) with max 3 retries

**1.4. Git Process Blocking Actor**
- **File:** `GitIngestionKernel.swift`
- **Problem:** `Process.run()` + `waitUntilExit()` blocks actor
- **Fix:** Wrap in `Task.detached`

### High Priority Issues

**2.1. God Object Pattern: OnboardingInterviewCoordinator**
- **File:** `OnboardingInterviewCoordinator.swift`
- **Problem:** Proxies dozens of methods to underlying services
- **Fix:** Expose sub-services directly (e.g., `coordinator.timeline.update(...)`)
- **Note:** Audit `.arch-spec` first to check if boundaries need redefining

**2.2. Unbounded Event History Growth**
- **File:** `OnboardingEvents.swift`
- **Problem:** 10,000 event cap with heavy payloads (Base64) consumes memory
- **Fix:** Reduce to 1,000; strip heavy payloads; wrap in `#if DEBUG`

**2.3. Tool Coupling via Coordinator**
- **Files:** All `Tools/Implementations/*.swift`
- **Problem:** Tools call coordinator directly, creating circular dependency
- **Fix:** Return `ToolResult` enum instead (`.requestUI(payload)`, `.updateData(data)`)

### Medium Priority Issues

**3.1. Tool Definition Duplication**
- **Files:** `CreateTimelineCardTool.swift`, `UpdateTimelineCardTool.swift`, `DeleteTimelineCardTool.swift`
- **Fix:** Create shared `TimelineToolSchema` or consolidate into `TimelineActionTool`

**3.2. Manual JSON Schema Definitions**
- **Files:** `Tools/Schemas/*.swift`
- **Fix:** Implement Codable → JSONSchema generator

**3.3. Hardcoded Prompt Strings**
- **Files:** `Phase/*Script.swift`, `KCAgentPrompts.swift`
- **Fix:** Move to external `.txt` resource files

### Dead Code

**4.1. Unused Tool Identifier Case**
- `OnboardingToolIdentifier.getMacOSContactCard` - not registered in `OnboardingToolRegistrar`

**4.2. Unused Sub-Objectives**
- `OnboardingObjectiveId` nested cases like `applicantProfileProfilePhoto.evaluate_need`

**4.3. Unused Property**
- `OnboardingModelConfig.userDefaultsKey` not used consistently

**4.4. Misplaced Enum**
- `LargePDFExtractionMethod` in `PersistentUploadDropZone.swift` should be in `Models/`
