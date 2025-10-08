# Physics Cloud Résumé

Physics Cloud Résumé is a native macOS application that stream-lines every
step of the modern job–search workflow: collecting postings, tailoring
résumés, generating cover letters, tracking application status and even
auditing your material with Gen-AI.  The project is written entirely in Swift
using SwiftUI for the interface and Swift Data for local persistence.

---

## Why another job-search app?

Most tools only focus on one piece of the puzzle (e.g. a résumé builder or
an application tracker).  Physics Cloud Résumé keeps everything in the same
place **and** adds an opinionated AI layer so you can

* 📝 **Generate, review & version résumés** – import existing files or build
  JSON-backed templates that can be exported to PDF through the
  `resume.physicscloud.net` API.
* 💌 **Write data-driven cover letters** – the AI module can
  cross-reference a job posting with your skills, suggest talking points and
  even read the final draft aloud with on-device TTS.
* 🗃 **Track job applications** – store links, descriptions, salaries and
  assign assets (résumés / cover letters) to each posting.
* 🤖 **Chat with your documents** – ask follow-up questions, request
  rewrites or let the model highlight missing keywords.

## High-level architecture

```
┌──────────────────┐    Dependency container    ┌────────────────────┐
│     SwiftUI      │ ─────────────────────────▶ │  LLM Facade + DTOs │
│  (macOS target)  │  `.environment(AppDeps)`   │  (streaming/JSON)   │
│                  │                            │                    │
└────────┬─────────┘                            └────────┬───────────┘
         │ observation                                async services
         ▼                                               │
┌──────────────────┐  SwiftData stores (JobApp, …) ┌──────▼───────────┐
│   SwiftData      │ ─────────────────────────────▶│ Resume export &  │
│  (Model layer)   │                               │ template builder │
└──────────────────┘                               └──────────────────┘
```

Key points

• **AppDependencies** – A lightweight DI container constructed once per scene
  ensures stores (`JobAppStore`, `EnabledLLMStore`, …) and services (`LLMFacade`,
  `LLMService`) have stable lifetimes. Views receive them via
  `.environment(deps.someStore)`.

• **SwiftData first** – All primary entities (`JobApp`, `Resume`, `CoverLetter`,
  …) are `@Model` types. Their stores expose computed collections so SwiftUI
  always reflects persistent state without manual refreshes.

• **LLM facade & adapters** – Feature code talks to a small DTO-based facade.
  Vendor SDK types are contained in adapters (`SwiftOpenAIClient`) so switching
  providers only touches the boundary layer.

• **Export pipeline** – `ResumeTemplateProcessor` builds Mustache contexts from
  the resume tree. `ResumeExportService` orchestrates template selection and
  file I/O, while `NativePDFGenerator` and `TextResumeGenerator` focus purely on
  rendering. UI sheets (menu commands, toolbar actions) invoke these services
  through the injected dependencies.

For a deep dive into the AI sub-system take a look at
`PhysCloudResume/AI/README.md`.

## Folder overview

```
Assets.xcassets/        App icons & custom SF Symbols
Docs/                   Planning docs & canonical résumé JSON
PhysCloudResume/        Source code (SwiftUI, SwiftData, AI module, …)
├─ App/                 @main entry-point & high-level state
├─ AI/                  LLM clients, services, providers & views
├─ DataManagers/        SwiftData store helpers
├─ Resumes/, CoverLetters/, JobApplications/ …
├─ Shared/              Cross-feature utilities
Tests/                  XCTRuntimeAssertions based unit tests
```

## Requirements

* macOS 14 Sonoma or newer (because SwiftData + SwiftUI 5)
* Xcode 15 or newer (Swift 5.9)
* API keys
  * `OPENAI_API_KEY` / `GEMINI_API_KEY` (environment or Keychain)
  * OpenRouter (or compatible) key stored via the in-app settings UI. Keys are
    persisted with `APIKeyManager` which wraps the macOS Keychain.

## Getting started

1. Clone the repo

   ```bash
   git clone https://github.com/your-org/PhysCloudResume.git
   cd PhysCloudResume
   ```

2. Open the Xcode project

   ```bash
   open PhysCloudResume.xcodeproj
   ```

3. Add your API keys to the *Physics Cloud Résumé* target → *Signing & 
   Capabilities* → *Environment Variables* (or export them in your shell).

4. Build & run. The app stores exports alongside the résumé record and exposes
   a quick preview inside the Resume Export panel.

## Running tests

`⌘` + `U` runs `xcodebuild test` for the `PhysCloudResume` scheme. Current
coverage focuses on template builders and AI DTO transforms; UI coverage is
manual for now.

## Manual smoke checklist

1. Launch the app, confirm the sidebar loads job applications, and switch tabs
   (Listing → Resume → Cover Letters) to verify SwiftData-backed stores persist
   selection state.
2. Open **Clarify & Customize** from the toolbar, select a model, and ensure the
   clarifying question sheet appears. Submit answers and confirm the revision
   review sheet opens with streaming output when supported by the model.
3. Export a résumé as PDF from the Résumé menu, verify the export succeeds, and
   open the generated file from the export panel.
4. Update the OpenRouter key in Settings → Debug Settings, then trigger a basic
   AI action (e.g., résumé review) to confirm the facade reconfigures without a
   restart.

## Contributing

Pull requests are welcome!  Please follow the existing code style
(Swift-Format default) and keep **changes minimal & focused**.

1. Fork → feature branch (`git checkout -b feature/my-thing`)
2. Run `swift test` or `⌘U`
3. Submit a PR describing *why* the change is needed.

## Roadmap

See `Docs/plan-and-progress.md` for the full migration checklist.  Short-term
goals include

• Expand integration tests around the resume export pipeline and template builder
• Add streaming TTS controls with structured logging
• Harden the résumé export API and move the key out of source-control

## License

The repository is currently *proprietary / all-rights-reserved* while I finish
MVP development.  If you would like to use any part of the code please reach
out first.
