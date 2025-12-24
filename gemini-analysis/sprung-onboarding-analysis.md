# Code Analysis: sprung-onboarding.swift.txt

Based on the comprehensive review of the `Sprung/Onboarding` module, here is the analysis regarding dead code, anti-patterns, duplication, and legacy cruft.

### 1. Legacy Cruft & Incomplete Migrations (Dedicated Section)

This module shows signs of a transition between a monolithic architecture and an event-driven actor system. Several components are explicitly marked as "Milestone M0" (MVP) or "First Pass".

**A. UI Stubs & WIPs (Safe to Delete/Update)**
*   **File:** `Sprung/Onboarding/Views/OnboardingInterviewView.swift`
*   **Issue:** The `ExtractionReviewSheet` confirmation action is a hardcoded stub explicitly marked as not implemented.
*   **Code:**
    ```swift
    onConfirm: { _, _ in
        Logger.debug("Extraction confirmation is not implemented in milestone M0.")
    },
    ```
*   **Recommendation:** Implement the logic to merge the extraction JSON into the `ApplicantProfile` or `Timeline`, or remove the sheet if extraction review is handled elsewhere (e.g., `DocumentArtifactHandler`).

*   **File:** `Sprung/Onboarding/Views/OnboardingCompletionReviewSheet.swift`
*   **Issue:** The UI contains explicit developer comments exposed to the user, indicating it is a temporary placeholder.
*   **Code:**
    ```swift
    Text("This screen is a first pass to avoid abrupt endings; we can expand it into a tabbed, per-asset feedback workflow.")
    ```
*   **Recommendation:** Remove the meta-commentary text view.

**B. Hardcoded Logic replacing Configuration**
*   **File:** `Sprung/Onboarding/Tools/Implementations/NextPhaseTool.swift`
*   **Issue:** The state transitions are hardcoded inside the tool implementation rather than relying purely on the `PhasePolicy` or `PhaseScript`.
*   **Code:** `switch currentPhase { case .phase1CoreFacts: nextPhase = .phase2DeepDive ... }`
*   **Recommendation:** Move transition logic entirely to `PhaseScriptRegistry` so the Tool acts as a generic trigger, asking the Registry "What is next?".

**C. Deprecated/Redundant Types**
*   **File:** `Sprung/Onboarding/Models/TimelineEntryDraft.swift`
*   **Issue:** Redundant model. `TimelineCard` exists and supports JSON serialization. `TimelineEntryDraft` mirrors it almost exactly but is used only in `TimelineCardEditorView`.
*   **Recommendation:** Consolidate usage to `TimelineCard` (struct) and `TimelineCardViewModel` (observable) to reduce type conversion boilerplate in `TimelineCardAdapter`.

---

### 2. Critical Issues (Fix Immediately)

**A. Force Unwrapping in Tool Execution**
*   **File:** `Sprung/Onboarding/Tools/Implementations/CreateTimelineCardTool.swift` (and others)
*   **Issue:** Force unwrapping dictionary values after helper checks. If `requireObject` implementation changes or returns a different type, this crashes.
*   **Code:**
    ```swift
    _ = try ToolResultHelpers.requireObject(params["fields"].dictionary, named: "fields")
    let fields = JSON(params["fields"].dictionary!) // Crash risk if dictionary is nil despite check
    ```
*   **Recommendation:** Bind the result of `requireObject` directly:
    ```swift
    let fieldsDict = try ToolResultHelpers.requireObject(params["fields"].dictionary, named: "fields")
    let fields = JSON(fieldsDict)
    ```

**B. Race Conditions in Data Store**
*   **File:** `Sprung/Onboarding/Core/ArtifactRepository.swift`
*   **Issue:** Use of `nonisolated(unsafe)` to expose sync properties from an actor for UI binding. While convenient for SwiftUI, this bypasses actor isolation guarantees and risks data races if background threads update the actor state while the main thread reads these properties.
*   **Code:** `nonisolated(unsafe) private(set) var artifactRecordsSync: [JSON] = []`
*   **Recommendation:** Remove `nonisolated(unsafe)`. Use `@MainActor` on the `OnboardingUIState` to hold the "view" copy of the data, and have the `ArtifactRepository` emit events to update the UI state asynchronously.

---

### 3. High Priority Issues

**A. Stringly-Typed Event Routing**
*   **File:** `Sprung/Onboarding/Core/Coordinators/CoordinatorEventRouter.swift`
*   **Issue:** The router logic relies heavily on raw string matching for Objective IDs and Tool Names, bypassing the type safety of `OnboardingObjectiveId` and `OnboardingToolName` enums.
*   **Code:** `if id == "applicant_profile" && newStatus == "completed"`
*   **Recommendation:** Use the enums defined in `OnboardingConstants.swift`.
    ```swift
    if id == OnboardingObjectiveId.applicantProfile.rawValue ...
    ```

**B. "God Object" Coordinator**
*   **File:** `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`
*   **Issue:** This class exposes *every* internal service (state, eventBus, toolRouter, wizardTracker, etc.) publicly. It creates tight coupling between Views and the entire backend graph.
*   **Recommendation:** Create specific ViewModels for the sub-views (e.g., `DocumentCollectionViewModel`, `TimelineViewModel`) that only expose the specific functions and state needed for those views, rather than passing the whole Coordinator.

**C. Hardcoded API/Model Fallbacks**
*   **File:** `Sprung/Onboarding/Services/DocumentExtractionService.swift`
*   **Issue:** Hardcoded model IDs buried in service logic.
*   **Code:** `private let defaultModelId = "gemini-2.0-flash"` and `UserDefaults.standard.string(...) ?? "google/gemini-2.0-flash-001"`
*   **Recommendation:** Move all Model ID configurations to `OnboardingModelConfig` or a unified `ModelProvider` struct to ensure consistency and easier updates.

---

### 4. Medium Priority (Anti-Patterns & Duplication)

**A. Distributed Prompt Management**
*   **File:** Various (Tool Implementations, PhaseScripts, Services)
*   **Issue:** Prompts are scattered.
    *   `PhaseOneScript.swift`: Contains `introductoryPrompt`.
    *   `KCAgentPrompts.swift`: Contains agent system prompts.
    *   `DocumentExtractionPrompts.swift`: Contains extraction prompts.
    *   `AgentReadyTool.swift`: Contains workflow summary strings.
*   **Recommendation:** Centralize all prompt strings into a `PromptLibrary` or grouped resource files. This makes tweaking system personalities or instructions significantly easier.

**B. JSON Schema Duplication**
*   **File:** `Sprung/Onboarding/Tools/Schemas/`
*   **Issue:** `MiscSchemas` defines schemas for `workItemSchema`, `educationItemSchema`, etc. These structures (JSON Resume standard) likely exist elsewhere in the core app or `ExperienceDefaultsDraft`.
*   **Recommendation:** If the core app has `Codable` structs for JSON Resume, use `Encoder` reflection or a shared schema generator to create these JSONSchemas, ensuring the AI tools always match the internal data models.

**C. Massive View Body**
*   **File:** `Sprung/Onboarding/Views/Components/OnboardingInterviewChatPanel.swift`
*   **Issue:** The `body` property is very large, containing logic for banners, scroll readers, dividers, and input fields.
*   **Recommendation:** Extract the `ComposerView`, `BannerView`, and `MessageListView` into separate, smaller SwiftUI components.

**D. Tool Gating Logic Complexity**
*   **File:** `Sprung/Onboarding/Core/SessionUIState.swift`
*   **Issue:** `ToolGating.availability` contains hardcoded sets of tools (`timelineTools`) inside the method logic.
*   **Code:** `static let timelineTools: Set<String> = [...]`
*   **Recommendation:** Move these groupings to `OnboardingToolName` as static properties (e.g., `OnboardingToolName.timelineTools`) to reuse them in the `PhaseScript` definitions and avoid drift.

---

### 5. Dead Code Detection

**A. Unused / Redundant Enum Cases**
*   **File:** `Sprung/Onboarding/Constants/OnboardingConstants.swift`
*   **Item:** `OnboardingToolName.getUserOption`
*   **Observation:** While defined, `ConfigureEnabledSectionsTool` seems to replace the generic `getUserOption` for the specific case of section selection. If `getUserOption` is no longer used for generic choices in the scripts, it can be removed.

**B. Orphaned Logic in Git Agent**
*   **File:** `Sprung/Onboarding/Services/GitAgent/AgentPrompts.swift`
*   **Item:** `authorFilter` parameter.
*   **Observation:** The system prompt builder accepts an `authorFilter`, but in `GitIngestionKernel`, it is populated with `gitData["contributors"].array?.first?["name"].string`. This logic effectively locks analysis to the *first* contributor found in shortlog, which might be incorrect for multi-author repos or if the user isn't the top contributor.

**C. Unused Properties**
*   **File:** `Sprung/Onboarding/Core/AgentActivityTracker.swift`
*   **Item:** `cachedTokens` in `TrackedAgent`.
*   **Observation:** It is incremented in `addTokenUsage`, but `totalTokens` calculation is `inputTokens + outputTokens`. It is displayed in the UI, but logically `totalTokens` usually implies billable load or total context, which might be misleading if cache isn't factored in or out explicitly.

### 6. Code Duplication

**A. Artifact/File Type Checking**
*   **Locations:**
    *   `DropZoneHandler.swift`: `acceptedExtensions` set.
    *   `DocumentArtifactMessenger.swift`: `extractableExtensions` set (different list).
    *   `DocumentArtifactHandler.swift`: `extractableExtensions` set (different list).
    *   `DocumentExtractionService.swift`: `extractPlainText` checks extensions.
*   **Recommendation:** Create a single `DocumentTypePolicy` struct that defines what extensions are accepted, which are extractable text, and which are images.

**B. Timeline Serialization**
*   **Locations:**
    *   `TimelineCardAdapter.swift`
    *   `OnboardingValidationReviewCard.swift` (`timelineJSON` method)
*   **Recommendation:** `OnboardingValidationReviewCard` manually reconstructs JSON from drafts. It should use `TimelineCardAdapter` or `ExperienceDefaultsEncoder` exclusively to ensure the JSON sent for validation matches exactly what the system processes.