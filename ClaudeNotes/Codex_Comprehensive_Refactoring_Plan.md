# Codex Comprehensive Refactoring Plan

This document extends the selected roadmap with a systematic, code‑anchored review of the current codebase and deeper recommendations, with particular focus on the LLM architecture. The goal is a portfolio‑ready codebase optimized for clarity, consistency, simplicity, and modern Swift/SwiftUI/SwiftData paradigms — without introducing tests or third‑party dependency managers at this stage.

**Executive Summary**
- Keep NotificationCenter limited to menu/toolbar bridging and a few UI toggles; it’s appropriate for macOS.
- Replace custom JSON and string‑built JSON with a standard `JSONSerialization`-backed builder while preserving `TreeNode` and template compatibility.
- Introduce a light `AppDependencies` and stabilize store lifetimes; stop constructing stores inside `View.body`.
- Strengthen the LLM layer: remove `.shared` singletons in call sites via DI, decouple from SwiftOpenAI types with small DTOs, move secrets to Keychain, narrow `@MainActor`, and centralize streaming + capability gating.
- Eliminate force‑unwraps/fatalErrors in user paths; unify error handling and logging over os.Logger (with an adapter).

**Codebase Topology (Observed Highlights)**
- App entry and command bridge: `PhysCloudResume/App/PhysicsCloudResumeApp.swift`, `PhysCloudResume/App/Views/MenuNotificationHandler.swift`, `PhysCloudResume/App/Views/MenuCommands.swift`
- Stores and SwiftData: `PhysCloudResume/DataManagers/*Store.swift`, `PhysCloudResume/Resumes/Models/Resume.swift`, `PhysCloudResume/ResumeTree/Models/TreeNodeModel.swift`
- JSON and templating: `PhysCloudResume/Shared/Utilities/JSONParser.swift`, `PhysCloudResume/ResumeTree/Utilities/JsonToTree.swift`, `PhysCloudResume/ResumeTree/Utilities/TreeToJson.swift`, `PhysCloudResume/Shared/Utilities/ResumeTemplateProcessor.swift`
- Export pipeline: `PhysCloudResume/Shared/Utilities/ResumeExportService.swift`, `PhysCloudResume/Shared/Utilities/NativePDFGenerator.swift`
- LLM architecture: `PhysCloudResume/AI/Models/Services/LLMService.swift`, `PhysCloudResume/AI/Models/Services/LLMRequestExecutor.swift`, `PhysCloudResume/AI/Models/Services/ModelValidationService.swift`, `PhysCloudResume/AI/Models/Services/OpenRouterService.swift`, `PhysCloudResume/AI/Models/Types/ConversationTypes.swift`
- LLM usage: `PhysCloudResume/Resumes/AI/Services/ResumeReviseViewModel.swift`, `PhysCloudResume/Resumes/AI/Services/ResumeReviewService.swift`, `PhysCloudResume/JobApplications/AI/Services/ClarifyingQuestionsViewModel.swift`, Reasoning overlay in `PhysCloudResume/AI/Views/ReasoningStreamView.swift`

**Key Risks Confirmed**
- Singletons: `LLMService.shared`, `OpenRouterService.shared`, `ModelValidationService.shared`, `ImageConversionService.shared`, `ApplicantProfileManager.shared`, some CoverLetter services.
- Force‑unwraps/fatalErrors in end‑user flows: PDF generation, URL creation from user input, scraping utilities, store operations, UI components (ImageButton).
- Secrets via `UserDefaults` instead of Keychain: OpenRouter API key reads in multiple places.
- `@MainActor` on network services: LLMRequestExecutor, LLMService, ModelValidationService — runs network and retry loops on main actor.
- Store lifetime: stores created inside `View.body` (re‑created on render), all stores hold `unowned let modelContext`.
- Duplicated template context logic: `NativePDFGenerator` and `ResumeTemplateProcessor` paths diverge.

**LLM Architecture Deep Dive**

Files: `PhysCloudResume/AI/Models/Services/LLMService.swift`, `PhysCloudResume/AI/Models/Services/LLMRequestExecutor.swift`, `PhysCloudResume/AI/Models/Services/ModelValidationService.swift`, `PhysCloudResume/AI/Models/Services/OpenRouterService.swift`, `PhysCloudResume/AI/Models/Types/ConversationTypes.swift`

Observations
- Strong feature coverage: text, vision, structured outputs (optional JSON Schema), streaming with reasoning, conversation management, basic retry/backoff.
- Tight coupling to SwiftOpenAI: `ConversationTypes.swift` typealiases propagate SwiftOpenAI types across the app; request builder and parser operate on those types directly.
- Singletons: LLMService, OpenRouterService, ModelValidationService are accessed globally; initialization flows depend on `AppState` and `UserDefaults`.
- Secrets/config: API key read in `LLMRequestExecutor.configureClient()` and `ModelValidationService.validateModel(_:)` via `UserDefaults.standard.string(forKey: "openRouterApiKey")`.
- Actor usage: `@MainActor` on LLMRequestExecutor and LLMService means network + retry logic run on the main actor; parsing and stream processing loops also run on main.
- Capability gating: Split between `OpenRouterService` model metadata, `EnabledLLMStore` persistence, and `ModelValidationService` remote checks; JSON Schema success/failure recorded back to `EnabledLLMStore`.
- UI coupling surface: Reasoning overlay (`ReasoningStreamManager`) toggled during streaming; Resume revision flow mixes schema enforcement and reasoning display.

Strengths
- Clear separation between request build, execute, and parse stages.
- Streaming APIs surfaced ergonomically to UI with `AsyncThrowingStream<LLMStreamChunk, Error>`.
- Capability tracking exists and feeds back (e.g., recording JSON Schema failures).

Gaps / Risks
- Vendor lock‑in via typealiases; hard to pivot away from SwiftOpenAI types.
- Main actor footprint is too broad; yields are awaited, but compute/logging/parsing and retry loops still occur on main.
- Secrets in `UserDefaults`; mixed places read and mask API key.
- Multiple sources of truth for capability data; some duplication across services.
- Singleton access from views/view models complicates lifecycles and makes DI harder later.

LLM Recommendations (Actionable, No New Deps)
- Introduce domain DTOs and a minimal facade:
  - `LLMClient` protocol with methods mirroring current needs: `executeText`, `executeVision`, `executeStructured<T>`, `streamText`, `streamStructured<T>`, `startConversationStreaming`.
  - Domain types for `LLMMessageDTO`, `LLMResponseDTO`, `LLMStreamChunk` (already present), `ModelId`, `JSONSchemaDTO` — implemented via adapters over SwiftOpenAI types in the service layer.
  - Keep the existing builder/parser internals, but confine SwiftOpenAI types behind adapters. Call sites use DTOs from the facade.
- Narrow `@MainActor`:
  - Remove class‑level `@MainActor` from `LLMRequestExecutor` and non‑UI portions of `LLMService`. Keep UI‑facing entry points (`@MainActor`) but run build/exec/parse on background actor (`Task {}` or helper actor). Ensure updates to UI state (e.g., reasoning overlay) hop to main.
- Secrets:
  - Introduce `APIKeyManager` (Keychain‑backed) and inject into `LLMRequestExecutor` and `ModelValidationService`. Replace `UserDefaults` reads with `APIKeyManager.get("openrouter")`.
- Capability gating:
  - Centralize capability checks in a single helper owned by LLMService; use `EnabledLLMStore` as persistence and `OpenRouterService` for metadata; keep `ModelValidationService` as a probe called by the helper. Avoid logic duplication.
- Cancellation and resource control:
  - Keep per‑request IDs, but expose cancel entry points at the facade level (already have `cancelAllRequests`). Consider per‑feature cancellation handles (e.g., for revision streaming vs. clarifying Qs) to avoid cross‑feature interference.
- Logging:
  - Wrap os.Logger behind a `Logging` protocol and inject into LLM layers; remove large multi‑line error dumps from main actor; retain detailed dumps only when a verbose flag is enabled.

**Other Subsystems (Comprehensive Review)**

App Lifecycle & DI
- Issue: Store instances are constructed inside `View.body` and re‑created on each render; all stores use `unowned let modelContext`.
- Action: Create `AppDependencies` in `App/PhysicsCloudResumeApp.swift` and inject once. Hold stores in `@StateObject` or within the dependencies container; pass via `.environment` to views.
- References: `PhysCloudResume/App/Views/ContentViewLaunch.swift`, all `*Store.swift` files.

JSON & Templating
- Issue: Custom JSONParser and manual string builders; duplicated context building across `ResumeTemplateProcessor` and `NativePDFGenerator`.
- Action: Replace parser with `JSONSerialization`; implement a single `ResumeTemplateDataBuilder` to produce the template context, preserving `TreeNode.myIndex` ordering. Switch both HTML and text paths to this builder.
- References: `PhysCloudResume/Shared/Utilities/JSONParser.swift`, `PhysCloudResume/ResumeTree/Utilities/JsonToTree.swift`, `PhysCloudResume/ResumeTree/Utilities/TreeToJson.swift`, `PhysCloudResume/Shared/Utilities/ResumeTemplateProcessor.swift`, `PhysCloudResume/Shared/Utilities/NativePDFGenerator.swift`.

Export Pipeline
- Issue: `ResumeExportService` contains UI alerts/panels; `NativePDFGenerator` does preprocessing/IO that should live outside rendering.
- Action: Extract an `ExportTemplateSelection` UI helper (the only place NSAlert/NSOpenPanel appear). Keep `ResumeExportService` orchestration‑only; make `NativePDFGenerator` purely rendering.
- References: `PhysCloudResume/Shared/Utilities/ResumeExportService.swift`, `PhysCloudResume/Shared/Utilities/NativePDFGenerator.swift`.

NotificationCenter
- Issue: One stray listener and a few sheet toggles through NC.
- Action: Remove `RefreshJobApps` listener (`JobAppStore.swift`); consider replacing sheet toggle notifications with bindings for strictly view‑local sheets. Keep menu/toolbar bridge as‑is.
- References: `PhysCloudResume/DataManagers/JobAppStore.swift:43`, `PhysCloudResume/App/Models/AppSheets.swift`.

Logging & Diagnostics
- Issue: Static `Logger` reads `UserDefaults`, writes to Downloads; noisy multi‑line logs in production paths.
- Action: Wrap os.Logger; use categories; keep file sink optional and only for debugging. Inject `Logging` dependency.
- References: `PhysCloudResume/Shared/Utilities/Logger.swift`.

Error Handling & Safety
- Issue: Force‑unwraps and fatalErrors in user paths.
- Action: Replace with guarded flows and user‑visible errors where appropriate. Quick wins:
  - `PhysCloudResume/Shared/Utilities/NativePDFGenerator.swift:556` (unwrap PDF data)
  - `PhysCloudResume/JobApplications/Views/NewAppSheetView.swift:158` (URL init)
  - `PhysCloudResume/JobApplications/Models/IndeedJobScrape.swift:171` (array `.first!`)
  - `PhysCloudResume/CoverLetters/AI/Utilities/CoverLetterModelNameFormatter.swift:30` (`.last!`)
  - `PhysCloudResume/DataManagers/JobAppStore.swift:92,124,132,140` (fatalError in typical flows)
  - `PhysCloudResume/Shared/UIComponents/ImageButton.swift:30` (init fatalError)

Secrets & Config
- Issue: API keys in `UserDefaults`.
- Action: `APIKeyManager` (Keychain) + `AppConfig` for non‑secret constants; inject where needed.
- References: `PhysCloudResume/AI/Models/Services/LLMRequestExecutor.swift:32`, `PhysCloudResume/AI/Models/Services/ModelValidationService.swift:43`, `PhysCloudResume/App/AppState.swift:177`.

Concurrency & Performance
- Issue: Broad `@MainActor` on services; streaming loops and retry backoffs run on main; heavy parsing on main.
- Action: Narrow `@MainActor`; use background tasks for build/exec/parse; hop to main only to mutate UI state.
- References: `PhysCloudResume/AI/Models/Services/LLMRequestExecutor.swift`, `PhysCloudResume/AI/Models/Services/LLMService.swift`, `PhysCloudResume/AI/Models/Services/ModelValidationService.swift`.

Web Scraping / HTML
- Issue: A few unwraps and brittle parsing.
- Action: Replace critical unwraps with guards; centralize per‑site parsing with explicit error states.
- References: `PhysCloudResume/JobApplications/Models/IndeedJobScrape.swift`, `PhysCloudResume/JobApplications/Utilities/WebViewHTMLFetcher.swift`, `PhysCloudResume/JobApplications/Utilities/CloudflareCookieManager.swift`.

Applicant Profile
- Issue: `ApplicantProfileManager` creates its own `ModelContainer` (even if schema‑matched), duplicating container responsibilities.
- Action: Prefer injecting `ModelContext` (from app container) via `AppDependencies` to avoid store contention and complexity.
- Reference: `PhysCloudResume/App/Applicant.swift:112`

Dead Code
- Action: Remove `RefreshJobApps` listener; prune commented‑out import features and legacy notes; prefer clean diffs over commented code.

**Updated Roadmap (Appended Slices)**

These extend the previously selected roadmap (Codex2_Selected_Refactor_Roadmap.md) with additional, concrete LLM and stability tasks.

- Slice 0: Stabilize Store Lifetimes
  - Convert stores in `ContentViewLaunch` to `@StateObject` or move to `AppDependencies` and inject once. Avoid constructing in `body`.
  - Audit all `unowned let modelContext` stores; ensure their lifetimes are bound to window scene or `AppDependencies`.

- Slice 1: Low‑Risk Safety Pass
  - Remove `RefreshJobApps` listener (PhysCloudResume/DataManagers/JobAppStore.swift:43).
  - Replace listed force‑unwraps/fatalErrors with safe handling.
  - Limit NotificationCenter usage to menu/toolbar; keep view‑local sheets as bindings.

- Slice 2: JSON & Template Context Builder
  - Implement `ResumeTemplateDataBuilder` (TreeNode → [String: Any]) preserving `myIndex` order.
  - Replace `TreeToJson` and eliminate `JSONParser.swift`; update `ResumeTemplateProcessor` and `NativePDFGenerator` to use the builder.

- Slice 3: LLM Facade + DTO Adapters (No New Deps)
  - Define `LLMClient` protocol + DTOs; implement an adapter backed by current SwiftOpenAI usage.
  - Confine SwiftOpenAI types to the adapter; update call sites in `ResumeReviseViewModel`, `ResumeReviewService`, `ClarifyingQuestionsViewModel` to depend on the facade.

- Slice 4: Secrets & DI Wiring
  - Add `APIKeyManager` (Keychain) and inject into `LLMRequestExecutor`/`ModelValidationService` via `AppDependencies`.
  - Replace `UserDefaults` API key reads. Keep existing settings UI; Settings writes to Keychain via `APIKeyManager`.

- Slice 5: Concurrency Hygiene
  - Remove class‑level `@MainActor` from `LLMRequestExecutor` and non‑UI LLMService APIs; move heavy work off main; ensure UI updates happen on main.
  - Shift JSON decoding and flexible parsing to background tasks.

- Slice 6: Capability Gating Unification
  - Centralize capability checks under LLMService; use `EnabledLLMStore` as persistence; probe via `ModelValidationService` only when needed.
  - Propagate JSON Schema success/failure via a single path.

- Slice 7: Logging Adapter
  - Provide a `Logging` protocol backed by os.Logger; inject across services. Keep file sink optional and debug‑only.

**Acceptance Criteria (Practical)**
- No fatalErrors/force‑unwraps in routine user flows.
- Store instances are stable across view updates; no construction inside `body`.
- JSON parser removed; TreeNode → template context builder used in both HTML and text export paths.
- LLM facade in place; SwiftOpenAI types confined to adapter; services accept facades via DI.
- API keys fetched from Keychain; no reads from `UserDefaults` for secrets.
- Services do not do work on main actor; only UI state updates are main‑isolated.
- NotificationCenter only for menu/toolbar and documented UI toggles.
- Logger backed by os.Logger; `UserDefaults` only for non‑secret prefs.

**Notes**
- Keep scope lean: no test harnesses or third‑party dependency managers in this phase.
- Favor small, reviewable PRs per slice; verify basic functionality after each slice manually (render a PDF, run a reasoning stream, export text, etc.).

