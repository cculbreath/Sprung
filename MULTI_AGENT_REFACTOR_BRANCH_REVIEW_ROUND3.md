# Multi-Agent Onboarding Refactor — Round 3 Plan Verification

This is a **third-round** assessment of `feature/multi-agent-onboarding` after the Round 2 issues were addressed. It evaluates whether the repository now satisfies the goals laid out in `MULTI_AGENT_REFACTOR_PLAN.md`.

## Scope

- **Branch**: `feature/multi-agent-onboarding`
- **Diff range (per request)**: `8743c9230f93e3651cd8d2981d01e74d2674ac2d..3c5465564b2833ea22b533e089697604936320d4`
- **New commits since Round 2**:
  - `fce78ee7` — Fix KC dispatch event routing and schema mismatch
  - `3c546556` — Parallelize document processing with Agents tab visibility
- **Compared against**: `MULTI_AGENT_REFACTOR_PLAN.md`

## Clarification (Non-Issue)

- **OpenRouter usage is allowed**. Git ingestion using OpenRouter is not treated as a bug in this assessment.

## Executive Conclusion

### ✅ The original refactor plan’s core goals are now satisfied

The branch now meets the plan’s primary outcomes:

- **Token-bloat prevention**: the main coordinator thread receives **summaries only** for uploaded documents (not full extracted text), preventing runaway `previous_response_id` context growth.
- **Parallelism**:
  - **Docs**: direct upload document extraction is now **parallelized** (with a concurrency limit).
  - **Git**: ingestion remains async/parallel and visible.
  - **Knowledge Cards**: KC generation runs via **parallel sub-agents** with isolated threads and a concurrency limit.
- **End-to-end Phase 2 multi-agent workflow** is reachable (plan → assignments → user approval → dispatch → persist cards).
- **Agent visibility UI** shows background activity (Docs, Git, KC agents) and supports cancellation for the agent types where task handles are registered.

### 🟡 One notable “plan vs implementation” drift remains

- The plan describes a dedicated **`request_additional_docs` tool**, but it is still **not implemented**. Gap handling is instead achieved through `propose_card_assignments` returning `gaps` plus explicit prompting/instructions and existing upload flows.

If you consider the plan’s goals as *behavioral outcomes*, the repo satisfies them. If you consider the plan as requiring *exact tool inventory*, it’s not 100% literal-match due to the missing `request_additional_docs` tool.

## Verification Against Plan Goals

Legend: ✅ implemented | 🟡 partial / drift | ❌ missing

### Part A — Token Reduction (Primary Goal)

- ✅ Summarize during ingestion and store summary on artifact record
- ✅ Main coordinator sees only summaries by default (no auto-injection of full extracted text)
- ✅ Full text preserved in artifacts and available via `get_artifact`
- ✅ KC agent conversations are isolated from main coordinator thread

### Part B — Parallel Processing (Efficiency Goal)

- ✅ Parallelize doc ingestion (direct upload path now runs extractions concurrently with a max concurrency)
- ✅ Git ingestion runs in parallel with doc ingestion (separate async task)
- ✅ Parallel KC generation via `dispatch_kc_agents` (concurrency-limited sub-agents)

### Tools & Workflow (Phase 2)

- ✅ `start_phase_two` returns timeline + artifact summaries and mandates next step
- ✅ `display_knowledge_card_plan` shows plan in UI
- ✅ `propose_card_assignments` records proposals and gates dispatch until user approval
- ✅ User approval path exists via “Generate Cards” UI → ungates `dispatch_kc_agents` with toolChoice
- ✅ `dispatch_kc_agents` returns card objects that can be fed into `submit_knowledge_card` (schema alignment fixed)
- ✅ `submit_knowledge_card` remains the persistence + approval gate
- 🟡 `request_additional_docs` tool (described in plan) not present

### Agent Visibility UI

- ✅ Agents tab list + transcript viewer exists
- ✅ Docs/Git/KC agents appear (doc ingestion visibility fixed)
- ✅ Kill cancels agents where task handles are registered (KC + Git). (Doc ingestion is tracked, but task-level cancellation isn’t currently wired the same way.)

## Round 2 Issues — Status

- ✅ **KC dispatch UI state “stuck generating”**: fixed by handling KC dispatch lifecycle events on the `.processing` stream.
- ✅ **Direct upload doc processing sequential**: fixed (now parallel, concurrency-limited).
- ✅ **Doc ingest missing from Agents tab**: fixed (document extractions are tracked as agents with transcript entries).
- ✅ **`dispatch_kc_agents` → `submit_knowledge_card` schema mismatch**: fixed by formatting generated card JSON to match the submit tool’s expected structure and updating dispatch instructions accordingly.

## Build Verification

- `xcodebuild -project Sprung.xcodeproj -scheme Sprung build | grep -Ei "(error:|warning:|failed|succeeded)" | head -20` → **BUILD SUCCEEDED** (warnings present, no errors).

