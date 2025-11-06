# Onboarding Interview Workflow — Updated Spec (vNext)

Status: Draft update to align scope and tooling with current implementation.
Date: 2025-11-06

This update narrows scope, simplifies the tool surface, strengthens user-validation guarantees, and restores the richer narrative flow and process detail from the original sketch.

- Removed: Writing Style Profile (analysis/profiling)
- Removed: Document extraction "return_types" contract (extractor now returns only enriched text + artifact)
- Removed: Sub-agents (single orchestrator + tools only)
- Unified: Upload flows (file or URL) under one `get_user_upload` tool with `allow_url`
- Derivation policy: Any profile/timeline derived from extraction must be shown for user confirmation/editing before persistence
- Dossier scope: Dossier questions appear throughout all three phases (P1–P3) and are always confirmed in-line
- Writing samples: Preserve full original manuscripts; no summaries, no style assessment

## Overview

The Onboarding Interview collects verified, structured data via a conversational, tool-assisted flow:

- Phase 1 (Structure): ApplicantProfile basics + SkeletonTimeline + Enabled Sections (+ a small number of dossier prompts)
- Phase 2 (Substance): Evidence-backed Knowledge Cards (+ opportunistic dossier updates as context arises)
- Phase 3 (Context): Writing Samples (preserve full text) and Candidate Dossier finalization (no style profiling)

Core data adopts the JSON Resume schema (with conservative custom fields under `meta` or `x-*`).

## Deliverables

- User-validated ApplicantProfile (JSON Resume basics)
- Completed SkeletonTimeline (no highlights/summary in P1)
- Enabled Sections for resume editor (user-approved)
- Knowledge Cards library (evidence-backed; quotes + optional artifact SHA)
- Candidate Dossier (concise, user-confirmed narrative/context, populated across P1–P3)
- Corpus of Writing Samples (optional, consented; store full manuscripts verbatim)

## Persistent Storage (App-local)

- `applicant_profile` (JSON)
- `skeleton_timeline` (JSON)
- `enabled_sections` (Set<String>) — represented in seed/defaults
- `artifact_record` (JSON) — enriched text + metadata
- `knowledge_card` (JSON)
- `writing_sample` (JSON)
- `candidate_dossier` (JSON)

Removed: `writing_style_profile` (nixed)

## Architecture

- Single Orchestrator LLM + tool calls
- Event bus + single state coordinator (objectives, artifacts, wizard)
- Tool gating during waiting states (selection/upload/validation/extraction)
- Tool pane provides UI continuations; LLM resumes only after user action

Removed: Sub-agents (artifact ingestion, code ingestion, style profile). Future consideration only.

## Tools (vNext)

- `get_user_option`
  - Present multiple-choice prompt; returns selected option ids

- `get_user_upload` (unified)
  - Parameters: `upload_type`, `title?`, `prompt_to_user`, `allowed_types[]?`, `allow_multiple?`, `allow_url?`, `target_key?`, `cancel_message?`
  - Supports file picker and URL input when `allow_url=true`
  - Use `target_key` for specialized routes (e.g., `"basics.image"` to update profile photo)
  - Typical `upload_type` values: `resume`, `writingSample`, `artifact`, `coverletter`, `portfolio`, `transcript`, `certificate`, `linkedIn`, `generic`

- `extract_document`
  - Input: `file_url`, optional `purpose`, optional `timeout_seconds`
  - Output: enriched Markdown text stored in an `artifact_record` with metadata (no derived profile/timeline in this step)
  - Writing samples: store full text in `artifact_record.extracted_content`; do not summarize or style-assess
  - Note: Any downstream derivation is performed by the LLM and always surfaced for user review

- `submit_for_validation`
  - `validation_type`: `applicant_profile` | `skeleton_timeline` | `enabled_sections` | `knowledge_card`
  - Presents the corresponding UI:
    - applicant_profile: inline profile editor
    - skeleton_timeline: timeline review/editor
    - enabled_sections: dedicated section toggle UI (not a generic JSON editor)
    - knowledge_card: card-specific validator w/ evidence references

- `validate_applicant_profile`
  - Shortcut to present profile validation UI (when already holding a proposed draft)

- `persist_data`
  - Persists approved JSON payloads to app-local store (e.g., `candidate_dossier`, `knowledge_card`)

- Timeline CRUD
  - `create_timeline_card`, `update_timeline_card`, `delete_timeline_card`, `reorder_timeline_cards`

- Artifact utilities
  - `list_artifacts`, `get_artifact`, `request_raw_file`

- Phase/objective control
  - `set_objective_status`, `next_phase`

- Local functions
  - `get_macos_contact_card` (fetches "Me" card to seed profile; always user-validated)

Removed: Separate "Fetch URL" and "Photo Upload" tools — replaced by `get_user_upload` (`allow_url`, `target_key`).

## Rules & Guardrails

- No evidence → no claim (knowledge cards): omit unsupported claims
- Derivation policy:
  - The LLM may derive `applicant_profile` or `skeleton_timeline` from enriched text
  - Derived drafts must be shown via `submit_for_validation` and only persisted after approval (no auto-persist)
- Contacts import and uploads are treated as suggestions until user validates
- Keep Phase 1 strictly structural (no highlights/skills)
- Gate tools during waiting states; orchestrator must wait on UI continuation
- Knowledge cards: verbatim quotes required; omit any claim without evidence
- Writing samples: preserve original text verbatim; do not generate summaries or style analysis

## Workflow Sequence & Narrative Flow

### Phase 1: Core Facts (Structure)

Objectives
1) `applicant_profile`: Collect and validate profile basics
2) `skeleton_timeline`: Create a minimal, chronologically ordered structure
3) `enabled_sections`: Let the user choose relevant resume sections

Notes
- Intake sources: manual entry, Contacts, upload+URL, profile URL (present choices with `get_user_option`)
- Greeting & orientation: outline the three phases and time expectations; explain approvals and privacy
- Contact intake: collect ApplicantProfile basics (name, email, phone, city/region, website, social); defer subjective fields (label/summary)
- Resume intake (optional): `get_user_upload` (allow_url=true) → `extract_document` (enriched text) → LLM proposes drafts → `submit_for_validation` → `persist_data`
- SkeletonTimeline: add minimal entries (work/education/projects/volunteer) with ISO8601 dates; no highlights; validate via `submit_for_validation`
- Enabled Sections: after a first timeline pass, call `submit_for_validation(validation_type="enabled_sections")` to open the section toggle card
- Dossier prompts (2–3 lightweight): goals/priorities, constraints, work arrangement; always reflect back and confirm; persist via `persist_data(dataType="candidate_dossier")`
- Anti-hallucination guardrails active (no invented facts; ask clarifying questions instead)

### Phase 2: Deep Dive (Substance)

Objectives
1) `interviewed_one_experience`
2) `one_card_generated`

Notes
- Generate evidence-backed knowledge cards with linked quotes and optional artifact SHA
- Validate cards before persistence
- Flow: pick an experience (user choice), conduct structured probing (problem → action → outcome), capture tangible metrics, then `generate_knowledge_card` → `submit_for_validation` → `persist_data`
- Dossier prompts (opportunistic): update context when natural (e.g., departure reasons, remote prefs shifts, constraints surfaced in stories)
- Transcript handling: when relevant, include transcript excerpts alongside artifacts for card generation; do not store transcripts as summaries in cards

### Phase 3: Writing Corpus & Dossier (Context)

Objectives
1) `one_writing_sample` (optional, consented)
2) `dossier_complete`

Notes
- Writing Samples: request samples via `get_user_upload` (allow_url=true); store full manuscripts verbatim (PDF/DOCX/TXT/MD). Do not summarize or style-assess
- Dossier: fill gaps and finalize; ask one focused question at a time; reflect and confirm; persist updated `candidate_dossier`
- Wrap-up: present a consolidated review (ApplicantProfile, SkeletonTimeline, Knowledge Cards, Writing Samples, Dossier) via `submit_for_validation`; on approval, mark objectives complete and `next_phase` to completion

## Candidate Dossier — Scope, Structure, and Prompts

Purpose: capture qualitative context that informs tailoring and fit without embedding subjective scoring.

Principles
- Short, crisp, user-confirmed entries only
- Sensitivity-aware; opt-in for optional topics
- Opportunistic prompting across all phases; never block on dossier

Suggested Fields (all strings unless noted)
- `job_search_context` — concise goals, motivations, constraints
- `work_arrangement_preferences` — remote/hybrid/onsite, relocation, cities
- `availability` — start window, notice, scheduling constraints
- `strengths_to_emphasize` — bullets
- `pitfalls_to_avoid` — bullets (things often misread, risks)
- `unique_circumstances` — optional, minimal wording if sensitive
- `sensitivity` — enum `public|personal` (default `personal`)

Collection Pattern (Ask → Reflect → Confirm → Persist)
1) Ask one focused question
2) Synthesize a terse reflection (2–4 sentences or bullets)
3) Present reflection to user for confirmation or edits (`submit_for_validation` or built-in UI pathway)
4) Persist with `persist_data(dataType="candidate_dossier")`

Phase Integration
- Phase 1: 2–3 general prompts (priorities, arrangement, non-negotiables)
- Phase 2: opportunistic updates tied to experiences (departure reasons, evolved preferences)
- Phase 3: finalize and fill gaps; optional sensitive context

Example Minimal Dossier JSON
```json
{
  "title": "CandidateDossier",
  "job_search_context": "Seeking IC role with ownership and user impact; avoid heavy on-call.",
  "work_arrangement_preferences": "Remote first; open to SF/SEA hybrid if high-impact.",
  "availability": "2 weeks notice; avoid Fri interviews",
  "strengths_to_emphasize": ["0→1 product shaping", "hands-on prototyping"],
  "pitfalls_to_avoid": ["Downplaying cross-functional work"],
  "unique_circumstances": null,
  "sensitivity": "personal",
  "meta": {"validation_state":"user_validated","validated_via":"validation_card"}
}
```

## Writing Samples — Policy and Handling

- Accept formats: PDF, DOCX, TXT, MD, RTF (images allowed but text extraction is primary)
- Ingestion: `get_user_upload` (allow_url=true) → `extract_document` to enriched Markdown
- Storage: persist full extracted manuscript in `artifact_record.extracted_content`; attach metadata (filename, size, content_type)
- Do not summarize or style-assess manuscripts
- Optional user-provided metadata (e.g., audience, date, context) may be stored under `metadata`

## Validation UX

- Applicant Profile: inline editor; prefill from Contacts/URL/Upload derivation; user confirms/edits; persist only on approval
- Skeleton Timeline: editor with add/update/reorder; enforce ISO dates; strip highlights in P1
- Enabled Sections: dedicated toggle card with suggested recommendations; user final say
- Knowledge Cards: show claims + evidence quotes; reject or modify; enforce “quote present” requirement

## Allowed Tools & Gating

- Each phase publishes allowed tools to the LLM (orchestrator)
- During waiting states (selection/upload/validation/extraction), tools are gated to prevent concurrent calls
- Phase transitions require required objectives met (or explicit user approval to override)

## Consent, Privacy, and Safety

- Explain at start what will be stored locally and why
- All derived content must be user-confirmed before persistence
- Dossier fields carrying sensitive context default to `personal` sensitivity and minimal phrasing
- No style profiling of writing; no behind-the-scenes scoring

## Error Handling & Recovery

- Missing model / invalid model: notify and request model change; allow resume
- Extraction failure: surface error; allow retry or alternate intake path
- Conflicting facts: ask clarifying question; prefer omission over invention

## Non-Goals (vNext)

- Sub-agents and repository browsing (MCP) — punted
- Writing Style Profile — removed
- Extractor return_types for derived profile/timeline — removed (derive via LLM + user validation instead)

## Data Conventions

- Custom fields live under `meta.*` or `x-*` namespaces
- Validation metadata on approved objects:
  - `meta.validation_state = "user_validated"`
  - `meta.validated_via = "validation_card" | "contacts" | ...`
  - `meta.validated_at = ISO8601`

## Future Considerations (Out of Scope for vNext)

- Sub-agents (Agent SDK), repo browsing via MCP, advanced code ingestion
- Writing style profiles and long-lived linguistic modeling
- Automatic derivation persisted without explicit approval
