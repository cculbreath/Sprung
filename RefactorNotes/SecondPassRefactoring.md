# Second Pass Refactoring Plan

**Purpose**
Address the gaps surfaced by the external review (CodeReviewFindings/
reports) in alignment with `ClaudeNotes/Final_Refactor_Guide_20251007.md`, and
fold them into the existing deferred initiatives (`RefactorNotes/
deferred_backup_implementation.md`, `RefactorNotes/deferred_data_restructuring.md`).
This plan assumes Phases 0–9 are complete and defines a follow-up roadmap
focused on architectural hardening, vendor isolation, data safety, and export
modernization.

---

## Verified Issue Summary (by report)

| Report                 | Legitimate Findings                                                                                                                                                                                                                                                                                                                   | Notes                                                                                                                               |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 01_CoreAppLayer        | `AppState` remains a singleton; `PhysicsCloudResumeApp` still calls `fatalError` on container failure; `AppDependencies` wires singletons (`AppState.shared`, `CoverLetterService.shared`); menu commands rely entirely on NotificationCenter.                                                                                        | All issues confirmed in source. NotificationCenter is now documented but still extensive; keep scoped to menu/toolbar in follow-up. |
| 02_DataManagement      | `SwiftDataStore.saveContext()` swallows errors; `ImportJobAppsScript` reads Proxycurl key from `UserDefaults`; `JobAppStore` notification listener already removed (resolved).                                                                                                                                                        | Two actionable items remain.                                                                                                        |
| 03_AIServices          | Public SwiftOpenAI typealiases (`ConversationTypes.swift`); services/classes annotated `@MainActor` unnecessarily (`ConversationManager`, `OpenRouterService`); singleton services (`OpenRouterService`, `CoverLetterService.shared` usage); force unwraps for data URLs (`LLMRequestBuilder`, `LLMService`); adapter boundary leaks. | Represents largest remaining Phase 6 gap.                                                                                           |
| 04_AIViews             | No blocking issues. Minor task: convert `.onAppear { Task { … } }` to `.task` in model pickers.                                                                                                                                                                                                                                       | Track as polish.                                                                                                                    |
| 05_ResumeTree          | `TreeToJson` still performs manual JSON string building; `Resume` model bridges via `TreeToJson` before `JSONSerialization`.                                                                                                                                                                                                          | Confirms Phase 4 work still outstanding.                                                                                            |
| 06_ResumesManagement   | `Resume` model contains throttle/export orchestration and legacy documentation; uses TreeToJson.                                                                                                                                                                                                                                      | Must migrate export logic to service layer and update comments.                                                                     |
| 07_JobApplications     | `IndeedJobScrape` mixes parsing and store mutation; silent error handling; direct `UserDefaults` usage. Presentation helper in `JobApp` model.                                                                                                                                                                                        | Parsing/service boundary needs clean split.                                                                                         |
| 08_CoverLetters        | Continued reliance on `CoverLetterService.shared`; similar throttle/export logic in view models.                                                                                                                                                                                                                                      | Address alongside DI cleanup.                                                                                                       |
| 09_ReferenceManagement | No critical issues; mostly documentation pointers.                                                                                                                                                                                                                                                                                    | –                                                                                                                                   |
| 10_SharedUtilities     | Highlighted lack of logging in shared helpers (already covered via `SwiftDataStore`) and lingering TODOs.                                                                                                                                                                                                                             | Fold into observability tasks.                                                                                                      |
| 11_SharedUIComponents  | No blocking issues.                                                                                                                                                                                                                                                                                                                   | –                                                                                                                                   |

---

## Phased Roadmap

### Phase SP1 – Core Lifecycle & DI Hardening

**Objectives**

* Eliminate singleton ownership of `AppState`, `OpenRouterService`, and
  `CoverLetterService`, instantiating them through `AppDependencies`.
* Replace `fatalError` fallback in `PhysicsCloudResumeApp` with user-visible
  error handling and backup restore guidance (ties into deferred backup plan).
* Narrow NotificationCenter usage to documented menu/toolbar bridges with clear
  environment-based bindings for sheet toggles (already started in Phase 8).

**Key Tasks**

1. Introduce an `AppEnvironment` struct owned by `AppDependencies` containing
   `AppState`, `OpenRouterService`, `CoverLetterService`, and any other
   long-lived services. Inject through `.environment`.
2. Remove `AppState.shared`; convert to standard class initialized by
   `AppDependencies` with explicit dependencies (`OpenRouterService`,
   `ModelValidationService`). Replace weak `llmService` references with strong
   references or delegate protocols.
3. Refactor `CoverLetterService` (and related batch/best-of services) from
   singleton to DI-friendly instances. Update all call sites (toolbar buttons,
   batch generator, AppWindowView).
4. Replace `fatalError` in `PhysicsCloudResumeApp` with recoverable flows: show
   alert, offer backup restore (Phase SP4), and fall back to read-only mode if
   migration fails.
5. Ensure NotificationCenter posts are limited to the documented set in
   `MenuCommands.swift`; migrate any remaining view-local toggles to bindings.

**Deliverables**

* `AppDependencies` no longer references `.shared` singletons.
* `AppState` loses singleton constructor; initialization becomes explicit.
* Cover letter workflows consume injected coordinator/service instances.
* Graceful ModelContainer failure handling with UI alert and logging.
* Updated architecture notes in `MenuNotificationHandler`/README.

**Dependencies**

* Must precede LLM vendor isolation (Phase SP2) so new services can be passed
  through DI graph cleanly.

**Validation**

* `xcodebuild` build + manual smoke checklist (selection persistence, cover
  letter generation) using injected services.

---

### Phase SP2 – LLM Vendor Isolation & Concurrency Cleanup

**Objectives**

* Conform fully to the Phase 6 mandate: confine SwiftOpenAI types to adapter
  boundaries, replace typealiases with domain DTOs, and remove unnecessary
  `@MainActor` annotations.

**Key Tasks**

1. Add domain types (`LLMMessageDTO`, `LLMResponseDTO`, `LLMRole`, `LLMStreamChunkDTO`)
   and update persistence (`ConversationContext`, `ConversationMessage`) to use
   them. Provide conversion extensions inside adapter layer only.
2. Rework `LLMRequestBuilder`, `LLMRequestExecutor`, and `LLMService` APIs to
   consume/emit domain types. Keep SwiftOpenAI-specific structs internal to a
   `SwiftOpenAIClient` adapter module.
3. Convert `ConversationManager` into an `actor` (or background queue) without
   `@MainActor`. Add persistence bridging into SwiftData as part of this work or
   remove the class if redundant with SwiftData persistence.
4. Remove `@MainActor` from `OpenRouterService`; expose main-actor properties
   via `@MainActor` computed wrappers while running network calls off the main
   thread.
5. Replace all force unwraps constructing data URLs (`URL(string: …)!`) with
   guarded fallbacks that return `LLMError.clientError`/`resumeReviseError` on
   failure.

**Deliverables**

* Public surface area for AI services no longer depends on SwiftOpenAI types.
* Conversations stored as domain roles/strings; adapters perform conversion.
* All `@MainActor` usage justified per Final Refactor Guide.
* Force unwraps removed from LLM request/image handling paths.

**Dependencies**

* Requires Phase SP1 DI work to ensure services are injectable before API
  surface changes propagate.

**Validation**

* Manual smoke checklist items 2 and 4 (clarifying questions, key update) pass.

> **2025-10-08 Update:** LLMService/Facade now speak DTOs and persist via `LLMConversationStore`; OpenRouterService concurrency updated. Manual smoke (conversation persistence + images) still outstanding.

---

### Phase SP3 – Export Pipeline & Template Data Modernization

**Objectives**

* Complete the remaining Phase 4/5 work: retire `TreeToJson`, move export
  orchestration out of models, and execute the SwiftData template plan captured
  in `deferred_data_restructuring.md`.

**Key Tasks**

1. Implement `ResumeTemplateDataBuilder` (or equivalent) that transforms
   `TreeNode` + metadata into `[String: Any]` using standard JSON facilities.
   Update resume export/text flows to consume the builder directly.
2. Delete `TreeToJson.swift` and update `Resume.jsonTxt` (and any other callers)
   to use the new builder. Ensure deterministic ordering via `OrderedDictionary`
   or sorted arrays.
3. Extract export throttling (`debounceExport`, etc.) from `Resume` into a
   dedicated `ResumeExportCoordinator` that lives in the ViewModel/service
   layer. Models become pure data holders.
4. Kick off **Phase A** from `deferred_data_restructuring.md`: introduce
   SwiftData `Template`/`TemplateAsset` models, import existing templates from
   the Documents override path, and persist active template selection per
   resume.
5. Document the new manifest/context pipeline in README and developer docs.

**Deliverables**

* No references to `TreeToJson`; new builder validated with existing templates.
* Export orchestration encapsulated in services; models remain slim.
* SwiftData stores hold template artifacts; override precedence maintained.
* Updated docstrings + README architecture diagram already reflects DI/export
  boundary.

> **Progress 2025-10-23:** ResumeTemplateDataBuilder replaces `TreeToJson`, exports now flow through `ResumeExportCoordinator`, and initial SwiftData-backed template store is live (see `PhaseSP3_Progress.md`).

**Dependencies**

* DTO-focused changes in Phase SP2 should land first so export coordinator can
  consume updated services without rework.

**Validation**

* Manual export smoke (checklist item 3) comparing PDF/text outputs before vs.
  after refactor.

---

### Phase SP4 – Data Safety, Logging, and Tooling

**Objectives**

* Finish the backup UI and retention work and address logging/configuration
  gaps identified in the DataManagers review.

**Key Tasks**

1. Implement Phase B/C items from `deferred_backup_implementation.md`:

   * Settings “Data Safety” section with backup/restore buttons,
     confirmations, and last-backup metadata.
   * Finder shortcut and retention policy management.
2. Enhance `SwiftDataStore.saveContext` to log errors using `Logger.error` and
   optionally throw or surface errors to callers.
3. Refactor `ImportJobAppsScript` (and any other utilities) to obtain API keys
   via `APIKeyManager` rather than `UserDefaults`.
4. Split `IndeedJobScrape.parseIndeedJobListing` into pure parsing plus store
   orchestration; add `Logger` calls for failure cases.
5. Audit other shared utilities for TODO/empty logging blocks and address them
   as part of observability improvements.

**Deliverables**

* User-facing backup controls and retention policy.
* Error logging in all save paths; ability to trace failures in production.
* Import scripts and scrapers use central key management and structured logs.

**Dependencies**

* None strictly, but benefits from Phase SP1 (DI) for injecting configuration
  services.

**Validation**

* Manual backup/restore test using temporary data set.
* Logging smoke tests (induce save failure via temporary directory sandbox).

---

### Phase SP5 – Advanced Data & LLM Roadmap

**Objectives**

* Pursue the longer-term restructuring captured under “Deferred Data
  Restructuring” once core architecture is stabilized.

**Key Tasks**

1. **Template Manifest & Context Builder (Phase B in deferred notes):** Add
   manifest-driven context construction and `JSONValue` extensions bag for
   schemaless resume data.
2. **LLM Edit Mask & Patch Applier (Phase C):** Define mask semantics, implement
   patch application with audit trail, and integrate with the structured output
   pipeline created in Phase SP2.
3. **Order Preservation:** Ensure ordering is maintained across context
   building, patching, and export.
4. **Documentation & Tooling:** Provide developer docs for manifest authoring
   and mask configuration. Optionally supply a CLI or preview tool.

**Deliverables**

* New SwiftData models (`Template`, `TemplateAsset`, optional `TemplateManifest`)
  fully adopted; manifest-driven context builder in production.
* LLM edit mask enforced end-to-end with undo/audit capabilities.
* Comprehensive coverage for ordering and patch safety.

**Dependencies**

* Requires completion of Phases SP1–SP3 to ensure DI and export pipelines are
  ready for advanced features.

**Validation**

* Regression coverage for context builder and patching logic.
* Manual QA for template switching, manifest validation, and LLM write safety.

---

## Cross-Cutting Considerations

* **Documentation:** Continue updating README, `agents.md`, and in-code
  comments as each phase completes. Phase SP3 already refreshed README; treat
  subsequent documentation updates as acceptance criteria.
* **Observability:** Ensure each phase leaves behind meaningful logging for new
  error surfaces (ModelContainer fallback, save failures, import scripts).
* **Risk Mitigation:** Sequence phases to minimize churn—address DI singleton
  removal before overhauling LLM APIs, since adapter changes will ripple through
  the same files.

---

## Next Steps

1. Socialize this plan with stakeholders; confirm prioritization/order.
2. Create feature branches per phase (`refactor/core-di-hardening`, etc.).
3. Track progress in `RefactorNotes/` (e.g., add Phase SP1 progress log).
4. Update manual smoke checklist as new features are validated.

**Operational cadence**

* Run `xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume build`
  after each substantive task slice; do not progress to the next checkpoint
  without a clean build.
* Commit frequently with phase-specific prefixes (e.g., `SP1: …`) so work can be
  reviewed and, if required, reverted surgically. Avoid mixing concerns across
  phases in a single commit.
* When completing a phase, create a dedicated progress note in
  `RefactorNotes/` (e.g., `PhaseSP1Progress.md`) capturing objectives met,
  validation performed, and outstanding risks before commencing the next phase.

This second-pass roadmap closes the remaining gaps highlighted in the external
review while integrating outstanding deferred work. Completing Phases SP1–SP5
will fully align the codebase with the architectural goals defined in the
Final Refactor Guide and prepare the project for future extensibility.
