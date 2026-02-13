<p align="center">
  <img src="docs/images/hero_logo.png" alt="Sprung" width="400">
</p>

<p align="center">
  <strong>AI-Powered Job Search Copilot for macOS</strong>
</p>

<p align="center">
  <a href="https://www.apple.com/macos/sequoia"><img src="https://img.shields.io/badge/macOS-14.0%2B-blue.svg" alt="macOS"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-5.0-purple.svg" alt="SwiftUI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License"></a>
</p>

---

Sprung is a native macOS application that streamlines job searching. It keeps your data local, builds a structured knowledge base about your experience through an AI-guided interview, and uses multiple LLM backends to generate tailored resumes, cover letters, and application materials.

> **Status:** Actively developed. The application is functional end-to-end but not yet distributed as a signed release. Clone and build from source to try it.

<!-- screenshots -->

## Features

### AI Onboarding Interview
An interactive, multi-phase interview builds a structured profile of your career history:

- **Phase 1 — Core facts**: Contact info, profile photo, work timeline, and resume section selection.
- **Phase 2 — Deep dive**: Evidence-first generation of detailed knowledge cards (500–2,000+ words) per role or skill area, including Git repository analysis and artifact ingestion.
- **Phase 3 — Writing corpus**: Captures writing samples, stylistic preferences, and produces a candidate dossier for downstream drafting.
- **Document and repo ingestion**: Processes PDFs, Word documents, and plain text with Gemini-backed extraction. Imports LinkedIn and portfolio content. Scans Git repositories for accomplishments.

### Resume Workspace
- **Tree-based editor** with drag-and-drop nodes, structured array-based data, and live PDF preview.
- **AI revision flows**: One-click revisions, clarifying-question workflows, overflow fixing, and a reasoning overlay for supported models.
- **Experience defaults editor** for curating reusable sections (summary, skills, work, projects, education) that seed new resumes.
- **Versioning**: Create role-specific resume variants from a shared baseline.

### Cover Letters
- **Job-aware drafting** using the selected job posting, resume, knowledge cards, and cover references.
- **Multi-model committee**: Generate drafts across models, tally votes and scores, and review model reasoning to select a winner.
- **Inspector and revisions**: View sources, model feedback, and iterate on the same conversation thread.
- **Batch generation and export**: Generate multiple drafts in parallel, render to PDF, and preview with streaming text-to-speech.

### Job Applications
- **Kanban-style tracker** with status groups: New, In Progress, Unsubmitted, Submitted, Interview Pending, Follow Up Required, Offer, Closed, and Rejected.
- **URL scraping**: Paste a job URL to parse listings from LinkedIn, Indeed, Apple Careers, and other sites (SwiftSoup with WebView fallback for JavaScript-rendered pages).
- **Packet review**: LLM-driven analysis of your resume and cover letter against the job posting.
- **Job recommendations**: Rank new listings against your background to prioritize applications.

### Discovery (Job Search Operations)
- **Daily task management**: AI-generated task lists based on your goals and current progress, with focus area customization and time tracking.
- **Job source discovery**: AI-powered identification and categorization of job boards, recruiter sites, and company career pages.
- **Networking event pipeline**: Discover and evaluate professional events, generate pre-event prep materials, and capture post-event debriefs.
- **Professional networking CRM**: Contact database with relationship warmth tracking, interaction history, health assessment, and AI-drafted outreach messages.
- **Coaching sessions**: Automated three-phase sessions — check-in, personalized activity review, and actionable recommendations.
- **Weekly goals and reflection**: Set targets for applications, networking, and time investment with progress tracking and AI-generated reflections.

### Templates and Export
- **Mustache-based templates**: HTML/CSS themes with live preview and quick actions.
- **Output formats**: Native PDF, plain text, structured JSON, and text rendering for LLM prompts.
- **Built-in template editor**: Edit HTML/CSS with live preview; templates are stored locally for full control.

### Knowledge Cards and References
- **ResRefs**: Knowledge cards with metadata (type, organization, time period, sources) created during onboarding or added manually. Toggle inclusion per resume or browse the interactive card deck.
- **CoverRefs**: Writing samples and background facts for cover letter generation, including dossier entries from onboarding.

## Architecture

```
SwiftUI Views
    ↓  @Observable bindings
AppEnvironment (dependency injection container)
    ↓
Domain Stores (SwiftData-backed)
    ↓
Services (LLMFacade, export, scraping, TTS, templates)
    ↓
SwiftData + Keychain + local assets
    ↓
External providers (Anthropic, OpenRouter, OpenAI TTS, Google Gemini)
```

- **SwiftUI + @Observable**: Views bind to stores and view models injected through `AppEnvironment`.
- **Dependency injection**: `AppDependencies` constructs long-lived services per scene — no singletons.
- **Unified LLM layer**: `LLMFacade` routes requests to the appropriate backend; model pickers surface capabilities (reasoning, image support).
- **Persistence**: SwiftData models with Keychain-backed API key storage.
- **Export pipeline**: Mustache template rendering to PDF via Chrome Headless Shell, with text renderers for LLM prompts.

## Project Structure

```
Sprung/
├── App/                # Entry point, environment, settings, windows, toolbar
├── Onboarding/         # Interview engine (state/event coordinators, phases, tools)
├── Discovery/          # Job search ops (coaching, tasks, sources, events, CRM)
├── Resumes/            # Resume models, AI revision flows, split editor
├── ResumeTree/         # Tree-based resume data and drag-drop node UI
├── CoverLetters/       # Generation, committee voting, inspector, PDF, TTS
├── JobApplications/    # Kanban tracker, scraping, application review
├── Experience/         # Experience defaults editor and section renderers
├── Templates/          # Mustache templates, manifests, template editor
├── ResRefs/            # Knowledge card models and card browser
├── DataManagers/       # SwiftData stores
├── Export/             # PDF and text generators
├── Shared/             # LLM facade, logging, utilities, model pickers, TTS
└── Resources/          # Static assets and default templates
```

## LLM Provider Support

| Area | Provider | Purpose |
|------|----------|---------|
| Onboarding interview | Anthropic Claude | Multi-turn interview with tool calling |
| Onboarding interview | Google Gemini | Document and artifact extraction |
| Resume, cover letter, job review | OpenRouter | Model selection across GPT, Claude, Gemini, etc. |
| Discovery coaching | OpenRouter | Coaching sessions with conversation history |
| Discovery web search | OpenAI | Structured output for source and event discovery |
| Text-to-speech | OpenAI | Streaming TTS with chunked audio playback |

API keys are required for Anthropic (onboarding), OpenAI (TTS + Discovery web search), OpenRouter (general LLM tasks), and Gemini (document extraction). All keys are stored in the macOS Keychain.

## Getting Started

### Prerequisites
- macOS 14.0 (Sonoma) or later
- Xcode 15+
- API keys: Anthropic, OpenAI, OpenRouter, and Google Gemini

### Build and Run
```bash
git clone https://github.com/cculbreath/Sprung.git
cd Sprung
./Scripts/download-chromium.sh   # Chrome Headless Shell for PDF generation
open Sprung.xcodeproj
```

1. Resolve packages if Xcode does not do so automatically: **File → Packages → Resolve Package Versions**.
2. Build and run (`Cmd + R`).
3. Open **Settings** (`Cmd + ,`) and enter your API keys. Select models for onboarding, document extraction, and general tasks.
4. If prompted, open the Template Editor to create or import a Mustache template (required for PDF export).

## Dependencies

| Package | Purpose |
|---------|---------|
| [SwiftOpenAI (fork)](https://github.com/cculbreath/SwiftOpenAI-ttsfork) | OpenAI TTS and streaming support |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | HTML parsing for job posting scraping |
| [GRMustache.swift](https://github.com/groue/GRMustache.swift) | Mustache templating for resume and cover letter export |
| [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON) | Dynamic JSON handling for LLM interchange |
| [swift-collections](https://github.com/apple/swift-collections) | Ordered collections used across stores |
| [swift-chunked-audio-player](https://github.com/cculbreath/swift-chunked-audio-player) | Streaming audio playback for TTS |

## Related Repositories

| Repository | Description |
|------------|-------------|
| [SwiftOpenAI-ttsfork](https://github.com/cculbreath/SwiftOpenAI-ttsfork) | Customized SwiftOpenAI fork with TTS streaming support |
| [swift-chunked-audio-player](https://github.com/cculbreath/swift-chunked-audio-player) | Chunked audio player for streaming TTS playback |

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. There is no automated test suite — please verify builds locally before opening a pull request.

## License

MIT License. See [LICENSE](LICENSE).

---

*Built by [Christopher Culbreath](https://github.com/cculbreath)*
