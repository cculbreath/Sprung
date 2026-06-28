# Logger Error-Surfacing Audit

**Date:** 2026-06-27
**Scope:** Every `Logger.error` / `Logger.warning` call site in `Sprung/` (≈609 sites: 254 error + 355 warning), plus swallowed `catch` blocks that log at any level.
**Method:** The codebase was partitioned into 10 modules and audited in parallel. Each module owner traced every error/warning site (and swallowing catch) to determine whether the error reaches the user through *any* channel, and flagged only **important** errors that are surfaced **solely** through a `Logger` call.

## The core problem

`Logger.error(...)` and `Logger.warning(...)` (`Sprung/Shared/Utilities/Logger.swift`) route to two places only:

1. Apple's `os.Logger` (visible in Console.app, not to the user).
2. A DEBUG-only in-repo file (`Onboarding/Logs/consolelog.txt`) and a DEBUG-only Downloads log.

```swift
#if DEBUG
appendToConsoleLog(formattedMessage)   // dev only
#endif
...
if shouldSaveDebugFiles && (level == .error || level == .warning) {
    saveLogToFile(message: formattedMessage)   // dev only
}
```

**In a release build, an error whose only output is a `Logger` call is completely invisible to the end user.** This audit finds the cases where that silence matters: a user-initiated action fails, data is lost, configuration the user must fix is wrong, or AI output is silently degraded — and the user is given no indication and no path to recovery.

### What counts as "properly surfaced" (and was therefore **not** flagged)

The app has real user-facing error channels, and the majority of error sites use them correctly:

- SwiftUI `.alert(...)` (36 sites) and `NSAlert`
- Toast overlays — `MacOSToastOverlay` via `onToast`
- Error banners and inline error labels
- `@Observable` / `@Published` error-state properties consumed by a view (`errorMessage`, `lastError`, `status = .error(...)`, `selectionError`, `suggestionError`, `voiceResultMessage`, `aiComment`, `retryError`)
- Thrown errors that propagate to a view that displays them
- `ModelConfigurationError` → the UI catches it and presents the model/settings picker (the canonical "fix your config" mechanism)
- Structured tool-result errors returned to the LLM (so the model can tell the user)

A `Logger` call that sits **alongside** one of these is not a finding. See [Appendix B](#appendix-b--notable-non-findings) for the well-handled paths that were explicitly verified.

---

## Summary

**76 findings: 26 High · 35 Medium · 15 Low**

| Module | High | Medium | Low | Total |
|--------|:---:|:---:|:---:|:---:|
| DataManagers + ResumeTree + Templates + Experience | 6 | 3 | 2 | 11 |
| Onboarding / Services | 3 | 6 | 1 | 10 |
| Onboarding / Handlers·Stores·Recording·Phase·Views | 2 | 7 | 4 | 13 |
| SeedGeneration + KnowledgeCardBrowser | 3 | 4 | 4 | 11 |
| Onboarding / Core | 4 | 2 | 0 | 6 |
| Discovery + JobApplications | 2 | 5 | 0 | 7 |
| App | 2 | 3 | 2 | 7 |
| Shared (incl. AI/LLM layer) | 3 | 1 | 0 | 4 |
| Resumes | 1 | 2 | 1 | 4 |
| CoverLetters + Export | 0 | 2 | 1 | 3 |
| **Total** | **26** | **35** | **15** | **76** |

---

## Cross-cutting patterns

The 76 findings collapse into eight recurring anti-patterns. Fixing them at the pattern level is more effective than site-by-site.

### Pattern 1 — Silent SwiftData save failures (data loss)
The largest and highest-impact cluster. The shared `SwiftDataStore.saveContext()` logs failures **only under `#if DEBUG`**, so release builds emit nothing at all. On top of that foundation, view-layer mutations (chip edits, title renames, drag-reorders, adding chips) update the in-memory model, run `refreshPDF()`, then call `save()` inside a `catch`-and-log block — the UI shows success while persistence silently failed; the change vanishes on next launch.
**Sites:** H1, H2, H3, H4, H5, H6, H7, H8, H9, M9, M10, M19, M27

### Pattern 2 — Swallowed `ModelConfigurationError` (violates project rule)
CLAUDE.md is explicit: a missing/invalid model must propagate `ModelConfigurationError` so the UI presents the picker — never swallow it. Several paths catch it and return `false`/`nil`/continue.
**Sites:** H10, H11, L8 (and contributes to M2, M28)

### Pattern 3 — LLM extraction silently produces 0 cards/skills (violates "must halt" rule)
The memory rule: *failed LLM document analysis must halt and prompt to top up budget, never silently produce 0 cards.* Git ingest (both onboarding and standalone) and per-document KC/skill extraction swallow pass failures; the artifact lands as a success with zero output. The git path is missing the `extractionFailures` write that the document path already does.
**Sites:** H12, H13, H14, M1, M21, M22, M28

### Pattern 4 — Broken prompt silently poisons the LLM
Prompt-template loaders return a sentinel string (`"[PROMPT LOAD ERROR: …]"`, `"Error loading prompt template"`) instead of `nil`/throwing when a bundle resource is missing. That string becomes the system prompt; every subsequent turn is degraded with no error.
**Sites:** H15, L4, L13

### Pattern 5 — Uploaded file/document silently dropped
The user drags in or picks a document/image; a read or process step fails in a `catch`/guard that just logs and returns. The LLM never receives the file, the conversation continues, and the user believes it was ingested.
**Sites:** H16, H17, H18, L5, L11, L12, L14, M8, M15, M16

### Pattern 6 — Export/generation "success-shaped failure"
The most insidious shape: the operation fails but the UI shows a *positive* signal. `Resume.swift` returns `""` → an empty file is written *and a success toast fires*. Debounced export fails → stale artifacts, no signal. Git ingest fails → agent pane turns green. Pending data reset fails → user believes the store was wiped.
**Sites:** H8 (reset), H13 (git green), H19 (stale), M12 (empty JSON), M14 (blank PDF), M26 (green section)

### Pattern 7 — User-triggered action: spinner stops, nothing else happens
A button kicks off async work; on failure the `defer` clears the spinner and the `catch` only logs. No error state exists on the view. The user sees the loading state end with no result and no explanation, and often re-clicks.
**Sites:** H21, H22, H23, H24, H25, M3, M4, M5, M6, M7, M23

### Pattern 8 — Frozen UI state with no recovery
A failure leaves a card/item stuck in a non-actionable state (e.g., permanently showing a "Regenerating" badge with no buttons), forcing a session restart.
**Sites:** H26

---

## High-priority findings (26)

Grouped by pattern. Each entry: ID · `file:line` · level · verbatim message · impact · remediation.

### Persistence / data loss (Pattern 1)

#### H1 — `DataManagers/SwiftDataStore.swift:29` · error · **foundational**
> `"SwiftData save failed: \(error.localizedDescription)"`

The single shared save path for every SwiftData-backed store, and its `Logger.error` is wrapped in `#if DEBUG` — **release builds emit nothing, even to Console.app.** `@discardableResult`, so every call site drops the `Bool`. This is the root cause that makes H3–H6, M9, M10, M19, M27 silent.
**Fix:** Remove the `#if DEBUG` guard so production at least logs; then propagate save failures to a user-visible channel (persistent banner/toast) for user-triggered mutations.

#### H2 — `DataManagers/ResStore.swift:39` & `:49` · error
> `"ResStore.create: No manifest found for template \(template.slug)"` / `"ResStore.create: Failed to build resume tree for template \(template.slug)"`

User clicks **Create Resume**; `create()` returns `nil`; call sites (`AppSheets.swift:68`, `ResumeSplitView.swift:76`, `ResumeBannerView.swift:114`) discard nil or take no action. The dialog closes, no resume appears, no explanation.
**Fix:** `create()` should `throw`/return `Result`; `CreateResumeView` surfaces the error in an alert before dismissing.

#### H3 — `ResumeTree/Views/ResumeEntryCardView.swift:181` · error
> `"Failed to save title rename: \(error)"`

In-memory title is updated (UI shows the rename) but `save()` threw; `isRenamingTitle = false` set unconditionally. Rename lost on restart; user believes it saved.
**Fix:** Roll back the in-memory value on failure and show a toast/banner.

#### H4 — `ResumeTree/Views/ChipView.swift:199` · error
> `"Failed to save chip edit: \(error)"`

`node.value` updated in-memory, `refreshPDF()` runs (reinforcing the illusion), but `save()` failed. Edit lost on restart.
**Fix:** Roll back `node.value`, skip `refreshPDF()`, show an error toast.

#### H5 — `ResumeTree/Views/ChipChildrenView.swift:405`, `:451`, `:499` · error
> `"Failed to save new chip: \(error)"` / `"Failed to save skill from bank: \(error)"` / `"Failed to save recommendation: \(error)"`

Three chip-add paths (direct text, skill bank, AI recommendation) insert the node into the tree and `refreshPDF()` before saving; on save failure the phantom chip renders but vanishes on next launch.
**Fix:** Remove the newly added node on failure, skip `refreshPDF()`, surface a toast.

#### H6 — `ResumeTree/Views/ChipDropDelegate.swift:93` & `DraggableNodeWrapper.swift:130` · warning
> `"Failed to save reordered chips: \(error.localizedDescription)"` / `"Failed to persist dragged node reorder: \(error.localizedDescription)"`

Drag-reorder applied in-memory, export runs against the new order, but persistence failed — next launch shows the old order; data is now inconsistent with the rendered PDF.
**Fix:** Restore original order on failure, show a toast.

#### H7 — `Onboarding/Services/OnboardingPersistenceService.swift:420` · error
> `"❌ Failed to persist experience_defaults to data store: \(error.localizedDescription)"`

After the persistence failure, execution **falls through** to `eventBus.publish(.objective(.statusUpdateRequested(... status: "completed" ...)))` — the phase-completion gate fires even though the generated ExperienceDefaults weren't saved. On next launch they may revert.
**Fix:** Rethrow or publish `processing(.errorOccurred(...))` and **skip** the completion event so the phase doesn't advance.

#### H8 — `Shared/AI/.../SwiftDataBackupService.swift:109` & `:139` · error
> `"❌ Pending reset failed: Application Support not found"` / `"❌ Pending reset failed: \(error.localizedDescription)"`

A user-requested data-store wipe runs at startup. The flag is pre-cleared (to avoid a loop) **before** the deletion attempt, and the `@discardableResult` return is discarded at `SprungApp.swift:37`. On failure the store survives but won't retry. **The user believes their data was erased** (e.g., before sharing the machine) — it wasn't.
**Fix:** Capture the flag state before clearing, check the return at the call site, and present an alert ("reset did not complete — Try Again / Quit") on first render.

#### H9 — `Onboarding/Services/VoiceProfileService.swift:177` · error
> `"🎤 Failed to encode voice profile for CoverRef storage"`

The InferenceGuidanceStore write succeeds (so extraction *looks* successful) but the `.voicePrimer` CoverRef entry — the path cover-letter generation and the Primers tab read — silently fails to write. Cover letters won't use the user's voice.
**Fix:** Throw from `upsertVoicePrimerRef`, propagate through `storeVoiceProfile`, surface an alert.

### Configuration the user must fix (Pattern 2)

#### H10 — `Onboarding/Core/InterviewLifecycleService.swift:132` & `:222` · error
> `"❌ Model not configured: \(error.localizedDescription)"`

Both fresh-start and resume catch `ModelConfigurationError`, log, and return `false`; the view discards it with `_ =`. **The user clicks "Start Interview"/"Resume" and nothing happens** — no error, no guidance to Settings. Directly violates the CLAUDE.md `ModelConfigurationError` propagation rule.
**Fix:** Let `ModelConfigurationError` propagate to the existing settings-picker path, or present an alert: "No Anthropic model configured for the interview. Go to Settings → Models."

#### H11 — `Onboarding/Core/InterviewLifecycleService.swift:390` · error
> `"Failed to start orchestrator: \(error)"`

Same silent-discard chain as H10 but for a first-request/serialization failure. Fires *before* the streaming error infrastructure is listening, so unlike live-interview errors it has no other surfacing path.
**Fix:** Propagate or emit a toast/alert before returning false.

### LLM extraction silently empty (Pattern 3)

#### H12 — `Onboarding/Services/GitIngestionKernel.swift:167` · warning
> `"⚠️ Git digest extraction had \(analysis.passFailures.count) pass failure(s): \(analysis.passFailures.joined(separator: " | "))"`

`analysis.passFailures` is logged then never written to `artifactRecord["extractionFailures"]`. The artifact is emitted as a fully successful ingest with 0 skills/0 cards — no ⚠️, no retry prompt. **The document path does this correctly; the git path is missing the write.**
**Fix:** `if !analysis.passFailures.isEmpty { record["extractionFailures"].arrayObject = analysis.passFailures }` before building the `IngestionResult`; the existing UI banner picks it up.

#### H13 — `KnowledgeCardBrowser/Services/StandaloneKCExtractor.swift:369` · warning
> `"StandaloneKCExtractor: git digest extraction had \(analysis.passFailures.count) pass failure(s): …"`

Standalone-KC equivalent of H12. `agentActivityTracker.markCompleted()` fires for the agent step (digest produced) **before** the extraction passes, so the agent pane turns green even when all passes fail and 0 cards/skills result.
**Fix:** If `passFailures` is non-empty (esp. when cards & skills are both empty), throw from `extractGitRepository` so `markFailed()` runs, or surface the failures in coordinator status.

#### H14 — `KnowledgeCardBrowser/Services/StandaloneKCAnalyzer.swift:92` · warning
> `"⚠️ StandaloneKCAnalyzer: Failed to extract narrative cards from \(filename): \(error.localizedDescription)"`

Per-document KC extraction is in a catch-continue loop; on failure the document contributes 0 cards and is indistinguishable from a document that legitimately had none. No status/toast/alert; coordinator `.failed` never set.
**Fix:** Accumulate per-document failures and surface them in `AnalysisConfirmationView` / `coordinator.status = .failed`; follow `BudgetPauseGate` for budget errors.

### Broken prompt poisons the LLM (Pattern 4)

#### H15 — `Onboarding/Resources/PromptLibrary.swift:167` · error
> `"⚠️ Failed to load prompt: \(name)"`

`loadPrompt(named:)` returns `"[PROMPT LOAD ERROR: \(name)]"` when a bundled prompt is missing — that placeholder becomes the LLM **system prompt**, silently degrading every subsequent turn.
**Fix:** Throw instead of returning a placeholder; abort onboarding startup with an actionable "App resources appear corrupted — please reinstall."

### Uploaded document silently dropped (Pattern 5)

#### H16 — `Onboarding/Core/Coordinators/UIResponseCoordinator.swift:824` · error
> `"❌ Direct upload failed: \(error.localizedDescription)"`

Drag-drop/file-picker document upload during the interview. On `processFile` failure the catch logs, cleans up, and returns — no event published, LLM never told. The user's document (often the resume) is silently excluded.
**Fix:** `ToastCenter.shared.show(.error("Could not add \"\(name)\" — \(error.localizedDescription)"))` (matches the replay-failure pattern already used elsewhere).

#### H17 — `Onboarding/Core/Coordinators/UIResponseCoordinator.swift:870` · error
> `"❌ Writing sample upload failed: \(error.localizedDescription)"`

Same pattern for writing samples — voice-profile/style analysis silently runs on nothing.
**Fix:** Same toast pattern as H16.

#### H18 — `Onboarding/Handlers/DocumentArtifactHandler.swift:573` · error
> `"❌ Failed to read PDF file: \(filename)"`

`sendPDFDirectlyToLLM` (requestKind `"resume"`) fails to read the uploaded resume PDF and returns early — the LLM never sees the resume; conversation continues normally.
**Fix:** Call the existing `handleProcessingFailure(_:filename:agentId:)` (shows a status message + retry guidance) or emit `.extractionStateChanged` with an error.

### Export failure after a completed user action (Pattern 6)

#### H19 — `Resumes/Services/ResumeExportCoordinator.swift:47` · error
> `"Debounced export failed: \(error)"`

The live-editing auto-save path. `onFinish?()` fires in `defer` with no failure signal; `resume.textResume`/`resume.pdfData` go stale. TreeNode data is safe, but the rendered PDF/text the user sees and re-exports are wrong with no indication. (Note: `forceRender` at `:91` *does* rethrow — only the debounced path is silent.)
**Fix:** Add an `onFailure: ((Error) -> Void)?` (or an observable `exportError`) and wire a toast/banner at the `ResumeDetailVM` call site.

#### H20 — `App/Views/.../ReferencesModuleView.swift:150` · error
> `"Export failed: \(error.localizedDescription)"`

User completes menu → `NSSavePanel` → Save; `encode()`/`write(to:)` throws; **file silently not written.** No state, no alert. Could be read as success or a hang.
**Fix:** `NSAlert` in the catch with `localizedDescription` + "Check disk permissions or available space."

### User-triggered action with no feedback (Pattern 7)

#### H21 — `App/Services/SecondaryWindowService.swift:577` · error
> `"Failed to build SeedGenerationContext"`

User picks **Generate Experience Defaults…** (⌘⇧G); prerequisite guards pass; `SeedGenerationContextBuilder.build()` returns nil; the window never opens via a bare `return`. Peer guard paths (`:562/:585/:596`) all call `presentNoKnowledgeCardsAlert`/`presentSeedModelAlert` — this one doesn't.
**Fix:** Replace the bare `return` with an `NSAlert` ("Couldn't assemble generation context. Ensure the onboarding interview has been completed.").

#### H22 — `Discovery/Views/Daily/DailyView.swift:407` · error
> `"Failed to generate daily tasks: \(error)"`

The **Refresh (↻)** button for today's AI tasks. `defer` stops the spinner; the catch only logs; `DailyView` has no error `@State`. A primary daily-use action fails invisibly.
**Fix:** `@State var taskGenerationError: String?` set in the catch → `.alert`/inline error.

#### H23 — `Discovery/Views/Daily/DailyView.swift:423` · error
> `"Failed to regenerate \(category.displayName) tasks: \(error)"`

User submits feedback and "Regenerate"; on failure the catch logs, then `regeneratingCategory = nil` / `feedbackText = ""` clear state — **the feedback sheet dismisses as if it succeeded.** The user's feedback is discarded silently.
**Fix:** Surface an alert/inline error before clearing state.

#### H24 — `Shared/Views/KnowledgeCardsBrowserTab.swift:325` · error
> `"Pipeline: Enrichment failed - \(error.localizedDescription)"`

The **Enrich** toolbar button runs in a bare `Task { do {} catch {} }`. On failure the progress overlay disappears and nothing else changes — the user can't tell network vs. model-config vs. credit shortfall.
**Fix:** Add `@State var pipelineError: String?` (or a `.error` status case) → alert/banner; `localizedDescription` is already meaningful for `ModelConfigurationError`/`insufficientCredits`.

#### H25 — `Shared/Views/KnowledgeCardsBrowserTab.swift:339` · error
> `"Pipeline: Merge failed - \(error.localizedDescription)"`

Same bare-`Task` pattern for the **Merge** button (which is destructive). Silent failure leaves the list unchanged with no explanation.
**Fix:** Same shared error state/banner as H24.

### Frozen UI with no recovery (Pattern 8)

#### H26 — `SeedGeneration/Core/SeedGenerationOrchestrator.swift:347/353/360/384` + `Models/ReviewItem.swift:213–218` · error
> `"Cannot regenerate: no context available"` / `"…item not found"` / `"…generator not found for \(generatorTypeName)"` / `"Regeneration failed: \(error)"` / `"❌ Regeneration failed for: \(item.task.displayName)"`

User rejects a generated item and confirms **Regenerate**; on `nil` return, `isRegenerating = false` but `userAction` stays `.rejected`. `ReviewItemCard` suppresses all action buttons when `userAction != nil` and renders a "Regenerating" badge → **the item is permanently frozen with no approve/reject/edit/delete and no error.** Recovery requires restarting the session.
**Fix:** On failure, reset `userAction = nil` with a visible error indicator, or add a `.regenerationFailed(reason:)` action with a Retry button.

---

## Medium-priority findings (35)

Degraded results, silent data-coverage gaps, or failures the user may not immediately notice. `file:line` · level · short description.

| ID | file:line | lvl | What's silent / impact |
|----|-----------|-----|------------------------|
| M1 | `Onboarding/Services/KnowledgeCardWorkflowService.swift:106` | warn | Chat-inventory extraction fails → skills/cards from the interview conversation silently dropped. |
| M2 | `Onboarding/Services/KnowledgeCardWorkflowService.swift:147` | warn | Dedup fails → falls back to raw cards; user sees inflated card count, no note. |
| M3 | `Onboarding/Services/KnowledgeCardWorkflowService.swift:184` | warn | Skill curation skipped silently → noisier skill bank. |
| M4 | `Onboarding/Services/KnowledgeCardWorkflowService.swift:214` | warn | ATS synonym expansion + dedup skipped → degraded resume match, no note. |
| M5 | `Onboarding/Services/WebExtractionService.swift:208` | error | URL skill extraction fails → "0 skills" indistinguishable from "URL had none." |
| M6 | `Onboarding/Services/WebExtractionService.swift:234` | error | URL narrative-card extraction fails → same "0 cards" ambiguity. |
| M7 | `Onboarding/Core/PhaseTransitionService.swift:163` | error | Phase-3 artifact filesystem export fails → LLM file tools find nothing all session. |
| M8 | `Onboarding/Core/PhaseTransitionService.swift:179` & `:195` | error | Incremental artifact/KC filesystem sync fails → LLM sees stale data. |
| M9 | `Onboarding/Stores/OnboardingSessionStore.swift:39` | error | Session `save()` fails → whole onboarding session lost on restart. |
| M10 | `Onboarding/Stores/ArtifactRecordStore.swift:37` | error | Artifact records `save()` fails → uploaded-doc metadata/links lost on restart. |
| M11 | `Onboarding/Stores/OnboardingSessionStore.swift:272` | error | `configure_enabled_sections` encode fails → user's section selection silently lost. |
| M12 | `Onboarding/Stores/OnboardingSessionStore.swift:284` | error | Section-config decode fails → returns empty config → all sections suppressed. |
| M13 | `Onboarding/Handlers/VoiceProfileExtractionHandler.swift:147` | error | Voice extraction fails; `.voicePrimerExtractionFailed` has no subscriber → no UI, LLM not told. |
| M14 | `Onboarding/Handlers/DocumentArtifactMessenger.swift:249` | warn | Batch timeout, no artifacts → LLM gets the "upload succeeded" tool result but no content message. |
| M15 | `Onboarding/Handlers/DocumentArtifactMessenger.swift:274` | warn | Batch completes empty → same silent drop as M14. |
| M16 | `App/Services/SecondaryWindowService.swift:375` | error | "Generate Weekly Reflection" throws after window opens → empty Discovery window, no explanation. |
| M17 | `App/Views/Settings/ApplicantProfileView.swift:120` | error | Signature image read fails → picker closes, no error, old/blank signature shown. |
| M18 | `App/Views/TemplateEditorView+Preview.swift:185,190` + `TemplateEditorView.swift:212` | error | Overlay PDF pick fails (3 paths) → panel no-ops; `previewErrorMessage` not set here. |
| M19 | `Resumes/AI/RevisionAgent/Views/ResumeRevisionView.swift:196` | error | Initial PDF load fails → preview pane spins "Loading PDF…" forever; agent still runs. |
| M20 | `Resumes/Models/Resume.swift:93` | error | `jsonTxt` returns `""` → empty file written **with a success toast** (success-shaped failure). |
| M21 | `KnowledgeCardBrowser/Services/StandaloneKCAnalyzer.swift:74` | warn | Per-document skills extraction fails silently → 0 skills, no status. |
| M22 | `SeedGeneration/Core/SeedGenerationOrchestrator.swift:211` | error | Task fails but section row set to `.completed` (green ✓); only an aggregate "(N failed)" count, no detail. |
| M23 | `KnowledgeCardBrowser/Views/DocumentIngestionSheet.swift:419` | error | File-picker `.failure` → only logs; no state/alert; nothing added. |
| M24 | `KnowledgeCardBrowser/Views/DocumentIngestionSheet.swift:456–459` | — | Swallowed catch; `coordinator.status = .failed` is **dead code** (never set) → analysis throws reset to idle. |
| M25 | `Discovery/Views/Events/EventPrepView.swift:411` | error | Pitch generation fails → pitch area stays empty, no explanation. |
| M26 | `Discovery/Views/Events/EventPrepView.swift:469` | error | "Add to Calendar" fails (e.g. permissions) → completely silent. |
| M27 | `Discovery/Views/Events/DebriefView.swift:487` | error | Debrief outcome generation fails → outcomes panel stays empty silently. |
| M28 | `Discovery/Services/CoachingService.swift:693` | error | End-of-session task gen fails → session shows `.complete` but 0 tasks created. |
| M29 | `Discovery/Services/CoachingService.swift:581` | error | Follow-up action (e.g. "choose focus jobs") fails → session ends as if success; action never ran. |
| M30 | `CoverLetters/AI/Services/MultiModelCoverLetterService.swift:497` | error | Committee-feedback `save()` fails → analysis won't survive relaunch; looks like "pending." |
| M31 | `CoverLetters/Views/CoverLetterPDFView.swift:77` | warn | `PDFDocument(data:)` returns nil after non-empty data → blank white preview, no message. |
| M32 | `DataManagers/Templates/TemplateDefaultsImporter.swift:41` | error | Startup template install fails → empty template list; user can't create resumes. |
| M33 | `DataManagers/Templates/TemplateManifestDefaults.swift:208` | warn | Manifest-override decode fails → silently drops custom AI-fields/sections/font sizing. |
| M34 | `DataManagers/EnabledLLMStore.swift:122` | error | Enabled-models fetch fails → empty model picker, no "fetch failed" vs "none enabled" distinction. |
| M35 | `Shared/AI/.../LLMConversationStore.swift:59` | error | `saveMessages()` swallows `save()` failure → conversation history lost on next launch. |

> Note: M11/M12 are listed under Pattern 1; M5/M6/M21/M28 under Pattern 3; M14/M15/M16 under Pattern 7; M20/M26 under Pattern 6.

---

## Low-priority findings (15)

Edge cases, dev/test-only impact, or graceful fallbacks worth a note.

| ID | file:line | lvl | What's silent / impact |
|----|-----------|-----|------------------------|
| L1 | `Onboarding/Services/TranscriptPersistenceService.swift:74` & `:90` | error | Transcript record persist fails → incomplete replay tape (dev/test impact). |
| L2 | `Onboarding/Stores/TranscriptionCheckpointStore.swift:130` | error | Checkpoint encode fails → chunk re-transcribed on resume (extra cost, no data loss). |
| L3 | `Onboarding/Views/Components/DropZoneHandler.swift:147` | error | Dropped image temp-write fails → `completion` never called; image silently lost. |
| L4 | `Onboarding/Handlers/DocumentArtifactMessenger.swift:461` | warn | Image artifact file missing → silently not sent to LLM. |
| L5 | `Onboarding/Handlers/DocumentArtifactMessenger.swift:467` | warn | Image data read fails → silently not sent to LLM. |
| L6 | `Resumes/AI/Types/ResumeReviewQuery.swift:14` | error | Missing prompt resource → `"Error loading prompt template"` sent as the prompt. |
| L7 | `App/AppDelegate.swift:230` | warn | `sprung://capture-job` missing `url` param → job silently not captured. |
| L8 | `App/Views/ToolbarButtons/BestJobButton.swift:159` | error | Missing prompt template → fallback string used as system prompt; root cause hidden behind a downstream API error. |
| L9 | `DataManagers/ResStore.swift:67` & `:107` | error | Initial PDF render after create/duplicate fails → blank preview until next open (resume itself is fine). |
| L10 | `ResumeTree/Models/TreeNode+JSON.swift:15` | error | `toJSONString()` returns nil → FixOverflow/SkillReorder silently can't proceed (very unlikely). |
| L11 | `KnowledgeCardBrowser/Services/StandaloneKCCoordinator.swift:308` & `:310` | warn | Post-persist skills dedup/ATS skipped; **`ModelConfigurationError` case violates the config-surfacing rule.** |
| L12 | `KnowledgeCardBrowser/Services/StandaloneKCCoordinator.swift:352` | warn | Per-card enrichment fails → dropped from count, no "N failed" detail (additive data, no loss). |
| L13 | `KnowledgeCardBrowser/Services/StandaloneKCExtractor.swift:280` | warn | LLM summary fails → local word-count summary fallback (cosmetic). |
| L14 | `KnowledgeCardBrowser/Services/MetadataExtractionService.swift:110` | warn | Metadata extraction fails → filename-derived defaults (cosmetic; deprecated single-card path). |
| L15 | `CoverLetters/AI/.../CoverLetterQuery.swift:183` | warn | Oversized resume silently truncated before generation → letter built on partial resume, no note. |

---

## Recommendations

1. **Fix the foundation first (H1).** Remove the `#if DEBUG` from `SwiftDataStore.saveContext()` and give it a user-visible failure channel. This single change addresses the root of the Pattern-1 cluster (H3–H6, M9, M10, M19, M27).
2. **Enforce the two project rules already on the books.** Stop swallowing `ModelConfigurationError` (H10, H11, L8, L11) and stop letting LLM extraction silently produce 0 cards (H12–H14, M1, M5, M6, M21, M28). The git ingest path (H12) just needs the `extractionFailures` write the document path already has.
3. **Kill "success-shaped failures" (Pattern 6).** Audit every place that returns `""`/empty/`nil` on failure and then fires a success toast or a green/complete status — these are worse than silence because they actively reassure the user. Priority: H8, H13, M20.
4. **Adopt a standard "operation failed" surface for buttons (Pattern 7).** A reusable toast/error-state helper for the many `Task { do {…} catch { Logger.error } }` button handlers would close H22–H25 and M16/M25–M29 consistently.
5. **Make prompt-template loaders throw, not return sentinels (Pattern 4).** H15, L6, L8.

---

## Appendix A — Audit coverage

| Module | Sites examined | Findings |
|--------|:---:|:---:|
| Onboarding / Core | ~90 | 6 |
| Onboarding / Services | ~90 | 10 |
| Onboarding / Handlers·Stores·Recording·Phase·Views·Tools·Utilities | ~90 | 13 |
| Resumes | 60+ | 4 |
| Shared (incl. AI/LLM layer) | ~40 | 4 |
| App | 45 | 7 |
| Discovery + JobApplications | 55 | 7 |
| CoverLetters + Export | 36 | 3 |
| SeedGeneration + KnowledgeCardBrowser | 38 | 11 |
| DataManagers + ResumeTree + Templates + Experience | 35 | 11 |

## Appendix B — Notable non-findings (verified well-handled)

These important-looking sites were traced and confirmed to surface properly — recorded so the audit is falsifiable:

- **LLM interview errors** — `LLMMessenger` emits `.processing(.errorOccurred)` + `surfaceErrorToUI` (system chat message); errors during a live interview are visible.
- **Cover-letter buttons** — `CoverLetterGenerateButton`/`CoverLetterReviseButton` both call `presentError(_:needsModelSettings:)` → alert with "Open Model Settings".
- **Data reset (settings path)** — `DataResetService.swift:162` rethrows; `ResetSettingsSection` shows `resetError`.
- **App startup/migration** — `SprungApp` maps all failures to `launchState = .readOnly(message:)`.
- **Batch cover letters** — per-item failures accumulate into `failureDetails` → thrown `BatchCoverLetterError.operationsFailed`.
- **Export file writes** — all route through `onToast` → `MacOSToastOverlay`; `NativePDFGenerator` throws `PDFGeneratorError`.
- **Job import / scraping** — `NewAppSheetView` sets `errorMessage`+`showError`; LinkedIn/Indeed scrapers return nil → surfaced there.
- **Application review** — `ApplicationReviewService` → `onComplete(.failure)` → red error text.
- **Discovery coordinator** — sets `status = .error(...)`, rendered in the UI.
- **OpenRouter / KC refine / Title sets / Writing samples** — set observable error state (`lastError`, `reasoningStreamManager.showError`, `aiComment`, `voiceResultMessage`, per-field `retryError`).
- **Resume revision agent** — stream/build failures set `status = .failed` → `ResumeRevisionView` alert; tool-dispatch errors returned to the LLM as tool results.
- **Revision verification passes** — advisory by design; degrade to notes on the completion card (never blocking).
- **Tool execution** — `ToolExecutionCoordinator.emitToolFailure()` delivers structured errors to the LLM.
- **Phase-script transitions** — every warning pairs with a `.blocked(reason:message:)` the LLM relays.
- **Recording/replay** — developer tooling; best-effort failures are acceptable by design.
- **`#if DEBUG`-only paths** — `DebugRegenerationService`, onboarding skills-dedup debug block, etc. — not release concerns.
