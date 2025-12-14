# Sprung Codebase Audit (Dead Code, Duplication, DRY, Technical Debt)

Audit date: 2025-12-13  
Repo revision: `21baa7cd`  
Scope: `Sprung/` (macOS app source)

## Methodology (What I Actually Looked At)

- Repo-wide indexing of Swift identifiers, `Notification.Name` usage (posted vs observed), onboarding event-case usage, and basic module/LOC inventory.
- Manual review of the largest/highest-risk files and subsystems:
  - App lifecycle + window/menu plumbing (`Sprung/App/*`)
  - Shared LLM layer (`Sprung/Shared/AI/*`)
  - Onboarding architecture (`Sprung/Onboarding/*`)
  - Resume editing + AI review (`Sprung/Resumes/*`, `Sprung/ResumeTree/*`)
  - Export + job scrape + cover letters (`Sprung/Export/*`, `Sprung/JobApplications/*`, `Sprung/CoverLetters/*`)

## Codebase Size & Layout

Total Swift LOC: ~90k (`Sprung/` has 447 Swift files, ~90,403 LOC)

Approximate LOC by module:

| Module | Swift files | LOC |
|---|---:|---:|
| `Sprung/Onboarding` | 178 | 37,419 |
| `Sprung/Resumes` | 32 | 9,789 |
| `Sprung/Shared` | 60 | 8,437 |
| `Sprung/App` | 49 | 8,422 |
| `Sprung/CoverLetters` | 31 | 7,637 |
| `Sprung/JobApplications` | 26 | 4,439 |
| `Sprung/Templates` | 18 | 4,201 |
| `Sprung/ResumeTree` | 19 | 3,841 |
| `Sprung/Experience` | 14 | 3,393 |
| `Sprung/Export` | 5 | 1,368 |
| `Sprung/DataManagers` | 10 | 974 |
| `Sprung/ResRefs` | 5 | 483 |

Largest Swift files (top 10):

1. `Sprung/Onboarding/Core/LLMMessenger.swift` (1228)
2. `Sprung/Resumes/AI/Services/PhaseReviewManager.swift` (1040)
3. `Sprung/ResumeTree/Utilities/ExperienceDefaultsToTree.swift` (1030)
4. `Sprung/Onboarding/Services/GitAgent/FileSystemTools.swift` (989)
5. `Sprung/Onboarding/Views/Components/ToolPaneTabsView.swift` (952)
6. `Sprung/Onboarding/Core/StateCoordinator.swift` (935)
7. `Sprung/ResumeTree/Models/TreeNodeModel.swift` (855)
8. `Sprung/Templates/Utilities/TemplateManifest.swift` (832)
9. `Sprung/Onboarding/Core/Coordinators/CoordinatorEventRouter.swift` (815)
10. `Sprung/Resumes/AI/Views/RevisionReviewView.swift` (782)

## Findings

### 1) Dead Code / Unused Wiring (High Confidence)

#### 1.1 Menu export notifications are posted but never observed (menu items currently no-op)

Defined in `Sprung/App/Views/MenuCommands.swift`, posted from menu commands in `Sprung/App/SprungApp.swift`, but **no `addObserver` / `publisher(for:)` exists** for these notifications:

- `.exportResumePDF`
- `.exportResumeText`
- `.exportResumeJSON`
- `.exportCoverLetterPDF`
- `.exportCoverLetterText`
- `.exportAllCoverLetters`
- `.exportApplicationPacket`

The export UI exists (e.g., `Sprung/Export/Views/ResumeExportView.swift`) but it does not subscribe to these notifications, so menu commands don’t trigger exports.

**Impact:** user-visible “menu feature doesn’t work”, and the notification constants are effectively dead wiring until hooked up.

#### 1.2 A notification is observed but never posted (likely leftover)

- `.reviseCoverLetter` is observed in `Sprung/App/Views/MenuNotificationHandler.swift` but never posted anywhere (menu doesn’t emit it, toolbar uses `.triggerReviseCoverLetterButton`).

**Impact:** dead notification + dead observer closure.

#### 1.3 Onboarding: multiple views/types appear completely unused

These top-level types are strong dead-code candidates (type name appears only once in the entire repo — the declaration):

- `EvidenceRequestView` — `Sprung/Onboarding/Views/Components/EvidenceRequestView.swift`
- `CitationRow` — `Sprung/Onboarding/Views/Components/CitationRow.swift`
- `KnowledgeCardDeckView` + `DeckPageIndicator` — `Sprung/Onboarding/Views/Components/KnowledgeCardDeckView.swift`
- `ExtractionStatusCard` — `Sprung/Onboarding/Views/Components/ExtractionStatusCard.swift`
- `TokenUsageTabContent` + `TokenUsageBadge` — `Sprung/Onboarding/Views/Components/TokenUsageView.swift`
- `ExperienceContext` — `Sprung/Onboarding/Models/KnowledgeCardDraft.swift`
- `GitToolRegistry` — `Sprung/Onboarding/Services/GitAgent/FileSystemTools.swift`
- `OnboardingDataType` — `Sprung/Onboarding/Constants/OnboardingConstants.swift`
- `OnboardingEventHandler` — `Sprung/Onboarding/Core/OnboardingEvents.swift`

Most of these are “half-built UI/infra” artifacts: the system creates/updates things like `EvidenceRequirement`, but there’s no integrated UI surface consuming them (the only UI is dead).

**Impact:** maintenance burden and architectural confusion (developers can’t tell which UI path is real).

#### 1.4 Onboarding: unused event cases (never referenced outside enum)

In `Sprung/Onboarding/Core/OnboardingEvents.swift`, these `OnboardingEvent` cases have **zero** references in the rest of `Sprung/Onboarding` (neither emitted nor handled):

- `profileSummaryUpdateRequested`
- `profileSummaryDismissRequested`
- `toolPaneCardRestored`
- `artifactGetRequested`
- `gitRepoAnalysisStarted`
- `gitRepoAnalysisCompleted`
- `gitRepoAnalysisFailed`
- `llmReasoningItemsForToolCalls`

**Impact:** “event bus entropy” — the enum grows, but the effective system behavior doesn’t.

#### 1.5 Resumes: unused error type

- `ResumeToolError` — `Sprung/Resumes/AI/Tools/ResumeToolRegistry.swift` is defined but never referenced.

**Impact:** minor, but it signals drift between intended and actual error handling.

### 2) Duplicative Features / DRY Violations (Architectural Debt)

#### 2.1 Multiple overlapping LLM stacks and APIs

You currently have multiple partially-overlapping abstraction layers:

- App-wide facade: `Sprung/Shared/AI/Models/Services/LLMFacade.swift` + internal `_LLMService`, `_LLMRequestExecutor`, etc.
- Onboarding uses a dedicated Responses API orchestration pipeline: `Sprung/Onboarding/Core/LLMMessenger.swift`, `NetworkRouter.swift`, `ConversationContextAssembler.swift`, etc.
- Git agent uses Chat Completions + tool calling: `Sprung/Onboarding/Services/GitAgent/GitAnalysisAgent.swift` (via `LLMFacade.executeWithTools(...)`).

This is not inherently wrong, but it produces:

- Duplicated concerns (streaming orchestration, tool-call handling, JSON parsing).
- Divergent configuration surfaces (different defaults, different knobs, different logging).

#### 2.2 Two tool-calling frameworks (Onboarding vs Resume customization)

- Onboarding tools: `InterviewTool` + `ToolRegistry` + `ToolBundlePolicy` (Responses API tool schema path).
- Resume tools: `ResumeTool` + `ResumeToolRegistry` (Chat Completions tools path).

Both do “tool schema + dispatch + UI request bridging”, but in different ways.

**Impact:** harder to add tools consistently and harder to reuse tooling infrastructure.

#### 2.3 Repeated “skills section” lookup logic (stringly-typed structural coupling)

The string matching for the skills section (`"skills-and-expertise"` vs `"skills and expertise"`) repeats across:

- `Sprung/Resumes/AI/Services/ResumeReviewService.swift`
- `Sprung/Shared/AI/Models/Services/SkillReorderService.swift`
- `Sprung/Resumes/AI/Services/ReorderSkillsService.swift`
- `Sprung/Resumes/AI/Services/FixOverflowService.swift` (via downstream calls)

**Impact:** templates/manifest changes can silently break AI features, and the fixes require touching multiple files.

#### 2.4 Repeated window-opening glue code (AppDelegate selector + NotificationCenter + fallback)

The pattern “post a notification, try `NSApp.sendAction`, fallback to casting `NSApplication.shared.delegate`” appears repeatedly in:

- `Sprung/App/Views/ContentView.swift`
- `Sprung/App/Views/UnifiedToolbar.swift`
- `Sprung/App/Views/TemplateEditorView.swift`
- `Sprung/App/SprungApp.swift`
- `Sprung/Onboarding/Views/OnboardingInterviewView.swift`

**Impact:** any change to window routing semantics must be applied in multiple call sites.

#### 2.5 Duplicated business logic for cover letter selection

The “ensure there’s a cover letter for the selected job app; otherwise create one” logic is duplicated:

- `Sprung/App/Views/ContentView.swift` (`updateMyLetter()`)
- `Sprung/App/Views/AppWindowView.swift` (`updateMyLetter()`)

**Impact:** bug fixes or behavior changes have to be mirrored.

### 3) Major Technical Debt / Risk Areas

#### 3.1 Onboarding architecture is powerful but very heavy (and accumulating drift)

The onboarding subsystem is ~37k LOC and includes:

- An event bus (`EventCoordinator`) with history retention (up to 10k events).
- Multiple coordinators + routers + state managers (`StateCoordinator`, `CoordinatorEventRouter`, etc.).
- Multiple incomplete UI/feature threads (evidence requests, token usage UI, deck UI, unused events).

**Impact:** high cognitive load for contributors; risk of “two ways to do the same thing” as new work lands.

#### 3.2 MenuNotificationHandler’s observer cleanup is incorrect for closure-based observers

`Sprung/App/Views/MenuNotificationHandler.swift` uses `NotificationCenter.default.addObserver(forName:object:queue:using:)` repeatedly but does not store the returned tokens.

It then calls `NotificationCenter.default.removeObserver(self)` in `deinit`, which does **not** remove those closure observers.

**Impact:** potential accumulation of inert observers across lifecycle edges; harder debugging when handlers are reconfigured.

#### 3.3 Potential privacy leak: logging full LLM responses on JSON parse failure

`Sprung/Resumes/AI/Services/LLMResponseParser.swift` logs the full LLM response content at error level when decoding fails.

Depending on user settings (`Logger` debug-file saving), this can write large amounts of potentially sensitive resume/job content to persistent logs.

**Impact:** privacy risk + large log volume.

#### 3.4 Onboarding “instructions parameter” vs documented architecture mismatch

Onboarding documentation (in-repo guidance) states that `instructions` is intentionally `nil` and persistent prompts are sent as `developer` messages.

But `Sprung/Onboarding/Core/LLMMessenger.swift` constructs `ModelResponseParameter(... instructions: workingMemory ...)`.

This could be intentional (working memory is explicitly non-persistent), but it’s a **doc/code drift** that should be resolved one way or the other.

#### 3.5 Lots of large files / God-object tendency

Many files exceed 700–1200 LOC. The biggest ones combine multiple responsibilities (prompt construction + request building + stream orchestration + error recovery + telemetry).

**Impact:** harder refactors, higher merge conflict rate (especially with parallel agents), and more risk when making changes.

#### 3.6 No tests

`SprungTests/` exists but the repo guidance says there are no automated tests.

**Impact:** dead code and wiring regressions (like the export menu notifications) are easy to introduce and hard to catch.

## Recommendations (Prioritized)

### Quick wins (high leverage, low risk)

1. Fix export menu wiring:
   - Either subscribe to the export notifications (likely in `ResumeExportView` or a central export coordinator) **or** delete the unused notifications/menu items.
2. Remove/merge confirmed dead onboarding UI/types/events:
   - Delete the unused views and the 8 unused `OnboardingEvent` cases.
   - Remove unused `ModelProvider` (`Sprung/Onboarding/Core/ModelProvider.swift`) or wire it into the actual model-selection path.
3. Fix `MenuNotificationHandler` observer lifecycle:
   - Store observer tokens and remove them on teardown, or switch to `NotificationCenter.Publisher` and `.onReceive` at the view layer.
4. Redact or downgrade sensitive logs:
   - Avoid logging full LLM responses at error level; prefer truncated/redacted content behind a debug flag.

### Medium-term cleanup

1. Consolidate “window actions” into a single routing surface:
   - Consider `FocusedValue`/`FocusedBinding` (you already use it for knowledge cards) to avoid NotificationCenter for most UI actions.
2. Consolidate duplicated “skills section” lookups:
   - Add a single `TreeNode`/`Resume` helper for “skills section resolution” and reuse it.
3. Reduce onboarding entropy:
   - Track/trim event cases regularly; keep the event enum aligned with emitted behavior.

### Longer-term structural improvements

1. Converge LLM/tooling stacks:
   - Decide whether onboarding (Responses API) and resume/tooling (Chat Completions) remain separate by design; if so, formalize boundaries and shared utilities (schema building, tool dispatch, streaming).
2. Add at least “build-level” automated checks:
   - A CI step that runs `xcodebuild` with the grep filter would catch many regressions, even without unit tests.

## Appendix: Concrete Evidence (scripts)

- Export notifications posted-but-never-observed: derived by scanning `Notification.Name` constants and counting `post(name:)` vs `addObserver`/`publisher(for:)`.
- Dead type candidates: type declarations where the type name appears only once across all Swift files (declaration only).
- Unused onboarding events: event-case names with zero `.caseName` references outside `OnboardingEvents.swift`.

