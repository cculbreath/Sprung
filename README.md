<p align="center">
  <img src="docs/images/hero_logo.png" alt="Sprung" width="400">
</p>

<p align="center">
  <strong>AI-Powered Job Search Copilot for macOS</strong>
</p>

<p align="center">
  <a href="https://www.apple.com/macos/sonoma"><img src="https://img.shields.io/badge/macOS-14.0%2B-blue.svg" alt="macOS"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-5.0-purple.svg" alt="SwiftUI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License"></a>
</p>

---

Sprung is a native macOS copilot for job hunting. It keeps your data local, builds a structured knowledge base about your experience, and uses multiple AI backends to tailor resumes, cover letters, and application packets without generic templates.

## Highlights

### AI Onboarding Interview (OpenAI Responses API)
- **Phase 1 – Core facts**: Collects contact info, profile photo, skeleton timeline, and which resume sections to enable.
- **Phase 2 – Deep dive**: Drives an evidence-first workflow to generate detailed knowledge cards (500–2000+ words) per role/skill, including Git repo analysis and artifact requests.
- **Phase 3 – Writing corpus**: Captures writing samples, style notes, and finalizes a candidate dossier for downstream drafting.
- **Document & repo ingestion**: Processes PDFs/Docs/TXT with Gemini-backed extraction, imports LinkedIn/portfolio content, and scans Git repos for accomplishments.
- **Event-driven, stateful orchestration**: Uses developer messages + `previous_response_id` for persistent context; tools are routed through an event bus and coordinator (see `.arch-spec.md`).

### Resume Workspace
- **Tree-based editor**: Structured, array-based JSON model with drag-and-drop nodes and live PDF preview.
- **AI revision flows**: Customize via one-click revisions or clarifying-question workflows; reasoning overlay shows model thinking for supported models.
- **Experience defaults editor**: Curate reusable sections (summary, skills, work, projects, education) before they flow into resumes.
- **Versioning + overflow fixes**: Create role-specific variants and auto-fix length overflows.

### Templates & Export
- **Mustache templates**: HTML/CSS-based themes with live preview and quick actions; default templates auto-imported if none exist.
- **Output options**: Native PDF generation, plain text, structured JSON, and text rendering for LLM prompts.
- **Template editor**: Built-in code editor and preview; templates stored locally for full control.
- **Template editor UI**: Manage manifests, duplicate/import/export themes, and tweak HTML/CSS live before exporting resumes and cover letters.

### Cover Letters
- **Job-aware drafting**: Uses the selected job app + resume + knowledge cards (ResRefs) and cover references (CoverRefs).
- **Multi-model committee**: Generate across models, tally votes/scores, and summarize model reasoning to pick a winner.
- **Inspector & revisions**: View sources, models, and committee feedback; iterate revisions on the same conversation.
- **Batch + export + TTS**: Batch generation, PDF rendering, and streaming text-to-speech via OpenAI + chunked audio playback.

### Job Applications
- **Kanban-style tracker**: Status groups for New, In Progress, Unsubmitted, Submitted, Interview Pending, Follow Up Required, Offer/Closed/Rejected.
- **Parsing & scraping**: Paste a job URL to scrape LinkedIn, Indeed, or Apple listings (SwiftSoup + WebView fallback with Cloudflare handling).
- **Packet review**: LLM review of resume + cover letter (with optional rendered PDF image) for a given posting.
- **Job recommendations**: Rank new listings against your resume/background facts to decide what to apply to next.
- **Context linking**: Attach specific resume and cover-letter versions plus notes and interview feedback to each job.

### Knowledge Cards & References
- **ResRefs**: Knowledge cards with metadata (type, organization, time period, sources) created during onboarding or manually. Toggle inclusion per resume or use globally from the interactive card deck browser.
- **CoverRefs**: Writing samples and background facts for cover letters, including dossier entries from onboarding.
- **Artifact pipeline**: Document and repo ingestion feed artifacts → knowledge cards → resumes and covers.

### Discovery (Job Search Operations)
- **Daily task management**: AI-generated daily job search tasks based on user goals and current progress. Focus area customization (balanced, applications-heavy, networking-heavy) with time tracking and idle detection.
- **Job source discovery**: AI-powered discovery of job boards and career websites via web search. URL validation, visit tracking, and categorization (job boards, recruiter sites, company career pages).
- **Networking event pipeline**: AI discovery and evaluation of professional events with recommendation levels. Pre-event prep (elevator pitch, talking points, company research) and post-event debrief capture (contacts, ratings, follow-ups).
- **Professional networking CRM**: Contact database with relationship warmth levels (cold/warm/hot), interaction history, relationship health assessment, and AI-powered outreach message drafting.
- **Job search coaching**: Automated three-phase coaching sessions—check-in questions, personalized activity review, and actionable recommendations. Integrates with all job search activity data and supports research tools (knowledge cards, job descriptions, resumes).
- **Weekly goals & reflection**: Goal setting for applications, networking events, contacts, and time investment with progress tracking and AI-generated weekly reflections.

### Audio & Reasoning
- **Reasoning stream overlay**: Displays model reasoning tokens for supported OpenRouter models during long-running flows.
- **Streaming TTS**: Pause/resume/stop controls with buffering safeguards using `swift-chunked-audio-player`.

### Data, Security, and Debugging
- **Local-first storage**: All data lives in SwiftData with migration support; no cloud sync.
- **Keychain-backed API keys**: OpenAI, OpenRouter, and Gemini keys are stored securely and never written in plaintext.
- **Debug tooling**: Toggle verbose logging, save prompts, and export onboarding logs (`Sprung/Onboarding/Logs/consolelog.txt`, `event-dump.txt`, `openai-log-output.txt`) from the debug panel.
- **Factory reset**: Settings include a danger-zone reset to wipe SwiftData stores and onboarding artifacts.

## Architecture

### App-wide layering
```
SwiftUI Views (split view, inspectors, sheets)
        ↓  @Observable bindings (stores + view models)
AppEnvironment container (DI for stores/services)
        ↓
Domain Stores (SwiftData-backed: resumes, cover letters, job apps, templates, refs, profiles)
        ↓
Services (LLMFacade, export/renderers, scraping, TTS, template loader)
        ↓
SwiftData persistence + Keychain (API keys) + local templates/assets
        ↓
External providers (OpenAI Responses/TTS, OpenRouter models, Gemini extraction)
```

- **SwiftUI + @Observable**: Views bind directly to stores/view models (e.g., `JobAppStore`, `CoverLetterStore`, `ResumeReviseViewModel`) supplied via `AppEnvironment`.
- **DI container**: `AppDependencies` builds long-lived stores/services per scene, avoiding singletons.
- **Unified LLM layer**: `LLMFacade` routes requests to OpenRouter for general workflows and to OpenAI for onboarding/TTS; model pickers surface capabilities (reasoning, images).
- **Persistence**: SwiftData models for resumes, cover letters, job apps, knowledge cards (ResRefs), cover refs, templates, and onboarding sessions; API keys are Keychain-backed.
- **Export/rendering**: Resume/Cover PDF generation via Mustache/GRMustache, text renderers for prompts, and chunked-audio playback for TTS.
- **Scraping/ingestion**: SwiftSoup/WebView fetchers for job postings; Gemini-backed document extraction; Git ingestion for accomplishments.

### Onboarding interview architecture
The onboarding interview uses a stricter event-driven stack (documented in `.arch-spec.md`):

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                        │
│                    (@Observable binding)                    │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                    EventCoordinator                         │
│            (AsyncStream pub/sub messaging)                  │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                    StateCoordinator                         │
│              (Actor - single source of truth)               │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                       SwiftData                             │
│                   (Persistent storage)                      │
└─────────────────────────────────────────────────────────────┘
```

- **StateCoordinator/EventCoordinator**: Owns interview state, tools, and phase transitions; all tool calls and developer messages flow through the event bus.
- **Tools/ingestion kernels**: Document extraction, Git analysis, artifact tracking, and knowledge card creation run through the coordinator/tool router.
- **LLM adapter**: Uses the OpenAI Responses API with persistent `developer` messages and `previous_response_id`; `instructions` is intentionally `nil`.

## Project Structure

```
Sprung/
├── App/                # Entry point, app environment, settings, windows, toolbar
├── Onboarding/         # Interview engine (state/event coordinators, phases, tools, ingestion services)
├── Discovery/          # Job search ops (coaching, daily tasks, sources, events, contacts, CRM)
├── Resumes/            # Resume models, AI revision flows, split editor, inspectors
├── ResumeTree/         # Tree-based resume data + draggable node UI
├── CoverLetters/       # Generation, committee voting, inspector, PDF/TTS, references
├── JobApplications/    # Kanban list, scraping, application review, clarifying questions
├── Experience/         # Experience defaults editor and section renderers
├── Templates/          # Mustache templates, manifests, template editor
├── ResRefs/            # Knowledge card models and sliding source list
├── DataManagers/       # SwiftData stores (resumes, covers, jobs, profiles, refs)
├── Export/             # PDF/text generators and export UI
├── Shared/             # LLM facade, logging, utilities, model pickers, TTS helpers
└── Resources/          # Static assets (images, HTML fragments, etc.)
```

## LLM & Provider Support

- **Onboarding**: Uses the in-repo OpenAI adapter (Responses API with tool calling). `instructions` is intentionally `nil`; developer messages carry persistent context.
- **Discovery**: Dual backend—OpenAI for web search operations (job sources, networking events) with structured output; OpenRouter for coaching and general LLM tasks with tool calling and conversation history.
- **Resume/Cover/Job tools**: Unified LLM facade primarily backed by OpenRouter (GPT-4o, Claude 3.5, Gemini 1.5, o1/o3, etc.). Model pickers surface available options and capabilities (reasoning support, images).
- **Document extraction**: Defaults to Gemini (`google/gemini-2.0-flash-001`) with configurable model ID in Settings.
- **Text-to-speech**: OpenAI TTS with streaming playback.
- API keys are required for OpenAI (onboarding + TTS + Discovery web search), OpenRouter (general LLM tasks + Discovery coaching), and Gemini (PDF/doc extraction).

## Getting Started

### Prerequisites
- macOS 14.0 (Sonoma) or later
- Xcode 15+
- API keys for: OpenAI (required for onboarding + TTS), OpenRouter (general LLM calls), Gemini (document extraction)

### Install & Run
1) Clone:
```bash
git clone https://github.com/cculbreath/Sprung.git
cd Sprung
```
2) Download Chrome Headless Shell (required for PDF generation):
```bash
./Scripts/download-chromium.sh
```
3) Open the project:
```bash
open Sprung.xcodeproj
```
4) Resolve packages if Xcode does not auto-resolve: `File → Packages → Resolve Package Versions`.
5) Build:
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung build 2>&1 | grep -Ei "(error:|warning:|failed|succeeded)" | head -20
```
6) Launch and open **Settings** (`Cmd + ,`):
   - Enter OpenAI, OpenRouter, and Gemini keys (stored in macOS Keychain).
   - Pick default onboarding, PDF extraction, and Git ingest models; adjust reasoning effort and overflow-fix attempts.
7) If prompted, open the Template Editor to create/import a Mustache template (templates are required for exports).

### Common Build Commands
- Quick check:
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung build 2>&1 | grep -Ei "(error:|warning:|failed|succeeded)" | head -20
```
- Release build:
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung -configuration Release build 2>&1 | grep -Ei "(error:|warning:|failed|succeeded)" | head -20
```
- Clean build:
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung clean build
```
- Resolve packages:
```bash
xcodebuild -resolvePackageDependencies -project Sprung.xcodeproj
```

## Dependencies

| Package | Purpose |
| --- | --- |
| [SwiftOpenAI (custom fork)](https://github.com/jamesrochabrun/SwiftOpenAI) | OpenAI Responses + tool calling, TTS |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | Job posting scraping and HTML parsing |
| [GRMustache.swift](https://github.com/groue/GRMustache.swift) | Mustache templating for resume/cover exports |
| [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON) | Dynamic JSON handling for resumes and onboarding artifacts |
| [swift-collections](https://github.com/apple/swift-collections) | Deques/ordered sets used across stores |
| [swift-chunked-audio-player](https://github.com/cculbreath/swift-chunked-audio-player) | Streaming audio playback for TTS |
| [ViewInspector](https://github.com/nalexn/ViewInspector) | UI testing utilities (not currently exercised) |

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for details. There is no automated test suite today—please verify builds locally before opening a PR.

## License

MIT License. See [LICENSE](LICENSE).

---

*Built by [Christopher Culbreath](https://github.com/cculbreath)*
