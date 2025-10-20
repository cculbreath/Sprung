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

## 📚 Template Data Flow Cheat Sheet

Sprung separates *where* data originates from *how* it is rendered. Understanding the pipeline makes it easier to introduce new fields, wire up the Experience Editor, and avoid unintended regressions.

### Primary Data Sources

- **Applicant Profile (`ApplicantProfile` SwiftData model):** Onboarding records that capture name, headline, contact information, links, etc. When we build a render context, `ResumeTemplateContextBuilder.profileContext` maps these values into the sections referenced by the manifest’s `applicantProfile` bindings.
- **Experience Editor (`ExperienceDefaults` SwiftData model):** Stores reusable work, education, project, and skill entries. `ExperienceDefaultsEncoder` converts these records to the array-based JSON structure, and the builder merges them before template-specific data so they act as global defaults.
- **Template Seed (`TemplateSeedStore` per template):** Template-specific example content maintained from the Template Editor’s “Seed” tab. Seeds are merged after experience defaults, letting them override shared defaults for a single template without touching the runtime resume.
- **Resume Tree (`Resume.rootNode` of `TreeNode`s):** Once a resume exists, its content lives in a tree detached from the manifest/seed. `ResumeTemplateDataBuilder` walks that tree to produce Mustache-ready dictionaries. Tree nodes are created during JSON imports or template operations and persist independently—changing templates later won’t retroactively rewrite existing resumes.

### Manifest vs. Seed Responsibilities

- **Manifest (`TemplateManifest`):** Describes *shape*, *editor metadata*, and *behaviour*. Each section defines its fields, input types, repeatability, validation hints, and behaviors (styling, applicant profile bindings, etc.). Manifest overrides are stored per template and merged on load (see `TemplateManifestDefaults.apply`). They also expose structural hints like `keys-in-editor`, `transparentKeys`, and `editorLabels` used by the resume tree and Template Editor UI.
- **Seed:** Supplies *data*. Seeds are literal JSON payloads encoded in SwiftData. They never change the schema; they simply provide sample values that merge against the context at runtime.

### Merge Order (highest priority last)

1. **Manifest defaults** – `TemplateManifest.makeDefaultContext()` provides base values like styling or any section defaults encoded in the manifest.
2. **Experience defaults** – Converted through `ExperienceDefaultsEncoder.makeSeedDictionary` and merged in.
3. **Template seed** – Template-specific sample content.
4. **Applicant profile** – Mapped via the manifest’s applicant-profile bindings.
5. **Resume tree** – When rendering a specific resume, `ResumeTemplateDataBuilder` reads the stored `TreeNode`s, overriding earlier data with whatever the user saved.

`ResumeTemplateContextBuilder.mergeValue` handles all merge stages. Dictionaries merge recursively (unless both sides contain only scalars). Arrays now support **custom-only overlays**: if a seed entry only contains `custom` (and optional `__key`), the builder merges that `custom` payload onto the corresponding Experience Editor row instead of replacing the whole section.

### Tree Nodes & Template Independence

- `JsonToTree` and `ResumeTemplateDataBuilder` convert manifest-aware JSON into a tree of nodes. Each `TreeNode` records path metadata, user-entered values, and editor hints.
- Once nodes are created (for example, when a resume is generated), they survive template edits. Switching templates only changes how future renders interpret the tree; the underlying node values remain untouched—ensuring the resume content is stable.

### Key Manifest Flags

- **`keys-in-editor`** – Ordered list of paths that drives the Resume Editor’s view hierarchy (`TreeNode.rebuildViewHierarchy`). Helpful for flattening deeply nested JSON into a curated editor experience.
- **`transparentKeys`** – Allows the editor to “look through” container nodes when locating keys. Any section listed here gets skipped while walking the tree, keeping the editor hierarchy shallow even if the data model nests values.
- **`section-visibility` / `section-visibility-labels`** – Default on/off state and display labels for toggleable sections. `ResumeTemplateDataBuilder.applySectionVisibility` reads these to set `workBool`, `educationBool`, etc.
- **`sections` override** – The `sections` block in a manifest lets you replace or extend the schema for a specific section. For example, you can append custom fields to `education` without touching source defaults.

### Adding Custom Fields

**Manifest snippet (append to `sections.education`):**

```json
"sections": {
  "education": {
    "type": "arrayOfObjects",
    "titleTemplate": "{{studyType}} in {{area}}",
    "fields": [
      { "key": "institution", "input": "text", "required": true },
      { "key": "area", "input": "text" },
      {
        "key": "custom",
        "children": [
          { "key": "location", "input": "text", "placeholder": "San Luis Obispo, CA" }
        ]
      }
    ]
  }
}
```

**Seed overlay (merges onto Experience Editor rows):**

```json
{
  "education": [
    { "custom": { "location": "San Luis Obispo, CA" } },
    { "custom": { "location": "Kent, Ohio" } }
  ]
}
```

Because of the custom overlay support, the entries above augment existing education data from the Experience Editor instead of replacing the section outright. Include a `__key` (usually the array index or a known identifier) if you need to target a specific row explicitly.

### Runtime Template Rendering

1. `ResumeTemplateDataBuilder.buildContext` collects section keys from the resume tree and manifest.
2. For each section, it resolves behaviours (styling, font sizes, editor keys) and builds the concrete value (string, array, dictionary) expected by Mustache templates.
3. The resulting dictionary feeds both PDF/HTML rendering and plain-text exports. Templates reference values directly (e.g., `{{custom.location}}`) without hitting the file system or manifests at runtime in accordance with the project’s “no filesystem templates” rule.

Armed with the manifest schema, seeds, and `TreeNode` storage, you can safely introduce bespoke fields while keeping the Experience Editor, resume rendering, and AI workflows aligned.

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
