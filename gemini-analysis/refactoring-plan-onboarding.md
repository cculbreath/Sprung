# Onboarding Module Refactoring Plan

## Executive Summary

This plan addresses architectural issues in the `Sprung/Onboarding/` module identified in the Gemini analysis. The module is in a "hybrid" state with incomplete migration from a monolithic architecture to a service-oriented design. This refactor completes that migration.

**Core Principles:**
- Complete implementation only - no stubs, no empty methods
- No backwards compatibility shims - delete legacy code entirely
- Full adoption of new paradigms - no dual state machines
- Regular commits after each discrete unit of work

---

## Parallel Work Streams

The refactoring is organized into **4 independent work streams** that can execute concurrently, plus a **final integration stream** that depends on all others completing.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PARALLEL EXECUTION PHASE                              │
├─────────────────┬─────────────────┬─────────────────┬─────────────────────────┤
│   Stream A      │   Stream B      │   Stream C      │   Stream D              │
│   Safety Fixes  │   State Machine │   God Proxy     │   Code Quality          │
│                 │   Unification   │   Elimination   │   Cleanup               │
│   (2 agents)    │   (1 agent)     │   (2 agents)    │   (1 agent)             │
└────────┬────────┴────────┬────────┴────────┬────────┴───────────┬─────────────┘
         │                 │                 │                     │
         └─────────────────┴─────────────────┴─────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │   Stream E: Integration       │
                    │   Final verification & build  │
                    │   (1 agent)                   │
                    └───────────────────────────────┘
```

---

## Stream A: Safety & Concurrency Fixes

**Agents Required:** 2 (can work in parallel on separate files)
**Dependencies:** None
**Scope:** `Sprung/Onboarding/Core/`, `Sprung/Onboarding/Handlers/`, `Sprung/Onboarding/Services/`

### A1: Fix Actor Isolation Violations

**Agent A1 Assignment:**

**Task 1: Eliminate `nonisolated(unsafe)` in ArtifactRepository**
- **File:** `Sprung/Onboarding/Core/ArtifactRepository.swift`
- **Problem:** Properties marked `nonisolated(unsafe)` bypass actor isolation protections, creating race conditions.
- **Solution:**
  - Remove `nonisolated(unsafe)` markers entirely
  - Move observable state needed by SwiftUI to `OnboardingUIState` (which is `@MainActor`)
  - Accept `await` access patterns for artifact data
  - Views should observe `OnboardingUIState.artifactRecords` rather than accessing repository directly
- **Implementation:**
  ```swift
  // DELETE these nonisolated(unsafe) properties
  // nonisolated(unsafe) var artifactRecordsSync: [ArtifactRecord] { ... }
  // nonisolated(unsafe) var applicantProfileSync: ApplicantProfile? { ... }

  // ADD to OnboardingUIState.swift instead:
  @MainActor @Observable
  final class OnboardingUIState {
      var artifactRecords: [ArtifactRecord] = []
      var applicantProfile: ApplicantProfile?
      // ... existing properties
  }
  ```
- **Commit:** "Remove nonisolated(unsafe) from ArtifactRepository, move observable state to UIState"

**Task 2: Convert AgentActivityTracker from Array to Dictionary**
- **File:** `Sprung/Onboarding/Core/AgentActivityTracker.swift`
- **Problem:** Array-based storage with index lookups is O(n) and prone to logical race conditions during concurrent access.
- **Solution:**
  - Replace `var agents: [TrackedAgent]` with `var agents: [String: TrackedAgent]`
  - Update all methods to use dictionary lookup by ID
  - Remove `firstIndex` usage entirely
- **Implementation:**
  ```swift
  // BEFORE
  var agents: [TrackedAgent] = []
  func markRunning(_ id: String) {
      guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
      agents[index].state = .running
  }

  // AFTER
  var agents: [String: TrackedAgent] = [:]
  func markRunning(_ id: String) {
      agents[id]?.state = .running
  }
  ```
  - Update `trackAgent` to use `agents[agent.id] = agent`
  - Update `pruneCompletedAgents` to use dictionary filtering
  - Update any views that iterate `agents` to use `agents.values`
- **Commit:** "Convert AgentActivityTracker to dictionary storage for O(1) lookups"

### A2: Fix I/O and Memory Safety Issues

**Agent A2 Assignment:**

**Task 1: Move Synchronous I/O Off Main Thread**
- **File:** `Sprung/Onboarding/Handlers/UploadInteractionHandler.swift`
- **Problem:** `applicantProfileStore.save()` potentially blocks main thread. Image/data operations may block.
- **Solution:**
  - Wrap all file I/O in `Task.detached` blocks
  - Ensure SwiftData saves happen on appropriate context
  - Move image validation to background
- **Implementation:**
  ```swift
  // Ensure all I/O is background:
  func handleTargetedUpload(...) async {
      let processedData = try await Task.detached {
          // ALL file reading here
          let data = try Data(contentsOf: fileURL)
          let validated = try self.validateImageData(data)
          return validated
      }.value

      // Only UI updates on main:
      await MainActor.run {
          // Update UI state only
      }
  }
  ```
- **Commit:** "Move all file I/O operations off main thread in UploadInteractionHandler"

**Task 2: Add File Size Limits to Document Extraction**
- **File:** `Sprung/Onboarding/Services/DocumentExtractionService.swift`
- **Problem:** Unbounded file reading can crash app with large files (100MB+).
- **Solution:**
  - Add file size validation before reading
  - Define maximum file sizes for each document type
  - Return clear error for oversized files
- **Implementation:**
  ```swift
  private enum FileSizeLimits {
      static let maxPDFSize: UInt64 = 50 * 1024 * 1024  // 50MB
      static let maxTextSize: UInt64 = 10 * 1024 * 1024 // 10MB
      static let maxImageSize: UInt64 = 20 * 1024 * 1024 // 20MB
  }

  func extractPlainText(from fileURL: URL) async throws -> String {
      let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      guard let size = attrs[.size] as? UInt64, size <= FileSizeLimits.maxTextSize else {
          throw DocumentExtractionError.fileTooLarge(maxSize: FileSizeLimits.maxTextSize)
      }
      // ... proceed with extraction
  }
  ```
- **Commit:** "Add file size validation to DocumentExtractionService"

**Task 3: Fix Git Binary Path Resolution**
- **File:** `Sprung/Onboarding/Services/GitIngestionKernel.swift`
- **Problem:** Hardcoded `/usr/bin/git` may not exist or may be wrong version.
- **Solution:**
  - Use `/usr/bin/env git` pattern
  - Or use `which git` to locate
- **Implementation:**
  ```swift
  // Use env to find git in PATH
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["git"] + gitArguments
  ```
- **Commit:** "Use /usr/bin/env for git path resolution"

---

## Stream B: State Machine Unification

**Agents Required:** 1
**Dependencies:** None
**Scope:** `Sprung/Onboarding/Constants/`, `Sprung/Onboarding/Core/`, `Sprung/Onboarding/Phase/`

### B1: Eliminate InterviewSubphase

**Problem:** The system has two competing state machines:
1. `ObjectiveWorkflowEngine` (new) - drives progress via Objectives
2. `InterviewSubphase` (old) - used to calculate tool bundles in `ToolBundlePolicy`

This creates fragile `inferSubphase` logic that maps Objectives back to Subphases.

**Solution:** Deprecate `InterviewSubphase` entirely. Define allowed tools directly in `PhaseScript` configuration.

**Task 1: Add Tool Configuration to PhaseScript**
- **File:** `Sprung/Onboarding/Phase/PhaseScript.swift`
- **Implementation:**
  ```swift
  protocol PhaseScript {
      var objectives: [ObjectiveWorkflow] { get }
      var allowedTools: Set<OnboardingToolName> { get }  // ADD THIS
      // ... existing properties
  }
  ```
- Update `PhaseOneScript.swift`, `PhaseTwoScript.swift`, `PhaseThreeScript.swift` to define their allowed tools directly
- **Commit:** "Add allowedTools configuration to PhaseScript protocol"

**Task 2: Refactor ToolBundlePolicy**
- **File:** `Sprung/Onboarding/Core/ToolBundlePolicy.swift`
- **DELETE:** The entire `inferSubphase` method and all `InterviewSubphase` switch logic
- **Implementation:**
  ```swift
  // BEFORE: Complex subphase inference
  func availableTools(for state: SessionUIState) -> Set<OnboardingToolName> {
      let subphase = inferSubphase(from: state)  // DELETE THIS
      switch subphase { ... }  // DELETE THIS
  }

  // AFTER: Direct phase script lookup
  func availableTools(for phase: InterviewPhase, script: PhaseScript) -> Set<OnboardingToolName> {
      return script.allowedTools
  }
  ```
- **Commit:** "Refactor ToolBundlePolicy to use PhaseScript.allowedTools directly"

**Task 3: Delete InterviewSubphase**
- **File:** `Sprung/Onboarding/Constants/OnboardingConstants.swift`
- **DELETE:** The entire `InterviewSubphase` enum
- **DELETE:** Any extension methods on `InterviewSubphase`
- Search codebase for any remaining references and remove them
- **Commit:** "Delete InterviewSubphase enum - replaced by PhaseScript.allowedTools"

**Task 4: Update SessionUIState**
- **File:** `Sprung/Onboarding/Core/SessionUIState.swift`
- Remove any `InterviewSubphase` references
- Remove the `timelineTools` string set if no longer needed
- **Commit:** "Remove InterviewSubphase references from SessionUIState"

---

## Stream C: God Proxy Elimination

**Agents Required:** 2 (can split by file groups)
**Dependencies:** None
**Scope:** `Sprung/Onboarding/Core/`, `Sprung/Onboarding/Views/`

### C1: Refactor OnboardingInterviewCoordinator

**Agent C1 Assignment:**

**Problem:** `OnboardingInterviewCoordinator` acts as a massive passthrough with 50+ methods that simply forward calls to specialized handlers.

**Solution:** Views should interact with handlers directly via dependency container, or the coordinator should expose handlers rather than wrapping every method.

**Task 1: Expose Handlers as Public Properties**
- **File:** `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`
- **Implementation:**
  ```swift
  // EXPOSE handlers directly instead of wrapping
  @Observable
  final class OnboardingInterviewCoordinator {
      // Public handler access
      let uploads: UploadInteractionHandler
      let profiles: ProfileInteractionHandler
      let prompts: PromptInteractionHandler
      let tools: ToolExecutionCoordinator
      let artifacts: ArtifactIngestionCoordinator

      // DELETE all forwarding methods like:
      // func completeUpload(id: UUID, fileURLs: [URL]) async -> JSON? {
      //     await tools.completeUpload(id: id, fileURLs: fileURLs)
      // }
  }
  ```
- **Commit:** "Expose handlers as public properties on OnboardingInterviewCoordinator"

**Task 2: Delete All Forwarding Methods**
- **File:** `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`
- Count and delete ALL methods that simply forward to handlers
- This should remove 50+ methods and hundreds of lines of boilerplate
- **Commit:** "Delete forwarding methods from OnboardingInterviewCoordinator"

### C2: Update Views to Use Handlers Directly

**Agent C2 Assignment:**

**Task 1: Update OnboardingInterviewView**
- **File:** `Sprung/Onboarding/Views/OnboardingInterviewView.swift`
- **Implementation:**
  ```swift
  // BEFORE
  await coordinator.completeUpload(id: id, fileURLs: urls)

  // AFTER
  await coordinator.uploads.completeUpload(id: id, fileURLs: urls)
  ```
- Apply this pattern to ALL coordinator method calls in the view
- **Commit:** "Update OnboardingInterviewView to use handlers directly"

**Task 2: Update OnboardingInterviewViewModel**
- **File:** `Sprung/Onboarding/ViewModels/OnboardingInterviewViewModel.swift`
- Same pattern: replace `coordinator.methodName()` with `coordinator.handler.methodName()`
- **Commit:** "Update OnboardingInterviewViewModel to use handlers directly"

**Task 3: Update All Component Views**
- **Files:** All files in `Sprung/Onboarding/Views/Components/`
- Apply the same handler access pattern
- **Commit:** "Update onboarding component views to use handlers directly"

---

## Stream D: Code Quality & Cleanup

**Agents Required:** 1
**Dependencies:** None
**Scope:** Various files across onboarding module

### D1: Delete Dead Code and Stubs

**Task 1: Delete Empty Stub in ConversationContextAssembler**
- **File:** `Sprung/Onboarding/Core/ConversationContextAssembler.swift`
- **DELETE:** The `buildScratchpadSummary()` method that returns empty string
- If the class becomes empty or only has unused methods, delete the entire file
- **Commit:** "Delete empty buildScratchpadSummary stub"

**Task 2: Delete Unused Methods in ArtifactRepository**
- **File:** `Sprung/Onboarding/Core/ArtifactRepository.swift`
- **DELETE:** `scratchpadSummary()` method - superseded by `LLMMessenger.listArtifactSummaries()`
- **Commit:** "Delete unused scratchpadSummary from ArtifactRepository"

**Task 3: Clean Up OnboardingConstants Extensions**
- **File:** `Sprung/Onboarding/Constants/OnboardingConstants.swift`
- **DELETE:** The `rawValues` helper method extension on `OnboardingToolName` if unused
- Verify no consumers before deletion
- **Commit:** "Remove unused OnboardingToolName extension methods"

### D2: Centralize Configuration

**Task 1: Centralize Model IDs**
- **File:** `Sprung/Onboarding/Services/DocumentProcessingService.swift` and others
- **Problem:** Model IDs are hardcoded in multiple places
- **Solution:** Move all to `OnboardingModelConfig` or similar central location
- **Implementation:**
  ```swift
  // Create or update: Sprung/Onboarding/Constants/OnboardingModelConfig.swift
  enum OnboardingModelConfig {
      static let pdfExtractionModel = "google/gemini-2.0-flash-001"
      static let interviewModel = "anthropic/claude-sonnet-4"
      // ... all other model IDs
  }
  ```
- Update all consumers to use centralized config
- **Commit:** "Centralize all model ID configuration"

### D3: Move Domain Logic Out of JSON Extensions

**Task 1: Extract UI Formatting from JSON Extensions**
- **File:** `Sprung/Onboarding/Models/Extensions/JSONViewHelpers.swift`
- **Problem:** `JSON` extensions contain domain-specific UI logic (`formattedLocation`, `formattedDateRange`)
- **Solution:** Move to dedicated `TimelineFormatter` or `ResumeFormatter` class
- **Implementation:**
  ```swift
  // Create: Sprung/Onboarding/Utilities/TimelineFormatter.swift
  struct TimelineFormatter {
      static func formattedLocation(_ json: JSON) -> String { ... }
      static func formattedDateRange(_ json: JSON) -> String { ... }
  }
  ```
- Update all callers to use new formatter
- Delete the JSON extension file
- **Commit:** "Move JSON formatting logic to TimelineFormatter"

### D4: Standardize Schema Definitions

**Task 1: Convert All Tools to Use SchemaBuilder**
- **Files:** `Sprung/Onboarding/Tools/Schemas/*.swift`, `Sprung/Onboarding/Tools/Implementations/*.swift`
- **Problem:** Schemas defined inconsistently across MiscSchemas, ArtifactSchemas, UserInteractionSchemas, and inline
- **Solution:** All tools use `SchemaBuilder` from `SchemaGenerator.swift`
- For each tool:
  1. Convert raw dictionary/JSONSchema to SchemaBuilder pattern
  2. Delete old schema definition
  3. Verify tool still works
- **Commit:** "Standardize all tool schemas to use SchemaBuilder" (or multiple commits per schema file)

---

## Stream E: Integration & Verification

**Agents Required:** 1
**Dependencies:** Streams A, B, C, D must complete first
**Scope:** Full onboarding module

### E1: Final Integration

**Task 1: Verify All Cross-References**
- Run grep/search for any remaining references to deleted items:
  - `InterviewSubphase`
  - `nonisolated(unsafe)`
  - Deleted forwarding methods
  - Old schema definitions
- Fix any remaining references

**Task 2: Build Verification**
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung build 2>&1 | grep -Ei "(error:|warning:|failed|succeeded)" | head -30
```

**Task 3: Verify Functionality**
- Ensure onboarding can be started
- Verify phase transitions work
- Confirm tool execution functions
- Test upload handling
- Validate artifact creation

**Commit:** "Complete onboarding module refactoring - verify build and functionality"

---

## Commit Checklist Summary

Each agent should commit after completing each discrete task. Expected commits:

**Stream A (6 commits):**
- [ ] Remove nonisolated(unsafe) from ArtifactRepository
- [ ] Convert AgentActivityTracker to dictionary storage
- [ ] Move file I/O off main thread in UploadInteractionHandler
- [ ] Add file size validation to DocumentExtractionService
- [ ] Use /usr/bin/env for git path resolution
- [ ] Stream A verification build

**Stream B (5 commits):**
- [ ] Add allowedTools configuration to PhaseScript
- [ ] Refactor ToolBundlePolicy to use PhaseScript.allowedTools
- [ ] Delete InterviewSubphase enum
- [ ] Remove InterviewSubphase references from SessionUIState
- [ ] Stream B verification build

**Stream C (5 commits):**
- [ ] Expose handlers as public properties
- [ ] Delete forwarding methods from coordinator
- [ ] Update OnboardingInterviewView to use handlers
- [ ] Update OnboardingInterviewViewModel to use handlers
- [ ] Update component views to use handlers

**Stream D (6 commits):**
- [ ] Delete empty buildScratchpadSummary stub
- [ ] Delete unused scratchpadSummary from ArtifactRepository
- [ ] Remove unused extension methods
- [ ] Centralize model ID configuration
- [ ] Move JSON formatting to TimelineFormatter
- [ ] Standardize tool schemas to use SchemaBuilder

**Stream E (1 commit):**
- [ ] Final integration verification

---

## Success Criteria

The refactoring is complete when:

1. **Zero `nonisolated(unsafe)` markers** remain in onboarding code
2. **Zero `InterviewSubphase` references** exist anywhere
3. **OnboardingInterviewCoordinator** has no forwarding methods (exposes handlers only)
4. **All schema definitions** use SchemaBuilder pattern
5. **No empty stubs or placeholder methods** remain
6. **Build succeeds** with no new warnings
7. **All file I/O** happens off main thread
8. **Model IDs** are centralized in single configuration
