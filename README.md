# Sprung: AI-Powered Job Search Copilot for macOS

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue.svg)](https://www.apple.com/macos/sonoma)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Sprung** is a native macOS application designed to streamline your entire job search workflow. By combining a robust resume builder, job application tracker, and powerful Generative AI, Sprung helps you craft tailored application materials and land your dream job.

![Sprung Dashboard](docs/images/dashboard.png)

## Key Features

*   **AI-Powered Resume Studio:**
    *   **Split-View Editor:** Edit your resume data (JSON-backed) while seeing a live PDF preview.
    *   **Version Control:** Create and manage multiple versions of your resume tailored to different roles.
    *   **Templating:** Robust Mustache-based templating system for professional PDF exports.
    *   **Smart Tree Structure:** Resume data is stored in a flexible tree structure, allowing for deep customization without breaking the schema.

*   **Generative AI Integration:**
    *   **Cover Letter Writer:** Generate data-driven cover letters tailored specifically to a job description.
    *   **Onboarding Interview:** A conversational AI agent interviews you to build your initial "Applicant Profile" and work history timeline.
    *   **Document Chat:** "Chat" with your documents to get feedback, rewrite suggestions, and identify missing keywords.
    *   **Multi-Model Support:** Bring your own keys for OpenAI (GPT-4o), Anthropic (Claude 3.5 Sonnet), Google (Gemini 1.5 Pro), or OpenRouter.

*   **Job Application Tracker:**
    *   **Kanban Workflow:** Track applications from "Draft" to "Applied" to "Interviewing" and "Offer".
    *   **Context Awareness:** Link specific resumes and cover letters to each job application so you never lose track of what you sent.
    *   **Web Scraping:** Automatically extract job details from URLs (via SwiftSoup).

## Architecture

Sprung is built with a **Hybrid Event-Driven + Reactive Architecture** designed for stability and clean separation of concerns:

*   **StateCoordinator (Actor):** The Single Source of Truth. All state mutations flow through this actor to ensure data consistency.
*   **EventCoordinator:** Handles process orchestration (e.g., LLM request/response cycles) using `AsyncStream` topics.
*   **SwiftUI @Observable:** Used strictly for UI reactivity. Views bind to observable state for smooth updates without tight coupling to business logic.
*   **SwiftData:** Modern persistence layer for storing Resumes, Job Applications, and History.

For a deeper dive, check out [.arch-spec.md](.arch-spec.md).

## Getting Started

### Prerequisites
*   macOS 14.0 (Sonoma) or later.
*   Xcode 15.0+ (for building from source).
*   API Key(s) for OpenAI, Anthropic, or OpenRouter.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/cculbreath/Sprung.git
    cd Sprung
    ```

2.  **Open in Xcode:**
    ```bash
    open Sprung.xcodeproj
    ```

3.  **Resolve Dependencies:**
    Xcode should automatically resolve Swift Package Manager dependencies (SwiftOpenAI, SwiftSoup, GRMustache.swift, etc.). If not, go to `File > Packages > Resolve Package Versions`.

4.  **Run:**
    Press `Cmd + R` to build and run.

### Configuration
Upon first launch, navigate to **Settings** (in the menu bar or app preferences) to enter your AI provider API keys. Keys are securely stored in the **macOS Keychain** and are never synced or exported.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---
*Built by Christopher Culbreath*