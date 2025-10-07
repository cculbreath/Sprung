# PhysCloudResume: Selected Refactor Roadmap

Recommended plan: Codex (with targeted merges from Claude’s JSON/templating builder). Optimized for clarity, consistency, simplicity, and modern Swift/SwiftUI/SwiftData. Testing and dependency‑management initiatives are explicitly out of scope for this phase.

## Goals
- Eliminate hidden globals and reduce coupling without heavy frameworks.
- Keep menu/toolbar parity via NotificationCenter bridge; avoid broad app re‑plumbing.
- Replace custom JSON parsing with standard library; keep flexible TreeNode.
- Separate UI concerns from services (especially export/PDF pipeline).
- Embrace SwiftData + Swift concurrency + idiomatic SwiftUI environment injection.

## Phase A — Foundations and DI (lightweight)

- Introduce `AppDependencies` container built in `App/PhysicsCloudResumeApp.swift` and provided via `.environment(...)`.
  - Start with minimal protocols only where they buy clarity (no test doubles now): `SecureStorage`, `Logging`, `PDFGenerator`, `AIService`.
  - Back them with existing implementations to avoid churn:
    - `SecureStorage` → `KeychainHelper` wrapper
    - `Logging` → keep current static Logger initially; add instance wrapper later
    - `PDFGenerator` → thin wrapper over `NativePDFGenerator`
    - `AIService` → thin wrapper over `LLMService` (initially still using `SwiftOpenAI` types internally)
- Keep NotificationCenter bridge intact for menu/toolbar parity; remove unused listeners (e.g., “RefreshJobApps”) in `DataManagers/JobAppStore.swift`.
- Narrow `@MainActor` usage to UI surfaces.

Outcomes
- Views continue to work; `@Environment` remains the primary access pattern.
- Singletons remain available but begin migration via `AppDependencies`.

Key files
- App/PhysicsCloudResumeApp.swift (add `AppDependencies` to environment)
- App/AppState.swift (no new responsibilities; see Phase B)
- DataManagers/JobAppStore.swift (remove unused NC listener)

## Phase B — Unbundle AppState (pragmatic)

- Introduce a tiny `SessionState` (`@Observable`) for UI‑only flags (e.g., `selectedTab`, `showSlidingList`).
- Keep `AppState` for now but cease adding services to it; move service references into `AppDependencies`.
- Migrate usages incrementally:
  - Where views use global service singletons (e.g., constructing `ResumeReviseViewModel` in App/Views/ContentView.swift), prefer retrieving via environment (`AppDependencies`).
- Maintain current `ReasoningStreamManager` but consider moving it under `SessionState` (UI concern).

Outcomes
- UI state becomes explicit and minimal.
- Services flow through a single DI point, not `AppState`.

Key files
- App/Views/ContentView.swift (construct view models with DI)
- App/Views/AppWindowView.swift (continue bridge; consult dependencies for services)
- App/Views/ToolbarButtons/* (replace `.shared` lookups with environment when touched)

## Phase C — JSON and Templating Modernization

- Remove custom JSON parsing and manual string construction:
  - Replace `Shared/Utilities/JSONParser.swift` usage and `ResumeTree/Utilities/JsonToTree.swift` to rely on `JSONSerialization`.
  - Replace `ResumeTree/Utilities/TreeToJson.swift` with a focused builder.
- Adopt a Claude‑style builder (`ResumeTemplateDataBuilder`) that converts `TreeNode` → `[String: Any]` context expected by Mustache templates.
  - Preserve order via `TreeNode.myIndex` and `orderedChildren`.
  - Keep the current flexible TreeNode model and template override paths.

Outcomes
- Simpler, safer, and more readable code paths.
- No template changes required; context remains compatible.

Key files
- ResumeTree/Utilities/JsonToTree.swift (std lib parsing)
- ResumeTree/Utilities/TreeToJson.swift (replaced by builder)
- ResumeTree/Models/TreeNodeModel.swift (leverage existing `orderedChildren`)
- Shared/Utilities/NativePDFGenerator.swift (switch to new builder for context)

## Phase D — Export Pipeline Boundary

- Keep `ResumeExportService` as orchestration only; move UI prompts/panels into a UI coordinator layer.
  - Introduce a small `ExportTemplateSelection` UI helper that owns `NSAlert` and file pickers.
  - Restrict `NativePDFGenerator` to rendering; perform IO/transformations outside it.
- Ensure background processing for IO/rendering where possible; keep UI on main.

Outcomes
- Clear UI/service boundary, less surprising side effects, easier future changes.

Key files
- Shared/Utilities/ResumeExportService.swift (remove alerts; call UI helper)
- Shared/Utilities/NativePDFGenerator.swift (rendering‑focused)

## Phase E — Service Cleanup and Decoupling

- `Logger` → wrap `os.Logger` behind `Logging` protocol; retain static facade for now for minimal diff, then switch call sites incrementally.
- `KeychainHelper` → add a thin `SecureStorage` adapter and inject via dependencies.
- `LLMService` → introduce minimal DTOs to isolate `SwiftOpenAI` types at the edge; keep feature parity.
- Replace force unwraps and `fatalError` in stores/views with guarded paths and user‑visible errors where needed.

Outcomes
- Modern logging with categories; secrets behind a clear seam; reduced vendor coupling.

Key files
- Shared/Utilities/Logger.swift (adapter over os.Logger)
- Shared/Utilities/KeychainHelper.swift (wrapped by `SecureStorage`)
- AI/Models/Services/LLMService.swift (introduce DTOs; consult dependencies)
- DataManagers/JobAppStore.swift and affected views (remove force unwraps)

## What Not To Do (Now)
- No new testing harnesses or frameworks; no 3rd‑party DI frameworks; no TCA.
- No repository layer unless a clear need arises during migration.

## Risks and Mitigations
- Broad `.shared` usage (LLMService/OpenRouterService): migrate via facades in `AppDependencies` to minimize call‑site edits; allow staged replacement.
- Export pipeline UX: extracting UI code can temporarily duplicate logic; keep a single `ExportTemplateSelection` helper to avoid drift.
- JSON builder parity: ensure output keys match existing templates; verify by exercising current templates after builder swap.

## Ready‑to‑Land Slices (suggested order)
1) Remove `RefreshJobApps` and other dead NC listeners; narrow `@MainActor` where obvious.
2) Add `AppDependencies`; wire existing implementations; expose via environment.
3) Replace custom JSON parser + create `ResumeTemplateDataBuilder`; switch `NativePDFGenerator` to it.
4) Extract UI from `ResumeExportService` into `ExportTemplateSelection`.
5) Introduce `Logging` adapter over os.Logger, then `SecureStorage` wrapper.
6) Begin swapping `.shared` usages for environment dependencies at view touch points.

Deliverables focus on readability and modern paradigms without introducing testing or dependency‑management at this stage.

