# Multi-Agent Onboarding Refactor — Branch Review

This report reviews all changes on `feature/multi-agent-onboarding` since the branch point and compares them to the stated goals in `MULTI_AGENT_REFACTOR_PLAN.md`.

## Scope

- **Branch**: `feature/multi-agent-onboarding`
- **Diff range**: `8743c9230f93e3651cd8d2981d01e74d2674ac2d..590bed3566d274db48e70df6deca7308db039a87`
- **Compared against**: `MULTI_AGENT_REFACTOR_PLAN.md`

## Executive Summary

### What’s implemented (high-level)

- **Artifact summaries** are generated during document processing and stored on artifact records, with a new lightweight `listArtifactSummaries()` accessor for coordinator-side planning:
  - `Sprung/Onboarding/Services/DocumentProcessingService.swift`
  - `Sprung/Shared/AI/Services/GoogleAIService.swift`
  - `Sprung/Onboarding/Core/ArtifactRepository.swift`
  - `Sprung/Onboarding/Models/DocumentSummary.swift`
- **Parallel KC agent infrastructure** exists (isolated sub-agent runner + restricted toolset) and can dispatch multiple card generations concurrently:
  - `Sprung/Onboarding/Services/AgentRunner.swift`
  - `Sprung/Onboarding/Services/SubAgentToolExecutor.swift`
  - `Sprung/Onboarding/Services/KnowledgeCardAgentService.swift`
  - `Sprung/Onboarding/Tools/Implementations/DispatchKCAgentsTool.swift`
  - `Sprung/Onboarding/Services/KCAgentPrompts.swift`
- **Phase 2 bootstrap + planning tools** exist and are registered/allowed for Phase 2:
  - `Sprung/Onboarding/Tools/Implementations/StartPhaseTwoTool.swift`
  - `Sprung/Onboarding/Tools/Implementations/DisplayKnowledgeCardPlanTool.swift`
  - `Sprung/Onboarding/Tools/Implementations/ProposeCardAssignmentsTool.swift`
  - `Sprung/Onboarding/Core/OnboardingToolRegistrar.swift`
  - `Sprung/Onboarding/Phase/PhaseTwoScript.swift`
- **Agent visibility** and **token usage** tabs were added to the Tool Pane:
  - `Sprung/Onboarding/Core/AgentActivityTracker.swift`
  - `Sprung/Onboarding/Views/Components/AgentsTabContent.swift`
  - `Sprung/Onboarding/Core/TokenUsageTracker.swift`
  - `Sprung/Onboarding/Views/Components/TokenUsageView.swift`
  - `Sprung/Onboarding/Views/Components/ToolPaneTabsView.swift`

### Critical oversights (blockers vs the plan’s goals)

1. **Token reduction is still defeated by the existing artifact-to-LLM messaging path**.
   - `MULTI_AGENT_REFACTOR_PLAN.md`’s primary goal is “main coordinator sees summaries only” to prevent `previous_response_id` accumulation.
   - However, `Sprung/Onboarding/Handlers/DocumentArtifactMessenger.swift` (unchanged in this branch) still sends **full `extracted_text`** to the main conversation as a user message or tool output (`extracted_content`), which will reintroduce the “200K+ document text accumulates forever” failure mode.

2. **Phase 2 “Generate Cards” gating/approval path is not currently reachable end-to-end**.
   - `propose_card_assignments` explicitly **excludes** `dispatch_kc_agents` until user approval (`Sprung/Onboarding/Tools/Implementations/ProposeCardAssignmentsTool.swift`).
   - The intended re-enable mechanism appears to be the event `.generateCardsButtonClicked` handled in `Sprung/Onboarding/Core/Coordinators/CoordinatorEventRouter.swift`, but there is **no UI code emitting this event** (repo search only finds the enum + handler).
   - Result: after assignments are proposed, `dispatch_kc_agents` stays excluded and the workflow can dead-end.

3. **Phase 2 UI/UX remains largely “single-card / done-button” oriented**, conflicting with the plan’s “plan → assignments → dispatch agents” pipeline.
   - `Sprung/Onboarding/Views/Components/KnowledgeCardCollectionView.swift` (unchanged) still drives a per-card “Done with this card” flow that forces `submit_knowledge_card`, rather than a “review assignments → Generate Cards” flow.

4. **KC agent cancellation (“Kill” button) does not actually cancel KC agents**.
   - `AgentActivityTracker.killAgent` can only cancel tasks registered in `activeTasks`.
   - Git ingestion registers its `Task` handle when tracking agents (`Sprung/Onboarding/Services/GitIngestionKernel.swift`).
   - KC agents are spawned via `withTaskGroup` and tracked without task handles (`Sprung/Onboarding/Services/KnowledgeCardAgentService.swift`), so “Kill” updates UI state but cannot cancel execution.

5. **New KC-agent event surface appears unused (dead code risk)**.
   - `Sprung/Onboarding/Core/OnboardingEvents.swift` adds multiple `.kcAgent*` events, but there are currently no call sites emitting them.
   - This conflicts with the repo’s “no dead code” guidance unless the wiring is completed soon.

## Change Inventory (since `8743c923...`)

### Commits

1. `76aba6ec` Add multi-agent infrastructure for parallel KC generation
2. `ec10ce5b` Add document summarization during ingestion with centralized prompts
3. `4a9fe245` Add KC agent service, prompts, and dispatch tool for parallel card generation
4. `098769b7` Add ProposeCardAssignmentsTool for doc-to-card mapping
5. `ab73cc66` Add Agents tab to tool pane for monitoring parallel agent activity
6. `6ea7c5ff` Update Phase 2 for multi-agent KC generation workflow
7. `b0480a08` Add KC agent events and improve documentation gap guidance
8. `75a7bed8` Integrate git ingestion with AgentActivityTracker for UI visibility
9. `0500ee6e` Rewrite Phase 2 script for multi-agent-only workflow
10. `7c892f51` Fix dossier spam during parallel document extraction
11. `59361eec` Enhance StartPhaseTwoTool with comprehensive gaps assessment guidance
12. `ed57d617` Add toolChoice chaining to DispatchKCAgentsTool
13. `87c9d498` Enhance KCAgentPrompts with pronouns and verbatim emphasis
14. `61fa9d8f` Add user validation phase after propose_card_assignments
15. `0d2fed3d` Add Generate Cards button event with toolChoice mandate
16. `d9da5b02` Update DisplayKnowledgeCardPlanTool for multi-agent workflow
17. `590bed35` Add OpenRouter token tracking to GitAnalysisAgent

### Files changed (A/M)

- **New files (A)**:
  - `Sprung/Onboarding/Core/AgentActivityTracker.swift`
  - `Sprung/Onboarding/Core/TokenUsageTracker.swift`
  - `Sprung/Onboarding/Models/DocumentSummary.swift`
  - `Sprung/Onboarding/Services/AgentRunner.swift`
  - `Sprung/Onboarding/Services/DocumentExtractionPrompts.swift`
  - `Sprung/Onboarding/Services/KCAgentPrompts.swift`
  - `Sprung/Onboarding/Services/KnowledgeCardAgentService.swift`
  - `Sprung/Onboarding/Services/SubAgentToolExecutor.swift`
  - `Sprung/Onboarding/Tools/Implementations/DispatchKCAgentsTool.swift`
  - `Sprung/Onboarding/Tools/Implementations/ProposeCardAssignmentsTool.swift`
  - `Sprung/Onboarding/Views/Components/AgentsTabContent.swift`
  - `Sprung/Onboarding/Views/Components/TokenUsageView.swift`
- **Modified files (M)**:
  - `Sprung/Onboarding/Core/ArtifactRepository.swift`
  - `Sprung/Onboarding/Core/Coordinators/CoordinatorEventRouter.swift`
  - `Sprung/Onboarding/Core/NetworkRouter.swift`
  - `Sprung/Onboarding/Core/OnboardingDependencyContainer.swift`
  - `Sprung/Onboarding/Core/OnboardingEvents.swift`
  - `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`
  - `Sprung/Onboarding/Core/OnboardingToolRegistrar.swift`
  - `Sprung/Onboarding/Core/StateCoordinator.swift`
  - `Sprung/Onboarding/Models/OnboardingArtifacts.swift`
  - `Sprung/Onboarding/Phase/PhaseTwoScript.swift`
  - `Sprung/Onboarding/Services/DocumentProcessingService.swift`
  - `Sprung/Onboarding/Services/GitAgent/GitAnalysisAgent.swift`
  - `Sprung/Onboarding/Services/GitIngestionKernel.swift`
  - `Sprung/Onboarding/Tools/Implementations/DisplayKnowledgeCardPlanTool.swift`
  - `Sprung/Onboarding/Tools/Implementations/StartPhaseTwoTool.swift`
  - `Sprung/Onboarding/Views/Components/ToolPaneTabsView.swift`
  - `Sprung/Onboarding/Views/EventDumpView.swift`
  - `Sprung/Shared/AI/Models/Services/LLMRequestBuilder.swift`
  - `Sprung/Shared/AI/Services/GoogleAIService.swift`
  - `Sprung/App/Views/SettingsView.swift`
  - `Sprung/Onboarding/Constants/OnboardingConstants.swift`
  - `Sprung.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

## Goal Alignment Matrix (vs `MULTI_AGENT_REFACTOR_PLAN.md`)

Legend: ✅ implemented | 🟡 partial | ❌ missing | ⚠️ implemented-but-undermined

### Part A — Token Reduction (primary goal)

- **Summarize during ingestion**: ✅
  - Summary generation exists via `GoogleAIService.generateSummary(...)` and is stored on the artifact record.
- **Main coordinator sees only summaries**: ⚠️
  - Tools (`list_artifacts`, `start_phase_two`) return summaries, but the existing artifact messenger path still pushes full text into the main conversation.
- **Tool-based full retrieval (`get_artifact`) on demand**: ✅
  - Main coordinator and sub-agents can retrieve full artifact records as needed.
- **KC agent threads isolated from main conversation**: ✅
  - KC agents use isolated in-memory chat histories and do not touch the main `previous_response_id` chain.

### Part B — Parallel Processing

- **Parallelize doc ingestion**: 🟡
  - The ingestion-kernel path (`DocumentIngestionKernel` via `ArtifactIngestionCoordinator`) is task-based and can be concurrent.
  - The primary Phase 2 UI upload path still routes through `DocumentArtifactHandler` which processes extractable documents sequentially.
- **Parallelize git ingestion**: ✅
  - Git ingestion runs in its own async task and is visible in Agents tab.
- **Offload KC generation via parallel sub-agents**: ✅
  - `dispatch_kc_agents` runs multiple KC agents concurrently with a configurable concurrency limit.

### Tools & Workflow

- **`start_phase_two` returns timeline + summaries + guidance**: ✅
- **`propose_card_assignments` for doc-to-card mapping**: ✅
- **“Gaps assessment” guidance**: ✅
  - Tool schema + StartPhaseTwoTool instructions are explicit and structured.
- **`dispatch_kc_agents` for generation**: 🟡
  - Tool exists and works conceptually, but current gating/approval path may prevent it from being callable after `propose_card_assignments`.
- **Coordinator persists cards without sub-agent writes**: 🟡
  - Sub-agents don’t write, but persistence still routes through `submit_knowledge_card` which triggers **user approval UI** for each card (not “LLM coordinator gate”).

### Agent Visibility UI

- **Agents tab list + transcript**: ✅
- **Kill running agents**: 🟡
  - Works for agents that register `Task` handles (git ingest).
  - Does not work for KC agents (no task handle registered).

## Detailed Findings (Critical)

### 1) Token Reduction is Undermined by Full-Text Artifact Messaging

**Plan intent**: only summaries should persist in the main conversation; full documents should be fetched on demand.

**Current reality**:
- `Sprung/Onboarding/Handlers/DocumentArtifactMessenger.swift` still builds a message that includes each artifact’s full `extracted_text` and sends it to the main LLM thread.

**Impact**:
- Recreates the >12M token growth scenario because all extracted content becomes part of the threaded `previous_response_id` context.
- Makes the new summarization work largely redundant.

**Recommended direction**:
- Stop sending full extracted text automatically to the main thread; send only IDs + summaries (+ minimal metadata).
- Preserve full text in artifacts for on-demand retrieval (`get_artifact`) and for KC agents.

### 2) “User Approval → Dispatch KC Agents” is Not Wired

**Observed behavior**:
- `propose_card_assignments` excludes `dispatch_kc_agents` until approval.
- Approval appears designed around a `.generateCardsButtonClicked` event that:
  - includes `dispatch_kc_agents` and
  - sends a forced-toolChoice user message

**Problem**:
- There is no UI emitting `.generateCardsButtonClicked`, so `dispatch_kc_agents` can remain excluded indefinitely.

**Impact**:
- Phase 2 can get stuck after document-to-card mapping.

### 3) Phase 2 UI Still Runs the Legacy “Done with this card → submit_knowledge_card” Flow

**Plan intent**: “Done” meaning shifts to “Ready to dispatch KC agents”.

**Current reality**:
- `Sprung/Onboarding/Views/Components/KnowledgeCardCollectionView.swift` still triggers `.knowledgeCardDoneButtonClicked`, and `CoordinatorEventRouter` still forces `submit_knowledge_card`.

**Impact**:
- UI and Phase 2 script/tooling are describing a different workflow than what the user can actually execute via the UI.

### 4) KC “Kill” is UI-Only (No Cancellation)

**Observed**:
- `AgentActivityTracker.killAgent` cancels only tasks registered in `activeTasks`.
- KC agents are not registered with a cancellable task handle.

**Impact**:
- User can’t actually stop runaway KC agents; UI will say killed, but resources/network calls may continue.

### 5) Unused KC-Agent Event Types (Dead Code Risk)

`Sprung/Onboarding/Core/OnboardingEvents.swift` defines a full set of KC-agent progress events, but there are no observed emitters.

**Impact**:
- Extra complexity with no functional behavior.
- Violates “no dead code” guidance unless this is completed promptly.

## Additional Gaps / Inconsistencies (Non-Blocking but Important)

1. **`KCAgentPrompts.initialPrompt` expects `summary_metadata` inside artifact summaries**, but `ArtifactRepository.listArtifactSummaries()` does not include it.
   - Result: doc type will show as empty for KC agents.

2. **Card proposals are stored but not actually used by `DispatchKCAgentsTool`**.
   - `ProposeCardAssignmentsTool` stores proposals in coordinator state.
   - `DispatchKCAgentsTool` requires proposals in its input and doesn’t read stored proposals as a fallback.

3. **Token usage tracking is directionally useful but not source-attributed**.
   - `TokenUsageTracker` treats all `.llmTokenUsageReceived` events as `.mainCoordinator`.
   - KC agents do not emit token usage events.

4. **Provider/back-end alignment (OpenAI vs OpenRouter)** should be re-validated.
   - Phase 2 settings introduce OpenRouter-style defaults for KC agents and git ingest.
   - If onboarding is intended to remain OpenAI-adapter-only, this is a strategic mismatch to resolve.

## Recommended Next Steps (No code changes in this report)

Prioritized fixes to align implementation with `MULTI_AGENT_REFACTOR_PLAN.md`:

1. **Stop feeding full extracted documents into the main thread** (update artifact-to-LLM messaging).
2. **Make the “Generate Cards” approval action real and reachable** (either via UI emission or via chat-driven ungating logic).
3. **Update Phase 2 UI to match the new pipeline** (plan → assignments → dispatch → persistence).
4. **Make KC agent cancellation real** (register cancellable tasks in `AgentActivityTracker`).
5. **Either wire or remove the unused `.kcAgent*` events** to meet “no dead code” expectations.
6. **Decide on the intended provider for KC agents (OpenAI-only vs allowing OpenRouter)** and enforce it consistently.
7. **Surface structured summary metadata in `listArtifactSummaries()`** (or stop prompts from expecting it).

