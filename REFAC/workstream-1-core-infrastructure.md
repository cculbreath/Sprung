# Workstream 1: Core Infrastructure & Threading Safety

**Owner:** Developer A  
**Estimated Duration:** 5-6 days  
**Priority:** Critical (blocks open-sourcing)  
**Dependencies:** None (can proceed independently)

---

## Executive Summary

This workstream addresses the critical architectural issues in the Core infrastructure layer, focusing on the "god object" pattern in `OnboardingInterviewCoordinator`, threading safety violations, and simplifying the event system. These changes are foundational but isolated from UI and Services work.

---

## Scope & Boundaries

### In Scope
- `/Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift`
- `/Sprung/Onboarding/Core/StateCoordinator.swift`
- `/Sprung/Onboarding/Core/OnboardingEvents.swift`
- `/Sprung/Onboarding/Core/LLMMessenger.swift`
- `/Sprung/Onboarding/Core/AnthropicRequestBuilder.swift`
- `/Sprung/Onboarding/Models/ArtifactRecord.swift`
- `/Sprung/Onboarding/Stores/ArtifactRecordStore.swift`
- `/Sprung/Onboarding/Stores/OnboardingSessionStore.swift`

### Out of Scope (handled by other workstreams)
- UI layer views and components
- Services layer (FileSystemTools, agents, PDF extraction)
- Handlers (except consultation on event changes)

---

## Task Breakdown

### Task 1.1: Fix Critical Threading Safety Issues
**Effort:** 4 hours  
**Priority:** P0 - Critical

#### 1.1.1 Remove `@unchecked Sendable` from ArtifactRecord

**File:** `Models/ArtifactRecord.swift` (Line 307)

**Current Code:**
```swift
extension ArtifactRecord: @unchecked Sendable {}
```

**Problem:** Bypasses Swift concurrency safety guarantees. Could cause data races when ArtifactRecord is accessed from multiple actors.

**Solution Options (choose based on access patterns):**

**Option A - Make immutable after creation (preferred if applicable):**
```swift
// Remove extension entirely
// Ensure all mutation happens before sharing across actor boundaries
// Use copy-on-write or actor isolation for mutations
```

**Option B - Use actor isolation:**
```swift
// Create ArtifactRecordActor that wraps mutable access
actor ArtifactRecordActor {
    private var _record: ArtifactRecord
    
    func update(_ mutation: (inout ArtifactRecord) -> Void) {
        mutation(&_record)
    }
    
    var record: ArtifactRecord { _record }
}
```

**Option C - Make genuinely Sendable:**
```swift
// Audit all properties for Sendable conformance
// Use @unchecked Sendable ONLY for properties that are:
// - Immutable after init, OR
// - Protected by locks/actors
```

**Verification:**
```bash
# Build with strict concurrency checking
swift build -Xswiftc -strict-concurrency=complete
```

#### 1.1.2 Replace `unowned` with `weak` in Stores

**Files:**
- `Stores/ArtifactRecordStore.swift` (Line 15)
- `Stores/OnboardingSessionStore.swift` (Line 17)

**Current Pattern:**
```swift
private unowned let modelContext: ModelContext
```

**Problem:** `unowned` crashes if ModelContext is deallocated before store. This can happen during container teardown.

**Solution:**
```swift
private weak var modelContext: ModelContext?

// Update all methods to handle nil:
func someMethod() {
    guard let modelContext else {
        Logger.warning("ModelContext deallocated, skipping operation", category: .data)
        return
    }
    // proceed with operation
}
```

---

### Task 1.2: Extract Services from OnboardingInterviewCoordinator
**Effort:** 2-3 days  
**Priority:** P0 - Critical (god object)

The coordinator at 1318 lines handles too many responsibilities. Extract three focused services:

#### 1.2.1 Create `OnboardingDataResetService`

**Extract from:** Lines 239-271 (`clearAllOnboardingData()` and related methods)

**New File:** `Core/Services/OnboardingDataResetService.swift`

```swift
import Foundation

/// Service responsible for clearing all onboarding data
/// Extracted from OnboardingInterviewCoordinator to follow SRP
@MainActor
final class OnboardingDataResetService {
    private let knowledgeCardStore: KnowledgeCardStore
    private let skillStore: SkillStore
    private let coverRefStore: CoverRefStore
    private let sessionStore: OnboardingSessionStore
    private let artifactStore: ArtifactRecordStore
    private let eventBus: EventCoordinator
    
    init(
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        coverRefStore: CoverRefStore,
        sessionStore: OnboardingSessionStore,
        artifactStore: ArtifactRecordStore,
        eventBus: EventCoordinator
    ) {
        self.knowledgeCardStore = knowledgeCardStore
        self.skillStore = skillStore
        self.coverRefStore = coverRefStore
        self.sessionStore = sessionStore
        self.artifactStore = artifactStore
        self.eventBus = eventBus
    }
    
    /// Clear all onboarding data across all stores
    func clearAllOnboardingData() async {
        // Implementation extracted from coordinator
        Logger.info("🧹 Clearing all onboarding data", category: .general)
        
        // Delete session
        sessionStore.deleteCurrentSession()
        
        // Clear knowledge cards
        knowledgeCardStore.deleteOnboardingCards()
        
        // Clear skills
        skillStore.deleteOnboardingSkills()
        
        // Clear cover refs
        for coverRef in coverRefStore.storedCoverRefs {
            coverRefStore.deleteCoverRef(coverRef)
        }
        
        // Clear artifacts
        artifactStore.deleteAllArtifacts()
        
        // Emit event
        eventBus.emit(.dataCleared, topic: .state)
    }
    
    /// Clear only session-specific data (keep skills/cards for reuse)
    func clearSessionData() async {
        // Implementation
    }
}
```

**Update Coordinator:**
```swift
// In OnboardingInterviewCoordinator
private let dataResetService: OnboardingDataResetService

func clearAllOnboardingData() {
    Task {
        await dataResetService.clearAllOnboardingData()
    }
}
```

#### 1.2.2 Create `ArtifactArchiveManager`

**Extract from:** Lines 813-935 (artifact export, JSON conversion, archive management)

**New File:** `Core/Services/ArtifactArchiveManager.swift`

```swift
import Foundation
import SwiftyJSON

/// Manages artifact archive operations: export, JSON conversion, promotion/demotion
actor ArtifactArchiveManager {
    private let artifactStore: ArtifactRecordStore
    private let eventBus: EventCoordinator
    
    init(artifactStore: ArtifactRecordStore, eventBus: EventCoordinator) {
        self.artifactStore = artifactStore
        self.eventBus = eventBus
    }
    
    /// Convert ArtifactRecord to JSON representation
    func artifactRecordToJSON(_ record: ArtifactRecord) -> JSON {
        // Extract implementation from coordinator lines 813-870
    }
    
    /// Export all artifacts to filesystem for agent browsing
    func exportArtifactsForBrowsing(sessionId: String) async throws -> URL {
        // Extract implementation
    }
    
    /// Promote artifact from archived to active
    func promoteArtifact(_ artifactId: String) async throws {
        // Extract implementation
    }
    
    /// Demote artifact from active to archived
    func demoteArtifact(_ artifactId: String) async throws {
        // Extract implementation
    }
    
    /// Archive all session artifacts
    func archiveSessionArtifacts(sessionId: String) async throws {
        // Extract implementation
    }
}
```

#### 1.2.3 Create `DebugRegenerationService`

**Extract from:** Lines 1017-1315 (the large `#if DEBUG` block)

**New File:** `Core/Debug/DebugRegenerationService.swift`

```swift
#if DEBUG
import Foundation

/// Debug-only service for regenerating onboarding data
/// Useful for testing and development workflows
@MainActor
final class DebugRegenerationService {
    private let coordinator: OnboardingInterviewCoordinator
    private let artifactStore: ArtifactRecordStore
    private let llmFacade: LLMFacade
    
    init(
        coordinator: OnboardingInterviewCoordinator,
        artifactStore: ArtifactRecordStore,
        llmFacade: LLMFacade
    ) {
        self.coordinator = coordinator
        self.artifactStore = artifactStore
        self.llmFacade = llmFacade
    }
    
    /// Regenerate knowledge cards from existing artifacts
    func regenerateKnowledgeCards() async throws {
        // Extract implementation from coordinator
    }
    
    /// Regenerate skills from existing artifacts
    func regenerateSkills() async throws {
        // Extract implementation
    }
    
    /// Regenerate timeline from existing artifacts
    func regenerateTimeline() async throws {
        // Extract implementation
    }
    
    /// Full regeneration (cards + skills + timeline)
    func fullRegeneration() async throws {
        try await regenerateKnowledgeCards()
        try await regenerateSkills()
        try await regenerateTimeline()
    }
}
#endif
```

**Coordinator Updates:**
After extraction, the coordinator should:
1. Hold references to these three services
2. Delegate to them instead of implementing directly
3. Target size: ~800-900 lines (down from 1318)

---

### Task 1.3: Group OnboardingEvents into Nested Enums
**Effort:** 4-6 hours  
**Priority:** P1 - High

**File:** `Core/OnboardingEvents.swift` (770 lines, 80+ cases)

**Current Structure:**
```swift
enum OnboardingEvent {
    case processingStateChanged(...)
    case streamingMessageBegan(...)
    case artifactCreated(...)
    case phaseTransitionBegan(...)
    // 80+ more flat cases
}
```

**Proposed Structure:**
```swift
enum OnboardingEvent {
    // Group 1: LLM/Processing events
    case llm(LLMEvent)
    
    // Group 2: Artifact events
    case artifact(ArtifactEvent)
    
    // Group 3: Phase/Objective events
    case phase(PhaseEvent)
    
    // Group 4: UI events
    case ui(UIEvent)
    
    // Group 5: State events
    case state(StateEvent)
}

// Nested enums
extension OnboardingEvent {
    enum LLMEvent {
        case processingStateChanged(Bool, String?)
        case streamingMessageBegan(String, Int, String?)
        case streamingTextDelta(String)
        case streamingMessageCompleted(String)
        case toolCallStarted(String, String, String)
        case toolCallCompleted(String, JSON)
        case errorOccurred(String)
    }
    
    enum ArtifactEvent {
        case created(ArtifactRecord)
        case updated(ArtifactRecord)
        case deleted(String)
        case archived(String)
        case promoted(String)
        case metadataUpdated(String, [String: Any])
    }
    
    enum PhaseEvent {
        case transitionBegan(InterviewPhase, InterviewPhase)
        case transitionCompleted(InterviewPhase)
        case objectiveStarted(String)
        case objectiveCompleted(String)
        case objectiveSkipped(String)
    }
    
    enum UIEvent {
        case choicePromptPresented(OnboardingChoicePrompt)
        case choiceSelected(String, String)
        case uploadRequested(OnboardingUploadRequest)
        case uploadCompleted(String)
        case validationPromptPresented(...)
    }
    
    enum StateEvent {
        case sessionCreated(String)
        case sessionResumed(String)
        case sessionCompleted
        case dataCleared
        case wizardStepChanged(OnboardingWizardStep)
    }
}
```

**Migration Strategy:**
1. Create the nested enum structure
2. Add deprecated cases that forward to new structure
3. Update all emit sites to use new structure
4. Remove deprecated cases after all handlers updated

**Handler Updates Required:**
Each handler's `switch` statements need updating:
```swift
// Before
case .artifactCreated(let record):

// After
case .artifact(.created(let record)):
```

---

### Task 1.4: Extract Retry Logic in LLMMessenger
**Effort:** 2-3 hours  
**Priority:** P2 - Medium

**File:** `Core/LLMMessenger.swift`

**Problem:** Three methods (`executeUserMessageViaAnthropic`, `executeCoordinatorMessageViaAnthropic`, `executeToolResponseViaAnthropic`) each contain identical retry loop patterns.

**Solution:** Create a generic retry wrapper:

```swift
// New file: Core/LLMRetryExecutor.swift

/// Generic retry executor for LLM operations
actor LLMRetryExecutor {
    private let maxRetries: Int
    private let retryPolicy: LLMRetryPolicy
    
    init(maxRetries: Int = 3, retryPolicy: LLMRetryPolicy = .default) {
        self.maxRetries = maxRetries
        self.retryPolicy = retryPolicy
    }
    
    /// Execute an LLM operation with retry logic
    func execute<T: Sendable>(
        operation: @Sendable () async throws -> AsyncThrowingStream<T, Error>,
        onRetry: @Sendable (Int, Error) async -> Void = { _, _ in }
    ) async throws -> AsyncThrowingStream<T, Error> {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                guard retryPolicy.shouldRetry(error: error, attempt: attempt) else {
                    throw error
                }
                
                let delay = retryPolicy.delay(for: attempt)
                try await Task.sleep(for: .seconds(delay))
                await onRetry(attempt, error)
            }
        }
        
        throw lastError ?? LLMError.maxRetriesExceeded
    }
}

// Usage in LLMMessenger:
func executeUserMessageViaAnthropic(...) async throws -> AsyncThrowingStream<...> {
    try await retryExecutor.execute(
        operation: { [self] in
            try await anthropicClient.stream(request: request)
        },
        onRetry: { attempt, error in
            Logger.warning("Retry attempt \(attempt) after error: \(error)", category: .ai)
        }
    )
}
```

---

### Task 1.5: Create LLM Configuration Constants
**Effort:** 30 minutes  
**Priority:** P2 - Medium

**Files affected:**
- `Core/AnthropicRequestBuilder.swift`
- `Core/LLMMessenger.swift`
- Various agent files

**New File:** `Core/Config/OnboardingLLMConfig.swift`

```swift
import Foundation

/// Centralized LLM configuration constants
enum OnboardingLLMConfig {
    // Token limits
    static let maxTokens = 4096
    static let maxContextTokens = 100_000
    
    // Generation parameters
    static let temperature: Double = 1.0
    static let topP: Double = 1.0
    
    // Retry configuration
    static let maxRetries = 3
    static let initialRetryDelay: TimeInterval = 1.0
    static let maxRetryDelay: TimeInterval = 30.0
    
    // Timeouts
    static let streamTimeout: TimeInterval = 120.0
    static let toolExecutionTimeout: TimeInterval = 60.0
    
    // Agent limits
    static let maxAgentTurns = 50
    static let ephemeralMessageTurns = 5
}
```

---

### Task 1.6: Remove Pass-Through Methods from StateCoordinator
**Effort:** 3-4 hours  
**Priority:** P3 - Low

**File:** `Core/StateCoordinator.swift` (863 lines)

**Problem:** Lines 660-862 contain 20+ methods that are pure pass-through delegations:
```swift
func getArtifactRecord(id: String) async -> JSON? {
    await artifactRepository.getArtifactRecord(id: id)
}
```

**Solution Options:**

**Option A - Expose sub-coordinators (recommended):**
```swift
// Make repository public via protocol
protocol ArtifactRepositoryAccessible {
    var artifactRepository: ArtifactRepository { get }
}

extension StateCoordinator: ArtifactRepositoryAccessible {
    nonisolated var artifactRepository: ArtifactRepository { _artifactRepository }
}

// Callers access directly:
await coordinator.artifactRepository.getArtifactRecord(id: id)
```

**Option B - Create focused protocols:**
```swift
protocol ArtifactAccess {
    func getArtifact(id: String) async -> JSON?
    func getArtifactsForObjective(_ id: String) async -> [JSON]
}

// StateCoordinator conforms but delegates
extension StateCoordinator: ArtifactAccess {
    // Only expose what's needed
}
```

---

## Verification Checklist

### Build Verification
- [ ] `swift build` succeeds with no errors
- [ ] `swift build -Xswiftc -strict-concurrency=complete` has no new warnings
- [ ] All unit tests pass
- [ ] Integration tests pass

### Architecture Verification
- [ ] OnboardingInterviewCoordinator < 900 lines
- [ ] No `@unchecked Sendable` without documented justification
- [ ] No `unowned` references in stores
- [ ] OnboardingEvents grouped into nested enums
- [ ] Retry logic extracted to shared utility

### Documentation
- [ ] New services have inline documentation
- [ ] Migration notes added to CHANGELOG
- [ ] Architecture diagram updated (if exists)

---

## Rollback Plan

If issues arise during integration:

1. **Partial rollback:** Each task is independent; revert individual PRs
2. **Full rollback:** Tag pre-refactor commit for easy reversion
3. **Feature flag:** New services can be behind a flag initially:
   ```swift
   let useExtractedServices = UserDefaults.standard.bool(forKey: "useExtractedServices")
   ```

---

## Communication Points

### With Workstream 2 (Services/Data)
- Coordinate on event enum changes
- Share timing on ArtifactRecord threading changes

### With Workstream 3 (UI/Handlers)
- Coordinate on event handler updates for grouped events
- Share timing on StateCoordinator API changes

---

## Definition of Done

- [ ] All P0 tasks complete
- [ ] All P1 tasks complete
- [ ] P2/P3 tasks complete or documented as future work
- [ ] Code reviewed by at least one other developer
- [ ] No regression in functionality
- [ ] Documentation updated
