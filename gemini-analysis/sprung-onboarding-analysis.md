# Code Analysis: sprung-onboarding.swift.txt

Here is a comprehensive code review of the `Sprung/Onboarding` module.

## Executive Summary

The Onboarding module is a sophisticated, event-driven system coordinating SwiftUI views, LLM interactions (via `SwiftOpenAI`), and local data persistence (`SwiftData`). The architecture utilizes a "Coordinator" pattern heavily, though the central `OnboardingInterviewCoordinator` has grown into a "God Object."

The codebase generally exhibits high quality with strong separation of concerns via sub-handlers (`ToolHandler`, `ProfileInteractionHandler`) and services. However, there are significant performance risks regarding file I/O on the Main Actor, several instances of code duplication in tool definitions, and potential memory management issues in the event coordination layer.

---

### 1. Critical Issues (Fix Immediately)

These issues present immediate risks to app stability, UI responsiveness, or data integrity.

**1.1. Synchronous File I/O on Main Actor**
**File:** `Sprung/Onboarding/Handlers/UploadInteractionHandler.swift`
**Issue Type:** Anti-Pattern / Performance
**Description:** The class is annotated with `@MainActor`. In `handleTargetedUpload`, file data is read synchronously using `Data(contentsOf:)`. If a user uploads a large image (e.g., a high-res scan), this will freeze the UI.
**Code Snippet:**
```swift
// Inside @MainActor class UploadInteractionHandler
private func handleTargetedUpload(target: String, processed: [OnboardingProcessedUpload]) async throws {
    // ...
    guard let first = processed.first else { ... }
    // BLOCKING CALL ON MAIN THREAD
    let data = try Data(contentsOf: first.storageURL) 
    // ...
}
```
**Recommendation:** Move the file reading to a detached Task or background actor before passing the data back to the Main Actor logic.

**1.2. Unsafe Force Unwrapping of File Paths**
**File:** `Sprung/Onboarding/Utilities/OnboardingUploadStorage.swift` & `InterviewDataStore.swift`
**Issue Type:** Anti-Pattern / Crash Risk
**Description:** `FileManager` URL retrieval uses array indexing `[0]` without checking for emptiness. While unlikely to fail on standard macOS configurations, it is unsafe.
**Code Snippet:**
```swift
// OnboardingUploadStorage.swift
init() {
    let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] // Crash risk
    // ...
}
```
**Recommendation:** Use `first` and a guard/throw pattern or a safe fallback.

**1.3. Potential Infinite Loop in Tool Recovery**
**File:** `Sprung/Onboarding/Core/StateCoordinator.swift`
**Issue Type:** Anti-Pattern
**Description:** In `handleProcessingEvent`, if a stream error occurs, the system attempts to retry pending tool responses. If the error persists (e.g., a deterministic API error), `eventBus.publish` calls will trigger the loop repeatedly with a 2-second sleep, potentially spamming the event bus and the API.
**Code Snippet:**
```swift
// handleProcessingEvent
if error.hasPrefix("Stream error:") {
    if let pendingPayloads = await llmStateManager.getPendingToolResponsesForRetry() {
        // ... sleeps 2 seconds ...
        await eventBus.publish(...) // Triggers new request -> potentially new error -> loop
    }
}
```
**Recommendation:** Implement an exponential backoff or a strict retry limit within the `StateCoordinator` itself, rather than relying solely on the `LLMStateManager`'s retry counter which resets on successful submission (but here the submission fails).

---

### 2. High Priority (Architectural & Quality)

**2.1. God Object Pattern: OnboardingInterviewCoordinator**
**File:** `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`
**Issue Type:** Anti-Pattern
**Description:** This class acts as a facade for the entire module. It exposes properties from the Dependency Container directly and proxies dozens of methods to underlying services (`timelineManagementService`, `artifactQueryCoordinator`, etc.). It makes the class hard to test and maintain.
**Code Snippet:**
```swift
// It proxies everything:
func createTimelineCard(...) { await timelineManagementService.createTimelineCard(...) }
func updateTimelineCard(...) { await timelineManagementService.updateTimelineCard(...) }
func deleteTimelineCard(...) { await timelineManagementService.deleteTimelineCard(...) }
// ... dozens more
```
**Recommendation:** Instead of proxying every method, expose the sub-services (e.g., `var timeline: TimelineManagementService { container.timelineManagementService }`) and let views call `coordinator.timeline.update(...)`.
**Dev Note** Be mindful of the ideals expressed in .arch-spec -- If the module has outgrown .arch-spec and we need to re-evaluate code boundaries, we should do that before refactoring OnboardingInterviewCoordinator

**2.2. Unbounded Event History Growth**
**File:** `Sprung/Onboarding/Core/OnboardingEvents.swift`
**Issue Type:** Anti-Pattern / Memory Leak Risk
**Description:** `EventCoordinator` keeps an `eventHistory` array. It caps at 10,000 events. While capped, 10,000 `OnboardingEvent` enums (which can contain large JSON payloads or Base64 strings in `llmSendUserMessage`) can consume significant memory.
**Code Snippet:**
```swift
private var eventHistory: [OnboardingEvent] = []
private let maxHistorySize = 10000 
```
**Recommendation:** Reduce `maxHistorySize` to 1,000 for production builds or make the history optional/debug-only using `#if DEBUG`. Ensure heavy payloads (like Base64 images) are stripped before storing in history.

**2.3. Git Process Blocking Actor**
**File:** `Sprung/Onboarding/Services/GitIngestionKernel.swift`
**Issue Type:** Anti-Pattern
**Description:** `runGitCommand` uses `Process.run()` and `process.waitUntilExit()`. Since `GitIngestionKernel` is an actor, this synchronously blocks the actor from processing other messages while waiting for the shell command (which could hang or take seconds).
**Code Snippet:**
```swift
private func runGitCommand(...) throws -> String {
    // ... setup process ...
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile() // Blocking I/O
    process.waitUntilExit() // Blocking wait
    return String(data: data, encoding: .utf8) ?? ""
}
```
**Recommendation:** Use `FileHandle` async reading or wrap the blocking call in a `Task.detached`.

---

### 3. Medium Priority (Duplication & Cleanup)

**3.1. Tool Definition Duplication**
**File:** `Sprung/Onboarding/Tools/Implementations/CreateTimelineCardTool.swift` vs `UpdateTimelineCardTool.swift`
**Issue Type:** Unnecessary Duplication
**Description:** These tools share nearly identical schema definitions and logic structures.
**Recommendation:** Create a shared `TimelineToolSchema` struct or helper to generate the parameter JSONSchema, reducing risk of divergence.

**3.2. Manual JSON Schema Definitions**
**File:** `Sprung/Onboarding/Tools/Schemas/*.swift`
**Issue Type:** Anti-Pattern / Maintenance
**Description:** JSON Schemas are manually constructed using dictionary literals and helper functions. This is error-prone.
**Code Snippet:**
```swift
static let workItemSchema = JSONSchema(
    type: .object,
    properties: [
        "name": JSONSchema(type: .string, ...),
        // ...
    ]
)
```
**Recommendation:** Use a `Codable` to `JSONSchema` generator or a more type-safe builder pattern to ensure the schema matches the Swift structs used for decoding later.

**3.3. Hardcoded Prompt Strings**
**File:** `Sprung/Onboarding/Phase/*Script.swift` and `KCAgentPrompts.swift`
**Issue Type:** Anti-Pattern
**Description:** Massive multi-line string literals containing system prompts are embedded directly in Swift code. This makes them hard to edit or version control independently of the code logic.
**Recommendation:** Move prompts to separate resource files (e.g., `.txt` or `.json` in the bundle) or a configuration manager that can be updated remotely without an app update.

---

### 4. Dead Code & Unused Elements

**4.1. Unused Tool Identifier Case**
**File:** `Sprung/Onboarding/Core/ToolHandler.swift`
**Item:** `OnboardingToolIdentifier.getMacOSContactCard`
**Description:** This enum case exists, but `OnboardingToolRegistrar` does not register a tool with this name. The functionality exists in `ProfileInteractionHandler` but is triggered via UI, not an LLM tool call.
**Recommendation:** Remove the enum case if it's not intended to be exposed to the LLM.

**4.2. Unused Sub-Objectives**
**File:** `Sprung/Onboarding/Constants/OnboardingConstants.swift`
**Item:** `OnboardingObjectiveId` (Deeply nested cases)
**Description:** Cases like `applicantProfileProfilePhoto.evaluate_need` or `evidenceAuditCompleted.analyze` appear unused in the provided Phase scripts. The Phase scripts (`PhaseOneScript`, etc.) tend to reference the parent IDs or specific leaf nodes, but not the intermediate logic steps defined in the enum.
**Recommendation:** Audit and remove unused enum cases to clarify the actual state machine.

**4.3. Unused Property in `OnboardingModelConfig`**
**File:** `Sprung/Onboarding/Constants/OnboardingConstants.swift`
**Item:** `userDefaultsKey`
**Description:** The static string is defined but the property `currentModelId` uses the string literal "onboardingInterviewDefaultModelId" (or similar variations found in `OnboardingInterviewView`) rather than referencing this constant consistently.
**Recommendation:** Refactor all UserDefaults lookups to use this constant.

**4.4. Redundant Extraction Method Enum**
**File:** `Sprung/Onboarding/Views/Components/PersistentUploadDropZone.swift`
**Item:** `LargePDFExtractionMethod`
**Description:** This enum is defined inside the view file but also referenced in `DocumentExtractionService`.
**Recommendation:** Move to a shared model file (`Sprung/Onboarding/Models`) to avoid circular dependencies or confusion if the view file is excluded from a target.

---

### 5. Specific Logic Flaws

**5.1. Token Usage Logic in AgentRunner**
**File:** `Sprung/Onboarding/Services/AgentRunner.swift`
**Description:** The runner emits token usage events via `eventBus.publish`. However, `TokenUsageTracker` listens to the event bus on `MainActor`. If `AgentRunner` is running in a background context (which it is), there is a risk of high-frequency event publishing overwhelming the main thread listener if agents are chatty.
**Recommendation:** Ensure `TokenUsageTracker` buffers updates or throttles UI repaints.

**5.2. Tool Gating Logic**
**File:** `Sprung/Onboarding/Core/SessionUIState.swift`
**Description:** `getAllowedToolsForCurrentPhase` subtracts `excludedTools`. However, `waitingState` logic overrides this by returning an empty set or a specific subset. The interaction between `excludedTools`, `phasePolicy.allowedTools`, and `waitingState` is complex and spread across `SessionUIState` and `LLMStateManager`.
**Recommendation:** Centralize the "Effective Allowed Tools" calculation logic into a single pure function that takes (Phase, WaitingState, Exclusions) and returns `Set<String>`.

### 6. Duplication Candidates

1.  **Validation Views:** `KnowledgeCardReviewCard` and `ApplicantProfileReviewCard` share very similar structures (Header, Content Scroll, Footer Actions). They could be refactored into a generic `ReviewCard<Content>` component.
2.  **Tool Implementations:** `CreateTimelineCardTool`, `UpdateTimelineCardTool`, `DeleteTimelineCardTool` are thin wrappers around `coordinator` methods. They could potentially be a single `TimelineActionTool` with an `action` parameter ("create", "update", "delete"), reducing boilerplate.