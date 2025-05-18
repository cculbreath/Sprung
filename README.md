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
┌──────────────────┐   Swift Package   ┌────────────────────┐
│     SwiftUI      │ ───────────────▶ │   AI Module (LLM)  │
│  (macOS target)  │                  │ • Client layer      │
│                  │                  │ • Services &        │
└────────┬─────────┘                  │   Providers        │
         │                           └────────┬───────────┘
         │  Observable objects                 │
         ▼                                      │  async/await
┌──────────────────┐                    ┌───────▼───────────┐
│   SwiftData      │  persistence      │ REST / OpenAI /   │
│  (Model layer)   │ ─────────────────▶ │ Gemini / TTS APIs │
└──────────────────┘                    └───────────────────┘
```

Key points

• **SwiftData first** – All primary entities (`JobApp`, `Resume`, `CoverLetter`,
  …) are `@Model` types persisted with SwiftData.  Dedicated stores such as
  `JobAppStore` and `ResRefStore` expose *computed* collections so the UI stays
  in sync automatically.

• **Pluggable AI clients** – `OpenAIClientProtocol` defines a thin facade that
  is currently implemented by both `SwiftOpenAIClient` and the MacPaw
  `OpenAI` SDK.  A factory decides which backend to use at runtime.

• **Service / provider split** –  Pure
  networking & prompt-building logic lives in the **Services** folder while
  higher-level, domain-specific operations are handled by **Providers** such as
  `ResumeChatProvider` or `CoverLetterRecommendationProvider`.

• **JSON → PDF pipeline** –  Résumé tree nodes are serialised to JSON, posted
  to `resume.physicscloud.net/build-resume-file` and the resulting PDF is
  downloaded back into the model (`ApiResumeExportService`).

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
  * Physics Cloud résumé export key – **currently hard-coded** in
    `ResumeExportService.swift` (TODO: move to secure storage)

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

4. Build & run – the app is sandboxed and uses the *Documents* directory to
   store exported PDFs.

## Running tests

`⌘` + `U` will run the test suite.  The current focus is on the pure-Swift AI
helpers – UI tests are planned but not yet implemented.

## Contributing

Pull requests are welcome!  Please follow the existing code style
(Swift-Format default) and keep **changes minimal & focused**.

1. Fork → feature branch (`git checkout -b feature/my-thing`)
2. Run `swift test` or `⌘U`
3. Submit a PR describing *why* the change is needed.

## Roadmap

See `Docs/plan-and-progress.md` for the full migration checklist.  Short-term
goals include

• Swap the remaining SwiftOpenAI code for the MacPaw client
• Add streaming TTS controls
• Harden the résumé export API and move the key out of source-control

## License

The repository is currently *proprietary / all-rights-reserved* while I finish
MVP development.  If you would like to use any part of the code please reach
out first.
