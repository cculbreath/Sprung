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

Sprung is a native macOS application that transforms how you approach job searching. Instead of spending hours manually tailoring resumes and cover letters for each application, Sprung combines a structured resume editor, AI-powered content generation, and application tracking into a unified workflow.

![Sprung Main Interface](docs/images/main-interface.png)

## Why Sprung?

Job seekers face a common problem: crafting compelling, tailored application materials takes significant time, and tracking multiple applications across companies becomes chaotic. Sprung solves this by:

- **Building your professional knowledge base** through an AI interview that extracts and organizes your experience
- **Generating tailored materials** using your actual background, not generic templates
- **Maintaining context** across applications so you never lose track of what you sent where
- **Storing everything locally** with your API keys secured in macOS Keychain

## Features

### Resume Studio

A split-view editor where you work with your resume data on the left while seeing a live PDF preview on the right.

![Resume Editor](docs/images/resume-editor.png)

- **Tree-based data model**: Your resume is stored as structured JSON, not formatted text. This enables AI to work with discrete facts rather than parsing documents.
- **Version control**: Create multiple resume versions tailored to different role types (e.g., "Backend Engineer", "Technical Lead")
- **Mustache templating**: Professional PDF generation using customizable templates
- **Export options**: PDF, plain text, or JSON for use with other tools

### AI Onboarding Interview

A conversational agent that interviews you to build your professional profile and work history timeline.

![Onboarding Interview](docs/images/onboarding-interview.png)

- **Structured extraction**: The AI asks targeted questions to capture your experience as discrete, reusable facts
- **Document ingestion**: Upload existing resumes, LinkedIn exports, or portfolio content for the AI to parse
- **Git repository analysis**: Point the AI at your code projects to extract technical accomplishments
- **Progressive refinement**: The interview spans multiple phases, from basic contact info through deep-dive experience exploration

### Cover Letter Generation

Generate cover letters that draw from your actual experience, not generic phrases.

![Cover Letter Writer](docs/images/cover-letter.png)

- **Job description analysis**: Paste a job posting and the AI identifies key requirements
- **Experience matching**: Your knowledge base is searched for relevant accomplishments
- **Multi-model support**: Compare outputs from different AI models side-by-side
- **Text-to-speech**: Listen to generated content with streaming audio playback

### Job Application Tracker

A Kanban-style board for tracking applications through your pipeline.

![Application Tracker](docs/images/job-tracker.png)

- **Status workflow**: New → Unsubmitted → Submitted → Interview Pending → Offer → Closed
- **Context linking**: Associate specific resume versions and cover letters with each application
- **Web scraping**: Paste a job URL and automatically extract company, title, and description
- **Application notes**: Track interview feedback, contacts, and follow-up items

### Multi-Model AI Support

Bring your own API keys for the models you prefer:

| Provider | Models |
|----------|--------|
| **OpenAI** | GPT-4o, GPT-4 Turbo |
| **Anthropic** | Claude 3.5 Sonnet, Claude 3 Opus |
| **Google** | Gemini 1.5 Pro |
| **OpenRouter** | Access to 100+ models |

All API keys are stored securely in the **macOS Keychain** and never leave your machine.

## Architecture

Sprung uses a **Hybrid Event-Driven + Reactive Architecture** designed for stability and clean separation of concerns:

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

- **StateCoordinator (Actor)**: Single source of truth for all state. Mutations flow through this actor for consistency.
- **EventCoordinator**: Pub/sub messaging using `AsyncStream` topics for cross-component communication.
- **SwiftUI @Observable**: UI reactivity layer. Views bind to observable state without tight coupling to business logic.
- **SwiftData**: Modern persistence for Resumes, Job Applications, Cover Letters, and Templates.

For architectural details, see [.arch-spec.md](.arch-spec.md).

## Project Structure

```
Sprung/
├── App/                    # Application entry point, settings, windows
│   ├── SprungApp.swift     # @main entry point
│   ├── AppDelegate.swift   # Multi-window management
│   └── Views/              # Settings, template editor
├── Resumes/                # Resume builder and export
│   ├── Models/             # Resume data model
│   ├── Services/           # Export coordination
│   └── Views/              # Editor UI
├── CoverLetters/           # Cover letter generation
│   ├── AI/Services/        # LLM-powered generation
│   └── TTS/Services/       # Text-to-speech streaming
├── JobApplications/        # Application tracking
│   ├── Models/             # JobApp data model
│   └── Views/              # Kanban board UI
├── Onboarding/             # AI interview system
│   ├── Core/               # StateCoordinator, EventCoordinator
│   ├── Handlers/           # Business logic
│   ├── Phase/              # Interview phase scripts
│   ├── Tools/              # AI tool definitions
│   └── Views/              # Interview UI
├── ResumeTree/             # Tree-based resume data model
├── Templates/              # Mustache template system
├── DataManagers/           # SwiftData stores
├── Shared/                 # Utilities, LLM clients, UI components
│   ├── AI/Models/          # LLM client abstractions
│   └── Utilities/          # Logger, helpers
└── Export/                 # PDF and text generation
```

## Getting Started

### Prerequisites

- **macOS 14.0** (Sonoma) or later
- **Xcode 15.0+** (for building from source)
- At least one AI provider API key (OpenAI, Anthropic, Google, or OpenRouter)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/cculbreath/Sprung.git
   cd Sprung
   ```

2. **Open in Xcode:**
   ```bash
   open Sprung.xcodeproj
   ```

3. **Resolve dependencies:**

   Xcode should automatically resolve Swift Package Manager dependencies. If not:
   ```
   File → Packages → Resolve Package Versions
   ```

4. **Build and run:**

   Press `Cmd + R` or:
   ```bash
   xcodebuild -project Sprung.xcodeproj -scheme Sprung build
   ```

### Configuration

On first launch, open **Settings** (menu bar → Sprung → Settings, or `Cmd + ,`) to enter your API keys.

![Settings](docs/images/settings.png)

Keys are stored in the **macOS Keychain** and are never:
- Written to disk in plaintext
- Synced to iCloud
- Transmitted except to the respective AI provider

## Dependencies

| Package | Purpose |
|---------|---------|
| [SwiftOpenAI](https://github.com/jamesrochabrun/SwiftOpenAI) | OpenAI API client (custom fork with tool support) |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | HTML parsing for job posting extraction |
| [GRMustache.swift](https://github.com/groue/GRMustache.swift) | Template rendering for PDF generation |
| [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON) | Dynamic JSON handling for resume data |
| [swift-collections](https://github.com/apple/swift-collections) | Apple collections library |
| [swift-chunked-audio-player](https://github.com/cculbreath/swift-chunked-audio-player) | Streaming TTS audio playback |

## Building

### Quick build with error filtering:
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung build 2>&1 | grep -Ei "(error:|warning:|failed|succeeded)"
```

### Release build:
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung -configuration Release build
```

### Clean build:
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung clean build
```

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Quick start for contributors:

1. Fork the repository
2. Create a feature branch from `main`
3. Make changes following existing code style
4. Ensure the project builds without errors
5. Submit a pull request with a clear description

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with Swift, SwiftUI, and SwiftData
- AI capabilities powered by OpenAI, Anthropic, and Google APIs
- PDF templating via GRMustache.swift
- HTML parsing via SwiftSoup

---

*Built by [Christopher Culbreath](https://github.com/cculbreath)*
