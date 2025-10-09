# PhysCloudResume — Final Refactoring Guide

This guide is a complete, self‑contained plan for executing the refactor of PhysCloudResume. It is written for an implementation team (human or LLM coding agent) with full repository access.

## 1) Executive Summary

Refactor PhysCloudResume to be a clean, modern, portfolio‑ready SwiftUI + SwiftData macOS app. The plan removes hidden globals, replaces fragile custom JSON code, clarifies export/templating boundaries, stabilizes store lifecycles, and modernizes the LLM integration (streaming, structured output, capability gating) without adding new third‑party dependencies or test frameworks. The outcome is a simpler, consistent, and maintainable codebase that highlights solid architecture and idiomatic Swift.

Key outcomes:
- Lightweight dependency injection (DI) and stable store lifetimes
- Custom JSON removal; a single TreeNode → Template Context builder
- Export pipeline clean boundary between UI and services
- LLM facade + DTO adapters, narrower @MainActor, Keychain‑backed secrets
- Safer code paths (no crashy force‑unwraps in UI flows), clearer logging
- NotificationCenter limited to menu/toolbar bridging and a few documented UI toggles

## 2) Objectives

- Eliminate fragile custom JSON parsing and manual string building
- Reduce global/singleton coupling; clarify lifecycles via DI
- Separate UI interactions from service/pipeline logic (export, LLM)
- Improve runtime safety: remove force‑unwraps/fatalErrors in user paths
- Use Keychain for secrets; remove UserDefaults for sensitive values
- Constrain NotificationCenter to macOS menu/toolbar bridging
- Align concurrency with Swift actors and responsiveness (no heavy work on main)
- Preserve feature behavior while improving maintainability and readability

## 3) Phase‑by‑Phase Roadmap

Each phase lists concrete tasks, primary targeted files/modules, and expected deliverables. Phases are designed to be merged independently. Keep changes small and reviewable.

Git workflow (single‑dev, no PRs):
- Create a dedicated branch per phase: `git checkout -b refactor/<short-description>`
- Commit early and often with descriptive messages
- Tag checkpoints: `git tag -a phase-<n>-checkpoint -m "Phase <n> checkpoint"`
- When a phase is complete, either:
  - Merge to main: `git checkout main && git merge --no-ff refactor/<short-description>`
  - Or remain on the branch and create a completion tag: `git tag -a phase-<n>-done -m "Phase <n> complete"`
- For rollback, use `git revert <sha>` (surgical) or `git reflog` (recover lost pointers)

### Phase 0 — Baseline and Project Hygiene (Small)

Tasks
- Create branch and capture a baseline (screenshots of key screens; a sample PDF/text export; quick AI run for streaming and structured output)
- Ensure the app builds and launches locally; note macOS target and Xcode version

Deliverables
- Baseline branch and reference artifacts (in repo or PR description)

### Phase 1 — Stabilize Store Lifetimes and DI Skeleton (Medium)

Tasks
- Create `AppDependencies` container (lightweight) initialized in `App/PhysicsCloudResumeApp.swift`
- Move store construction out of `View.body`; own `@Observable` store instances via `@State` in the parent view (scene root) or keep them in `AppDependencies`
- Provide stores and core services to the view hierarchy via `.environment(...)` using the Observation framework (`@Observable`, `@Environment`)

Targeted files
- App/PhysicsCloudResumeApp.swift
- App/Views/ContentViewLaunch.swift (stop constructing stores in body; inject once)
- DataManagers/*Store.swift (confirm initialization signatures and environment injection)

Deliverables
- Single DI container or `@State`‑owned `@Observable` instances ensuring stable store lifetimes
- No functional changes; app behavior is unchanged

### Phase 2 — Safety Pass: Remove Force‑Unwraps and FatalErrors (Medium)

Tasks
- Replace force‑unwraps and `fatalError` in user‑reachable paths with guarded logic and user‑visible error handling where appropriate
- Typical fixes include optional binding, early returns, and small alert surfaces for invalid input

Targeted files (examples; scan and fix project‑wide)
- Shared/Utilities/NativePDFGenerator.swift (guard returned PDF data; no `pdfData!`)
- JobApplications/Views/NewAppSheetView.swift (safe `URL(string:)` handling)
- JobApplications/Models/IndeedJobScrape.swift (avoid `.first!`)
- CoverLetters/AI/Utilities/CoverLetterModelNameFormatter.swift (avoid `.last!`)
- DataManagers/JobAppStore.swift (replace `fatalError` with safe flows)
- Shared/UIComponents/ImageButton.swift (replace `fatalError` initializer guard)

Deliverables
- No `fatalError` or unsafe unwraps in end‑user paths

### Phase 3 — Secrets and Configuration (Small)

Tasks
- Introduce `APIKeyManager` (Keychain‑backed) to read/write OpenRouter (and other) API keys
- Replace `UserDefaults` API key reads in services with `APIKeyManager`
- Add `AppConfig` for non‑secret constants and magic numbers

Targeted files
- AI/Models/Services/LLMRequestExecutor.swift (configure client using Keychain)
- AI/Models/Services/ModelValidationService.swift (use Keychain for requests)
- App/AppState.swift and App/AppState+APIKeys.swift (reconfigure flows)
- Shared/Utilities/KeychainHelper.swift (used under `APIKeyManager`)

Deliverables
- Secrets read from Keychain only; no sensitive values in `UserDefaults`

### Phase 4 — JSON and Template Context Modernization (Large)

Tasks
- Remove custom byte‑level `JSONParser` and string‑built JSON utilities
- Implement `ResumeTemplateDataBuilder` to map `TreeNode` → `[String: Any]` template context, preserving `TreeNode.myIndex` order
- Replace `TreeToJson` and refactor `JsonToTree` to use `JSONSerialization`
- Make `NativePDFGenerator` and text generation consume the new builder (via a common `ResumeTemplateProcessor` entry point)

Targeted files
- Shared/Utilities/JSONParser.swift (delete; replace usages)
- ResumeTree/Utilities/JsonToTree.swift (refactor to stdlib JSON)
- ResumeTree/Utilities/TreeToJson.swift (retire; replace with builder)
- ResumeTree/Models/TreeNodeModel.swift (ensure `orderedChildren` and indices drive builder order)
- Shared/Utilities/ResumeTemplateProcessor.swift (single entry to build context)
- Shared/Utilities/NativePDFGenerator.swift and Shared/Utilities/TextResumeGenerator.swift (switch to builder)

Deliverables
- A single, standard JSON path: TreeNode → context dictionary → Mustache rendering
- No manual JSON string concatenation anywhere

### Phase 5 — Export Pipeline Boundary (Medium)

Tasks
- Extract all alerts/panels and file pickers into `ExportTemplateSelection` (UI/helper)
- Keep `ResumeExportService` orchestration‑only; keep `NativePDFGenerator` rendering‑only; move pre/post‑processing out of the renderer

Targeted files
- Shared/Utilities/ResumeExportService.swift (no view logic)
- Shared/Utilities/NativePDFGenerator.swift (rendering only; IO/transform helpers moved out)
- New: ExportTemplateSelection (NSAlert/NSOpenPanel ownership)

Deliverables
- Clear UI/service boundary; improved readability and testability later

### Phase 6 — LLM Facade, DTO Adapters, and Concurrency Hygiene (Large)

Tasks
- Introduce `LLMClient` protocol and minimal domain DTOs (`LLMMessageDTO`, `LLMResponseDTO`, existing `LLMStreamChunk`) to decouple call sites from SwiftOpenAI types
- Implement an adapter using existing SwiftOpenAI plumbing under the hood
- Narrow `@MainActor`: keep only UI entry points main‑isolated; run network/retry/parse on background tasks
- Unify capability gating: centralize checks in LLM service layer; use `EnabledLLMStore` persistence; call `ModelValidationService` on demand
- Expose per‑feature cancellation handles where long‑lived streams exist (e.g., resume revision vs clarifying questions)
- Migrate view models and services to use the DI‑provided LLM facade instead of `.shared`

Targeted files
- AI/Models/Services/LLMService.swift (use facade internally; narrower `@MainActor`)
- AI/Models/Services/LLMRequestExecutor.swift (remove class‑level `@MainActor`; Keychain for API key)
- AI/Models/Services/ModelValidationService.swift (Keychain; background work)
- AI/Models/Types/ConversationTypes.swift (confine SwiftOpenAI typealiases to adapter boundary)
- Resumes/AI/Services/ResumeReviseViewModel.swift, JobApplications/AI/Services/ClarifyingQuestionsViewModel.swift, Resumes/AI/Services/ResumeReviewService.swift (inject LLM facade via dependencies; no `.shared`)

Deliverables
- LLM call sites depend on a small, stable facade; vendor types isolated
- Streaming remains ergonomic; reasoning overlay remains intact and responsive

### Phase 7 — Logging and Diagnostics (Small)

Tasks
- Provide a `Logging` protocol and an os.Logger‑backed implementation; keep current `Logger` facade temporarily to limit churn
- Reduce chatty multi‑line logs on the main actor; keep detailed dumps only under a verbose flag

Targeted files
- Shared/Utilities/Logger.swift (adapter + categories)
- Callers across AI/ and Shared/

Deliverables
- Modern, categorized logging with optional file sink used only in debug mode

### Phase 8 — NotificationCenter Boundaries and UI State (Small)

Tasks
- Remove unused NC listeners (e.g., RefreshJobApps)
- Keep NotificationCenter for menu/toolbar bridging and a few documented sheet toggles; convert view‑local sheets to bindings where feasible

Targeted files
- DataManagers/JobAppStore.swift (remove `RefreshJobApps` listener)
- App/Views/MenuNotificationHandler.swift, App/PhysicsCloudResumeApp.swift (documented notifications only)
- App/Models/AppSheets.swift (consider swap to bindings)

Deliverables
- Minimal, purposeful NC usage aligned with platform needs

### Phase 9 — Polish and Documentation (Small)

Tasks
- Update README and in‑repo docs: DI overview, LLM facade usage, template override precedence, export UI location, capability gating overview
- Provide manual smoke steps: render PDF/text, run a structured response, verify streaming + reasoning overlay

Deliverables
- Clear handoff documentation; portfolio‑ready presentation

## 4) Timeline and Effort Levels

The following is an indicative sequence and effort sizing. Adjust to team capacity.
- Phase 0: Small (0.5 day)
- Phase 1: Medium (1–2 days)
- Phase 2: Medium (1–2 days)
- Phase 3: Small (0.5–1 day)
- Phase 4: Large (3–5 days)
- Phase 5: Medium (1–2 days)
- Phase 6: Large (3–6 days)
- Phase 7: Small (0.5 day)
- Phase 8: Small (0.5 day)
- Phase 9: Small (0.5–1 day)

Total: ~12–19 days of focused effort (1 developer). Parallelization is possible if code ownership is clear.

## 5) Risks and Mitigation

- JSON builder parity with templates
  - Risk: Builder output mismatches template expectations
  - Mitigation: Validate with current templates after swap; compare generated HTML/text to baseline outputs

- Secrets migration
  - Risk: Missing API key after switching to Keychain
  - Mitigation: Add a one‑time fallback read from `UserDefaults` on first launch and persist to Keychain; surface a settings prompt if empty

- LLM facade introduction
  - Risk: Compile‑time breaks from replacing vendor types
  - Mitigation: Stage via adapters; keep typealiases behind adapter boundary; migrate feature by feature

- Concurrency changes
  - Risk: UI freezes or race conditions if work remains on main
  - Mitigation: Keep UI entry points main‑isolated; audit long loops and parsing for background execution; use simple smoke checks per PR

- Store lifetime adjustments
  - Risk: Unintended instance duplication or context lifetime issues
  - Mitigation: Centralize creation; rely on environment injection; verify selection and editing state persists across view updates

- NotificationCenter cleanup
  - Risk: Removing a listener that had a hidden caller
  - Mitigation: Search for posters; remove only after confirming none exist; favor bindings when replacing sheet toggles

## 6) Best Practice Alignment

- Simplicity & Clarity
  - Fewer global singletons; explicit DI and lifecycles
  - Single path for JSON/template context; no stringly JSON
  - Clear UI/service boundaries in export and LLM layers

- Maintainability
  - Facade over vendor SDKs; capability checks in one place
  - Logging via os.Logger with categories
  - Minimal NotificationCenter surface, documented intents

- Modern Swift/SwiftUI/SwiftData
  - Use the Observation framework: define models/stores with `@Observable`, own instances with `@State` in the parent, pass down via `@Environment`
  - SwiftData as single source of truth; stable store instances
  - Concurrency: main actor only for UI mutation; background for IO/network/parse

- Practical Constraints
  - No new third‑party dependencies introduced
  - No test framework rollout in this phase; use manual smoke validation per slice

## 7) Final Deliverables

- A clean DI surface (`AppDependencies`), stable store lifetimes, and minimal globals
- A standard TreeNode → Template Context builder powering both HTML and text output; custom parser removed
- An export pipeline with UI interactions isolated from service logic
- An LLM facade with narrow, stable DTOs; vendor types isolated; Keychain secrets; unified capability gating; responsive streaming UI
- Safer code paths with guard rails and user‑visible error handling
- Minimal, purposeful NotificationCenter usage aligned to macOS patterns
- Updated documentation describing architecture seams and extension points

---

Implementation note
- Keep commits scoped to one phase at a time; avoid combining architectural changes and UI tweaks in the same commit. Commit frequently, reference targeted files explicitly in commit messages, and maintain a short checklist of smoke steps per phase (in a tag message, CHANGELOG entry, or the branch description).

*** End of Guide ***
