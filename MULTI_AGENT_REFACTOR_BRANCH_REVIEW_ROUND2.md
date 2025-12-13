# Multi-Agent Onboarding Refactor — Round 2 Branch Assessment

This is a **second-round** review of `feature/multi-agent-onboarding`, after developers addressed the first round of issues. It compares the branch changes (since the specified base commit) against the goals in `MULTI_AGENT_REFACTOR_PLAN.md` and identifies any remaining gaps or risks.

## Scope

- **Branch**: `feature/multi-agent-onboarding`
- **Diff range**: `8743c9230f93e3651cd8d2981d01e74d2674ac2d..6fecc7ec17ee0634c5fc4e4fe5f767c125be92e8`
- **Commit count in range**: 23
- **Compared against**: `MULTI_AGENT_REFACTOR_PLAN.md`

## Key Clarification (Non-Issue)

- **OpenRouter usage is allowed**. In particular, **Git ingestion has always used OpenRouter** and this is not a bug. This review does **not** flag OpenRouter usage (e.g., git ingestion / other features) as an issue.

## Executive Summary

### Major objectives now satisfied (from the original plan)

- **Primary token-bloat fix achieved**: document uploads now notify the main LLM thread using **summaries only**, avoiding the “full extracted text accumulates via `previous_response_id`” failure mode.
  - See `Sprung/Onboarding/Handlers/DocumentArtifactMessenger.swift:262-297` (summary-only messaging).
- **Phase 2 “Generate Cards” gating flow is wired end-to-end**:
  - UI shows a **Generate Cards** button and emits `.generateCardsButtonClicked`.
    - `Sprung/Onboarding/Views/Components/OnboardingInterviewToolPane.swift:245-269`
  - Coordinator ungates `dispatch_kc_agents` and forces tool choice.
    - `Sprung/Onboarding/Core/Coordinators/CoordinatorEventRouter.swift:284-305`
- **KC agent cancellation is now real** (Kill cancels running KC agent tasks):
  - `AgentActivityTracker` stores cancellable task handles and `killAgent()` cancels them.
  - `KnowledgeCardAgentService` registers each KC agent `Task` with the tracker.
- **KC agent lifecycle events are now emitted** (dispatch started/completed; agent started/completed/failed/killed).

### Remaining gaps / risks (still worth addressing)

1. **UI event topic mismatch**: KC dispatch lifecycle events are categorized as `.processing` but UI state updates for those events are implemented under the `.artifact` stream; this can leave the UI stuck showing “Generating…” indefinitely.
2. **Document ingestion parallelism is still incomplete on the primary user path**: the direct upload handler processes documents **sequentially**, and document ingestion is not tracked in Agents tab.
3. **`dispatch_kc_agents` output schema does not match `submit_knowledge_card` input schema**, but the tool instructs the LLM to “call submit_knowledge_card with the card data” without specifying the required transformation; this is a reliability risk (tool call failures / stuck workflows).
4. **Plan/tooling drift**: `request_additional_docs` tool described in the plan is not implemented (gap handling is currently via instructions + chat + uploads).

## Goal Alignment Matrix (vs `MULTI_AGENT_REFACTOR_PLAN.md`)

Legend: ✅ implemented | 🟡 partial | ❌ missing | ⚠️ risk/fragile

### Part A — Token Reduction (Primary Goal)

- ✅ Summarize during ingestion and store summaries on artifact records
- ✅ Main thread receives summaries only (no full extracted text injected by default)
- ✅ Full text preserved in artifacts for on-demand access (`get_artifact`)
- ✅ KC agent conversations are isolated from main conversation thread

### Part B — Parallel Processing (Efficiency Goal)

- 🟡 Parallel doc ingestion (primary UI path still sequential; alternate ingestion kernel exists but isn’t wired to the direct upload flow)
- ✅ Git ingestion runs asynchronously and is visible in Agents tab
- ✅ Parallel KC generation via `dispatch_kc_agents` with concurrency limit

### Workflow Tools & UX

- ✅ `start_phase_two` bootstrap tool returns timeline + artifact summaries
- ✅ `display_knowledge_card_plan` shows plan in UI
- ✅ `propose_card_assignments` stores proposals and gates `dispatch_kc_agents` until user validation
- ✅ “Generate Cards” UI control exists and ungates dispatch tool
- ⚠️ `dispatch_kc_agents` → `submit_knowledge_card` handoff is fragile due to schema mismatch
- ❌ `request_additional_docs` tool (plan item) not implemented (replaced by prompting behavior)

### Agent Visibility UI

- ✅ Agents tab list + detail transcript
- ✅ Kill cancels Git and KC agents (task handles registered)
- 🟡 Doc ingest agent visibility (AgentType exists, but doc ingest tasks are not tracked)

## Detailed Findings — Remaining Issues / Investigation List

### 1) KC Dispatch UI State Updates Are Wired to the Wrong Topic (High)

**What’s happening**

- KC lifecycle events are categorized as `.processing`:
  - `Sprung/Onboarding/Core/OnboardingEvents.swift:393-396`
- But `UIStateUpdateHandler` updates `ui.isGeneratingCards` for those events inside the `.artifact` stream handler:
  - `Sprung/Onboarding/Core/Coordinators/UIStateUpdateHandler.swift:84-115` (see cases at `:105` and `:109`)

**Impact**

- The UI can remain in “Generating knowledge cards…” state after generation completes because `.kcAgentsDispatchCompleted` will not be observed in `handleArtifactEvent`.

**Why it matters**

- This is a UX correctness issue that directly affects Phase 2 completion and user trust.

---

### 2) Direct Upload Document Processing Is Still Sequential (Medium)

**What’s happening**

- The main upload flow (`uploadFilesDirectly` → `.uploadCompleted`) is processed by `DocumentArtifactHandler`.
- `DocumentArtifactHandler` iterates extractable documents sequentially:
  - `Sprung/Onboarding/Handlers/DocumentArtifactHandler.swift:92-138`

**Plan expectation**

- `MULTI_AGENT_REFACTOR_PLAN.md` calls out parallel doc ingestion as a key Phase 2A requirement.

**Impact**

- Large multi-document uploads still take “sum of all extraction times”, which undermines the latency improvements promised by the multi-agent architecture.

**Note**

- There *is* an async ingestion kernel (`DocumentIngestionKernel`) that can run multiple docs concurrently, but it is not currently used by the direct upload path.

---

### 3) Doc Ingest Is Not Visible in Agents Tab (Medium)

**What’s happening**

- `AgentType.documentIngestion` exists, but document extraction tasks are not registered with `AgentActivityTracker`.
- Agents tab therefore shows Git and KC agents, but not doc ingestion tasks (despite plan UI examples including “Doc: resume.pdf”).

**Impact**

- Users lose visibility into the most time-consuming background work (PDF extraction + summarization), which is exactly where visibility helps most.

---

### 4) `dispatch_kc_agents` Output vs `submit_knowledge_card` Input Schema Mismatch (High)

**What’s happening**

- `dispatch_kc_agents` returns cards in a custom schema (e.g., `prose`, `highlights`, `sources: [String]`).
  - `Sprung/Onboarding/Tools/Implementations/DispatchKCAgentsTool.swift:141-169`
- But `submit_knowledge_card` expects:
  - `params.card.content` (not `prose`)
  - `params.card.sources` as an array of objects (`{type, artifact_id}` / `{type, chat_excerpt, ...}`)
  - Plus `params.summary`
  - See `Sprung/Onboarding/Tools/Implementations/SubmitKnowledgeCardTool.swift` schema.

**Risk**

- `DispatchKCAgentsTool` currently instructs:
  - “Call `submit_knowledge_card` with the card data”
  - `Sprung/Onboarding/Tools/Implementations/DispatchKCAgentsTool.swift:174-206`
- This is ambiguous and can lead to **tool call failures** or repeated retries, especially given `next_required_tool` toolChoice chaining is set to `submit_knowledge_card`.

**Impact**

- This is one of the most likely remaining “workflow breaker” issues even if the underlying generation is correct.

---

### 5) Plan Drift: `request_additional_docs` Tool Not Implemented (Low/Medium)

**Plan expectation**

- `MULTI_AGENT_REFACTOR_PLAN.md` describes a dedicated `request_additional_docs` tool.

**Current implementation**

- The workflow relies on:
  - `propose_card_assignments` returning `gaps`, plus
  - Phase 2 prompt instructions telling the model to ask the user for specific documents, plus
  - Upload mechanisms already in place.

**Impact**

- Not necessarily a functional blocker, but it is a “plan vs implementation” divergence that may matter if the team expected a structured tool for gap requests (for UI, persistence, or later automation).

## Verification Notes

- **Build**: `xcodebuild -project Sprung.xcodeproj -scheme Sprung build | grep -Ei "(error:|warning:|failed|succeeded)" | head -20` → **BUILD SUCCEEDED** (destination warning only).

## Suggested Next Actions (No code changes in this report)

1. Fix the KC dispatch event/UI topic mismatch (either route KC dispatch events to `.artifact`, or handle them under `handleProcessingEvent`).
2. Decide on the intended “parallel doc ingestion” implementation:
   - migrate the direct upload flow to use the ingestion kernels, or
   - parallelize `DocumentArtifactHandler` explicitly (and ensure batching/UX remains correct).
3. Make the `dispatch_kc_agents` → `submit_knowledge_card` handoff robust:
   - either change dispatch output to match `submit_knowledge_card` schema, or
   - update dispatch tool instructions to explicitly require transformation (including `summary` and `sources` object shaping).
4. Decide whether `request_additional_docs` is required as a tool or officially removed from the plan.

