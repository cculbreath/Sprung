# PhysCloudResume Refactoring Plan (Codex)

This plan distills the key issues and recommendations from ClaudeNotes/Gemini_Architectural_Review.md into an actionable roadmap that prioritizes simplicity, reliability, and consistency, while adopting modern Swift and SwiftUI paradigms.

## Issue Summary

- Global state and singletons
  - App-wide God objects and implicit dependencies: `AppState` centralizes unrelated state/services; `LLMService`, `OpenRouterService`, `EnabledLLMStore`, `ApplicantProfileManager`, and `Logger` use singletons and access `UserDefaults` directly.
  - Configuration scattered in lifecycle hooks (e.g., API key setup in `PhysCloudResumeApp`), hidden coupling to `KeychainHelper` and `UserDefaults`.

- NotificationCenter as a command bridge (targeted use)
  - Primarily used to unify menu commands and toolbar buttons via `MenuNotificationHandler` and `.onReceive` on toolbar items; also used for a few global window actions and a sheet toggle in `ResumeReviseViewModel`.
  - This is a reasonable bridging pattern; avoid expanding it into general state propagation. One stray listener (`RefreshJobApps`) appears unused and can be removed.

- Massive views and mixed responsibilities
  - `ContentView` (and several feature views) contain business logic, diverse state sources (`@State`, `@Environment`, `@AppStorage`), and direct calls into services/stores.
  - Tight coupling to global stores in views (`JobAppStore.shared`, `ResumeStore.shared`, etc.) and frequent force unwraps.

- Stores and models mixing UI with data concerns
  - `JobAppStore` holds CRUD and UI selection/form state; `Resume` model is a “God object” doing persistence, export generation, debouncing, and template management.

- AI services and request pipeline coupling
  - Singletons, hidden configuration, and tight coupling to `SwiftOpenAI` types; duplicated retry/cancellation logic; in‑memory conversation history tied to external types; logging embedded in builders.

- Export/PDF generation and UI entanglement
  - `ResumeExportService` and `NativePDFGenerator` intermix export orchestration, template lookup, and UI (alerts/panels) with rendering.

- HTML fetching and Cloudflare handling
  - Network utilities live on models (e.g., `JobApp` extension); global/static utilities; WKWebView-based flows mixed with utility logic; brittle scraping and parsing paths.

- Logging and diagnostics
  - Static logger reads global state, mixes formatting with file IO, and hardcodes locations; limited structure and configurability.

- Persistence and profile/config management
  - Direct `UserDefaults` usage scattered; hardcoded keys; ad‑hoc keychain access from entry points; inconsistent validation.

- Utility/components cleanliness
  - Minor but pervasive issues (e.g., `CheckboxToggleStyle` toggles state in style; heavy `NSAttributedString` usage for HTML entity decode; repeated force unwraps; silent catch blocks).

- Deprecated Node resumeapi service
  - Shells out to `hackmyresume`, writes to disk, weak error handling, and lacks containerization/schema validation (review notes it is deprecated but still worth capturing lessons or cleanup).

- Flexible document and template architecture needed
  - Resume data must be editable and extensible without rigid compile‑time schemas, while templates stay portable plain text. Users must be able to toggle specific fields/sections for LLM replacement. Current ad‑hoc JSON handling limits structure and evolution.

## Refactoring Roadmap

The roadmap is incremental and aims to stabilize foundations first, then simplify features. Each step lists rationale and relevant tradeoffs.

1) Establish dependency injection and configuration
- Actions
  - Introduce `AppDependencies` (lightweight container) constructed in `PhysCloudResumeApp`, responsible for wiring services/stores with explicit initializers (no singletons).
  - Replace singleton access patterns with injected protocols (e.g., `LLMServiceProtocol`, `AIModelProvider`, `JobAppRepository`, `LoggerProtocol`).
  - Add `AppConfig` for static configuration and a `Secrets/APIKeyManager` for key retrieval. Keep `KeychainHelper` behind a small protocol abstraction.
- Rationale
  - Eliminates global state, clarifies lifecycles, and enables testing. Keeps architecture simple (protocol + concrete, no heavy IoC container).
- Tradeoffs
  - TCA or service locators are options; prefer simple protocol‑oriented DI with SwiftUI `.environment`/initializer injection to minimize complexity.

2) Consolidate command handling (keep bridge, add type-safety)
- Actions
  - Leave the existing NotificationCenter bridge in place for menu↔toolbar parity, as implemented in `App/Views/MenuNotificationHandler.swift` and toolbar button `.onReceive` handlers.
  - Remove unused listeners (e.g., `RefreshJobApps` in `DataManagers/JobAppStore.swift`) and ensure all remaining notifications are documented and scoped to command bridging only.
  - For new work and where feasible, route actions through a small typed `AppCommands` (protocol/struct with funcs) injected via environment; menus and toolbars call the same closures instead of posts. Use `FocusedSceneValue` where targeting the active window is important.
- Rationale
  - Preserves working menu/toolbar parity while gradually improving type-safety and discoverability; reduces reliance on stringly‑typed events over time.
- Tradeoffs
  - A typed command router adds a small abstraction; keeping the current bridge minimizes churn. Migrate opportunistically rather than forcing a full rewrite.

3) Simplify view layer with MVVM‑lite
- Actions
  - Extract focused ViewModels for complex screens/flows (start with `ContentView`, Export, and AI workflows) to encapsulate async orchestration, derived state, and side effects.
  - Bind simple forms directly to `@Model`/`@Observable` domain types; avoid mirror “Form” models unless you need transactional editing (then use a copy/rollback strategy).
  - Standardize navigation and presentation: `NavigationSplitView` + small subviews; toolbars pulled into focused `ToolbarView`/`ToolbarButtons/*`.
  - Keep ViewModels ephemeral and injected (no singletons); prefer initializer/`.environment` injection and contain lifetimes within the view hierarchy.
  - Remove force unwraps; adopt `if let/guard` and empty states; consolidate style/strings.
- Rationale
  - MVVM‑lite fits SwiftUI: Views stay declarative; ViewModels isolate logic and dependencies only where it pays off; simple screens remain just Views + observable models.
- Tradeoffs
  - TCA offers stronger unidirectional constraints; for simplicity, MVVM‑lite with DI and clear boundaries is sufficient and lighter weight.

4) Untangle stores and models
- Actions
  - Split `JobAppStore` into `JobAppRepository` (CRUD, persistence) and `JobAppSelectionViewModel` (UI selection/form state). Remove manual refresh logic; rely on SwiftData/Observation.
  - Decompose `Resume` into smaller SwiftData models (metadata/content/output) and move generation/debouncing/persistence to services (`ResumeGeneratorService`, `ResumePersistenceService`).
  - Prefer direct binding to `@Model` for simple edits; remove mirror form types like `ResumeForm` unless transactional editing is required.
  - Ensure models are “dumb” data holders with validation helpers only.
- Rationale
  - Aligns with single‑responsibility and separation of concerns; reduces incidental complexity in models.
- Tradeoffs
  - More files/types, but clearer boundaries and simpler mental model long‑term.

5) Generalized document + templating (schemaless JSON + manifest + LLM edit mask)
- Actions
  - Introduce a schemaless `JSONValue` (or AnyCodable) representation and persist raw resume JSON alongside a minimal typed core (for listing/search) and the existing tree where useful. Add `extensions: [String: JSONValue]` on core models for template‑specific data.
  - Add `TemplateManifest` (JSON/YAML) per template to declare: required paths, bindings (`contextKey -> JSONPath/Pointer`), defaults, and named transforms/filters; list partials/assets. Load at runtime from a user templates folder; no recompilation required.
  - Build a `ContextBuilder` to project stored JSON into a template context via the manifest and helper transforms (format date, join, limit, sort, map, conditional). Keep templates clean and logic‑light.
  - Define an `LLMEditMask` (path‑based include/exclude) and/or annotate nodes/fields with flags (e.g., `aiEditable`, `locked`). Provide a UI to toggle fields/sections. Use the mask when: (a) constructing LLM prompts, and (b) applying structured output.
 - Implement a `PatchApplier` that applies LLM‑returned structured diffs only to masked paths. Store diffs/audit entries for undo/versioning. Prefer JSON Patch/Merge Patch semantics to bound changes.
 - Ensure field identity stability: assign stable IDs to nodes/sections; map manifests and masks to IDs or JSON Pointers; provide migration helpers when structure changes.
  - Preserve order deterministically:
    - Model ordered collections as arrays and avoid relying on object key order.
    - Where an ordered map is truly needed, use an order‑preserving structure (e.g., an `OrderedDictionary` or `[ (key, value) ]` pair arrays in `JSONValue`).
    - Expose ordering explicitly in manifests (e.g., `order: source|sortBy:field|custom`) so templates can opt into source order or deterministic sorts.
    - Maintain stable indices and/or explicit `position` fields for user‑reorderable lists; propagate order changes via JSON Patch with array index ops (add/move/remove).
- Rationale
  - Decouples data shape from code; empowers plain‑text template authoring; enables per‑field LLM replacement toggles without rigid compile‑time schemas.
- Tradeoffs
  - You maintain a compact manifest DSL and a small set of reusable transforms. Gains in flexibility and authoring speed outweigh the light indirection.

6) Modernize AI services pipeline
- Actions
  - Convert `OpenRouterService`, `LLMService`, `EnabledLLMStore`, and `ConversationManager` to non‑singletons; inject via protocols.
  - Introduce `LLMAPIClient` protocol and wrap `SwiftOpenAI` behind it; make `LLMRequestExecutor` depend on the protocol and accept API key via init.
  - Centralize retry/cancellation in a small `RetryPolicy`; use Swift concurrency cancellation (`Task`/`Task.checkCancellation()`).
  - Persist conversations with SwiftData and decouple stored types from external `SwiftOpenAI` types using internal DTOs.
  - Move logging out of builders; builders become pure data assembly.
- Rationale
  - Increases testability and provider flexibility; improves reliability and cancellation semantics.
- Tradeoffs
  - Abstracting vendors adds light indirection; protocol wrappers remain thin to preserve simplicity.

7) Rework HTML fetch and Cloudflare handling
- Actions
  - Move HTML/network utilities off models; create `HTMLFetchService` with a strategy (native fetch first, WKWebView fallback) and typed errors.
  - Wrap `CloudflareCookieManager` behind `CloudflareCookieProviding` and split into `CloudflareChallengeHandler` (WKWebView) + `CookiePersistenceService` (file/Keychain).
  - Replace brittle scraping (regex/selectors) with `Codable` JSON extraction where possible; centralize text cleanup in `HTMLSanitizer/TextProcessor`.
- Rationale
  - Improves modularity and testability; isolates WKWebView and cookie lifecycles; reduces brittleness.
- Tradeoffs
  - Strategy pattern adds small ceremony; gains in clarity and isolation are significant for reliability.

8) Decompose export/PDF generation and remove UI from services
- Actions
  - Define `PDFGeneratorProtocol` and inject into `ResumeExportService` (which becomes orchestration only). Extract UI prompts to `ExportUIHandler`/`TemplateSelectionCoordinator` and template orchestration to a `TemplateManager`.
  - Reduce `NativePDFGenerator` to focused rendering primitives; move preprocessing and data transformations to `ResumeDataTransformer`.
  - Restrict `@MainActor` to UI/WKWebView calls; perform rendering/IO off the main thread; improve error taxonomy.
- Rationale
  - Clean layering improves testability and responsiveness; enables future renderer swaps.
- Tradeoffs
  - More types, but simpler responsibilities per type; clearer UI/service boundary.

9) Logging overhaul
- Actions
  - Replace static `Logger` with instance‑based wrapper over `os.Logger`; add `LogSink` protocol and optional `LogFileWriter` sink with configurable location.
  - Inject logger where needed; centralize formatting and redact sensitive values.
- Rationale
  - Aligns with Apple’s unified logging; simplifies filtering and privacy; removes hidden dependencies.
- Tradeoffs
  - `os.Logger` categories require lightweight naming discipline; benefits outweigh cost.

10) Persistence and profile/config cleanup
- Actions
  - Introduce small persistence protocols for `EnabledLLMStore`, applicant profile, and settings; consolidate `UserDefaults` keys in a type‑safe namespace; adopt `Codable` where appropriate.
  - Create `APIKeyManager` abstraction, backed by `KeychainHelper` via protocol; inject into services during construction.
- Rationale
  - Reduces stringly‑typed errors and hidden global state; improves testability.
- Tradeoffs
  - Slight indirection vs direct `UserDefaults`; gains in reliability and clarity.

11) Utilities and component fixes (low‑risk, high‑value)
- Actions
  - `CheckboxToggleStyle`: remove `onTapGesture` and keep style purely visual; add optional parameters for symbol/color.
  - `String.decodingHTMLEntities`: prefer `applyingTransform(.init("Any-XML/HTML"), reverse: true)` for efficient decoding.
  - Replace silent `catch {}` with explicit error paths; eliminate force unwraps project‑wide; standardize `@MainActor` usage on narrow surfaces.
  - Remove dead observers and unused notifications (e.g., `RefreshJobApps` in `JobAppStore`) and keep NotificationCenter limited to menu/toolbar and window actions.
- Rationale
  - Improves correctness, accessibility, and performance in common paths with minimal change risk.

12) Deprecated resumeapi service (cleanup/lessons)
- Actions
  - If the `resumeapi/` directory still exists historically, archive or remove it from the active project; document lessons learned in `Docs/`.
  - If the functionality is ever reintroduced, containerize, abstract the builder, adopt schema validation, stream responses, and add structured logging.
- Rationale
  - Keeps repo focused; avoids confusion over deprecated subsystems.

13) Testing and migration strategy
- Actions
  - Add unit tests for pure services (LLM request build/exec wrappers, export transformers, HTML sanitization) and SwiftData persistence for conversations.
  - Add a few view model tests for `ContentViewModel`/export flows; smoke tests for rendering/export.
  - Migrate in vertical slices: pick one area (e.g., logging + DI), land it, then refactor a single feature (e.g., Export), then HTML fetch, then AI.
- Rationale
  - Ensures incremental progress with confidence; contains blast radius.
- Tradeoffs
  - Test scaffolding adds some overhead; pick high‑leverage seams first.

## Best Practice Alignment

- Dependency Injection and Protocols
  - Eliminates singletons, clarifies lifecycles, and enables mocking. Keeps DI simple using initializers and SwiftUI environment objects.

- Swift Concurrency and Cancellation
  - Prefer `async/await`, `Task` cancellation, and `AsyncSequence` over manual token tracking. Restrict `@MainActor` to UI‑only work.

- MVVM‑lite with Thin Models
  - Use ViewModels selectively for complex flows (async orchestration, multi‑service coordination, derived/presentation state). Keep them ephemeral and injected.
  - Bind simple screens and forms directly to `@Model`/`@Observable` domain types; avoid duplicate “Form” ViewModels unless you need cancel/rollback semantics.
  - Views focus on rendering; models remain data‑centric. Improves testability and separation of concerns without unnecessary ceremony.
  
 - Order Preservation
   - Treat ordering as first‑class: represent user‑ordered collections as arrays (not dictionaries); use stable IDs and optional `position` fields.
   - For ordered maps, adopt an order‑preserving type (e.g., `[ (key, value) ]` or `OrderedDictionary`) rather than relying on dictionary iteration order.
   - Ensure JSON Patch operations preserve or intentionally change order via index‑based add/move; verify with unit tests.

- Type Safety and Error Handling
  - Replace notifications and stringly‑typed keys with strong types and enums. Consolidate error types and avoid force unwraps and silent catches.
  - Schema‑on‑read: use schemaless JSON storage with manifest‑driven projection to keep the data evolvable while templates remain plain text.
  - Patch‑based updates: apply LLM changes through constrained patches to masked paths; maintain audit/versioning.

- Modularity and Single Responsibility
  - Split large classes/services into focused protocols and components (repositories, managers, transformers, generators). Compose rather than nest responsibilities.

- Unified Logging and Observability
  - Use `os.Logger` with categories and level control. Add optional sinks for file capture during debugging.

- User Experience and Accessibility
  - Standardize sheet/navigation patterns; avoid duplicate gestures in styles; centralize strings/styles for consistency and localization.

## Codebase References

When details are unclear or to resolve edge cases, review these concrete files and their call sites:

- App lifecycle and global wiring
  - `PhysCloudResume/PhysCloudResume/PhysCloudResume/PhysCloudResumeApp.swift`
  - `PhysCloudResume/App/PhysicsCloudResumeApp.swift` (SwiftUI `.commands` menu definitions that post notifications)
  - `PhysCloudResume/App/AppState.swift`
  - `PhysCloudResume/App/Views/ContentView.swift`, `PhysCloudResume/App/Views/AppWindowView.swift`
  - `PhysCloudResume/App/Views/MenuNotificationHandler.swift` (menu→toolbar bridge and sheet/tab coordination)
  - `PhysCloudResume/App/Views/MenuCommands.swift` (notification names)
  - `PhysCloudResume/App/Models/AppSheets.swift` (sheet presentation bridged via notifications for revision review)

- Stores, models, and forms
  - `PhysCloudResume/DataManagers/JobAppStore.swift`
  - `PhysCloudResume/ResModels/Resume.swift`, `PhysCloudResume/ResModels/ResumeForm.swift`
  - `PhysCloudResume/Resumes/ViewModels/ResumeDetailVM.swift`

- AI services and LLM integration
  - `PhysCloudResume/AI/Models/Services/LLMService.swift`
  - `PhysCloudResume/AI/Models/Services/LLMRequestExecutor.swift`
  - `PhysCloudResume/AI/Models/Services/LLMRequestBuilder.swift`
  - `PhysCloudResume/AI/Models/Services/OpenRouterService.swift`
  - `PhysCloudResume/DataManagers/EnabledLLMStore.swift`
  - `PhysCloudResume/AI/Models/OpenRouterModel.swift`, `PhysCloudResume/AI/Models/EnabledLLM.swift`
  - Conversation persistence: `PhysCloudResume/AI/Models/Services/ConversationManager.swift` (if present) and related usage

- Export and PDF generation
  - `PhysCloudResume/Shared/Utilities/ResumeExportService.swift`
  - `PhysCloudResume/Shared/Utilities/NativePDFGenerator.swift`
  - Cover letters: `PhysCloudResume/CoverLetters/Utilities/CoverLetterPDFGenerator.swift`, `CoverLetterExportService.swift`
  - Export UI: `PhysCloudResume/ExportTab/Views/ResumeExportView.swift`, `ExportFormatPicker.swift`, `ExportResumePicker.swift`

- HTML fetching and scraping
  - `PhysCloudResume/JobApplications/Utilities/HTMLFetcher.swift`
  - `PhysCloudResume/JobApplications/Utilities/WebViewHTMLFetcher.swift`
  - `PhysCloudResume/JobApplications/Utilities/CloudflareCookieManager.swift`
  - Vendor-specific parsers: `AppleJobScrape.swift`, `IndeedJobScrape.swift`, `ProxycurlParse.swift`, `BrightDataParse.swift`

- Document model, templating, and toggles
  - Existing tree/JSON utilities: `PhysCloudResume/ResumeTree/Utilities/JsonMap.swift`, `JsonToTree.swift`, `TreeToJson.swift`
  - Tree models and views: `PhysCloudResume/ResumeTree/Models/TreeNodeModel.swift`, `ResumeTree/Views/*`
  - Resume views/VMs where toggles exist (e.g., nodes marked for AI updates): `PhysCloudResume/ResumeTree/Views/ResumeDetailView.swift`, `Resumes/ViewModels/ResumeDetailVM.swift`
  - Reordering UI and models (order preservation): `PhysCloudResume/ResumeTree/Views/NodeChildrenListView.swift`, `ResumeTree/Views/ReorderableLeafRow.swift`, `ResumeTree/Views/DraggableNodeWrapper.swift`
  - Templating/export integration points for the new ContextBuilder/TemplateManifest: `Shared/Utilities/NativePDFGenerator.swift`, `ResumeExportService.swift`

- Logging, persistence helpers, and utilities
  - `PhysCloudResume/Shared/Utilities/Logger.swift`
  - `PhysCloudResume/Shared/Utilities/KeychainHelper.swift`
  - `PhysCloudResume/Shared/Utilities/JSONParser.swift` and `PhysCloudResume/Shared/Extensions/String+Extensions.swift`
  - `PhysCloudResume/Shared/Utilities/TextFormatHelpers.swift`

- View cleanup candidates (force unwraps, singletons, UI logic)
  - `PhysCloudResume/JobApplications/Views/*`
  - `PhysCloudResume/Resumes/Views/*`, `PhysCloudResume/ResumeTree/Views/*`
  - `PhysCloudResume/CoverLetters/Views/*`
  - `PhysCloudResume/Sidebar/Views/SidebarView.swift`
  - `PhysCloudResume/Shared/UIComponents/CheckboxToggleStyle.swift`, `CustomTextEditor.swift`
  - Toolbar buttons using `.onReceive`: `App/Views/ToolbarButtons/*.swift` (verify bridge usage remains focused)

- Deprecated service (if still present historically)
  - `resumeapi/` (Node/Express service, now deprecated; see review section 6 for rationale and alternatives)

---

Execution guidance: apply steps 1–2 first (DI + command handling consolidation), then 3–5 (view/model simplification + document/templating revamp), followed by 6–8 (AI, HTML, export). Keep steps 9–11 as ongoing cleanup in parallel, and use step 13 to enforce guardrails as you iterate.
