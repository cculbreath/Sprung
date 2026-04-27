# Sprung — Architecture Overview

Sprung is a macOS application that turns a user's complete career history into tailored, job-specific resumes and cover letters. Three interconnected systems make this possible: a unified multi-provider LLM routing layer, a structured career knowledge pipeline, and a declarative Mustache rendering engine backed by Chromium PDF export.

---

## High-Level Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Onboarding Interview                                                        │
│  (Multi-turn LLM conversation with 40+ tool calls)                          │
│                                                                             │
│  Documents (PDF, DOCX, git)  ──►  Knowledge Cards  ──►  Skill Bank         │
│                                        │                      │             │
└────────────────────────────────────────┼──────────────────────┼─────────────┘
                                         │                      │
                                         ▼                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Resume Customization Pipeline                                              │
│                                                                             │
│  Job Posting  ──►  TreeNode  ──►  AI Review (2 phases)  ──►  Updated Tree  │
│                                         ▲                                   │
│                              Knowledge Cards + Skill Bank + Guidance        │
└──────────────────────────────────────────────┬──────────────────────────────┘
                                               │
                                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Render Pipeline                                                            │
│                                                                             │
│  TreeNode + ApplicantProfile  ──►  Mustache Context  ──►  HTML  ──►  PDF   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. LLMFacade — Unified Multi-Provider Routing

`LLMFacade` (`Sprung/Shared/AI/Models/Services/LLMFacade.swift`) is a single `@Observable @MainActor` class that is the **only** entry point for every LLM call in the application. Feature code never imports a provider SDK directly — it calls the facade, which routes to the correct backend.

### Supported Backends

| Backend | Provider | Primary Use |
|---------|----------|-------------|
| `.openRouter` | 100+ models via OpenRouter | Default — resume customization, job analysis, cover letters |
| `.anthropic` | Claude (direct Anthropic API) | Onboarding interview, prompt-cached system preambles |
| `.gemini` | Google Gemini (direct API) | PDF vision extraction, image analysis, document understanding |
| `.openAI` | OpenAI Responses API | Web search grounding, reasoning-heavy tasks |

### Routing Strategy

Provider selection happens automatically at call time:

```
Model ID prefix              →  Backend dispatched
────────────────────────────────────────────────────
"claude-" / "anthropic/"     →  .anthropic
"google/" / "gemini-"        →  .gemini (or .openRouter)
"openai/" / "gpt-"           →  .openAI (or .openRouter)
(all others)                 →  .openRouter (default)
```

Callers can also pass an explicit `backend:` parameter. All backends are registered at startup via `LLMFacadeFactory` and injected through `AppDependencies` — if an API key is absent, that backend is simply skipped. There are no hardcoded fallback model IDs anywhere in the codebase; a missing model configuration surfaces the Settings picker rather than silently substituting a model.

### Capability Validation

Before dispatching, `LLMFacadeCapabilityValidator` checks whether the user-selected model supports the required capability (`.vision`, `.structuredOutput`, `.reasoning`, `.textOnly`). Per-model capability metadata is tracked in `EnabledLLM` (SwiftData), with automatic refresh via `ModelValidationService` when a model is first seen.

### Public API Surface

```
Text          executeText(prompt:modelId:backend:)
              executeTextWithImages(prompt:modelId:images:backend:)

Structured    executeStructured<T: Codable>(prompt:modelId:as:backend:)
              executeStructuredWithSchema<T>(prompt:modelId:as:schema:schemaName:backend:)
              executeFlexibleJSON<T>(prompt:modelId:as:jsonSchema:backend:)

Streaming     startConversationStreaming(systemPrompt:userMessage:modelId:...)
              continueConversationStreaming(userMessage:modelId:conversationId:...)

Multi-turn    startConversation(systemPrompt:userMessage:modelId:backend:)
              continueConversation(userMessage:modelId:conversationId:backend:)

Tool calling  executeWithTools(messages:tools:toolChoice:modelId:backend:)

Anthropic     executeTextWithAnthropicCaching(systemContent:userPrompt:modelId:)
              anthropicMessagesStream(parameters:)
              anthropicListModels()

Gemini        generateFromPDF(pdfData:filename:prompt:modelId:)
              analyzeImagesWithGemini(images:prompt:modelId:)

OpenAI        executeWithWebSearch(systemPrompt:userMessage:modelId:...)
              responseCreateStream(parameters:)

TTS           createTTSClient()
```

### Internal Components

```
LLMFacade
├── LLMFacadeFactory             — constructs and registers all backends at startup
├── LLMFacadeStreamingManager    — streaming handle lifecycle and cancellation
├── LLMFacadeCapabilityValidator — pre-flight model capability checks
├── LLMFacadeSpecializedAPIs     — holds AnthropicService, GoogleAIService, OpenAIService
├── LLMFacadeOpenAIToolsAdapter  — marshals tool schemas for OpenAI format
└── backendClients: [Backend: LLMClient]   — registered client implementations
```

### Dependency Injection

`LLMFacade` is constructed once in `AppDependencies.swift` and distributed via SwiftUI's `@Environment`. Services receive it at init; views access it via `@Environment(LLMFacade.self)`.

---

## 2. Knowledge Cards Pipeline

Knowledge Cards are the user's structured career knowledge base. Each card is a rich narrative (500–2,000 words) describing a job, project, achievement, or education experience. Cards are created during onboarding from uploaded documents and an LLM-driven interview, then enriched with structured facts for use in resume customization.

### Data Model: `KnowledgeCard` (SwiftData `@Model`)

| Field | Description |
|-------|-------------|
| `title` | Display name ("Led platform migration at Acme Corp") |
| `narrative` | 500–2,000 word story in WHY / JOURNEY / LESSONS format |
| `cardType` | `employment`, `project`, `achievement`, or `education` |
| `dateRange` | "2020-09 to 2024-06" |
| `organization` | Company, university, or org name |
| `evidenceAnchorsJSON` | Links narrative back to exact source document locations |
| `extractableJSON` | Domains, scale indicators, and keywords (for job-match scoring) |
| `factsJSON` | Structured facts by category with confidence scores |
| `suggestedBulletsJSON` | Resume bullet templates with `[BRACKETED PLACEHOLDERS]` |
| `technologiesJSON` | Tools and frameworks extracted from the narrative |
| `outcomesJSON` | Measurable or qualitative outcomes produced |
| `verbatimExcerptsJSON` | 100–500 word passages preserved verbatim (voice-matching) |

### Pipeline Stages

```
User uploads documents (PDF, DOCX, text, git repo)
                │
                ▼
┌───────────────────────────────────────────────────┐
│  Stage 1: Document Extraction                     │
│                                                   │
│  PDF → Pass 1: PDFKit extracts plain text         │
│        Pass 2: Gemini vision analyzes graphics,   │
│                diagrams, charts, screenshots       │
│                (parallel, up to 30 pages/batch)   │
│                                                   │
│  DOCX / text → direct extraction                  │
│  Git repo    → GitAnalysisAgent (commit history)  │
│                                                   │
│  Result: ArtifactRecord with extractedContent     │
└───────────────────┬───────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────┐
│  Stage 2: Narrative Extraction (LLM)              │
│                                                   │
│  KnowledgeCardExtractionService sends document    │
│  text to LLM with a JSON schema, producing per   │
│  card:                                            │
│   • title, narrative (WHY/JOURNEY/LESSONS)        │
│   • card_type                                     │
│   • evidence_anchors (source + page location)     │
│   • extractable metadata (domains, scale,         │
│     keywords for job matching)                    │
│                                                   │
│  Large documents are chunked at section           │
│  boundaries; chunks merged after extraction       │
│                                                   │
│  Cards created with isPending = true              │
└───────────────────┬───────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────┐
│  Stage 3: Deduplication & User Review             │
│                                                   │
│  CardMergeService deduplicates similar cards      │
│  across multiple uploaded documents               │
│                                                   │
│  User reviews pending cards in UI, removes        │
│  unwanted ones, approves the rest                 │
│  (isPending → false)                              │
└───────────────────┬───────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────┐
│  Stage 4: Background Enrichment (async)           │
│                                                   │
│  CardEnrichmentService runs a fact-extraction     │
│  LLM call per card (5 cards/batch), adding:       │
│   • facts[] with category + confidence            │
│   • suggestedBullets[] (resume-ready templates)   │
│   • outcomes[], technologies[]                    │
│   • verbatimExcerpts[] (voice-matched passages)   │
│                                                   │
│  Progress tracked in status bar via               │
│  AgentActivityTracker                             │
└───────────────────────────────────────────────────┘
```

### Parallel Skill Bank

The same documents also feed a **Skill Bank** — a deduplicated, evidence-backed inventory of every skill (`SkillStore`, SwiftData). Each `Skill` record carries:
- `canonical` name ("Python")
- `atsVariants` — ATS spelling variants ("python", "Python 3", "python3")
- `category` — "Programming Languages", "Data Visualization", etc.
- `proficiency` — `expert` / `proficient` / `familiar`
- `evidence[]` — source document, location, context, strength

During resume customization, the Skill Bank drives ATS-aware keyword injection and the skills resume section.

### Storage

`KnowledgeCardStore` (SwiftData `@Observable @MainActor`) persists all cards. The `Resume` model maintains a many-to-many `enabledSources` relationship to the cards it draws from, so each job-specific resume can use a different subset of the career history.

---

## 3. Resume Rendering Pipeline

### Step 1: ExperienceDefaults → TreeNode

`ExperienceDefaults` is a `Codable` struct holding the user's generally-applicable resume data: `work[]`, `education[]`, `skills[]`, `projects[]`, `awards[]`, and more.

`ExperienceDefaultsToTree` converts this into a recursive `TreeNode` hierarchy where each leaf is a single editable resume field. During conversion, manifest patterns are applied to flag nodes for AI review:

| Manifest Pattern | Review Mode | Effect on TreeNode |
|-----------------|-------------|-------------------|
| `skills.*.name` | Bundled | All skill names reviewed together as a set |
| `skills[].keywords` | Enumerated | Each skill's keywords reviewed individually |
| `custom.objective` | Scalar | Single objective field flagged for rewrite |

### Step 2: AI Customization (Two-Phase Review)

```
PhaseReviewManager reads TreeNode AI-review flags
        │
        ├── Phase 1 (Bundled): 1 ExportedReviewNode per bundle
        │   LLM reviews all bundled values holistically
        │   (e.g., reviews all skill names together to ensure consistency)
        │
        └── Phase 2 (Enumerated): 1 ExportedReviewNode per entry
            LLM reviews each entry in isolation, informed by Phase 1 results

Context injected into every LLM call:
  • Knowledge Cards (enriched narrative + facts)
  • Skill Bank (canonical skills + ATS variants)
  • InferenceGuidance (per-node user instructions)
  • Full job posting text
  • ApplicantProfile (identity)

LLM returns ProposedRevisionNode[] with oldValue / newValue
User reviews proposals in streaming queue UI
  → Accepts, edits, or rejects each proposal
  → Rejected proposals can be resubmitted with feedback

FeedbackNode.applyToResume() patches TreeNode leaves in place
```

`InferenceGuidance` is a SwiftData model keyed by tree path (e.g., `"experience.*.bullets"`, `"custom.jobTitles"`) that stores per-node LLM instructions set by the user — preferred phrasing, emphasis, constraints — giving fine-grained control over tone in each section.

### Step 3: Context Assembly (ResumeContextBuilder)

```
Updated TreeNode  +  ApplicantProfile
        │
        ▼
ResumeContextBuilder.buildContext(resume:profile:)
  ├── ResumeTemplateDataBuilder   — flattens TreeNode hierarchy into [String: Any]
  ├── nestCustomFields()          — groups custom.* fields under "custom" key
  ├── mergeApplicantProfile()     — overlays identity data (merged fresh at render time,
  │                                 never cached in TreeNode)
  ├── applySectionVisibility()    — hides/shows sections per manifest + user overrides
  ├── addTemplateFields()         — injects sectionLabels and fontSizes
  └── HandlebarsContextAugmentor  — computes derived fields (contact line, date formats)
        │
        ▼
[String: Any] Mustache context
```

**Key invariant:** `basics.*` (name, email, phone, location, social profiles) always comes from `ApplicantProfile` at render time — it is never stored inside `TreeNode`. `basics.summary` and all other content comes from `TreeNode`. This means updating contact info in one place propagates to every resume on next export.

### Step 4: Mustache Rendering → Output

```
Mustache context
        │
        ├── HandlebarsTranslator        — translates Handlebars syntax to Mustache
        │   (enables JSON Resume community themes without modification)
        │
        ├── Mustache.Template.render()  — GRMustache Swift library
        │
        ▼
HTML string
        │
        ├── NativePDFGenerator
        │   ├── Inline Google Fonts (network-free rendering)
        │   ├── Inject paged.js (CSS pagination polyfill)
        │   ├── Write to temp file
        │   └── chrome-headless-shell --print-to-pdf → PDF bytes
        │
        └── TextResumeGenerator
            ├── applyTextTransformations() (normalize arrays, build contact line)
            └── sanitizeRenderedText() → plain text string
```

**Template context shape (JSON Resume–inspired schema):**

```
basics.{name, email, phone, location, profiles[], summary}
work[].{name, position, startDate, endDate, highlights[]}
education[].{institution, area, studyType, startDate, endDate}
skills[].{name, level, keywords[]}
projects[].{name, description, highlights[], url}
custom.{objective, <user-defined sections>}
template.{sectionLabels, fontSizes}
{section}Bool   — visibility flags per section
```

HTML templates ship in `Sprung/Resources/TemplateDefaults/` (one directory per theme: `atrium`, `mercury`, `ethel`, `fraunces`, `aleo`, `canopy`) and are stored in `TemplateStore` (SwiftData).

---

## Technology Stack

| Layer | Technology |
|-------|------------|
| Platform | macOS (SwiftUI, native AppKit integration) |
| State management | `@Observable`, `@MainActor`, SwiftUI `@Environment` |
| Persistence | SwiftData (`@Model` entities, `ModelContext`) |
| LLM providers | OpenRouter · Anthropic Claude · Google Gemini · OpenAI |
| LLM routing | Custom `LLMFacade` with enum-based backend dispatch |
| Structured output | JSON Schema-constrained LLM responses, per-model capability tracking |
| Document parsing | PDFKit (text) + Gemini vision (graphics), VisionKit OCR fallback |
| Template rendering | Mustache via GRMustache Swift |
| PDF export | Chromium headless shell (`--print-to-pdf`) |
| Concurrency | Swift Structured Concurrency (`async/await`, `TaskGroup`, actors) |
| Data interchange | `Codable` (all internal types), SwiftyJSON (LLM JSON responses only) |

---

## Key Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| Single `LLMFacade` entry point | Feature code stays provider-agnostic; backends swap without touching callers |
| Backend inferred from model ID prefix | User-selected models route automatically; no per-feature backend configuration needed |
| No hardcoded model IDs or fallbacks | Model IDs change constantly; missing config surfaces Settings picker rather than silently degrading |
| Two-phase review (bundled → enumerated) | Holistic Phase 1 review produces better context for per-entry Phase 2 proposals |
| Knowledge Cards enriched at creation time | Resume customization LLM receives structured facts and bullet templates, not raw narratives |
| `ApplicantProfile` merged fresh at render time | Identity never goes stale in stored resumes; one update propagates everywhere |
| Handlebars→Mustache translation layer | Entire JSON Resume community theme ecosystem is reusable without forking themes |
| TreeNode carries AI config inline | Single source of truth for what gets reviewed; UI mode changes take effect immediately |
