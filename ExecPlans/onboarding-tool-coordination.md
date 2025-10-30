# Onboarding Tool Coordination Without capabilities_describe
This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds. Maintain this plan in accordance with Plans.md located at Plans.md.
## Purpose / Big Picture
Give the onboarding interviewer LLM a reliable view of available tools and their states without relying on `capabilities_describe`. Instead we will use OpenAI’s `allowed_tools`, tool preambles, and atomic system-message updates so the model always knows which tools it may call and which tool requests are waiting on user action. Humans benefit because multi-step interactions (contact intake, uploads, validations) stay synchronized even when the LLM waits for UI input. After implementation users should see that long-running tools report status immediately, the LLM does not call disabled tools, and objective status changes appear as inline messages.
## Progress
- [x] (2025-10-29 05:00Z) Draft initial plan skeleton referencing Plans.md guidance.
- [x] (2025-10-29 05:32Z) Removed `capabilities_describe`, deleted `capabilityManifest`, and cleaned documentation/tool registration.
- [x] (2025-10-30 00:45Z) Implemented tool registry / coordinator changes (allowed_tools plumbing, queue tracking, ledger messages).
- [x] (2025-10-30 00:55Z) Updated Sprung to consume new SwiftOpenAI branch with allowed_tools envelope support and wired developer status prompts for photo intake.
- [x] (2025-10-30 01:20Z) Reinforced prompts so already-validated applicant data does not re-trigger validation flows (developer instructions + phase script guidance).
- [x] (2025-10-30 01:30Z) Sanitized tool outputs (suppressed hidden email options), mirrored chat/developer traffic in logs, and added photo follow-up logging.
- [x] (2025-10-30 01:55Z) Added validate_applicant_profile tool (strict schema removed per request), restored validation metadata propagation, and updated Phase 1 prompt guidance.
- [x] (2025-10-30 03:40Z) Wired objective-led photo prompt observer, de-duplicated applicant persistence, relaxed validation schema, refreshed prompts, and aligned reasoning effort with user settings.
- [ ] Validate manually by exercising the onboarding interview start → contact intake → auto-approval flow observing tool queue messages.
- [ ] Capture findings in Outcomes & Retrospective.
## Surprises & Discoveries
- (2025-10-29 05:40Z) Model spec confirms status traffic should use the `developer` message role instead of `user`; plan updated accordingly.

## Decision Log
- Decision: Retired `capabilities_describe` tool and `capabilityManifest`; future tool visibility will rely on static tool definitions plus queue/ledger updates.
  Rationale: GPT-5 function calling prefers `allowed_tools` and explicit status messaging; keeping the manifest would duplicate responsibility.
  Date/Author: 2025-10-29 / Codex agent
- Decision: Management status traffic will use `developer` message role (per OpenAI model spec) instead of `user`.
  Rationale: Ensures instructions have higher authority, keeps chat log clean, and aligns with spec priority rules.
  Date/Author: 2025-10-29 / Codex agent
- Decision: Added allowed_tools envelope support to SwiftOpenAI fork so Sprung can send restricted tool subsets without manual JSON.
  Rationale: Native client lacked an enum case; extending it keeps orchestration strongly typed across the app and dependency.
  Date/Author: 2025-10-30 / Codex agent

## Outcomes & Retrospective
- Pending implementation.
## Context and Orientation
Current state: the onboarding module lives under `Sprung/Onboarding`. Tool calls are handled by `InterviewOrchestrator`, tool metadata comes from `ToolExecutor`, and `OnboardingInterviewCoordinator` exposes state to SwiftUI. Today the LLM can call `capabilities_describe` to learn tool readiness, but the new GPT-5 flow prefers `allowed_tools` with dynamic system updates.
Key files:
- `Sprung/Onboarding/Core/InterviewOrchestrator.swift` orchestrates responses, tracks conversation IDs, pipes tool outputs back to OpenAI.
- `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift` maintains state, ledger, and tool router.
- `Sprung/Onboarding/Core/OnboardingToolRouter.swift` exposes handler state and pending continuations.
- `Sprung/Onboarding/Tools/ToolExecutor.swift` executes tools and now guarantees JSON responses.
- `Sprung/Onboarding/Handlers/*.swift` manage interactive flows such as profile intake or uploads.
Terminology:
- *Tool queue*: a list of active tool requests (waiting for user response or long-running). We will surface it via system messages so the LLM knows what is outstanding.
- *Allowed tools*: subset configuration passed via OpenAI `tool_choice` that controls which functions the LLM may invoke at this step.
## Plan of Work
1. **Remove `capabilities_describe` reliance**
   - Update orchestrator setup so `capabilities_describe` is no longer registered or exposed. Delete the tool and remove `capabilityManifest` entirely, folding any metadata into static `tools` definitions or descriptive system messages.
2. **Implement tool queue tracking**
   - Leverage the existing router/coordinator pending-state properties (choice prompts, uploads, profile intake, validations) as the authoritative tool queue. Provide a coordinator helper that snapshots these states into a serializable array. `tool_executor` should call back when a continuation is registered/resolved so the snapshot stays accurate. `InterviewOrchestrator.requestResponse` must prepend a management status message (`Tool Queue: […]`) derived from this snapshot; omit the message when the queue is empty.
3. **Add preamble support**
   - Update system prompt fragments (phase scripts) to instruct the LLM to output a brief “why” message before tool calls (e.g., “Before calling a tool, explain why.”).
   - Optionally detect preamble outputs in orchestrator (not strictly required but we can log them for debugging).
4. **Allowed-tools plumbing**
   - Extend orchestrator call parameters to set `tool_choice` with `allowed_tools`. Coordinator decides subset per phase / state (e.g., disable profile tools in later phases).
   - Provide helper on coordinator to compute allowed tool list from queue + current phase to avoid conflicting requests.
5. **Developer-message updates**
   - Ensure every incoming `function_call` from the LLM is answered immediately with a `function_call_output` payload. Waiting states must include a status JSON emitted as a `developer` message (hidden from chat) listing `call_id`, requested input, and queue positioning. Completion states must emit developer-role JSON summaries tailored to the applicant-profile source (manual entry, contacts import, resume upload, URL) indicating whether data is already user-validated or still needs parsing. Ledger state changes must trigger additional developer status outputs (“Objective X marked complete / ready”).
6. **Cleanup / data contracts**
   - Ensure `CapabilitiesDescribeTool` either returns a static error or is removed so the LLM never invokes it.
   - Update documentation under `Sprung/Onboarding/ARCHITECTURE.md` to reflect new tool flow (no `capabilities_describe`, use allowed_tools + queue messages).
## Concrete Steps
1. Remove `capabilities_describe` usage from orchestrator and tool registry. Work in repo root `/Users/cculbreath/devlocal/codebase/Sprung`.
2. Expose helper(s) in `OnboardingInterviewCoordinator` that derive queue entries from existing pending-state properties. Update `ToolExecutor` to notify the coordinator whenever a continuation is registered or resolved so those helpers remain accurate.
3. Modify `InterviewOrchestrator.requestResponse` to prepend system messages for queue snapshot and ledger updates.
4. Set `tool_choice` with allowed tools in `requestResponse` using OpenAI API parameter structure.
5. Adjust validation/long-running tool pathways to send developer-role messages when resuming (in coordinator/service after `resumeToolContinuation`).
6. Update phase script prompts to ask for preambles and describe queue usage.
7. Update docs and run manual verification (start interview, choose contacts, confirm auto-approval) verifying logs and chat show queue updates.
Use commands like:
    cd /Users/cculbreath/devlocal/codebase/Sprung
    xcodebuild -project Sprung.xcodeproj -scheme Sprung -destination 'platform=macOS' build
(Repo has no automated tests.)
## Validation and Acceptance
- Launch the app, start the onboarding interview. Observe initial system message `Tool Queue: []` (or absence).
- Trigger contact intake (manual or contacts). After LLM calls `get_applicant_profile`, watch chat/system log show queue entry “waiting for user input”.
- Submit the form; chat should display user message describing returned data and queue entry should disappear next turn.
- Confirm no `capabilities_describe` tool calls occur (check console log).
- Verify objective completion messages appear when ledger updates (contact data validated, etc.).
## Idempotence and Recovery
Changes affect coordinator/orchestrator; re-running the plan re-applies queue snapshots safely. If build fails, revert commits (`git reset --hard HEAD~n`) and rerun steps. Queue data structures should initialize cleanly on app launch.
## Artifacts and Notes
- Capture console log snippet showing tool queue status transitions and user message summarizing returned data.
## Interfaces and Dependencies
- `InterviewOrchestrator.requestResponse` must set `tool_choice` parameter and inject system/user messages.
- `OnboardingInterviewCoordinator` must expose functions to add/remove tool queue entries and compute allowed tool names.
- `ToolExecutor` must notify coordinator when tool enters/exits waiting state and return immediate error payloads.
Revision history: initial draft 2025-10-29 by Codex agent.
