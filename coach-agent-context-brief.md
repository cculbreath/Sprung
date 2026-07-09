# Coach-Agent — Self-Contained Context Brief (for the ultraplan agent)

*You are drafting a **detailed, comprehensive, phased implementation plan** for "coach-agent":
turning Sprung's existing Discovery machinery into a proactive, conversational job-search
coach named **Juniper**. This file is self-contained — assume you cannot read the other
`plans/*.md` docs or `CLAUDE.md`/`Agents.md` (all gitignored). Everything you need to plan
the HOW is here. The decisions below are **SETTLED — do not relitigate them**; plan the
implementation, not the product.*

*Sibling authoritative docs (read if accessible, but this brief embeds their essentials):
`coach-agent-spec.md` (has a "Ratified decisions" block = the contract), `coach-agent-spec-review-2026-07-08.md`
(adversarial review, 6 addenda), `coach-channel-v1-telegram-relay-spec.md` + `-handoff.md`
(the channel — already planned, do NOT replan it), `coach-companion-app-spec.md` (deferred).*

---

## 1. The product in one paragraph

Sprung's application-prep pipeline (résumé customization, cover letters, grounded in
knowledge cards / skill bank / writing samples / a dossier) is already good. The rest of the
machinery should become a **proactive, non-annoying, conversational coach that lives in the
user's texts**, knows their funnel and dossier, and does what a great human career coach
does: diagnose why they're stuck, steer cold→warm, surface the network they don't realize
they have, and meet them where they are — shrinking the ask to one 10-minute step on a bad
week. It is **not** a machine that runs the search; it lowers activation energy so the user
can. **Draft-not-act**: it prepares and proposes; the user decides and sends.

## 2. Ratified decisions (the settled contract — plan around these, do not revisit)

1. **Channel — DONE, do not replan.** Telegram bot + an always-on **relay on a home Debian
   box** (a *separate* repo at `../coach-relay`, pure-stdlib Python, already has its own
   wave-structured handoff ready to build). CloudKit iOS companion deferred until a $99 Apple
   fee is paid — a later channel adapter, out of scope now. The Mac side needs a
   **`CoachChannelAdapter` protocol** + a **`TelegramRelayChannel`** HTTP client that talks to
   the relay's REST API (send / schedule / revoke / drainInbound / heartbeat / capabilities).
   `capabilities.hasReadReceipts = false` (Telegram bots are blind to read receipts).
2. **Identity = Juniper.** The **constitution** is a versioned soul-doc file loaded at runtime
   as the system-prompt prefix. It **templates the user's first name from `ApplicantProfile`**
   (never hardcoded). Runtime prompt = `constitution | synthesized-dossier-view | volatile
   current-state`, assembled **byte-stable** for prompt caching.
3. **Memory = immutable base + append-only overlay + synthesized view.** The extracted
   dossier + knowledge cards + skill bank are **immutable** (extraction quality is a hard
   guarantee — never regress it, never let the model rewrite it). Learned traits/preferences
   live in an **append-only overlay**: one fact per record + provenance + timestamp +
   source-quote, revocable. The runtime "dossier" the prompt sees is a **synthesized view**
   regenerable from base+overlay, re-synthesized in a **nightly batch, never per-message**
   (keeps cache bytes stable). Plus **episodic search history** (every application + its
   outcome-with-reason: submitted / no-response / rejected-after-screen / interviewed-then-passed
   / offer) — barely exists today, is the forcing function for diagnosis. Plus a
   **network map** (contacts surfaced by excavation, tied to opportunities), agent-populated.
   One query interface over all of it.
4. **Cadence = a light DEBOUNCE, NOT a policy "arbiter."** Do NOT build priority tables /
   daily quotas / suppression rules in code (rejected as a straightjacket). Triggers emit
   *candidates* into a short **coalescing buffer**; the only code mechanics are a debounce
   interval, an anti-spam floor, and "never talk over an in-flight reply." Juniper receives
   the buffered candidates **together** and decides which/whether to send — cadence judgment
   lives in the model + dossier, not code. Decay = the model reading stored engagement
   receipts, not a code counter.
5. **Soft budget.** Budget + duration set in Settings; Juniper is told his envelope +
   spend-so-far (via the existing `anthropicUsageObserver` cost telemetry) and budgets in
   real time. The hard API-balance error (existing `BudgetPauseGate`) is only a backstop.
   **Never silently downgrade to a cheaper model.**
6. **Per-task-category model picker in Settings.** Each coach task category (coalescing
   decision / diagnosis / drafting / …) gets its own **user-configured** model — consistent
   with the house rule that all model selection is user-driven. Never an automatic downgrade.
7. **Cost machinery plumbed from day one.** Route every coach turn through the existing
   **tape record/replay seam** from the start (enables a scenario-battery for prompt
   refinement + character eval). Prompt builder is **cache-aware** (stable prefix per #2).
   Use the Anthropic **Batch API** (50% off) for async work only — nightly re-synthesis,
   scenario replays, outcome analysis — never live turns.
8. **Diagnosis = minimum-datapoints HARD gate.** This is the ONE place a hard code gate is
   sanctioned (everywhere else is light-touch per #4): a minimum-N gate governs **long-term
   assessments** (the "why aren't you getting hired" diagnostic altitude), because LLMs
   narrate small-sample noise as signal. **Compute the sample stats in code and hand them to
   Juniper as facts** (he must not do the arithmetic); whether/how to raise a leak is his
   call, with delicacy enforced by the constitution.
9. **UI = a new dedicated Juniper module (consolidate-and-densify).** NOT an extension of the
   Résumé Customizer (it's out of UI real-estate). Fold the scattered, low-density Discovery
   dashboards into one module. **Chat is the hero**; alongside it a **dense state / plan /
   progress + drafts-to-approve** view (the draft-not-act review surface) + reference surfaces
   (leads / contacts / calendar). The Pipeline hub survives as its own separate module.
   Reuse the existing `ModuleContentView` top-tab pattern (same as the Résumé Customizer / KC
   Browser). Emphasis: fewer, denser, higher-information views — not more sparse tabs.
10. **Autonomy ceiling = draft-not-act, recipient-scoped.** Autonomous sends **to the
    principal (the user)** are the product; anything addressed to a **third party** (an
    outreach message, a job application) is **draft-only**, review-then-send. Never auto-submit.
11. **Grounding fixes.** There is no `notificationFatiguePauseOffered`/`notificationsPausedAt`
    anymore (deleted) → **build fresh decay state**, don't "resurrect." Define the great-fit
    trigger against **Scout's dimensioned enum signal** (there is no scalar "≥ threshold").
    The scheduler host is the **relay**, not the Mac.

## 3. Codebase grounding (verified this session — map work to these real files)

**Exists and is reusable / extendable:**
- **Existing coaching subsystem** (this is what you extend): `Sprung/Discovery/` —
  `Services/CoachingService.swift`, `Services/CoachingContextBuilder.swift`,
  `Services/CoachingToolHandler.swift`, `Stores/CoachingSessionStore.swift`,
  `Models/CoachingModels.swift`, `Tools/Schemas/CoachingToolSchemas.swift`,
  `Services/DiscoveryCoordinator.swift`, `Services/DailyTaskGenerator.swift`.
- **Tape / replay seam**: `Sprung/Onboarding/Recording/` — `SessionTapeRecorder.swift`,
  `TapeStore.swift`, `TapeEvent.swift`, `ReplayAnthropicService.swift`,
  `ReplayToolGateway.swift`, `SessionReplayService.swift`.
- **SwiftData model registry**: `Sprung/DataManagers/SchemaVersioning.swift` (this is where
  `SprungSchema.models` lives — new `@Model`s register here).
- **Settings**: `Sprung/App/Views/Settings/ModelsSettingsView.swift` (model pickers),
  `SettingsView.swift`, `App/AppState+Settings.swift` (@AppStorage keys).
- **DI wiring**: `Sprung/App/AppDependencies.swift` (register stores/services, inject via
  `@Environment`).
- **Prompt/context builders + caching**: `Sprung/SeedGeneration/Services/PromptCacheService.swift`
  (reference for byte-stable cache prefix), `Discovery/Services/CoachingContextBuilder.swift`,
  `Templates/Utilities/ResumeContextBuilder.swift`.
- **Shared Anthropic tool loop**: `AnthropicToolLoopRunner` (the coach composes tools on
  this — same runner Discovery/import already use).
- **Also reusable**: Scout (+ taste profile + outcome feedback), RevisionAgent / packet-prep,
  LinkedIn MCP, `CNContactStore` (Contacts permission already held from onboarding),
  `BudgetPauseGate`, `anthropicUsageObserver` (cost telemetry), the `JobApp` pipeline +
  date-stamped stage transitions.

**Greenfield (do not exist yet — you are designing them):** any `Dossier` first-class model
(there is none today), `CoachChannelAdapter`, `TelegramRelayChannel`, anything "Juniper",
the memory overlay entities, the constitution loader, the debounce/coalesce runtime, the
episodic-outcome model, the network-map model, the Juniper UI module.

**Missing primitive:** there are **zero scheduler/notification primitives** in the app today;
`autoRun*` fires only on app-open (`DiscoveryCoordinator` ~lines 202/204). The proactive
runtime now lives in the **relay** (already planned), not the Mac — the Mac side is the
brain + a heartbeat + drain-inbound loop against the relay.

## 4. Architecture shape

**4 pillars:** Constitution (character / soul-doc) · Memory (brain) · Tools (hands) ·
Scheduling/cadence (heartbeat, now debounce-governed). **3 layers:** Mac app = workspace ·
texts = the coach · memory/dossier = the spine. **3 altitudes:** Tactical (unstick, one
10-min step, intervention scales inversely with momentum) · Strategic (cold→warm networking
engine: excavate the invisible network, graded warmth×effort menu, warm-path-first, nurture-
not-nag, anxiety-aware as a learned dial) · Diagnostic (why-not-hired = funnel-leak × dossier
pitfalls; gated per Decision 8).

**Tools to build (new), on `AnthropicToolLoopRunner`:** `start_packet(jobId)`,
`draft_message(contactId, purpose)`, `log_contact` + `link_contact_to_opportunity`,
`find_warm_path(jobId)`, `excavate_network(category)`, `advance_stage(jobId, status)`,
`record_outcome(jobId, outcome, reason)`, `deep_link(jobId, tab, docId)`,
`send_message(channel, text)` (via the relay; draft-and-notify, never auto-submits).

## 5. Proposed build phasing + the gating reality

Spec's phase order: **(1) Foundations** — constitution file + memory schema (incl. episodic
outcomes) + the Mac channel adapter + settings additions + tape/cost plumbing. **(2) Channel**
— DONE (relay handoff ready). **(3) Conversational coach** — tactical altitude first (unstick,
sized nudges) + debounce + decay on the real channel. **(4) Excavation + warm strategy.**
**(5) Funnel diagnosis** — after episodic data accrues. **(6) Seams as tools** — the
Discovery↔Customizer integration seams (card-hub deep-links, lead→packet, submit→advance,
people↔opportunity, events↔opportunity) become coach tools.

**GATING (critical for sequencing):** the coach *runtime* and *UI* edit the existing
`Discovery/` subsystem and the module shell — the same files a parked "D-Strat" integration
effort and a just-completed UX-consistency refactor also touch. So: **Foundations is largely
un-gated** (mostly new files + additive edits to `SchemaVersioning`/`AppDependencies`/
`ModelsSettingsView`), but the **conversational runtime + Juniper UI are gated** behind that
contended zone settling. Your plan should front-load the un-gated Foundations and flag the
gated phases.

## 6. Why a naive parallel handoff isn't possible yet (design this in)

coach-agent is **ratified on decisions but not specified to the file/type level**. Before any
parallel `/tackle` handoff can assign disjoint files, the plan needs a **Foundations design
pass** that pins concrete contracts (like the relay spec did): the memory-overlay + episodic
+ network-map SwiftData entities and their `SprungSchema` registration; the
`CoachChannelAdapter` protocol signatures + `TelegramRelayChannel` against the relay's REST
contract; the constitution file format + loader + exactly where it assembles into the cached
prompt prefix (respecting cache byte-stability); the new Settings keys (per-task models +
soft budget). **Make this design pass the plan's first deliverable.** Later phases
(conversational runtime, networking excavation, diagnosis, Juniper UI) each need their own
file-level design before they're tackle-able — treat them as design-then-build, not
build-now.

## 7. Binding house rules (this repo — honor them in every step of the plan)

- **No hardcoded model IDs, no fallbacks.** `@AppStorage` model keys default to `""`; on
  missing config, throw `ModelConfigurationError` and surface the picker — never substitute a
  model. All model choice is user-driven (pickers populated from provider APIs).
- **Extraction quality never regresses.** Do not touch the dossier/KC/skill-bank extraction
  pipeline; the memory overlay wraps it, never mutates it.
- **No formula bullets / fabricated metrics / buzzwords / corporate-speak** in any generated
  content — Juniper's drafts meet the packet-prep engine's bar. (No "[verb] resulting in X%".)
- **Clean breaks over backwards compatibility** — no shims/adapters/legacy paths/deprecated
  code; complete transitions, delete the old.
- **JSON:** camelCase for keys we control (match Swift property names, no CodingKeys);
  snake_case only via explicit CodingKeys for external API envelopes; never blanket
  `convertFromSnakeCase`. Anthropic request serialization uses `.sortedKeys` (cache-load-bearing).
- **Prompt caching:** byte-stable prefix, ≤4 cache breakpoints; the constitution + synthesized
  dossier must not churn mid-session (hence nightly batch re-synthesis).
- **SwiftData:** `@Model` in domain location + an `@Observable @MainActor` Store in
  `DataManagers/`; register in `SprungSchema.models`; instantiate in `AppDependencies`; inject
  via `@Environment`. Suffix taxonomy is strict (`Service`/`Store`/`State`/`Coordinator`/
  `Handler`/…; "Manager" is banned).
- **Determinism:** any id minted by a replay-re-executable tool routes through
  `DeterminismIDProvider.nextUUID()`, never raw `UUID()`.
- **Platform:** macOS (not iOS); no `#Preview`; `@MainActor` for UI-facing state/most stores.
- **Testing:** `SprungTests` (app-hosted, in-memory store). Subclass `InMemoryStoreCase`;
  use `TestDefaults` (never `UserDefaults.standard`); do NOT construct/fake `LLMFacade` —
  test pure request-build/response-parse halves + cover streaming via the tape record/replay
  seam. Keep the fork's `AnthropicRequestSerializationTests` green.
- **Commits:** no AI attribution, no `Claude-Session` trailer; work on `main`.

## 8. The failure mode to design against (from the adversarial review)

The most likely way this dies is **not** a crash — it's a coach that works in week 1, gets
budget-paused or sleep-killed **silently** in week 2, reappears awkwardly in week 3, and is
ignored by week 4. **Reliability earns the right to interrupt.** Everything defensive in the
decisions serves this: the soft budget with *communicated* pauses (not silent modal death),
the relay's dead-man switch, the debounce (a nag that isn't landing must not keep firing at
volume), and the tape-based character eval so constitution edits don't blindly ship a naggy
coach against the user's own patience. Bake these in from the start, not as polish.
