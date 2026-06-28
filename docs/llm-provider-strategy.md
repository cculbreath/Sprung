# LLM Provider Strategy: Anthropic-Direct vs. OpenRouter (DeepSeek V4 / Gemini 3.5 Flash)

> **Why this doc exists.** We periodically reconsider whether the Anthropic-direct
> onboarding/doc-ingest stack should move onto a unified OpenRouter stack, given that
> cheaper models now match or beat Anthropic's lower tiers on benchmarks at a fraction of
> the price. This records (a) which Claude API features we actually depend on, (b) whether
> each survives OpenRouter's abstraction, and (c) parity on the two concrete cheaper
> targets we care about: **DeepSeek V4** and **Gemini 3.5 Flash**. Decision-support, not a directive.

_Last reviewed: 2026-06-26. **Supersedes the earlier draft of this doc**, which assumed
DeepSeek was text-only; DeepSeek V4 (Apr 2026) is natively multimodal, which removes the
vision/PDF blocker that previously justified Anthropic-direct. Now also covers OpenAI
(GPT-5.6) and other OpenRouter-routable models._

---

## TL;DR

1. **The hard blocker is gone.** The earlier rationale for Anthropic-direct leaned on
   "only Claude (and Gemini) can read the raw PDF natively." That's no longer true:
   **DeepSeek V4** is natively multimodal, and **Gemini 3.5 Flash** does native document
   understanding. Both are reachable via OpenRouter with native PDF passthrough.

2. **Caching parity now exists too.** The doc-ingest economics (transcribe once, read the
   cached prefix at ~0.1×) is no longer Anthropic-only. Gemini 3.5 Flash has context
   caching (cached input $0.15/1M vs $1.50 miss = 90% off); DeepSeek V4 has automatic
   prefix caching. Via OpenRouter you lose *explicit* cache-handle control and rely on
   automatic/implicit caching — a real but soft cost.

3. **The remaining frictions are infrastructure, not capability:**
   - **Determinism/replay test harness** is built on Anthropic wire bytes
     (`.sortedKeys`, `CachePrefixAuditor`, `SessionTapeRecorder`) and would need reworking
     for an OpenRouter/OpenAI SSE shape.
   - **Explicit cache-prefix control** becomes automatic caching (less auditable, but the
     provider handles the economics).
   - **Extraction quality** at the Flash tier must be validated against the
     "KC quality never regresses" bar before trusting it on the locked path.

4. **A new split appears on tool reliability.** Gemini 3.5 Flash has clean native
   function-calling + structured output. **DeepSeek V4 does not**: it intermittently emits
   tool calls as plain text and **rejects `tool_choice="required"`/specific-tool** with a
   400 — which breaks our forced terminal-tool pattern (`complete_analysis`) and strict
   extraction. So DeepSeek V4 is great for the *stateless* services, risky for the
   *agentic* onboarding path.

5. **Recommendation:**
   - **Onboarding / doc-ingest:** your instinct is right — **Gemini 3.5 Flash** is the
     credible cheaper replacement (native PDF, caching, reliable structured output,
     1M context, ~3× cheaper than Opus). Prefer **Gemini *direct*** (we already have
     `GoogleAIService`) if you want to keep explicit caching + Files API + a controllable
     request shape for the replay harness; use **Gemini via OpenRouter** if stack
     unification + model freedom outweigh losing explicit control. Validate Flash-tier
     extraction quality before flipping the default.
   - **OpenAI is the dark horse for the forced-tool path:** GPT-5.6 (Terra/Luna) pairs
     best-in-class strict structured outputs + reliable forced `tool_choice` with explicit
     0.1× caching and native PDF — the one combo DeepSeek V4 lacks. Cheap tiers are preview
     (GA flagship GPT-5.5 = $5/$30); worth A/B-ing against Gemini for doc-ingest.
   - **Stateless OpenRouter services** (Discovery, seed-gen, cover letters, job-app
     preprocessing, skills): deploy **DeepSeek V4** here for the biggest cost win — these
     don't use forced terminal tools, so V4's tool-choice limitation doesn't bite.

---

## Current split

| Path | Provider today | Why |
|---|---|---|
| Onboarding interview, KC/skill extraction, doc/git ingest, card-merge, resume-revision agent | **Anthropic Messages API (direct)** + Google Gemini (direct) | Prompt caching, Files API, strict tool use, native PDF, determinism/replay |
| Discovery / coaching, seed generation, cover letters, job-app preprocessing, skills curation, resume-review reasoning, background processing | **OpenRouter** | Stateless / single-pass, no cache-prefix or Files-API dependency |

We are **already hybrid**, and the OpenRouter services already let you pick any model.
The only thing locked to Anthropic-direct is onboarding/doc-ingest.

---

## Why we originally switched onboarding to Anthropic-direct

Reconstructed from the codebase + overhaul history. Note that #1 (native PDF) is the item
that has since been commoditized:

1. ~~Native PDF + Files API was Claude/Gemini-only~~ — **no longer a differentiator**;
   DeepSeek V4 and Gemini 3.5 Flash both do native documents.
2. **Controllable prompt caching** for the transcribe-once / read-many pipeline —
   `Sprung/Onboarding/Services/AnthropicDocumentAnalysisService.swift`,
   `Sprung/Shared/AI/AnthropicCacheBreakpointPlanner.swift`.
3. **Server-enforced strict tool use** for terminal/structured tools — `complete_analysis`
   in `Sprung/Onboarding/Services/GitAgent/RepositoryDigestTool.swift`.
4. **Determinism + record/replay** on byte-stable Anthropic requests —
   `Sprung/Onboarding/Core/CachePrefixAuditor.swift`,
   `Sprung/Onboarding/Recording/SessionTapeRecorder.swift`.
5. **KC/extraction quality non-negotiable** — the interview reads the raw PDF; Claude's
   extraction/voice quality is the baseline.
6. **Budget pause** keyed to Anthropic's raw `400 "credit balance too low"` —
   `Sprung/Onboarding/Core/BudgetPauseGate.swift` (distinct from OpenRouter's `402`).

Items 2–4 and 6 are the residual lock; they are *infrastructure* coupled to direct access,
not model capabilities.

---

## Feature-by-feature

Legend: ✅ works · ⚠️ works but degraded / not under our control · ❌ unavailable.

| Claude API feature | What we use it for | Via OpenRouter (transport) | DeepSeek V4 | Gemini 3.5 Flash |
|---|---|---|---|---|
| **Native PDF / vision** | Interview reads raw PDF; doc transcription | ✅ native passthrough (or OCR plugin) | ✅ natively multimodal | ✅ native document understanding (50MB/doc) |
| **Controllable prompt caching (`cache_control`, breakpoints, 1h TTL)** | Transcribe-once / read-many at 0.1×; CachePrefixAuditor | ⚠️ passthrough only; byte-prefix is OpenRouter's, not ours | ⚠️ automatic prefix caching, no breakpoint control | ⚠️ has context caching ($0.15/1M cached) but explicit handle not exposed via OpenRouter |
| **Files API (upload once, reference by id)** | sha256 cross-session reuse | ❌ stateless; inline per request | ❌ | ❌ via OpenRouter (Gemini *direct* has its own Files API) |
| **Server-enforced strict tool use** | `complete_analysis`, guaranteed-valid extraction | ⚠️ provider-dependent | ⚠️ has strict mode, **but** see tool-reliability row | ✅ native structured output |
| **Tool-use loop / `tool_choice` (forced terminal tool)** | Git/card-merge/revision agents; forced `complete_analysis` | ⚠️ OpenAI shape; our `AnthropicToolLoopRunner` replaced | ❌ **rejects `tool_choice="required"`/specific (400)**; intermittently emits tool calls as plain text | ✅ reliable function calling + combined tool use |
| **Structured output (json_schema)** | Domain extractions | ✅ for supporting models | ⚠️ improved over V3; ~60% tool-call rate in complex agents | ✅ |
| **Streaming (SSE)** | Interactive turns | ✅ | ✅ | ✅ |
| **Token counting (`count_tokens`)** | Pre-flight estimates | ❌ | ❌ | ❌ via OpenRouter |
| **Usage incl. cache tokens** | Cost telemetry | ⚠️ shape differs; chokepoint rework | ⚠️ | ⚠️ |
| **Extended thinking / reasoning** | Resume-review reasoning | ✅ (already used) | ✅ adjustable reasoning effort | ✅ |
| **Determinism / record-replay harness** | Tests | ⚠️ Anthropic wire bytes → OpenRouter SSE rework | ⚠️ | ⚠️ |
| **Budget pause (raw 400)** | Pause/refill gate | n/a (OpenRouter = 402, handled) | n/a | n/a |

---

## The candidates

### Gemini 3.5 Flash — the cost-cut for the *locked* path
- **Pricing:** $1.50/1M input · $9/1M output; **cached input $0.15/1M** (90% off);
  $1/hr cache storage. 1M context, ~66K output.
- **Capabilities:** native PDF/document, vision, audio, video; **reliable** function
  calling + structured output; context caching.
- **vs Claude:** between Haiku ($1/$5) and Opus ($5/$25). If onboarding runs an Opus/Sonnet
  tier for quality today, Flash is a ~2.7–3× cut **with native PDF retained**.
- **Adoption options:**
  - **Gemini direct** (reuse `GoogleAIService`): keeps explicit context caching + Files
    API + a controllable request shape → lowest-risk for the replay harness. Downside:
    a second bespoke integration to maintain.
  - **Gemini via OpenRouter**: unifies the stack, leans on automatic caching, loses
    explicit control. Downside: replay-harness rework + less predictable cache hits.
- **Caveat:** Flash is a fast/cheap tier — **validate KC extraction quality** against the
  current Claude output before flipping the onboarding default. For the highest-stakes
  passes, Gemini 3.x **Pro** is the quality-matched (costlier) fallback.

### DeepSeek V4 — the cost-floor for the *stateless* services
- **Capabilities:** 1.6T/49B MoE (V4-Pro), 1M context, natively multimodal, strict JSON
  schema mode, OpenAI-compatible API, reasoning-effort control. Cheapest of the three.
- **Blocker for agentic use:** documented non-determinism — tool calls occasionally
  rendered as plain text in `content`, and **`tool_choice="required"`/specific-tool
  returns 400**. Our forced terminal-tool pattern (`complete_analysis`) and strict
  extraction depend on exactly those, so V4 is **not** a safe drop-in for the onboarding
  agents yet.
- **Where it wins now:** Discovery, seed generation, cover letters, job-app preprocessing,
  skills — single-pass / no forced terminal tool. Point the existing OpenRouter picker
  here and measure the savings with zero migration risk.

### OpenAI GPT-5.6 (Terra / Luna) — the best fit for the *forced-tool* path
- **Pricing (GPT-5.6, previewed 2026-06-26):** Sol $5/$30 · Terra $2.50/$15 ·
  **Luna $1/$6**. GA flagship today is GPT-5.5 ($5/$30, ~1.05M context). The cheap 5.6
  tiers are **preview**, not yet GA — factor that into a production decision.
- **Why it matters here:** OpenAI's strict **structured outputs** (100% JSON-schema
  adherence) and reliable forced `tool_choice` are the single thing DeepSeek V4 *can't* do
  — so OpenAI is the natural cheaper home for the agentic onboarding tools
  (`complete_analysis`, card-merge, revision) if we ever move them off Anthropic.
- **Caching caught up:** GPT-5.6 adds **explicit cache breakpoints** with the 90%
  cached-input discount (0.1× reads, 1.25× writes, 30-min min life) — so the earlier
  "only Anthropic/Gemini have controllable 0.1× caching" framing no longer holds.
- **Plus:** native vision + PDF input, ~1M context.
- **vs Gemini 3.5 Flash:** Luna ($1/$6) undercuts Flash ($1.50/$9) *and* brings stronger
  forced-tool reliability — but Flash is GA today and Luna is preview. For doc-ingest
  (which leans on a forced terminal tool), OpenAI is at least as strong a candidate as
  Gemini; pick on GA-readiness + a quality A/B.

## Others on the radar (test, don't adopt blind)

For the **stateless OpenRouter services** (cost-driven, no forced terminal tool), worth
A/B-ing alongside DeepSeek V4 — all cheap and OpenRouter-routable:

- **Grok 4.3** — function calling, structured outputs, 1M context, configurable reasoning;
  strong on document-review workflows.
- **Qwen 3.7 Max** — budget reasoning + structured output; open-weights.
- **Mistral Small 4** — purpose-built for production agents (function calling + JSON mode);
  cheapest tier.
- **GLM-5.1 / Kimi K2.6** — agentic candidates (long context, tool-use reliability).
- **Llama 4 Scout / Maverick** — document-heavy workflows; open weights.

None of these clear the bar for the **forced-tool agentic onboarding path** without
per-model tool-choice + structured-output verification — that path stays Anthropic / OpenAI
/ Gemini until proven otherwise.

---

## The economics, restated

Caching parity now exists across **four** providers, so the comparison is no longer "0.1×
cached reads vs full price":

- Anthropic cache read ≈ 0.1×; **Gemini 3.5 Flash cached input $0.15/1M (≈0.1×)**;
  DeepSeek V4 automatic prefix caching ≈ 0.1×; **OpenAI GPT-5.6 explicit breakpoints,
  0.1× reads / 1.25× writes**.
- The realized cost of our multi-pass extraction is dominated by *cached reads* on any of
  the three. So the relevant cost lever is the **per-tier sticker price of the model doing
  the work**, not the caching mechanism — and Flash undercuts Opus/Sonnet there while
  keeping native PDF.

`★ Insight ─────────────────────────────────────`
- When the earlier "moat" feature (native PDF) gets commoditized, the lock-in collapses to
  the *infrastructure* you built around the old constraint — here, the byte-stable replay
  harness and explicit cache control — not the model capability itself.
- The cheaper a model's headline price, the more its *tool-call reliability* becomes the
  real cost: a 60%-reliable forced tool call means retries, repairs, and fallbacks that
  erase the sticker-price win on exactly the agentic path that needs it.
`─────────────────────────────────────────────────`

---

## Decision framework

1. **Lowest-risk savings, do now:** put **DeepSeek V4** on the stateless OpenRouter
   services. No forced terminal tools there → its tool-choice limitation doesn't bite.
2. **The real onboarding cost cut:** migrate doc-ingest to **Gemini 3.5 Flash**, preferring
   **Gemini direct** to preserve explicit caching + a controllable request shape (and the
   replay harness with minimal rework). Gate the flip on a KC-extraction-quality A/B vs
   current Claude output; keep Gemini 3.x Pro as the quality fallback.
3. **Full OpenRouter unification** (Gemini/DeepSeek via OpenRouter for onboarding too) is
   now *viable* — the capability blockers are gone — but it costs you: reworking the
   determinism/replay harness, delegating cache control to automatic caching, and (for
   DeepSeek) accepting the forced-tool-choice limitation. Do this only if stack
   unification + model freedom are worth those three.
4. **Do not** put DeepSeek V4 on the forced-terminal-tool agents (git ingest
   `complete_analysis`, card-merge, revision) until `tool_choice="required"` and reliable
   `tool_calls` emission are confirmed fixed.

---

## Caveats

- DeepSeek V4 (Apr 2026) and Gemini 3.5 Flash are both **post the assistant's training
  cutoff**; specifics above are from current web sources and should be re-verified against
  the live provider docs at decision time, especially the DeepSeek tool-choice bug status.
- Model ids are intentionally **not pinned** — selection is user-driven via Settings per
  project policy. This doc compares *capabilities*, not specific ids.
- OpenRouter's caching/PDF behavior is an evolving implementation detail; verify the ⚠️
  rows against OpenRouter docs before acting.
