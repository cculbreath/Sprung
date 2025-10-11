# LLM Pass-off Summary

## Repository / Branch
- **Location:** `/Users/cculbreath/devlocal/codebase/Sprung`
- **Current branch:** `SecondPassRefactor`
- **Latest commit:** `c483129 chore: baseline before LLM cleanup` (baseline snapshot before any new LLM cleanup work)

## Current Focus
- Goal: eliminate the “god object” footprint in the LLM pipeline and keep only functionality required for the active workflows documented in the design intent notes.
- Status: planning phase only — no code changes beyond the new baseline commit have been made in this session after the commit.

## High-Level Work Plan (agreed with user)
1. **Delete unused surface area**  
   Remove the legacy `execute*` and parallel helper functions from `LLMService`/`LLMFacade`, ensuring the remaining API aligns strictly with the live workflows (resume review, fix overflow, resume revision streaming, clarifying questions, cover-letter committee flows).

2. **Consolidate capability gating**  
   Keep model-capability checks in a single place (the façade) and drop the duplicate `LLMService.validateModel`.

3. **Extract focused collaborators**  
   - `ConversationCoordinator` actor (cache + SwiftData persistence).  
   - `StreamingExecutor` (wrapping `LLMRequestExecutor.executeStreaming` with reasoning overrides and accumulation).  
   - `FlexibleJSONExecutor` (JSON-schema fallback heuristics backing committee/parallel flows).

4. **Finish vendor isolation**  
   Extend `LLMClient`/`SwiftOpenAIClient` to cover only the primitives the workflows use (text, vision, structured, flexible JSON, streaming/conversation).  
   Refactor `LLMFacade` to depend on the protocol and the extracted helpers; once satisfied, delete the now-empty legacy `LLMService`.

5. **Tighten DI & environment surface**  
   Update `AppDependencies`/`AppEnvironment` to inject only the façade (plus extracted helpers as needed) and remove unused environment bindings (e.g. `llmFacade` injection in `AppWindowView` that currently does nothing).

6. **Validation & docs**  
   - Run Periphery and a smoke `xcodebuild` build.  
   - Update `LLM Design Intent Docs/LLM_OPERATIONS_ARCHITECTURE.md` with the final slim API mapping.  
   - Document smoke steps for the four supported workflows.

## Immediate Next Steps for the Next Agent
1. Confirm there are no uncommitted changes (`git status` should be clean).
2. Start with Step 1 above — remove unused façade/service methods, run tests/build to ensure nothing calls them.
3. Continue through the plan, committing frequently (user requested frequent commits).

## Prompt / Instruction History

1. **Repository instructions**  
   ```
   <user_instructions>
   # agents.md
   ...
   ```
   (Build strategy, avoidance of excessive builds, concurrency guidance.)

2. **Environment contexts**  
   ```
   <environment_context>
     <cwd>/Users/cculbreath/devlocal/codebase/Sprung</cwd>
     <approval_policy>on-request</approval_policy>
     <sandbox_mode>workspace-write</sandbox_mode>
     <network_access>restricted</network_access>
   </environment_context>
   ```
   followed by an updated context:
   ```
   <environment_context>
     <approval_policy>never</approval_policy>
     <sandbox_mode>danger-full-access</sandbox_mode>
     <network_access>enabled</network_access>
   </environment_context>
   ```

3. **Periphery analysis request**  
   ```
   I ran the periphery code analysis tool on this codebase. The log is available periphery_log.txt Please assess the findings in the log and make a prioritized list of code recommendations (no code changes for now)
   ```

4. **LLM cleanup planning request**  
   ```
   Please assess changes needed to clean up LLMSerice and facade in light of Notes/RefactorNotes/Final_Refactor_Guide_20251007.md ...
   I want god-object free non-embarrassing, editable, maintainable code. ...
   Provide a plan for getting rid of cruft and debt-inducing code on the LLMSevice and facade pipeline
   ```

5. **Architecture preference clarification**  
   ```
   If it's am issue of finishing the refactor and deprecicating LLMClient in favof of LLMService, I can do that instead
   ```

6. **Doc relocation notice**  
   ```
   I moved those files to "LLM Design Intent Docs/LLM_MULTI_TURN_WORKFLOWS.md" and "LLM Design Intent Docs/LLM_OPERATIONS_ARCHITECTURE.md"
   ```

7. **Git hygiene instruction**  
   ```
   Git commit befoe you start and frequently along the way
   ```

8. **Pass-off request**  
   ```
   Please provide a detailed summary of what you're working on including the full history of the prompts I've provied into a mardown file LLM_Passoff.md so I can resume this work in another session with an LLM coding agent.
   ```
   (Same request repeated immediately after.)

## Notes
- No refactor work has started beyond planning; the new markdown file (this document) constitutes the only change after the baseline commit.
- Per user instructions, run commits frequently once code changes begin.

