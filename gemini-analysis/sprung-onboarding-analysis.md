# Code Analysis: sprung-onboarding.swift.txt

Here is the comprehensive code review of the Sprung Onboarding module.

### Executive Summary
The codebase represents a sophisticated, AI-driven onboarding flow. It recently underwent a significant refactor to move from a monolithic architecture to a service-oriented one (Dependency Injection via `OnboardingDependencyContainer`).

**Key Architectural Observation:** The system is currently in a "hybrid" state. While logic has been moved to specialized services (e.g., `ToolHandler`, `UIResponseCoordinator`), the main `OnboardingInterviewCoordinator` remains as a massive "God Proxy," forwarding calls to these new services rather than Views interacting with services directly. This results in significant boilerplate code.

---

### 1. Legacy Cleanup (Refactoring Remnants)

These items appear to be artifacts of the recent refactor that were left behind or only partially migrated.

#### Safe to Delete Immediately

1.  **File:** `Sprung/Onboarding/Core/ConversationContextAssembler.swift`
    *   **Issue:** Empty Method Stub.
    *   **Description:** `buildScratchpadSummary` returns an empty string and is likely a remnant of a previous context assembly strategy before `WorkingMemory` was implemented in `LLMMessenger`.
    *   **Code:**
        ```swift
        func buildScratchpadSummary() async -> String {
            return ""
        }
        ```

2.  **File:** `Sprung/Onboarding/Core/OnboardingConstants.swift`
    *   **Issue:** Unused Enum Extensions.
    *   **Description:** `OnboardingToolName.timelineTools` creates a Set of raw strings. While used in `SessionUIState`, `rawValues` helper methods are largely redundant given direct Set initialization is often cleaner.
    *   **Code:**
        ```swift
        extension OnboardingToolName {
            static func rawValues(_ tools: [OnboardingToolName]) -> [String] { ... }
            // ...
        }
        ```

3.  **File:** `Sprung/Onboarding/Core/ArtifactRepository.swift`
    *   **Issue:** Unused Method.
    *   **Description:** `scratchpadSummary()` generates a string representation of artifacts, likely for the old `ConversationContextAssembler`. The new `LLMMessenger` builds its own `WorkingMemory` string directly via `listArtifactSummaries()`.
    *   **Code:**
        ```swift
        func scratchpadSummary() -> [String] {
            var lines: [String] = []
            // ... logic to build summary ...
            return lines
        }
        ```

#### Requires Verification / Needs Completion

4.  **File:** `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`
    *   **Issue:** The "God Proxy" Pattern (Incomplete Migration).
    *   **Description:** This class acts as a massive passthrough. It exposes methods that simply forward calls to `toolRouter`, `uiResponseCoordinator`, or `artifactIngestionCoordinator`.
    *   **Recommendation:** Views should interact with the specific coordinators/handlers exposed by the `OnboardingDependencyContainer` or the `OnboardingInterviewCoordinator` should expose the *handlers* (e.g., `var uploads: UploadInteractionHandler`) rather than wrapping every single method.
    *   **Code:**
        ```swift
        // Example of 50+ methods like this:
        func completeUpload(id: UUID, fileURLs: [URL]) async -> JSON? {
            await tools.completeUpload(id: id, fileURLs: fileURLs)
        }
        ```

5.  **File:** `Sprung/Onboarding/Constants/OnboardingConstants.swift`
    *   **Issue:** Competing State Machines (`InterviewSubphase`).
    *   **Description:** The system uses `ObjectiveWorkflowEngine` (new) to drive progress via Objectives, but *also* retains `InterviewSubphase` (old) to calculate tool bundles in `ToolBundlePolicy`.
    *   **Problem:** `ToolBundlePolicy.inferSubphase` contains massive `switch` logic trying to map Objectives/UI State back to a `Subphase`. This is fragile.
    *   **Recommendation:** Deprecate `InterviewSubphase`. Define allowed tools directly in the `PhaseScript` or `ObjectiveWorkflow` configuration, removing the need to infer a "subphase" to determine tool availability.

---

### 2. Critical Issues (Stability & Concurrency)

1.  **File:** `Sprung/Onboarding/Handlers/UploadInteractionHandler.swift`
    *   **Issue:** Synchronous I/O on Main Thread/Actor.
    *   **Description:** `handleTargetedUpload` is an `async` function on a `@MainActor` class, yet it calls `Data(contentsOf: ...)` inside a `Task.detached` block that returns to the main actor context, but `applicantProfileStore.save` (which might write to disk) happens on Main. More critically, `Image(nsImage: ...)` initialization from data happens on Main in `ApplicantProfileSummaryCard`.
    *   **Specific Concern:** `validateImageData` reads data. If `processed.first` is a large file, this might hitch.
    *   **Code:**
        ```swift
        // In handleTargetedUpload
        let data = try await Task.detached {
            try Data(contentsOf: first.storageURL) // Good, background
        }.value
        // ...
        applicantProfileStore.save(profile) // SwiftData/CoreData on Main? Potentially blocking.
        ```

2.  **File:** `Sprung/Onboarding/Services/DocumentExtractionService.swift`
    *   **Issue:** Unbounded File Reading.
    *   **Description:** `extractPlainText` reads the entire file content into a String or Data object in memory. For a very large PDF or text file (e.g., 100MB log file renamed to .txt), this could crash the app.
    *   **Recommendation:** Implement a file size limit check *before* attempting to read `Data(contentsOf: fileURL)`.
    *   **Code:**
        ```swift
        guard let fileData = try? Data(contentsOf: fileURL) else { ... }
        ```

3.  **File:** `Sprung/Onboarding/Core/AgentActivityTracker.swift`
    *   **Issue:** Unsafe Array Access.
    *   **Description:** The class is `@MainActor`, but `agents` is modified by `trackAgent` (insert at 0) and accessed by index in `markRunning`, `appendTranscript`, etc. If an agent is removed (e.g. `pruneCompletedAgents`) while an async task tries to update it by ID via `firstIndex`, it might be safe, but relying on `firstIndex` followed by subscript `agents[index]` is risky if `prune` happens in between (though Actor isolation helps here, logical race conditions exist).
    *   **Recommendation:** Use a Dictionary `[String: TrackedAgent]` keyed by ID instead of an Array to prevent index-out-of-bounds logic errors and improve lookup performance from O(n) to O(1).

---

### 3. High Priority (Architecture & Anti-Patterns)

1.  **File:** `Sprung/Onboarding/Core/ArtifactRepository.swift`
    *   **Issue:** `nonisolated(unsafe)` usage.
    *   **Description:** Several properties are marked `nonisolated(unsafe)` to allow synchronous access (`artifactRecordsSync`, `applicantProfileSync`).
    *   **Why it's bad:** This bypasses actor isolation protections. If `artifacts.artifactRecords` (internal) is updated while a view reads `artifactRecordsSync`, you have a race condition unless you guarantee strictly that updates *only* happen on the thread reading them (Main), which isn't guaranteed by `Actor` semantics alone.
    *   **Recommendation:** Move this state to `OnboardingUIState` (which is `@MainActor`) if it needs to be observed by SwiftUI, or accept `await` access.

2.  **File:** `Sprung/Onboarding/Core/OnboardingToolRegistrar.swift`
    *   **Issue:** Hardcoded Tool Registration.
    *   **Description:** The registrar manually instantiates every tool. If a new tool is added but not added to this list, it fails silently or requires debugging.
    *   **Code:**
        ```swift
        toolRegistry.register(GetUserOptionTool(coordinator: coordinator))
        toolRegistry.register(GetUserUploadTool(coordinator: coordinator))
        // ... 30+ lines of this
        ```
    *   **Recommendation:** Use a protocol-based discovery or a list iteration if possible, though manual registration is acceptable if the list is maintained carefully. The bigger issue is that `ToolRegistry` relies on `OnboardingInterviewCoordinator` for *every* tool, reinforcing the "God Object" anti-pattern.

3.  **File:** `Sprung/Onboarding/Views/Components/OnboardingInterviewView.swift`
    *   **Issue:** Massive View / Logic Leakage.
    *   **Description:** The main view handles window dragging, view transitions, settings logic, resume prompts, and debug overlays.
    *   **Recommendation:** Extract `OnboardingInterviewContainer` logic (the window/chrome management) from the actual `InterviewContent`. Move the "Resume/Start Over" logic into the ViewModel.

---

### 4. Medium Priority (Duplication & Code Quality)

1.  **File:** `Sprung/Onboarding/Services/GitIngestionKernel.swift`
    *   **Issue:** Hardcoded Binary Paths.
    *   **Description:** The code assumes git is located at `/usr/bin/git`. While standard on macOS, it might vary or be managed by Xcode/Homebrew.
    *   **Code:**
        ```swift
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        ```
    *   **Recommendation:** Use `/usr/bin/env git` or configuration to find the git executable.

2.  **File:** `Sprung/Onboarding/Tools/Shared/MiscSchemas.swift` vs. Tool Definitions
    *   **Issue:** JSON Schema Definition Duplication.
    *   **Description:** Schemas are defined in `MiscSchemas`, `ArtifactSchemas`, `UserInteractionSchemas`, and sometimes inline in Tools.
    *   **Recommendation:** The `SchemaBuilder` in `SchemaGenerator.swift` is a great start. Standardize *all* tools to use `SchemaBuilder` to define their parameters, making them type-safe(r) and easier to read than raw Dictionaries/`JSONSchema` initializers.

3.  **File:** `Sprung/Onboarding/Services/DocumentProcessingService.swift`
    *   **Issue:** Hardcoded Model IDs.
    *   **Description:** Fallback model IDs are hardcoded in multiple places.
    *   **Code:**
        ```swift
        let modelId = UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId") ?? "google/gemini-2.0-flash-001"
        ```
    *   **Recommendation:** Centralize all model ID constants in `OnboardingModelConfig`.

---

### 5. Low Priority / Suggestions

1.  **File:** `Sprung/Onboarding/Models/Extensions/JSONViewHelpers.swift`
    *   **Suggestion:** The extension on `JSON` (SwiftyJSON) adds UI formatting logic (`formattedLocation`, `formattedDateRange`).
    *   **Refinement:** Move this logic to a specific `ResumeFormatter` or `TimelineViewModel`. Extending a generic library type like `JSON` with domain-specific UI logic pollutes the namespace.

2.  **File:** `Sprung/Onboarding/Services/GitAgent/GitAnalysisAgent.swift`
    *   **Suggestion:** The `run()` method is very long (cyclomatic complexity).
    *   **Refinement:** Extract the tool execution loop and the response parsing logic into separate private methods.

3.  **File:** `Sprung/Onboarding/Core/StreamQueueManager.swift`
    *   **Suggestion:** `instanceId` is generated but rarely used except for logging.
    *   **Refinement:** Ensure loggers actually use it to trace specific stream sessions, otherwise it's noise.

### Summary of Refactoring Steps

1.  **Phase 1 (Safety):** Fix the `nonisolated(unsafe)` properties in `ArtifactRepository` and the synchronous I/O in `UploadInteractionHandler`.
2.  **Phase 2 (Cleanup):** Remove `InterviewSubphase` and refactor `ToolBundlePolicy` to use `Phase` + `ObjectiveStatus` directly. Delete the empty stubs in `ConversationContextAssembler`.
3.  **Phase 3 (Architecture):** Decouple `OnboardingInterviewCoordinator`. Make Views call `coordinator.tools.upload...` instead of `coordinator.completeUpload...`. Remove the forwarding methods from the main coordinator.