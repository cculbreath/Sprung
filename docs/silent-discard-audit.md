# Silent-Discard Error Audit

**Date:** 2026-06-29
**Scope:** Failure paths in `Sprung/` that produce **no user-visible surface AND no `Logger.error`/`Logger.warning`** — i.e. the failures the [logger error-surfacing audit](logger-error-surfacing-audit.md) was structurally blind to. Baseline triaged: ~397 `try?`, 0 `try!`, 0 empty `catch {}`, plus catch blocks whose only statement is `Logger.info`/`.debug`/`.verbose`, bare `return`/`nil` guards, and discarded `Bool`/`Result` returns.
**Method:** The codebase was partitioned into the same 10 modules as the prior audit and swept in parallel (two independent passes on six of the modules). Each owner greped the silent-discard signatures, opened each candidate, and traced whether the failure reaches the user through *any* channel. Only **important** failures with **zero surface of any kind** are flagged.

## The core problem

The prior audit was complete over every `Logger.error` / `Logger.warning` site and fixed 76 findings. It was **structurally blind** to two failure shapes that are equally invisible in a release build:

1. **True zero-log discards** — `try?` on a high-stakes call, a discarded `@discardableResult Bool`/`Result`, or a `guard … else { return }` with no statement at all. Nothing is emitted anywhere.
2. **Below-threshold logs** — a `catch { Logger.debug(…) }` or `Logger.info(…)`. `Logger.swift` only writes its DEBUG file for `.error`/`.warning`; `.info`/`.debug`/`.verbose` go to Apple's `os.Logger` (Console.app) and nowhere a user or a surfacing layer can see.

In both shapes a user-initiated action fails, data is lost, configuration the user must fix is silently wrong, or AI output is silently degraded — and the user gets no indication and no path to recovery. This audit finds exactly those cases. It deliberately **excludes** every site the prior audit already covered (anything with `.error`/`.warning` in its failure path) and the 76 already-fixed findings.

### What was treated as "properly surfaced" (not flagged)

Same channels as the prior audit: `.alert` / `NSAlert`, `ToastCenter`/`MacOSToastOverlay`, `@Observable` error-state consumed by a view, thrown-and-handled errors, `ModelConfigurationError` → settings picker, and **structured tool-result errors returned to the LLM** (so the model can tell the user). A silent path whose failure also surfaces a few lines away or in its caller is a non-finding — see [Appendix B](#appendix-b--notable-non-findings).

---

## Summary

**40 findings: 1 High · 15 Medium · 24 Low**

| Module | High | Med | Low | Total |
|--------|:---:|:---:|:---:|:---:|
| B — Onboarding / Services | 0 | 2 | 5 | 7 |
| J — DataManagers + Templates + Experience | 0 | 2 | 5 | 7 |
| A — Onboarding / Core | 0 | 2 | 3 | 5 |
| C — Onboarding / Handlers·Stores·Views·Tools·Utilities | 0 | 1 | 3 | 4 |
| H — CoverLetters + Export | 0 | 2 | 2 | 4 |
| D — Resumes (+ ResumeTree) | 0 | 1 | 2 | 3 |
| E — Shared (incl. AI/LLM layer) | 0 | 2 | 1 | 3 |
| F — App | 0 | 2 | 1 | 3 |
| G — Discovery + JobApplications | 1 | 0 | 1 | 2 |
| I — SeedGeneration + KnowledgeCardBrowser | 0 | 1 | 1 | 2 |
| **Total** | **1** | **15** | **24** | **40** |

> IDs use a fresh `S` prefix to avoid collision with the prior audit's H/M/L ids. `LOG:` records what the failure path emits today (`none` = zero-log discard; `info`/`debug` = below-threshold).

---

## Cross-cutting patterns

The 40 findings collapse into seven recurring shapes. Fix at the pattern level.

### Pattern S-1 — Bootstrap fetch failure overwrites real data with a blank entity
A store's `init`/lazy-getter does `try? modelContext.fetch(...).first`; on **nil** it creates and `saveContext()`s a blank (or dummy) record. The `try?` cannot distinguish "no record yet" from "fetch threw" — so a transient/corrupt-store fetch *throw* causes the user's real data to be silently overwritten with blanks on disk. Highest-impact silent pattern after S-2.
**Sites:** S15 (ExperienceDefaults), S16 (ApplicantProfile/"John Doe"), S39 (CandidateDossier), S40 (EntityStore family).

### Pattern S-2 — `try? <store>.save()` after a completed action (success-shaped data loss)
The work succeeded, the result is written to the in-memory model, an activity tracker is marked `.completed` (green) — then the persistence is dropped with a bare `try?`. The user sees success; the data is gone on next launch and the expensive work silently re-runs (re-burning LLM tokens).
**Sites:** S1 (JobAppPreprocessor — the single High).

### Pattern S-3 — Silent JSON encode/decode of a persisted blob drops extracted content
A `try? encoder.encode(...)` (or `try? decode`) inside an `if let`/`guard` writes the result only on success; on failure the skills/cards/enrichment/title-words are silently absent and the record persists empty. The encoded types are pure `Codable` so failure is low-probability — but the surface is zero and the impact (0 skills / 0 KCs / wiped enrichment) is high-shaped.
**Sites:** S4, S20, S21, S22, S23, S24, S25, S34, S36, S37, S19.

### Pattern S-4 — File-read `try?` drops a document/asset from an LLM request, verification, or the UI
`try? Data(contentsOf:)` / `try? String(contentsOf:)` returns nil and the `if let` chain quietly omits a PDF, the git-evidence file, the grounding corpus, the conversation history, the CSS, or the profile photo. The LLM/verification pass then runs on incomplete input → silently degraded output; or the UI silently shows the old value.
**Sites:** S2, S3, S5, S7, S28, S29, S30, S8, S9.

### Pattern S-5 — Discarded `Bool`/`Result` from a config or persist write
`_ = APIKeyStore.set(...)`, `try? store.updateManifest(...)`, `_ = startInterview(...)`, `try? fetch()` whose forEach clears a flag. The write fails, the UI reflects success, and the breakage shows up only much later (next launch, wrong default, "key not configured").
**Sites:** S10, S11, S6, S38.

### Pattern S-6 — Below-threshold catch (`.info` / `.debug`) — the prior audit's blind spot
The failure *does* log, just beneath the surfacing threshold, so it is invisible to the user and to the release DEBUG-file. Includes a few that set an `@Observable` error property the view never reads.
**Sites:** S12, S13, S26, S27, S34, S35.

### Pattern S-7 — Swallowed throw leaves a frozen/forever-spinner UI
An unstructured `Task { try await … }` with no `do/catch`; on throw the spinner state is never cleared and the user is stuck with no error.
**Sites:** S14 (DocumentIngestionSheet — `isGenerating` stuck true).

---

## High-priority findings (1)

#### S1 — `JobApplications/AI/Services/JobAppPreprocessor.swift:213` · High · LOG: none · Pattern S-2
> `try? job.context.save()`

After two LLM calls successfully extract `extractedRequirements` and `relevantCardIds` onto the `JobApp`, the SwiftData save is dropped with a bare `try?`; the next line marks the activity tracker `.completed`, so the UI shows a **green/success status while the extracted data is lost on next launch** — and the expensive preprocessing silently re-runs on that job, re-burning tokens. Confirmed by both independent passes.
**Fix (§2):** `do { try job.context.save() } catch { Logger.error(…, category: .storage); SaveFailureToastThrottle.showIfNeeded() }` — the codebase-standard save-failure surface (already used by `SwiftDataStore.saveContext()`).

---

## Medium-priority findings (15)

Each entry: ID · `file:line` · LOG · pattern · impact · fix surface.

#### S2 — `Onboarding/Core/AnthropicHistoryBuilder.swift:116` · LOG: none · S-4
> `let pdfData = try? Data(contentsOf: URL(fileURLWithPath: storagePath))`

On session resume, the `.toolResult`-branch PDF re-inclusion: if the stored file is unreadable the document block is silently omitted from the rebuilt `user` message, so **the LLM continues the interview without the PDF it was originally sent**. No log, no surface. **Fix:** `Task { @MainActor in ToastCenter.shared.show(.error("Your uploaded PDF is no longer accessible — the AI won't see it this session.")) }`.

#### S3 — `Onboarding/Core/AnthropicHistoryBuilder.swift:265` · LOG: none · S-4
> `let pdfData = try? Data(contentsOf: URL(fileURLWithPath: storagePath))`

Same drop in `extractPDFFromUserMessage(_:)` — returns nil, the user-message PDF block is omitted, the LLM resumes blind to the uploaded resume. **Fix:** same toast as S2.

#### S4 — `Onboarding/Services/DocumentProcessingService.swift:267` · LOG: none · S-3
> `if let intermediateRepresentation, let irString = try? intermediateRepresentation.encodedJSONString() { artifactRecord["intermediateRepresentation"].string = irString; artifactRecord["extractedText"].string = intermediateRepresentation.fullText }`

If the IR encode throws, **both** the stored IR and the full-text replacement are dropped — the expensive transcription (tables + vision pass) is lost, `reanalyzeFromIR` later finds no IR and falls back to full re-transcription, and downstream reads raw native PDF text. No `passFailures` entry, no log. (One pass rated this High for the KC-quality risk; set to Med because the data is recoverable at re-transcription cost.) **Fix:** `do { … } catch { passFailures.append("ir-encode: \(error.localizedDescription)") }` — `passFailures` already surfaces to the coordinator/UI.

#### S5 — `Onboarding/Services/ArtifactExporter.swift:95` · LOG: none · S-4
> `let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any], let rawData = metadata["rawData"] as? [String: Any]`

Called on every phase transition (`exportArtifactsForFilesystemBrowsing`): a malformed/absent `rawData` silently breaks the `if-let` chain, `exportGitAnalysis` never runs, no git-analysis file is written, and the outer `do/catch` sees no error — so **the interviewer runs the rest of the interview with no git evidence**, silently producing fewer/lower-quality KCs and skills. **Fix:** restructure to throw on the parse failure so the existing export `catch` surfaces it.

#### S6 — `Onboarding/Views/OnboardingInterviewView.swift:441` (also :444, :448) · LOG: info · S-5
> `_ = await interviewCoordinator.startInterview(resumeExisting: false)`

The `Bool` return is discarded at all three Start/Resume call sites. The specific unlogged `false` path is `InterviewLifecycleService.startLLM`'s `guard let facade = llmFacade else { … return false }`, which logs only `Logger.info`. The view has no error `@State`/alert/toast, so **pressing "Start Interview" / "Resume" does nothing with no explanation.** (Distinct from the prior audit's H10/H11, which were the `.error`-logged `ModelConfigurationError` catches.) **Fix:** local error `@State` + `.alert` driven by the `false` return.

#### S7 — `Resumes/AI/RevisionAgent/RevisionGroundTruth.swift:131` · LOG: none · S-4
> `if let flattened = try? flattenNodeFiles(in: layout.treenodes) { nodesBySlug = flattened } else { nodesBySlug = [:] }`  (and `:137` for snapshots)

If `contentsOfDirectory` throws (workspace corruption), both the workspace and snapshot sets silently become empty; every proposal with a non-empty `beforePreview` then evaluates against an empty set and returns a **false `.mismatch` on every valid change** — pushing the user to reject correct AI proposals mid-revision. **Fix:** `ToastCenter.shared.show(.error(...))` (wrap in `Task { @MainActor in }`) rather than swallowing to `[:]`.

#### S8 — `Shared/Views/ApplicantProfileEditor.swift:207` (also :219) · LOG: none · S-4
> `guard let data = try? Data(contentsOf: url) else { return }`

User picks a profile picture via `NSOpenPanel`; if the file is unreadable the completion block silently returns — no toast/alert/log — leaving the photo unchanged with zero feedback (repeats in `presentPhotoLibraryPicker`). **Fix:** local error `@State` + `.alert`.

#### S9 — `Shared/Utilities/ExportTemplateSelection.swift:49` · LOG: none · S-4
> `if cssPanel.runModal() == .OK, let cssURL = cssPanel.url, let cssContent = try? String(contentsOf: cssURL, encoding: .utf8) {`

The user explicitly selects a CSS file; if it can't be read the combined `if` falls into the "treat cancel as no CSS" else, so **export proceeds with `css: nil` → an unstyled/wrong PDF**, silently. The parallel HTML path (`:34`) correctly throws `ExportTemplateSelectionError.failedToReadFile`. **Fix:** mirror the HTML path — throw, delete the swallow.

#### S10 — `App/Views/Settings/APIKeysSettingsView.swift:90` (also :102, :113; `SetupWizardView.swift:607/612/617`) · LOG: none · S-5
> `_ = APIKeyStore.set(.openRouter, value: trimmed)`

`APIKeyStore.set` returns `false` on a Keychain `SecItem*` non-success, and the `Bool` is discarded at every key-save site. **The UI shows the key as accepted, but it was never persisted** — on next launch every LLM operation fails with "key not configured" and no prior warning. **Fix:** check the return; local error `@State` + `.alert` ("Couldn't save the key to Keychain").

#### S11 — `App/Views/TemplateEditor/TemplateEditorView+Persistence.swift:143` · LOG: none · S-5
> `try? appEnvironment.templateStore.updateManifest(slug: candidateSlug, manifestData: manifest)`

When duplicating a template, if the `modelContext.save()` inside `updateManifest` throws, the manifest (section order, layout, custom-field definitions) is silently dropped — **the duplicate is created with only default settings** and no indication the copy is incomplete. **Fix:** local error `@State` + `.alert`.

#### S12 — `Export/ExportFileService.swift:133` · LOG: debug · S-6 / success-shaped
> `Logger.debug("Warning: Expected \(expectedPages) pages but got \(combinedPDF.pageCount)")` — then `return combinedPDF.dataRepresentation()` regardless

If one of the two source PDFs fails to parse inside `combinePDFs` (`PDFDocument(data:)` nil), the combined packet is written **with fewer pages**, and `exportApplicationPacket` fires its success toast ("Application packet has been exported to…"). The user submits an **incomplete job-application packet** believing it's complete. (Verified: the short data is returned, not nil.) **Fix:** return `nil` on the page-count mismatch so the existing `else { onToast("Failed to combine PDFs…") }` fires.

#### S13 — `CoverLetters/TTS/TTSViewModel.swift:108` · LOG: debug · S-6
> `self.ttsError = error.localizedDescription`

On a TTS failure (API/decode/network) `onError` sets `ttsError` on the `@Observable` model and logs `.debug` — but **`TTSButton` never reads `ttsViewModel.ttsError`** (no `.alert`, `onChange`, or toast), so the "Read Aloud" action silently returns to idle with no explanation. **Fix:** observe `ttsError` → `.alert`/toast in `TTSButton`.

#### S14 — `KnowledgeCardBrowser/Views/DocumentIngestionSheet.swift:102` · LOG: none · S-7
> `try await coordinator.generateSelected(newCards:…, enhancements:…, artifacts:…, skillBank:…, persistSkills:…)`

The wrapping `Task` has no `do/catch`; if `generateSelected` throws (e.g. `StandaloneKCError.llmNotConfigured` when the weak `llmFacade` is nil), the Task dies silently, **`isGenerating` stays `true` and the confirmation view spins forever** with no error/toast/log. **Fix:** wrap in `do/catch` → local error `@State` + `.alert`.

#### S15 — `DataManagers/ExperienceDefaultsStore.swift:21` · LOG: none · S-1
> `try? modelContext.fetch(FetchDescriptor<ExperienceDefaults>()).first`

If the fetch **throws** (migration/corruption), control falls through to insert a blank `ExperienceDefaults` and `saveContext()`; if that save succeeds, **the user's entire work history, education, and skills are silently overwritten with blanks** on disk. (A failing save would only show the generic "Couldn't save your changes" toast — never "couldn't load your data".) **Fix:** explicit `else` on the thrown error → `ToastCenter.shared.show(.error("Couldn't load your experience data — sections may appear empty."))`; don't create-and-save on a fetch *throw*.

#### S16 — `DataManagers/ApplicantProfileStore.swift:27` · LOG: none · S-1
> `try? modelContext.fetch(FetchDescriptor<ApplicantProfile>()).first`

Same pattern: a fetch throw inserts and saves a blank profile with placeholder values (**"John Doe" / "applicant@example.com"**), silently replacing the user's real name, email, phone, and photo in every rendered resume and cover letter. **Fix:** same as S15.

---

## Low-priority findings (24)

Low probability, recoverable, dev-adjacent, or graceful-degradation worth a note. `file:line` · LOG · what's silent. Several are kept (not dropped) per the falsifiability rule, with the reason inline.

| ID | file:line | LOG | Pattern | What's silent / impact |
|----|-----------|-----|:---:|------------------------|
| S17 | `Onboarding/Core/AnthropicHistoryBuilder.swift:175` | none | S-3 | Recorded tool-call args unparseable → `deterministicToolInput` returns `[:]` → `{}` sent in that `tool_use.input` on every history rebuild, no trace. |
| S18 | `Onboarding/Core/InterviewLifecycleService.swift:340` | none | S-3 | `restoreTodoList` decode mismatch → guard `else { return }`; session checklist silently not restored on resume. |
| S19 | `Onboarding/Stores/InterviewTodoStore.swift:223` | none | S-3 | `emitUpdateEvent` encode fail → `.todoListUpdated` never published / not snapshotted. (All-Codable; ~never fails.) |
| S20 | `Onboarding/Services/DocumentProcessingService.swift:459` | none | S-3 | `try? encode(skillsResult)` fails → `record["skills"]` unset → artifact stored with **0 skills**, silent. |
| S21 | `Onboarding/Services/DocumentProcessingService.swift:479` | none | S-3 | Same for `record["narrativeCards"]` → **0 KCs** from that document, silent. |
| S22 | `Onboarding/Services/DocumentProcessingService.swift:619` | none | S-3 | IR re-analysis: `try? encode(skills)` fails → `artifact.skillsJSON` keeps stale/empty value, no log. |
| S23 | `Onboarding/Services/CardMergeAgent/BackgroundMergeAgent.swift:296` | none | S-3 | Merged-card JSON unparseable → card omitted from `index.json` → next merge pass can't see it. |
| S24 | `Onboarding/Services/SessionPersistenceService.swift:443-458` | none | S-3 | Tool-call status decode/re-encode fails → silent `return`; stale status on restore (possible re-exec of completed tool calls). *One pass judged this a non-finding (re-synced on restore) — kept as Low for falsifiability.* |
| S25 | `Onboarding/Tools/Implementations/SubmitForValidationTool.swift:89-100` | none | S-3 | `compactMap` `try? encode(card)` → a `SectionCard`/`PublicationCard` silently dropped from the validation payload the user/LLM review. |
| S26 | `Onboarding/Stores/InterviewDataStore.swift:25` | debug | S-6 | Data-dir creation fail logs only `.debug`; root cause of later opaque "Failed to persist data" is invisible. *Downstream `persist()` failures do surface via `.error` — kept as Low (root-cause diagnosis only).* |
| S27 | `Onboarding/Utilities/OnboardingUploadStorage.swift:39` | debug | S-6 | Uploads-dir creation fail logs only `.debug`; `processFile()` then throws `ToolError` to the LLM, but the dev log can't see the cause. |
| S28 | `Resumes/AI/RevisionAgent/RevisionGroundTruth.swift:213` | none | S-4 | Treenode file read skipped on failure → coherence pass audits an **incomplete resume**, can miss cross-section issues. |
| S29 | `Resumes/AI/RevisionAgent/RevisionGroundTruth.swift:272` | none | S-4 | Skill-bank/card corpus read fails → grounding pass runs with **zero evidence** (only flagged when `wasTruncated`), weakening fabrication detection. |
| S30 | `Shared/AI/Models/Services/LLMConversationStore.swift:20` | none | S-4 | `try? fetch().first` throws → `loadMessages` returns `[]` → conversation treated as brand-new → LLM loses prior context for that session. |
| S31 | `App/SprungApp.swift:417` | none | S-5 | "Try Again on Next Launch": second `try? destroyCurrentStore()` swallowed → user thinks reset is scheduled; store unchanged, no re-alert. |
| S32 | `Discovery/Services/ActivityReportService.swift:173,201,226` | none | S-4 | Coaching-context fetch fails → reports **zero** resumes/cover-letters/activity → AI coaches as if the user has done nothing. *One pass judged this a non-finding (background report) — kept as Low (AI output degraded).* |
| S33 | `Export/ExportFileService.swift:319` | none | S-5 | `guard let jobApp = jobAppStore.selectedApp else { return }` → `exportAllCoverLetters` silent no-op; every other guard here calls `onToast`. |
| S34 | `CoverLetters/Models/CoverLetter.swift:114,160,179` | debug | S-3/S-6 | `assessmentData`/`committeeFeedback`/`generationSources` encode fail logs `.debug` → committee tallies/analysis/"Sources Used" silently not persisted; inspector empty next launch. |
| S35 | `SeedGeneration/Generators/ObjectiveGenerator.swift:196` | info | S-6 | `apply()` logs `.info` and writes nothing (no store injected); currently dead (dispatch routes by `sectionKey`), but if dispatch is corrected to `generatorType` the **approved professional summary silently disappears**. |
| S36 | `DataManagers/KnowledgeCard.swift:319` (+301/359/379/399/424/444/464) | none | S-3 | Enrichment setters (`extractable`, `evidenceAnchors`, `suggestedBullets`, `technologies`, `facts`, `verbatimExcerpts`, `evidenceCardIds`, `outcomes`) `try? encode` with no else → stale LLM-derived metadata silently retained. |
| S37 | `DataManagers/TitleSetStore.swift:70` | none | S-3 | `encodeWords` returns hard-coded `"[]"` on encode fail → a non-empty title-word list silently zeroed in the persisted record. |
| S38 | `Templates/Stores/TemplateStore.swift:90` | none | S-5 | `try? fetch(default templates)` fails → the `forEach` clearing `isDefault` is skipped → multiple `isDefault=true` rows → wrong default after restart. |
| S39 | `DataManagers/CandidateDossierStore.swift:28` | none | S-1 | `(try? fetch())?.first` throws → `dossier` silently nil → `hasDossier` lies → a later `upsertDossier` inserts a blank dossier that shadows the real one. |
| S40 | `DataManagers/EntityStore.swift:43` (+`TitleSetStore.swift:167`) | none | S-1 | `(try? fetch()) ?? []` → fetch fail shows **zero** KCs/skills/writing-samples and can feed an empty KC list into AI generation. *One pass judged non-finding (recovers next call, no create+save) — kept as Low.* |

---

## Recommendations

1. **Fix the two data-loss patterns first.** S-2 (S1, the only High) and S-1 (S15/S16/S39/S40). Both silently overwrite or drop the user's real data. For S-1, the root cause is using `try?` on a bootstrap fetch — a thrown fetch must **not** fall through to create-and-save a blank. Distinguish "empty result" from "fetch error" explicitly.
2. **Standardize the `try? save()` → `SaveFailureToastThrottle` fix (S-2).** S1 is the last fire-and-forget save that doesn't route through the throttle the prior audit established for `SwiftDataStore.saveContext()`. Grep for remaining `try? *.save()` / `try? *.context.save()` and convert them.
3. **Make file-read drops loud (S-4).** Every `try? Data(contentsOf:)` / `try? String(contentsOf:)` that feeds an LLM request, a verification pass, or a UI asset should toast on failure rather than silently omitting the input — S2/S3/S5/S7/S9 directly degrade AI output or a user export.
4. **Catch the encode/decode-blob class as a group (S-3).** S4/S20/S21/S22/S23/S25/S34/S36/S37 are the same shape (`try? encode(...)` inside an `if let`, write-on-success-only). Low probability individually, but the aggregate risk is silent loss of skills/cards/enrichment. A small `encodeOrThrow` helper that appends to `passFailures`/logs `.error` would close them uniformly.
5. **Surface below-threshold catches (S-6).** S12, S13, S26, S27, S34, S35 emit only `.info`/`.debug`. Promote to `.error` (so the release DEBUG-file captures them) and/or wire the existing `@Observable` error property to a view (S13's `ttsError` is set but never read).
6. **Check discarded config-write returns (S-5).** S10 (Keychain key-save) is the user-facing one: a silently-unsaved API key breaks every later LLM call. Check the `Bool` and alert.

---

## Appendix A — Audit coverage

| Module | Primary signal swept | Findings |
|--------|----------------------|:---:|
| A — Onboarding / Core | `try?` file/decode in history rebuild + lifecycle | 5 |
| B — Onboarding / Services | `try? encode` of artifact blobs + git export | 7 |
| C — Onboarding / Handlers·Stores·Views·Tools·Utilities | tool-payload encode + Bool discards + `.debug` catches | 4 |
| D — Resumes (+ ResumeTree) | revision ground-truth file reads | 3 |
| E — Shared (incl. AI/LLM) | picker reads, CSS read, conversation fetch | 3 |
| F — App | Keychain/manifest write Bool discards | 3 |
| G — Discovery + JobApplications | `try? context.save()` + coaching fetches | 2 |
| H — CoverLetters + Export | packet page-mismatch + TTS error state + `.debug` encodes | 4 |
| I — SeedGeneration + KnowledgeCardBrowser | unstructured `Task` throw + dead apply() | 2 |
| J — DataManagers + Templates + Experience | bootstrap fetch + blob-setter encodes | 7 |

---

## Appendix B — Notable non-findings (verified well-handled)

Important-looking silent-shaped sites that were traced and confirmed to surface (or to be genuinely benign) — recorded so the audit is falsifiable:

- **Tool execution** — `ToolExecutor`/`ToolExecutionCoordinator` catches convert to `ToolResult.error()` → `emitToolFailure` → structured `tool_result` the LLM can relay.
- **Cooperative cancellation** — `LLMMessenger` `catch is CancellationError { Logger.verbose }` paths are intentional teardown, cleanly completed via `markStreamCompleted`.
- **`@discardableResult` store mutators with internal save** — `upsertDossier`, `addArtifact` etc. internally route their save through `SaveFailureToastThrottle` (the prior audit's H1 fix); discarding their return value is safe.
- **`llmFacade == nil` guards in browser tabs** — `TitleSetsBrowserTab`, `SkillsBankBrowser`, `KnowledgeCardsBrowserTab` guards are unreachable: the triggering buttons are `.disabled`/not rendered when `llmFacade == nil`.
- **Coaching session views** — `CoachingService.processNextResponse` sets `state = .error(...)` before re-throwing, so the view's `try?` swallow is harmless (the `.error` case renders).
- **Job scraping** — `IndeedJobScrape`/etc. return nil → `NewAppSheetView` logs `.warning` and shows the challenge sheet or `errorMessage`.
- **App launch / migration** — `SprungApp` ModelContainer fallbacks log `.error` and set `launchState = .readOnly(message:)` (rendered by `ContentViewLaunch`).
- **Template manifest decode** — `TemplateManifestDefaults.manifest()` logs `.warning` + `ToastCenter` toast; raw `Template.manifest` is only read where nil is handled.
- **Pure-`Codable` value-type encodes** — `[String:String]`/`[String:Bool]`/`[CoverRef]`/`SearchPreferences`/`DiscoverySettings` `try? encode` cannot realistically fail (no custom throwing encode); flagged only where the encoded payload is large/nested or the drop is high-impact.
- **`DataResetService` fetch `try?`** — empty-array fallback is intentional; the subsequent `try save()` throws and propagates to `ResetSettingsSection` which surfaces it.
- **Best-effort cleanup `try?`** — backup pruning, snapshot-dir removal, Cloudflare cookie cache, uploads cleanup: failure leaves stale files but never loses user-authored data.
- **Recording/replay tooling** — `SessionTapeRecorder`/`TapeStore`/`Replay*` swallows are best-effort by design (dev seam).
- **`InterviewDataStore.list()`** — silent `try?` chains, but the method has zero callers (dead code).
