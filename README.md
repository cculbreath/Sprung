# Sprung: Your AI-Powered Job Search Copilot for macOS

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue.svg)](https://www.apple.com/macos/sonoma)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-15.0%2B-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Sprung is a native macOS application that streamlines your entire job search workflow. From finding job postings to crafting the perfect resume and cover letter, Sprung uses the power of generative AI to help you land your dream job.

![Sprung App Screenshot](https://via.placeholder.com/800x450.png?text=Sprung+App+Screenshot)
*(Add a screenshot or GIF of the app here)*

## ✨ Key Features

*   **📝 AI-Powered Resume & Cover Letter Crafting:**
    *   Generate, review, and version your resumes.
    *   Build JSON-backed resume templates.
    *   Export to professional-looking PDFs.
    *   Write data-driven cover letters that are tailored to each job description.
    *   Get AI-powered suggestions and talking points.
    *   Listen to your cover letters with on-device Text-to-Speech.

*   **🗃️ Smart Job Application Tracking:**
    *   Keep all your job applications in one place.
    *   Store links, descriptions, salaries, and other important details.
    *   Assign specific resumes and cover letters to each application.

*   **🤖 Interactive Document Chat:**
    *   "Chat" with your resumes and cover letters.
    *   Ask for feedback, request rewrites, and get suggestions for improvement.
    *   Let the AI analyze your documents and highlight missing keywords.

*   **🎙️ AI Onboarding Interview:**
    *   Get started quickly with an AI-powered onboarding interview that helps you build your applicant profile.

## 🚀 Why Sprung?

Most job search tools only solve one part of the problem. Sprung is an all-in-one solution that brings everything together in a single, beautiful, and native macOS application. With its powerful AI features, Sprung helps you create high-quality application materials that stand out from the crowd.

## 🛠️ Getting Started

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/cculbreath/Sprung.git
    cd Sprung
    ```

2.  **Open the project in Xcode:**
    ```bash
    open Sprung.xcodeproj
    ```

3.  **Resolve Swift Package dependencies (first run):**
    ```bash
    xcodebuild -resolvePackageDependencies -project Sprung.xcodeproj -scheme Sprung
    ```

4.  **Add your API keys:**
    *   You'll need API keys for OpenAI, Gemini, and/or OpenRouter.
    *   Add them in the "Settings" screen of the app. Keys are securely stored in the macOS Keychain.

5.  **Build and run the app (⌘ + R).**

## 🏗️ Technology & Architecture

Sprung is built with modern Apple technologies:

*   **SwiftUI:** For a beautiful and responsive user interface.
*   **SwiftData:** for robust and efficient data persistence.
*   **Generative AI:** A flexible architecture that supports multiple LLMs (OpenAI, Gemini, OpenRouter).

The app uses a dependency injection pattern to manage dependencies and ensure a clean and maintainable codebase. For a deeper dive into the architecture, see [`docs/architecture.md`](docs/architecture.md).

## 🙌 Contributing

We welcome contributions from the community! Whether you want to fix a bug, add a new feature, or improve the documentation, your help is appreciated.

Please read our [Contributing Guidelines](CONTRIBUTING.md) to get started.

## 🗺️ Roadmap

We have exciting plans for the future of Sprung! Here are some of the things we're working on:

*   Expanding our test coverage.
*   Adding more advanced AI features.
*   Improving the resume export pipeline.

For a more detailed look at our roadmap, please see [`docs/roadmap.md`](docs/roadmap.md).

## 📄 License

Sprung is released under the MIT License. See [LICENSE](LICENSE) for details and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for bundled dependency attributions.
