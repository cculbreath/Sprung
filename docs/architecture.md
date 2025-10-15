# Sprung Architecture Overview

Sprung is a SwiftUI-first macOS application that keeps every major concern in a
dedicated layer:

- **Views** – declarative SwiftUI screens composed from small, testable
  subviews. Views receive dependencies via `@Environment` or view-model
  initialisers.
- **View Models** – lightweight observable objects that prepare data for the
  UI, coordinate asynchronous work, and expose intent handlers.
- **Services** – feature-specific units (e.g. `CoverLetterService`,
  `ResumeExportService`) encapsulating business logic and API calls. Services
  depend on protocol abstractions for testability.
- **Stores** – SwiftData-backed models (`@Model`) surfaced to SwiftUI through
  helper stores (e.g. `JobAppStore`). Stores provide computed collections so
  UI stays in sync with persistence.
- **Infrastructure** – shared utilities such as logging, networking adapters,
  and the LLM façade that routes requests to OpenRouter/OpenAI/Gemini clients.

### Dependency Injection

`AppDependencies` constructs services and stores once per window scene and
injects them into the SwiftUI environment:

```swift
@main
struct SprungApp: App {
    let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            AppWindowView()
                .environment(dependencies.applicantProfileStore)
                .environment(dependencies.llmFacade)
                .environment(dependencies.jobAppStore)
        }
    }
}
```

### Resume & Cover Letter Pipeline

1. **SwiftData Models** capture applicant details, resumes, cover letters, and
   job applications.
2. **Services** orchestrate AI interactions using the LLM façade. Requests are
   represented as DTOs and parsed with SwiftyJSON for adaptability.
3. **Export Layer** converts resume trees into Mustache templates for HTML/PDF
   or creates plain text variants.
4. **UI Sheets & Commands** trigger actions through injected services, keeping
   UI logic minimal.

### LLM Facade

The LLM subsystem exposes capability-driven operations:

- Model catalogue with feature flags (streaming, tool use, TTS).
- Request builder/executor pair that normalises prompts across providers.
- Response parsers with strict error handling and logging.

Providers live in adapters so swapping OpenAI for another vendor touches only
the boundaries.

### Testing Strategy

Protocols and dependency injection make it straightforward to supply mocks. The
project currently focuses automated coverage on template builders and parsing
logic; UI flows are exercised manually. A future milestone is to extend the
ViewInspector test suite across critical views.
