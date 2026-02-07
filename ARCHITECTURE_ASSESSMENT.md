# Sprung Resume Customization: Architecture Assessment

*February 2026 — Comprehensive audit of the KC-based customization pipeline*

---

## Executive Summary

The Knowledge Card system is **architecturally superior** to the original single-shot summary approach. The data quality is genuinely excellent: 24 fully-enriched KCs with deep narrative content, structured facts, verbatim excerpts, and evidence anchoring. The extraction and enrichment prompts are among the best-crafted in the codebase.

**The problem is not the KC system. The problem is that the downstream customization pipeline doesn't use what the KC system provides.**

Three specific execution gaps account for most of the quality loss:

1. **Relevance filtering is computed but discarded** — `JobAppPreprocessor` identifies relevant KCs per job, but `CustomizationContext.build()` loads all 24 cards regardless, producing a 196K-character preamble where most content is noise for any given job.

2. **Generic prompts are underdeveloped** — The most important resume fields (work highlights, project descriptions, objective) use a 6-line generic prompt, while skill selection gets 40+ lines of well-structured guidance. The fields that most need lateral thinking get the least help.

3. **Parallel execution destroys cross-field coherence** — Each parallel task operates independently. The summary doesn't know what skills were selected. Work highlights can't reference the objective's framing. This is where the "formulaic" quality creeps in — not because the system is wrong, but because each field is optimized in isolation.

**Recommendation: Do not revert to summaries.** Fix these three gaps. The infrastructure for all three fixes already exists in the codebase — it's wiring, not architecture.

---

## Table of Contents

1. [The Case Against Reverting to Summaries](#1-the-case-against-reverting-to-summaries)
2. [Data Store Audit: What You Actually Have](#2-data-store-audit)
3. [The Relevance Filtering Gap](#3-the-relevance-filtering-gap)
4. [The Generic Prompt Problem](#4-the-generic-prompt-problem)
5. [The Coherence Problem](#5-the-coherence-problem)
6. [Skill Bank Bloat](#6-skill-bank-bloat)
7. [Underutilized Enrichment Data](#7-underutilized-enrichment-data)
8. [Two-Pipeline Divergence](#8-two-pipeline-divergence)
9. [Token Economics](#9-token-economics)
10. [Recommendations: Priority-Ordered](#10-recommendations)
11. [Architecture Diagram](#11-architecture-diagram)

---

## 1. The Case Against Reverting to Summaries

The original single-shot approach had one advantage (coherence — everything decided at once) and several fatal disadvantages:

| Dimension | Single-Shot Summaries | KC System (Current) |
|-----------|----------------------|---------------------|
| **Source fidelity** | Lossy human-written summaries | Raw documents → structured extraction |
| **Evidence grounding** | No verification possible | Facts with confidence levels, evidence anchors, verbatim excerpts |
| **Skill accuracy** | Whatever the LLM invents | Constrained to verified skill bank |
| **Scalability** | Context window limits (~27 fields max) | Parallel execution, unlimited fields |
| **Voice preservation** | Lost in summarization | Verbatim excerpts preserve original voice |
| **Lateral thinking** | Limited to summary content | Full narrative + facts + outcomes available |
| **Cross-field coherence** | Natural (single pass) | Currently broken (fixable) |

The KC system's data quality is genuinely high. Your 24 KCs contain an average of 3,233 characters of narrative and 3,915 characters of structured facts each. The enrichment prompts explicitly guard against LinkedIn slop, demand evidence-based claims, and preserve your authentic voice. This is not reformatting — it's structured knowledge that summaries would throw away.

**The single-shot approach would lose:** evidence anchoring, confidence-rated facts, verbatim voice excerpts, skill bank constraints, and the ability to verify that every claim on the resume traces back to a source document. These are the things that make the difference between "formulaic action-number-result" and genuinely grounded content.

---

## 2. Data Store Audit

Direct inspection of `~/Library/Application Support/Sprung/default.store`:

### Knowledge Cards: 24 cards, all enriched

| Card Type | Count | Examples |
|-----------|-------|---------|
| Employment | 5 | Pioneering Commercial-Scale SMA Production, Custom Instrumentation for Ohno Casting |
| Project | 16 | Sprung AI Copilot, Physics Cloud CMS, Gas-Propelled Autoinjector Model |
| Education | 3 | Doctoral dissertation research, physics teaching |

**Enrichment completeness:** All 24 cards have populated `factsJSON`, `suggestedBulletsJSON`, `technologiesJSON`, `outcomesJSON`, and `verbatimExcerptsJSON`. The enrichment pipeline has been fully executed.

**Content depth examples:**
- Sprung KC: 15 technologies, 4 outcomes, 3 verbatim excerpts, suggested bullets with `[BRACKETED_PLACEHOLDERS]` for customization
- SMA Production KC: Domain expertise in metallurgy, materials science, manufacturing at scale
- Physics Cloud KC: Full-stack web development, PHP/MySQL, curriculum design

### Skill Bank: 163 skills, poorly distributed

| Category | Count | % |
|----------|-------|---|
| Tools & Platforms | 79 | 48% |
| Scientific & Analysis | 25 | 15% |
| Leadership & Communication | 16 | 10% |
| Domain Expertise | 13 | 8% |
| Hardware & Electronics | 11 | 7% |
| Fabrication & Manufacturing | 10 | 6% |
| Programming Languages | 8 | 5% |
| Frameworks & Libraries | 1 | <1% |

**Duplicates identified:** Machining / Manual Machining / Machining & Fabrication; Embedded C++ / Embedded C/C++ / C++; Mentoring / Mentoring & Advising; State Machines / State Machine Architecture; Mechanical Design / Mechanical Engineering / Mechanics.

**Over-granular entries:** Circular Buffers, EEPROM Management, RPM Measurement, Rotary Encoders, Hardware Interrupts, Motorized Slider Control — these are implementation details, not resume-level skills.

### Job Applications: 42 apps, all with relevantCardIds

Every job application has `relevantCardIds` populated (665-759 bytes each). The preprocessor is doing its job. The data is there. It's just not being used downstream.

### Other Data
- 7 writing samples (cover letter references, 2.5-6K chars each)
- 1 ExperienceDefaults record (work, education, skills, projects enabled; custom section enabled)
- 167 TreeNode records across resume versions

---

## 3. The Relevance Filtering Gap

**This is the single highest-impact bug in the system.**

### What happens now

```
JobAppPreprocessor.preprocess()
  → LLM identifies which KCs are relevant to this specific job
  → Stores result in jobApp.relevantCardIds ✅

CustomizationContext.build()
  → Loads knowledgeCardStore.approvedCards (ALL 24 cards) ❌
  → Never reads jobApp.relevantCardIds
  → Passes all 24 to preamble builder
```

### Impact

- **Token waste:** ~196K characters of KC content in every preamble. If only 8-12 KCs are relevant per job, that's 50-60% noise.
- **Signal dilution:** The LLM must pick out relevant evidence from a wall of 24 narratives. Irrelevant cards about physics teaching dilute the signal when applying for a manufacturing automation role, and vice versa.
- **Cache inefficiency:** With Anthropic prompt caching, the preamble is cached per unique content hash. Since ALL cards are always included, the same cache is used for every job — good for caching, bad for relevance. Filtering to relevant cards would create job-cluster-specific caches that are smaller and more focused.

### Fix

**Option A (minimum viable):** In `CustomizationContext.build()`, filter KCs using the preprocessor's output:

```swift
let relevantIds = resume.jobApp?.relevantCardIds.compactMap(UUID.init) ?? []
let knowledgeCards = relevantIds.isEmpty
    ? knowledgeCardStore.approvedCards  // fallback if no preprocessing
    : knowledgeCardStore.approvedCards.filter { relevantIds.contains($0.id) }
```

**Option B (better — tiered KC presentation):** Instead of binary include/exclude, organize the preamble into relevance tiers:

```markdown
## Primary Evidence (directly relevant to this job)
[Full narrative + facts + bullets + technologies for relevant KCs]

## Supporting Evidence (transferable skills, adjacent experience)
[Abbreviated: title + type + org + key technologies + 1-2 sentence summary]

## Background Context (establishes breadth, not core to this role)
[Title + type + org only — available via read_knowledge_cards tool]
```

This preserves breadth (the LLM knows you have physics teaching experience) while focusing depth (it processes the full narrative only for relevant cards). The tiering could derive from the strategic pre-analysis pass (see Section 5) or from the preprocessor's `relevantCardIds`.

**Location:** `Resumes/AI/Types/CustomizationContext.swift` (filtering), `CustomizationPromptCacheService.swift` (tiered presentation).

---

## 4. The Generic Prompt Problem

### Current state

`RevisionTaskBuilder.swift` has four prompt types:

| Type | Lines of prompt | Quality | Fields handled |
|------|----------------|---------|----------------|
| `.skills` | ~40 | Excellent | Skill category names |
| `.skillKeywords` | ~55 | Excellent | Keywords per skill category |
| `.titles` | ~55 | Good | Job title selection |
| `.generic` | ~6 | Poor | **Everything else** — highlights, descriptions, objective, summary |

The generic prompt (lines 249-272) is essentially:

> "Revise this resume content for the target job. Maintain voice. Use evidence from Knowledge Cards only. Return JSON with newValue."

That's it. No guidance on structure, tone, length, what makes a good highlight vs a bad one, how to leverage specific KC evidence, or how to differentiate from formulaic resume language.

### Why this matters

The fields handled by the generic prompt are the ones where quality matters most:
- `work[].highlights` — the bullet points that make or break a resume
- `projects[].description` — narrative positioning of project work
- `custom.objective` — the opening statement that frames everything

These fields need the MOST guidance about lateral thinking, evidence leveraging, and voice preservation. Instead they get the least.

### Fix

Create field-aware prompt variants within the generic category:

```swift
private func generateGenericPrompt(for task: RevisionTask) -> String {
    let path = task.revNode.path
    if path.contains("highlights") {
        return generateHighlightsPrompt(for: task)
    } else if path.contains("objective") || path.contains("summary") {
        return generateNarrativePrompt(for: task)
    } else if path.contains("description") {
        return generateDescriptionPrompt(for: task)
    }
    return generateDefaultGenericPrompt(for: task)
}
```

Each specialized variant should:
- Reference specific KC evidence relevant to this field
- Provide anti-patterns (what NOT to write — generic LinkedIn language)
- Give structural guidance (length, format, emphasis)
- Include examples of the voice and style you want

**Key insight: these prompts already exist in the Seed Generation Module.** The `WorkHighlightsGenerator`, `ObjectiveGenerator`, `SkillsGroupingGenerator`, and `ProjectsGenerator` in the SGM pipeline have detailed, carefully crafted prompts with role-appropriate framing, forbidden patterns, and structural guidance. The fix is to **port these existing SGM prompts** into `RevisionTaskBuilder`, not author new ones from scratch. The SGM generators are the quality bar.

**Location:** `Resumes/AI/Services/RevisionTaskBuilder.swift`, lines 248-273. Reference SGM generators for prompt templates.

---

## 5. The Coherence Problem

### How parallel execution breaks coherence

The current flow:

```
Phase 1: Bundled reviews (e.g., all skill names together)
  → Each bundled group is ONE LLM call → coherent within group ✅

Phase 2: Enumerated reviews (e.g., each job's highlights)
  → Each field is a SEPARATE parallel LLM call
  → No shared context about what other fields decided
  → Skills task doesn't know what the objective says
  → Work highlights don't reference the skill framing
  → Result: each field is individually reasonable but collectively disjointed ❌
```

### Why this produces "formulaic" output

Without cross-field awareness, each LLM call falls back to the safest, most generic interpretation of the job description. The summary emphasizes "leadership" because the job description mentions it. The highlights also emphasize "leadership." The objective also mentions "leadership." Nobody coordinated.

A coherent resume would have the summary frame a narrative arc, the highlights provide specific evidence for that arc, and the skills demonstrate the technical depth behind it. That requires awareness of what the other fields are saying.

### Fix options

**Option A: Targeting plan pre-pass (recommended — highest impact)**

Before generating any fields, run a single "strategic planner" call that establishes the resume's narrative angle for this job:

**Input:** Job description + KC titles/summaries (abbreviated) + current resume structure + extracted requirements + dossier

**Output:** A targeting plan:
- Which KCs map to which resume sections
- What narrative themes to emphasize across the resume
- Which skills/categories are highest-priority
- What the resume's "story" should be for this application
- How to differentiate similar work entries
- Non-obvious connections: *"Precision optics work involved sub-micron measurement — relevant to semiconductor metrology even though the domain is different"*
- Narrative thread: *"For this role, lead with the custom instrumentation builder angle, not the physicist angle"*

Then every parallel task receives this targeting plan as context. This separates strategic thinking (holistic, needs to see everything) from content generation (local, needs depth on specific KCs). **The planner sees breadth; the generators see depth.**

This is where "lateral thinking" should live — the planner is explicitly prompted for non-obvious skill transfers, framing angles, and positioning strategy. Without this, each parallel call independently makes conservative, formulaic choices.

**Option B: Phase 1 context forwarding (simpler, partial fix)**
After Phase 1 completes, extract approved decisions (selected skills, titles, framing themes) and include them in every Phase 2 task prompt. Less powerful than Option A but requires no new LLM call.

**Option C: Post-assembly coherence pass (complementary)**
After all parallel results are collected and user-reviewed, run a single coherence check:

```
Review this assembled resume and check for:
1. Achievement repetition across sections
2. Summary ↔ highlights ↔ skills alignment
3. Consistent emphasis on job-relevant themes
4. Narrative flow from most to least relevant experience
Flag specific issues with suggested edits.
```

This catches coherence problems that slip through Options A/B. Can be combined with either.

**Option D: Compound calls for related fields (complementary)**
Instead of separate calls for `work.0.position`, `work.0.description`, and `work.0.highlights`, group them into one call per work entry. This prevents description and highlights from repeating each other within the same job, reduces total LLM calls by ~60%, and improves intra-section coherence while still allowing per-field review.

**Recommended combination:** Option A (targeting plan) + Option D (compound calls). This gives both global coherence (targeting plan) and local coherence (compound calls), with Option C as an optional quality gate.

**Location:** `Resumes/AI/Services/RevisionWorkflowOrchestrator.swift`, around lines 264-270.

---

## 6. Skill Bank Bloat

### Current state: 163 skills, ~50-60 are marketable

The skill bank extraction prompt prioritizes completeness ("extract everything"), which is correct for the extraction phase. But no curation step follows. The result:

- **79 skills in "Tools & Platforms"** — a catch-all that includes everything from "SolidWorks" (legitimate) to "Circular Buffers" (implementation detail) to "Assignment and Submission Tracking" (not a skill)
- **1 skill in "Frameworks & Libraries"** — LabVIEW alone, despite using SwiftUI, SwiftData, Yii2, Mustache, etc.
- **Multiple duplicates** across categories
- **Alphabetical truncation at 100** — `buildSkillBankSection()` sorts alphabetically and caps at 100, silently dropping the rest

### Impact on resume quality

When the LLM selects skills for a resume, it chooses from a noisy list where "EEPROM Management" competes with "Python" for attention. The alphabetical cutoff means skills starting with S-Z (Swift, SwiftUI, SolidWorks, TypeScript, etc.) may be silently excluded if the skill count exceeds 100.

### Fix

1. **Curate the skill bank** to ~50-60 distinct, marketable skills. Merge duplicates, promote implementation details to parent skills (Circular Buffers → Embedded Systems), fix category assignments.

2. **Sort by relevance, not alphabet.** When building the preamble, sort skills by: (a) match to job requirements, (b) proficiency level, (c) evidence count. This ensures the most relevant skills appear first even if truncation occurs.

3. **Remove the arbitrary 100-skill cap** or raise it. With a curated bank of ~60 skills, truncation becomes irrelevant.

4. **Cross-reference skills to KCs in the preamble.** Skills already have `evidenceCardIds`. Including provenance is cheap and gives the LLM grounding for every skill claim:

```markdown
### Programming & Software
- Python (expert) — evidenced in KC: Physics Cloud, Dissertation Research
- Swift (proficient) — evidenced in KC: Sprung Development
```

**Location:** `CustomizationPromptCacheService.swift`, `buildSkillBankSection()` around line 362.

---

## 7. Underutilized Enrichment Data

The enrichment pipeline extracts five categories of structured data per KC. Here's what's actually used downstream:

| Enrichment Field | Extracted? | In Preamble? | Used by LLM? |
|-----------------|-----------|-------------|--------------|
| Narrative | ✅ | ✅ Full text | ✅ Primary context |
| Facts (categorized, confidence-rated) | ✅ | ✅ Listed | ⚠️ Available but no prompt guidance to use them |
| Suggested Bullets (with [PLACEHOLDERS]) | ✅ | ✅ Listed | ❌ LLM generates from scratch, ignores templates |
| Technologies | ✅ | ✅ Listed | ⚠️ Available but not specifically referenced |
| Outcomes | ✅ | ❌ Not included | ❌ Never surfaces |
| Verbatim Excerpts | ✅ | ❌ Only via tool | ❌ Tool unreachable in parallel execution |

### Key waste

- **Suggested bullets** are pre-extracted resume templates with bracketed placeholders designed for customization. The LLM never uses them because the generic prompt doesn't mention them. These could dramatically improve highlight quality if the prompt said "adapt these templates for the target job."

- **Outcomes** capture what CHANGED as a result of the work (deltas, not activities). This is exactly what differentiates good resume bullets from bad ones. They're extracted but never included in the preamble or referenced by prompts.

- **Verbatim excerpts** preserve the candidate's authentic voice. They're only accessible via `ReadKnowledgeCardsTool`, which is registered but unreachable during parallel task execution (parallel executor uses `executeFlexibleJSON`, not `ToolConversationRunner`).

### Fix

1. **Include outcomes in preamble** — add an "Outcomes" subsection to each KC in `buildKnowledgeCardSection()`.
2. **Reference suggested bullets in highlight prompts** — the specialized highlights prompt (from fix #4) should explicitly say "use these pre-extracted bullet templates as starting points."
3. **Long-term:** Enable tool use in parallel execution so the LLM can pull verbatim excerpts on demand without bloating the preamble.

---

## 8. Two-Pipeline Divergence

An important architectural observation: there are actually **two separate generation pipelines** with divergent capabilities.

### Seed Generation Module (SGM)
Generates initial ExperienceDefaults from onboarding data (no job target). Uses `PromptCacheService` (separate from customization). Has dedicated generators per section:
- `WorkHighlightsGenerator` — detailed prompt with role-appropriate framing, forbidden patterns, structural guidance
- `SkillsGroupingGenerator` — explicit grouping logic
- `ObjectiveGenerator`, `ProjectsGenerator`, etc.

KC presentation: First 20 cards, max 5 facts + 3 bullets each. Skills: flat list, no proficiency or category.

### Resume Customization (Parallel Path)
Customizes for a specific job. Uses `CustomizationPromptCacheService`. Has `RevisionTaskBuilder` with specialized skills/titles prompts but minimal generic prompt.

KC presentation: ALL cards, full content. Skills: alphabetical, no proficiency in preamble (proficiency in skills-specific task prompt only).

### The Problem

The SGM generators contain **higher-quality prompts** for highlights, objectives, and descriptions than the customization path's `generateGenericPrompt()`. The customization path also has a legacy `PhaseReviewManager` single-conversation approach (with tool use and reasoning support) that coexists with the newer parallel path but has different capabilities.

### Resolution: Retire Legacy, Upgrade Parallel

The legacy single-conversation `PhaseReviewManager` customization path should be **fully retired** (clean break, no fallback — per project standards). Its capabilities must be absorbed into the parallel path:

1. **Port SGM prompt quality to customization** — don't write new prompts from scratch; adapt what's already working in seed generation.
2. **Add tool use to parallel execution** — `ReadKnowledgeCardsTool` support is essential for evidence drill-down. The parallel executor needs to switch from `executeFlexibleJSON` to a tool-capable execution mode.
3. **Standardize KC presentation** — the two paths present different evidence windows for the same data. The customization path is richer but unfiltered; the seed path is filtered but thinner. Converge on tiered relevance-based presentation.
4. **Delete the legacy path entirely** — no deprecated markers, no fallback branches. `PhaseReviewManager`'s customization-specific code, `ResumeApiQuery`, and the single-conversation execution path should be removed once the parallel path has parity.

---

## 9. Token Economics

### Current cost per customization run

| Component | Characters | Tokens (est.) | Notes |
|-----------|-----------|---------------|-------|
| Role preamble | 2,500 | 625 | Constraints, voice guidance |
| Applicant profile | 500 | 125 | Name, email, location |
| Writer's voice | 500-1,500 | 125-375 | Style examples |
| **Knowledge Cards** | **196,000** | **49,000** | **All 24 KCs, full content** |
| Skill bank (≤100) | 3,000 | 750 | Alphabetical, truncated |
| Title sets | 1,000 | 250 | Professional identity options |
| Dossier | 2,000 | 500 | Strategic insights |
| Job description | 2,000-10,000 | 500-2,500 | Target job posting |
| **Total preamble** | **~207K** | **~52K** | |

With ~20 parallel tasks at max 5 concurrent:
- 4 batches × preamble sent = preamble transmitted 4 times
- Anthropic prompt caching reduces repeat cost to ~10% of base price
- **Effective cost:** ~52K input tokens (first batch) + ~5.2K cached × 3 batches = ~67.6K input tokens total

### After relevance filtering (est. 10 of 24 KCs)

| Component | Tokens (est.) | Savings |
|-----------|--------------|---------|
| KC section | ~20,000 | -29,000 tokens (59% reduction) |
| Total preamble | ~23,000 | -29,000 tokens |
| Per-run cost | ~37K effective | -45% total |

The savings come not just from cost but from signal quality — the LLM processes 20K tokens of relevant context instead of 52K tokens of mixed relevance.

---

## 10. Recommendations (Consolidated from Three Assessments)

These are ordered for implementation sequencing — later items build on earlier ones.

### Priority 1: Wire up relevance filtering + tiered KC presentation

**Impact:** Highest (quality + cost)
**Effort:** Small-medium
**Depends on:** Nothing — can start immediately

Modify `CustomizationContext.build()` to use `jobApp.relevantCardIds` (already computed). Implement tiered presentation in `buildKnowledgeCardSection()`: primary KCs get full detail, supporting KCs get abbreviated summaries, background KCs get title-only with tool reference. Even the minimum viable fix (binary filter) cuts preamble by ~60%.

**Key files:** `CustomizationContext.swift`, `CustomizationPromptCacheService.swift`

### Priority 2: Add tool use to parallel execution + retire legacy path

**Impact:** High (unblocks preamble slimming, enables evidence drill-down)
**Effort:** Medium-high
**Depends on:** Nothing — can start in parallel with Priority 1

The parallel executor (`CustomizationParallelExecutor`) currently uses `executeFlexibleJSON` which doesn't support tools. Switch to a tool-capable execution mode so `ReadKnowledgeCardsTool` works during parallel tasks. This is the prerequisite for retiring the legacy path and for making tiered KC presentation effective (background KCs become retrievable via tool instead of dead references).

Once tool support is working in the parallel path: **delete the legacy `PhaseReviewManager` single-conversation customization path entirely.** No deprecation markers, no fallback branches, no "legacy support" code. Clean break. The phase-building logic (`buildReviewRounds()`) is still needed — it's the single-conversation execution mode and `ResumeApiQuery` prompt assembly that get deleted.

**Key files:** `CustomizationParallelExecutor.swift`, `PhaseReviewManager.swift` (keep phase-building, delete single-conversation execution), `ResumeApiQuery` (delete)

### Priority 3: Strategic pre-analysis pass ("targeting plan")

**Impact:** Highest (quality — this is where lateral thinking lives)
**Effort:** Medium (one new LLM call with a well-crafted prompt)
**Depends on:** Priority 1 (needs filtered KCs to be useful)

Before any field generation, run a single "strategic planner" call that establishes: the resume's narrative arc for this job, which KCs map to which sections, emphasis allocation per work entry, cross-cutting themes, non-obvious skill transfers, and gaps to address. This plan becomes context for all parallel tasks.

This directly addresses the core concern about formulaic output. Without it, each parallel call independently makes conservative, generic choices. With it, the LLM is told *"for this role, lead with the custom instrumentation builder angle, not the physicist angle"* — and every field reflects that strategic decision.

The targeting plan also produces the tiered KC relevance ranking for Priority 1 (replacing or augmenting the preprocessor's `relevantCardIds`).

**Key files:** New service (e.g., `TargetingPlanService.swift`), `RevisionWorkflowOrchestrator.swift`

### Priority 4: Port SGM prompt quality to customization

**Impact:** High (quality)
**Effort:** Low-medium (adapt existing prompts, not author from scratch)
**Depends on:** Priority 3 (targeting plan provides context these prompts need)

The Seed Generation Module's `WorkHighlightsGenerator`, `ObjectiveGenerator`, and `ProjectsGenerator` already have detailed prompts with role-appropriate framing, forbidden patterns, and structural guidance. Port these into `RevisionTaskBuilder` as field-specific prompt variants, replacing the 6-line generic prompt. Include the targeting plan's emphasis allocation and KC-to-section mapping in each prompt. The SGM generators are the quality bar.

**Key files:** `RevisionTaskBuilder.swift`, SGM generators (as reference)

### Priority 5: Phase 1 → Phase 2 context forwarding + compound calls

**Impact:** High (quality + efficiency)
**Effort:** Medium
**Depends on:** Priorities 3 and 4 (targeting plan + better prompts make compound calls more effective)

Two complementary changes: (a) After Phase 1 approval, include approved skill categories, selected titles, and targeting plan emphasis in Phase 2 task prompts. (b) Group related fields (position + description + highlights) into compound calls per work entry, preventing intra-section repetition and reducing total calls by ~60%.

**Key files:** `RevisionWorkflowOrchestrator.swift`, `RevisionTaskBuilder.swift`, `CustomizationParallelExecutor.swift`

### Priority 6: Curate the skill bank + add KC cross-references

**Impact:** Medium (quality)
**Effort:** Medium (curation requires user involvement)
**Depends on:** Nothing — can proceed any time, but most impactful after Priority 1

Reduce from 163 to ~50-60 distinct marketable skills. Merge duplicates, consolidate implementation details into parent skills, rebalance categories. Add skill-to-KC cross-references in the preamble (skills already have `evidenceCardIds`) to give the LLM provenance for every skill claim. Sort by job relevance + proficiency, not alphabetically.

**Key files:** Data store (manual curation), `CustomizationPromptCacheService.swift` (presentation), `SkillsProcessingService.swift` (dedup improvements)

### Priority 7: Surface outcomes + suggested bullets in prompts

**Impact:** Medium (quality)
**Effort:** Small
**Depends on:** Priority 4 (the new field-specific prompts are where these get referenced)

Add outcomes (what CHANGED) to the KC preamble section. Instruct the highlights prompt to use suggested bullets as starting templates rather than generating from scratch. These are already extracted and stored — just not surfaced.

**Key files:** `CustomizationPromptCacheService.swift`, `RevisionTaskBuilder.swift`

### Priority 8: Post-assembly coherence pass

**Impact:** Medium (quality)
**Effort:** Small
**Depends on:** Priorities 3-5 (most useful as a final quality gate after the other improvements)

After all results are collected, run a single coherence check that scans for achievement repetition, summary-highlights-skills alignment, and consistent emphasis. Complementary to the targeting plan — catches what slipped through.

**Key files:** New service or addition to `RevisionWorkflowOrchestrator.swift`

### Not recommended

- **Revert to single-shot summaries.** The coherence advantage is achievable through the targeting plan and compound calls.
- **Keep the legacy PhaseReview customization path as fallback.** Clean break. Git has the old code if needed.
- **Slim the preamble to title-only before adding tool support.** Background KCs need to be tool-retrievable first (Priority 2), otherwise they're just dead references.

---

## 11. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    DOCUMENT INGESTION                            │
│  PDFs, portfolios, dissertations, website text, git repos       │
│  → PDFExtractionRouter → VisionOCR or PDFKit                   │
└───────────────────────────┬─────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                 KC EXTRACTION (Gemini)                           │
│  kc_extraction.txt prompt: "Extract STORY, not facts"           │
│  → 24 Knowledge Cards with 500-2000 word narratives             │
│  → Anti-LinkedIn-slop, applicant advocacy framing               │
└───────────────────────────┬─────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                 KC ENRICHMENT (Gemini)                           │
│  CardEnrichmentService: structured fact extraction               │
│  → Facts (9 categories, confidence-rated)                       │
│  → Suggested bullets (with [PLACEHOLDERS])                      │
│  → Technologies, outcomes, verbatim excerpts                    │
│  All 24 KCs fully enriched ✅                                   │
└───────────────────────────┬─────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              SKILL BANK EXTRACTION (Gemini)                     │
│  "Completeness > selectivity" — extract everything              │
│  → 163 skills (needs curation to ~60) ⚠️                       │
│  → ATS variants, proficiency, evidence anchors                  │
└───────────────────────────┬─────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              JOB APPLICATION PREPROCESSING                      │
│  JobAppPreprocessor: requirements + relevant KC matching        │
│  → relevantCardIds computed per job ✅                          │
│  → Skill matching and evidence extraction                       │
│  ⚠️ relevantCardIds STORED but NOT USED downstream             │
└───────────────────────────┬─────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              CUSTOMIZATION CONTEXT                              │
│  CustomizationContext.build():                                  │
│  → Loads ALL 24 KCs (ignores relevantCardIds) ❌               │
│  → Loads ALL 163 skills (no filtering) ⚠️                      │
│  → Loads title sets, voice, profile, dossier                    │
└───────────────────────────┬─────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              PREAMBLE CONSTRUCTION (~52K tokens)                │
│  CustomizationPromptCacheService.buildPreamble():               │
│  → Role constraints (well-crafted) ✅                           │
│  → All KC narratives + facts + bullets + tech (196K chars) ⚠️  │
│  → Skills alphabetical, capped at 100 ⚠️                       │
│  → Job description, dossier, voice                              │
│  → Cached with Anthropic cache_control ✅                       │
│  ⚠️ Outcomes and verbatim excerpts NOT included                │
└───────────────────────────┬─────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              TASK GENERATION & PARALLEL EXECUTION               │
│                                                                 │
│  Phase 1 (bundled): skills.*.name → 1 LLM call ✅              │
│  Phase 2 (enumerated): parallel, max 5 concurrent               │
│    → skills prompt: 40+ lines, well-crafted ✅                  │
│    → titles prompt: 55 lines, good ✅                           │
│    → generic prompt: 6 lines, insufficient ❌                   │
│  ⚠️ No cross-field coherence between parallel tasks             │
│  ⚠️ ReadKnowledgeCardsTool registered but unreachable           │
└───────────────────────────┬─────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              USER REVIEW QUEUE                                  │
│  PhaseReviewItem: proposed vs original, user decides            │
│  → Accept, reject, edit, reject-with-feedback                   │
│  → Phase 1 applied before Phase 2 starts ✅                     │
│  → All changes require user approval ✅                         │
└───────────────────────────┬─────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              TEMPLATE RENDERING                                 │
│  TreeNode → ResumeTemplateDataBuilder → Mustache → PDF          │
│  → ApplicantProfile merged fresh at render time ✅              │
│  → Section visibility from manifest ✅                          │
│  → Font scaling, descriptor validation ✅                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Summary of Findings

| Area | Status | Severity |
|------|--------|----------|
| KC data quality | Excellent | — |
| KC enrichment completeness | All 24 enriched | — |
| Extraction/enrichment prompts | Well-crafted | — |
| Relevance filtering computed | ✅ Done | — |
| **Relevance filtering used** | **❌ Ignored** | **Critical** |
| Specialized prompts (skills, titles) | Well-crafted | — |
| **Generic prompts (highlights, narrative)** | **6 lines** | **High** |
| **Cross-field coherence** | **None** | **High** |
| Skill bank quality | Bloated, duplicates | Medium |
| Outcome data utilization | Not surfaced | Medium |
| Suggested bullet utilization | Not referenced | Medium |
| Skill bank sort/truncation | Alphabetical, arbitrary 100 cap | Low-Medium |
| User review flow | Well-designed | — |
| Template rendering | Solid | — |
| Prompt caching | Properly implemented | — |

**Bottom line:** The KC system built something genuinely valuable — a structured, evidence-grounded knowledge base with excellent extraction quality. The customization pipeline then throws away most of that value by not filtering for relevance, not providing field-specific guidance, and not coordinating across fields. Fix the plumbing, not the architecture.
