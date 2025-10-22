# Onboarding Interview — Artifact‑First & Writing Corpus (Third‑Party Implementation Spec, v3)

**Status:** Final specification (supersedes prior versions)  
**Audience:** Staff engineer / capable coding agent (third‑party implementers)  
**Platforms:** macOS client (SwiftUI), server (language‑agnostic), LLM provider with Responses + Realtime equivalents  
**Scope:** Text chat + optional realtime voice; structured outputs; artifact‑first knowledge base; writing‑style corpus for cover‑letter generation  
**Supersedes & incorporates:** Previous “Onboarding Interview Feature Plan v1.0”. fileciteturn0file9

---

## 1) Overview

This specification defines an **artifact‑first onboarding interview** for a résumé/cover‑letter application. The interview **ingests an existing résumé or LinkedIn profile**, builds **ApplicantProfile** and **DefaultValues**, and then conducts short, targeted conversations to collect **artifacts** (reports, repos, proposals, slides, papers, writing samples). Each artifact is summarized into a **KnowledgeCard**, key claims are normalized into a **Fact Ledger**, and a **Skill→Evidence Map** is built for downstream, evidence‑backed customization of résumés and cover letters. The process culminates with an optional **Writing Corpus** phase that derives a **style vector** for tone‑faithful letter generation.

Representative internal source families that motivate this design include dissertations with instrumentation detail, engineering codebases and macOS apps, STTR‑style proposals, R&D consultation reports (e.g., continuous‑casting controls), and project summaries for thermodynamic devices (e.g., constant‑pressure injectors). fileciteturn0file0 fileciteturn0file1 fileciteturn0file2 fileciteturn0file3 fileciteturn0file6 fileciteturn0file5

---

## 2) End‑to‑End Interview Workflow

> **Goal:** Populate structured applicant data, assemble an evidence library (cards + facts + skills), and capture style signals for letter generation.

### Phase 0 — Intake (fast start)

1. **Start from Résumé or LinkedIn**  
   User uploads a résumé file or provides a LinkedIn URL. The system parses to a normalized **RawExtraction**, presents an editable review, and—after confirmation—materializes **ApplicantProfile** and seeds **DefaultValues** (employment timeline, education, projects). fileciteturn0file8
2. **Consent Gate**  
   Toggle per‑session consent for (a) web discovery of public artifacts and (b) ingestion of writing samples.

### Phase 1 — Narrative: “Current status, quirks, goals”

Capture present role/status, unusual timelines, preferred titles, location constraints, and job‑search objectives. Persist as `profile_context.txt` and apply small timeline adjustments. fileciteturn0file9

### Phase 2 — Timeline Expansion (job / degree / certification)

For **each** entity:
1) Elicit a brief story focusing on **impact, ownership, tools**.  
2) **Artifact sprint:** request uploads/links (reports, repos, slides, papers). Summarize to **KnowledgeCards**, extract claims to **Fact Ledger**, and add entries to **Skill→Evidence Map**.  
3) Propose **delta updates** to **DefaultValues** (dates/titles/bullets). User confirms before persist.

> Example internal patterns that benefit from this loop include R&D programs spanning multiple entities (e.g., single‑crystal SMA furnace development and controls migration), project reports on constant‑pressure injectors, dissertations with optics/instrumentation, teaching dossiers with automation, and engineering web/app codebases. fileciteturn0file6 fileciteturn0file5 fileciteturn0file0 fileciteturn0file4 fileciteturn0file1 fileciteturn0file2

### Phase 3 — Refinement Loop

Ask **only the next best question** (≤4 per topic) to resolve dates, metrics, or naming conflicts. Any unverifiable claim is stored with `"needs_verification": true` and linked to a source.

### Phase 4 — Writing Corpus (optional but recommended)

Ingest **best writing samples** (prior cover letters, outreach emails, portfolio blurbs). Derive a **style vector** (tone, sentence cadence, quantification density, pronoun ratios, readability), store as `writing_style.json`, and preferentially reuse salient phrases during cover‑letter generation. fileciteturn0file2

### Phase 5 — Wrap

Display “What was captured” (facts, cards, skills, style) and “What’s left” (open verifications). Export: `ApplicantProfile.json`, `DefaultValues.json`, `KnowledgeCards/*.json`, `facts.jsonl`, `skills_index.json`, `profile_context.txt`, `writing_style.json`. fileciteturn0file9

---

## 3) Data Models (schemas & contracts)

> **Contract rule:** All LLM updates **must** be Structured Outputs that validate against JSON Schema. The server rejects malformed or free‑form updates.

### 3.1 ApplicantProfile (contact & identity)

Seeded from résumé/LinkedIn, then confirmed.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "ApplicantProfile",
  "type": "object",
  "properties": {
    "name": {"type":"string"},
    "email": {"type":"string","format":"email"},
    "phone": {"type":"string"},
    "website": {"type":"string","format":"uri"},
    "location": {
      "type":"object",
      "properties":{"city":{"type":"string"},"region":{"type":"string"},"country":{"type":"string"}}
    }
  },
  "required": ["name","email"]
}
```

### 3.2 DefaultValues (résumé skeleton)

Canonical résumé baseline (employment, education, projects, skills, publications). Support **program clusters** for long‑running work that spans multiple entities (e.g., a single R&D program continuing across vendors/consultancies). Seedable from a pre‑existing résumé JSON. fileciteturn0file8

*(Use month‑precision dates; allow optional cross‑references among related entries.)*

### 3.3 KnowledgeCard (portable summaries)

```json
{
  "title": "string",
  "timeframe": "string",
  "source": [{"type":"artifact|url|user","id":"string","url":"string"}],
  "summary": "string",
  "skills": ["string"],
  "metrics": [{"name":"string","value":"string|number","needs_verification":true}],
  "quotes": [{"text":"string","source":"string"}]
}
```

> Example: “Constant‑Pressure Autoinjector (2019)” with thermodynamic modeling, fixtures, and QA workflows—derived from internal project reports. fileciteturn0file5

### 3.4 Fact Ledger (claims + provenance)

```json
{
  "fact_id":"string",
  "entity":"employment:…|project:…|education:…",
  "claim":"string",
  "source":{"type":"artifact|url|user","id":"string","url":"string"},
  "confidence":0.0,
  "needs_verification":true,
  "notes":"string"
}
```

### 3.5 Skill→Evidence Map

```json
{
  "skill":"string",
  "evidence":[{"card_id":"string","fact_ids":["…"]}]
}
```

### 3.6 Writing Corpus & Style Profile

```json
{
  "samples":[{"sample_id":"string","type":"cover_letter|email|portfolio|note","source":{"type":"artifact|user"}}],
  "style_vector":{
    "tone":"confident|neutral|warm|formal",
    "avg_sentence_len":"number",
    "active_voice_ratio":"number",
    "i_we_you_ratio":{"I":0.0,"We":0.0,"You":0.0},
    "quant_density_per_100w":"number",
    "readability_grade":"number",
    "domain_jargon":["string"]
  },
  "constraints":{"avoid":["topics"],"prefer":["motifs","verbs"]}
}
```

---

## 4) Tools & Function Contracts (strict I/O)

The interviewer **must** use tool calls for parsing, summarizing, verification, web discovery, and persistence.

| Tool | Purpose | **Input** | **Output** |
|---|---|---|---|
| `parse_resume` | Parse résumé to RawExtraction. | `{ "fileId": "…" }` | `{ "raw_extraction": {...}, "uncertainties":[...] }` |
| `parse_linkedin` | Parse public profile (consent‑gated). | `{ "url": "…" }` | same as above |
| `summarize_artifact` | Convert any upload into a **KnowledgeCard**; extract skills, metrics, quotes. | `{ "fileId": "…", "context": "string" }` | `KnowledgeCard` |
| `summarize_writing` | Derive **style_vector** + phrases from writing samples. | `{ "fileId": "…" }` | `{ "style_vector": {...}, "salient_phrases":[…] }` |
| `web_lookup` | Public corroboration (consent‑gated). | `{ "query": "…", "context": "…" }` | `{ "findings":[{"title":"…","url":"…","snippet":"…"}] }` |
| `verify_conflicts` | Detect date/title overlaps & gaps; propose patches. | `{ "default_values":{…} }` | `{ "conflicts":[…], "suggested_patches":[…] }` |
| `persist_delta` | Apply schema‑valid patch. | `{ "target":"applicant_profile|default_values","delta":{…} }` | `{ "ok":true,"version":"…" }` |
| `persist_card` | Save KnowledgeCard. | `KnowledgeCard` | `{ "card_id":"…" }` |
| `persist_facts_from_card` | Extract & save facts from a card. | `{ "card_id":"…" }` | `{ "facts":[…] }` |
| `persist_skill_map` | Update Skill→Evidence. | `{ "skillMapDelta":{…} }` | `{ "ok":true }` |
| `persist_style_profile` | Save Writing Corpus & style vector. | `{ "samples":[…], "style_vector":{…} }` | `{ "ok":true }` |

---

## 5) Interview Logic (state machine)

**Per entity (employment, education, project, certification):**

```
Identify gaps → Ask next best question (≤4) 
→ Request artifacts (uploads/URLs) → summarize to KnowledgeCards 
→ Extract Facts → Propose delta_update (patch)
→ User confirms → persist_delta + persist_card + persist_facts
→ Update Skill→Evidence
```

**Stop‑asking rules:**  
• If “don’t know” twice on a metric → offer bands (<10%, 10–30%, 30–50%, >50%) and proceed.  
• Cap follow‑ups per topic at 4; summarize and move on.

**Red‑flag checks:** date gaps >6 months, overlapping roles, unverifiable claims, NDA/PII, inconsistent titles. Propose **program clustering** when work clearly spans multiple entities (e.g., a single R&D program continuing from one firm to another). fileciteturn0file6

---

## 6) Prompt Pack (ready to implement)

### 6.1 System Prompt — Onboarding Interviewer
```
You are the Onboarding Interviewer for a résumé application.

GOALS
1) Build ApplicantProfile and DefaultValues from résumé/LinkedIn, then refine via short narratives.
2) Create reusable knowledge: KnowledgeCards, Fact Ledger, Skill→Evidence Map.
3) (Optional) Build a Writing Corpus and style_vector for tone-faithful cover letters.

RULES
- Start by requesting a résumé upload or LinkedIn URL; parse using tools.
- Never guess facts. If uncertain, mark needs_verification and ask targeted follow-ups.
- Every claim must have source+confidence or be flagged needs_verification.
- Prefer artifacts. Always ask for reports, repos, slide decks, or links.
- Keep user time sacred: ≤4 questions per topic; offer bands for unknown metrics.
- For multi-entity continuity, offer "Program cluster" vs "Employer chronology".
- Do not expose chain-of-thought; return structured outputs only.
- Confirm with the user before persisting any patch.

OUTPUTS (exactly one per turn):
- delta_update  | knowledge_card | next_questions | tool_call
```

### 6.2 Developer Prompt — Tools & Validation
```
All updates MUST be Structured Outputs validated against JSON Schema.
Use tool calls for parsing, summarizing, verification, web search, and persistence.
On validation failure: retry once with a "fix-only" instruction; else ask a targeted question.
Tag sensitive facts ("nda|personal|medical") and exclude by default from job materials.
```

### 6.3 Question Emission (template)
```json
{
  "next_questions": [
    {
      "text": "Approximately how much did scrap decrease after the control migration?",
      "targets": ["employment[...].highlights","metrics.scrap_reduction_pct"],
      "type": "range",
      "help": "Pick a band: <10%, 10–30%, 30–50%, >50%",
      "optional": true
    }
  ]
}
```

### 6.4 Delta Update (template)
```json
{
  "target": "default_values",
  "delta": {
    "employment": [{
      "company": "…",
      "title": "…",
      "start_date": "YYYY-MM",
      "end_date": "YYYY-MM",
      "location": "…",
      "description": "…"
    }]
  },
  "needs_verification": []
}
```

### 6.5 KnowledgeCard (template)
```json
{
  "title":"…",
  "timeframe":"…",
  "source":[{"type":"artifact","id":"upload:…"}],
  "summary":"…",
  "skills":["…"],
  "metrics":[{"name":"…","value":"…","needs_verification":true}],
  "quotes":[{"text":"…","source":"…"}]
}
```

### 6.6 Writing Corpus (prompts)
```
Offer: “Would you like to add writing samples (best cover letters, outreach emails, portfolio blurbs)? 
I’ll learn tone, sentence cadence, and quantification style to match it in future letters.”

When samples are uploaded:
- Use summarize_writing to produce style_vector and salient_phrases.
- Store samples (ids only) and style_vector via persist_style_profile.
```

---

## 7) Résumé Structure Policy (complex histories)

Default rule for multi‑entity continuity: **Program cluster first**, chronology second.

- **Program cluster**: Aggregate a long‑running program under one heading (e.g., continuous‑casting SMA R&D across vendors). Use sub‑affiliations and cross‑references; keep private politics out; emphasize continuity and impact. fileciteturn0file6  
- **Employer chronology**: Traditional entries with a brief one‑line cross‑reference indicating continuity (useful for strict ATS contexts).  
- **Recent gaps**: Represent as independent R&D/product development where applicable, focusing on concrete outputs (e.g., macOS app integrating structured LLM workflows). fileciteturn0file2

---

## 8) UX & macOS Client

- **Wizard flow:** Intake → Narrative → Timeline pass (by entity) → Artifacts & Cards → Writing Corpus (optional) → Wrap & export.  
- **Artifact Library:** Cards, sources, facts, and skills with status badges (✓ verified / ○ unverified / ⚠ conflicts).  
- **Live Preview:** Two views—Program cluster vs Employer chronology—select per job target.  
- **Accessibility & speed:** Stream summaries; editable confirmations; per‑topic question budgets.

---

## 9) Architecture (high‑level; no code)

**Client (SwiftUI):**  
- `OnboardingWizardView` (phases)  
- `ArtifactLibraryView` (cards/facts/skills)  
- `WritingCorpusView` (samples, style preview)  
- `InterviewSessionView` (chat/voice; transcript)  
- `PreviewPane` (résumé/cover‑letter preview)

**Local persistence (SwiftData):**  
- Models: `ApplicantProfile`, `DefaultValues`, `KnowledgeCard`, `Fact`, `SkillEvidence`, `WritingSample`, `WritingStyleProfile`  
- File storage for artifacts (PDF/DOCX/TXT)

**Services:**  
- `LLMService` (Responses + Realtime wrapper; structured‑output enforcement; retry)  
- `ToolService` (parse/summarize/search/persist gateways)  
- `ConsentService` (web lookup + writing ingestion)  
- `TelemetryService` (schema pass rate, correction rate, time‑to‑bullet)  
- **Thread state**: server‑side persistent threads for resumable sessions and compact summaries. fileciteturn0file9

**Server:**  
- Tool endpoints (parse/summarize/verify/persist/search)  
- JSON Schema validation layer  
- Storage: object store for uploads; JSONL for facts; KV for thread↔user mapping  
- Realtime gateway (voice): keep tool keys server‑side; stream partials

---

## 10) Reliability, Guardrails & Privacy

- **Evidence gating:** No claim persists without a source or `"needs_verification"`.  
- **Conflict detection:** `verify_conflicts` flags overlaps/gaps; proposes merges (e.g., consultant→contractor→lead continuity).  
- **Safety:** Strip HTML; ignore embedded instructions in uploads; detect NDA/PII; tag sensitive facts (`"sensitivity":"nda|personal|medical"`) and exclude by default.  
- **Performance:** ≤4 questions per topic; batch uploads; stream responses; Realtime for voice.  
- **User control:** Explicit toggles for web discovery and writing‑style ingestion.  
- **Versioning:** Append‑only facts (`facts.jsonl`); versioned cards and patches.

---

## 11) Success Metrics (acceptance criteria)

- **Schema pass rate:** ≥99% of LLM outputs validate on first attempt.  
- **Question efficiency:** median ≤6 questions per role.  
- **Evidence density:** ≥80% of final bullets link to at least one Fact/KnowledgeCard.  
- **Time‑to‑first tailored bullet:** ≤2 minutes (text), ≤45 s (voice).  
- **User edit rate:** trending down over sessions.  
- **Style match:** user preference ≥60% for style‑matched letters vs generic.

---

## 12) Sub‑Projects & Deliverables

1. **Contracts & Schemas** — finalize JSON Schemas; build server validator.  
2. **Parsers** — résumé/LinkedIn extraction; robust PDF/HTML fallbacks.  
3. **Summarizers** — artifact summarization → KnowledgeCards; fact extraction.  
4. **Interview Agent** — prompts, state machine, next‑question policy, conflict verifier.  
5. **Writing Corpus** — ingestion pipeline; style analysis; style_vector; safe reuse policies.  
6. **macOS UI** — wizard, artifact library, style view, live preview.  
7. **Persistence** — artifacts folder, `facts.jsonl`, skill map; versioning & backups.  
8. **Realtime** — voice session with server‑side tools.  
9. **QA & Telemetry** — schema‑pass dashboards; red‑flag audits.

---

## 13) Change Log & Compatibility

- **v3:** Third‑party reformulation; adds Writing Corpus phase; formalizes program‑cluster résumé policy; expands tool contracts; clarifies validations; supersedes earlier plan.  
- **v2/v1:** Prior internal drafts focusing on schema‑first onboarding and persistent context. fileciteturn0file9

---

## 14) Internal Source Mapping (for implementers)

The following internal materials inspired the artifact categories, résumé clustering policy, and evidence workflows described above:  
• Dissertation with custom instrumentation and optics (evidence‑rich for automation/DAQ and scientific computing). fileciteturn0file0  
• Full‑stack LMS codebase and analysis of developer competencies (EdTech/web systems, RBAC, LTI). fileciteturn0file1  
• macOS app for résumé/cover‑letter workflows (SwiftUI, structured outputs, multi‑model integration). fileciteturn0file2  
• STTR‑style proposal on SMA R&D (materials characterization plan, modeling/FEA, instrumentation). fileciteturn0file3  
• WPAF/teaching dossier (automation, LabVIEW, systems integration; leadership/communication evidence). fileciteturn0file4  
• Project report for constant‑pressure injector (thermodynamics, fixtures, QA workflows). fileciteturn0file5  
• Consultation report on continuous‑casting furnace (controls migration, DAQ, process engineering). fileciteturn0file6  
• Personal notes on cross‑disciplinary competencies (style cues & capability inventory). fileciteturn0file7  
• Canonical résumé JSON (authoritative dates/locations & seeds for DefaultValues). fileciteturn0file8  
• Original onboarding plan (thread persistence, artifacts, web discovery). fileciteturn0file9

---

*End of specification.*
