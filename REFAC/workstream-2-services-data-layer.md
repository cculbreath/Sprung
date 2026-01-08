# Workstream 2: Services & Data Layer Cleanup

**Owner:** Developer B  
**Estimated Duration:** 4-5 days  
**Priority:** Critical (singleton + structural debt)  
**Dependencies:** None (can proceed independently)

---

## Executive Summary

This workstream addresses structural issues in the Services layer (god objects, singletons, duplicate code) and Data layer cleanup (model splitting, legacy removal). The focus is on maintainability and testability improvements that don't impact the Core or UI layers.

---

## Scope & Boundaries

### In Scope
- `/Sprung/Onboarding/Services/GitAgent/FileSystemTools.swift`
- `/Sprung/Onboarding/Services/CardMergeAgent/MergeCardsTool.swift`
- `/Sprung/Onboarding/Tools/Implementations/FileSystemToolWrappers.swift`
- `/Sprung/Onboarding/Models/OnboardingSessionModels.swift`
- `/Sprung/Onboarding/Models/OnboardingPlaceholders.swift`
- `/Sprung/Onboarding/Constants/OnboardingConstants.swift`
- `/Sprung/Onboarding/Handlers/DocumentArtifactHandler.swift`
- Shared utility extraction (buildJSONSchema, progress callbacks)

### Out of Scope
- Core coordinator refactoring (Workstream 1)
- UI views and components (Workstream 3)
- Event system changes (coordinated with Workstream 1)

---

## Task Breakdown

### Task 2.1: Remove ArtifactFilesystemContext Singleton
**Effort:** 3-4 hours  
**Priority:** P0 - Critical (violates stated DI principles)

**File:** `Tools/Implementations/FileSystemToolWrappers.swift` (Lines 22-34)

**Current Code:**
```swift
actor ArtifactFilesystemContext {
    static let shared = ArtifactFilesystemContext()
    private var _rootURL: URL?
    // ...
}
```

**Problem:** This singleton violates the project's architectural principle: "AVOID singletons (.shared) whenever possible - they create hidden dependencies and make testing difficult."

**Solution - Dependency Injection:**

#### Step 1: Modify ArtifactFilesystemContext
```swift
// Keep the actor but remove static shared
actor ArtifactFilesystemContext {
    private var _rootURL: URL?
    
    var rootURL: URL? { _rootURL }
    
    func setRoot(_ url: URL?) {
        _rootURL = url
    }
    
    // Add initializer for testing
    init(rootURL: URL? = nil) {
        self._rootURL = rootURL
    }
}
```

#### Step 2: Update Tool Wrappers to Accept Context
```swift
struct ReadArtifactFileTool: InterviewTool {
    let name = "read_artifact_file"
    
    private let context: ArtifactFilesystemContext
    unowned let coordinator: OnboardingInterviewCoordinator
    
    init(coordinator: OnboardingInterviewCoordinator, context: ArtifactFilesystemContext) {
        self.coordinator = coordinator
        self.context = context
    }
    
    func execute(parameters: JSON) async -> ToolResult {
        guard let rootURL = await context.rootURL else {
            return .failure(ToolError.preconditionFailed("Artifact filesystem not initialized"))
        }
        // ... rest of implementation
    }
}

// Apply same pattern to:
// - ListArtifactDirectoryTool
// - GlobSearchArtifactsTool  
// - GrepSearchArtifactsTool
```

#### Step 3: Create Context in DI Container
```swift
// In OnboardingDependencyContainer.swift
let artifactFilesystemContext = ArtifactFilesystemContext()

// Pass to tool registration
toolRegistrar.registerTool(
    ReadArtifactFileTool(
        coordinator: coordinator,
        context: artifactFilesystemContext
    )
)
```

#### Step 4: Update Context Setting
```swift
// Wherever root is currently set via .shared
// Before:
await ArtifactFilesystemContext.shared.setRoot(exportURL)

// After (context is injected):
await artifactFilesystemContext.setRoot(exportURL)
```

**Verification:**
- [ ] All 4 filesystem tool wrappers use injected context
- [ ] No remaining references to `.shared`
- [ ] Unit tests can inject mock context
- [ ] Integration tests pass

---

### Task 2.2: Split FileSystemTools.swift (1104 lines)
**Effort:** 2-3 hours  
**Priority:** P1 - High

**File:** `Services/GitAgent/FileSystemTools.swift`

**Current State:** Single file containing:
- `AgentTool` protocol
- 6 tool implementations (ReadFileTool, ListDirectoryTool, GlobSearchTool, GrepSearchTool, WriteFileTool, DeleteFileTool)
- `GitToolError` enum
- Utility functions (binary detection, path validation)

**Target Structure:**
```
Services/GitAgent/
├── AgentToolProtocol.swift          (~50 lines)
├── GitToolError.swift               (~30 lines)
├── GitToolUtilities.swift           (~100 lines)
└── Tools/
    ├── ReadFileTool.swift           (~180 lines)
    ├── ListDirectoryTool.swift      (~150 lines)
    ├── GlobSearchTool.swift         (~200 lines)
    ├── GrepSearchTool.swift         (~250 lines)
    ├── WriteFileTool.swift          (~100 lines)
    └── DeleteFileTool.swift         (~80 lines)
```

#### Step 1: Create AgentToolProtocol.swift
```swift
import Foundation
import SwiftyJSON

/// Protocol for tools used by git analysis agent
protocol AgentTool {
    associatedtype Parameters: Decodable
    associatedtype Result: Encodable
    
    static var name: String { get }
    static var description: String { get }
    static var schema: [String: Any] { get }
    
    static func execute(
        parameters: Parameters,
        repoRoot: URL,
        gitignorePatterns: [String]
    ) throws -> Result
}

extension AgentTool {
    static func schemaJSON() -> JSON {
        JSON(schema)
    }
}
```

#### Step 2: Create GitToolError.swift
```swift
import Foundation

/// Errors from git filesystem tools
enum GitToolError: LocalizedError {
    case pathOutsideRepo(String)
    case fileNotFound(String)
    case notADirectory(String)
    case binaryFile(String)
    case notAFile(String)
    case readError(String, Error)
    case writeError(String, Error)
    case deleteError(String, Error)
    case invalidPattern(String)
    case commandFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .pathOutsideRepo(let path):
            return "Path '\(path)' is outside repository root"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        // ... other cases
        }
    }
}
```

#### Step 3: Create GitToolUtilities.swift
```swift
import Foundation

/// Shared utilities for git tools
enum GitToolUtilities {
    
    /// Resolve and validate path is within repo root
    static func resolveAndValidatePath(_ userPath: String, repoRoot: URL) throws -> String {
        // Extract from current lines 1078-1103
    }
    
    /// Detect if file is binary using magic bytes and extension
    static func isBinaryFile(at url: URL) -> Bool {
        // Extract from current lines 136-177
    }
    
    /// Build JSON schema from dictionary
    static func buildJSONSchema(from dict: [String: Any]) -> JSONSchema {
        // Extract from current implementation
        // This is also needed by Task 2.4
    }
    
    /// Safe file reading with encoding detection
    static func readFileContents(at url: URL, maxLines: Int? = nil) throws -> String {
        // Extract shared reading logic
    }
}
```

#### Step 4: Create Individual Tool Files

Example for ReadFileTool.swift:
```swift
import Foundation
import SwiftyJSON

/// Tool for reading file contents with pagination
struct ReadFileTool: AgentTool {
    struct Parameters: Decodable {
        let path: String
        let offset: Int?
        let limit: Int?
    }
    
    struct Result: Encodable {
        let content: String
        let totalLines: Int
        let returnedLines: Int
        let isTruncated: Bool
    }
    
    static let name = "read_file"
    static let description = "Read contents of a file with optional pagination"
    
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "path": ["type": "string", "description": "Path to file relative to repo root"],
            "offset": ["type": "integer", "description": "Starting line (0-indexed)"],
            "limit": ["type": "integer", "description": "Maximum lines to return"]
        ],
        "required": ["path"]
    ]
    
    static func execute(
        parameters: Parameters,
        repoRoot: URL,
        gitignorePatterns: [String] = []
    ) throws -> Result {
        let resolvedPath = try GitToolUtilities.resolveAndValidatePath(
            parameters.path,
            repoRoot: repoRoot
        )
        
        let fileURL = URL(fileURLWithPath: resolvedPath)
        
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw GitToolError.fileNotFound(parameters.path)
        }
        
        guard !GitToolUtilities.isBinaryFile(at: fileURL) else {
            throw GitToolError.binaryFile(parameters.path)
        }
        
        // Read and paginate content
        // ... implementation
    }
}
```

Repeat similar pattern for other tools.

---

### Task 2.3: Extract BackgroundMergeAgent from MergeCardsTool
**Effort:** 1 hour  
**Priority:** P1 - High

**File:** `Services/CardMergeAgent/MergeCardsTool.swift` (353 lines)

**Problem:** Contains both a tool schema definition AND a full agent implementation.

**Solution:**

#### New File: `Services/CardMergeAgent/BackgroundMergeAgent.swift`
```swift
import Foundation
import SwiftyJSON

/// Background agent for merging knowledge cards
/// Operates asynchronously during document processing
actor BackgroundMergeAgent {
    private let llmFacade: LLMFacade
    private let knowledgeCardStore: KnowledgeCardStore
    private let eventBus: EventCoordinator
    
    // Extract from MergeCardsTool.swift lines 150-353
    
    init(
        llmFacade: LLMFacade,
        knowledgeCardStore: KnowledgeCardStore,
        eventBus: EventCoordinator
    ) {
        self.llmFacade = llmFacade
        self.knowledgeCardStore = knowledgeCardStore
        self.eventBus = eventBus
    }
    
    /// Execute merge operation for given card IDs
    func executeMerge(sourceCardIds: [String], into targetId: String?) async throws -> MergeResult {
        // Implementation extracted from MergeCardsTool
    }
    
    /// Analyze cards and suggest merges
    func analyzePotentialMerges(cards: [KnowledgeCard]) async throws -> [MergeSuggestion] {
        // Implementation
    }
}

struct MergeResult {
    let mergedCardId: String
    let sourceCardIds: [String]
    let reasoning: String
}

struct MergeSuggestion {
    let cardIds: [String]
    let confidence: Double
    let reasoning: String
}
```

#### Updated MergeCardsTool.swift (~100 lines)
```swift
import Foundation
import SwiftyJSON

/// Tool schema for card merge operations
/// Delegates execution to BackgroundMergeAgent
struct MergeCardsTool: AgentTool {
    struct Parameters: Decodable {
        let action: String
        let sourceCardIds: [String]?
        let resultCardId: String?
        let reasoning: String?
    }
    
    static let name = "merge_cards"
    static let description = "Merge multiple knowledge cards into one"
    static let schema: [String: Any] = [
        // Schema definition only
    ]
    
    // Tool execution handled by CardMergeAgent orchestrator,
    // not embedded agent implementation
}
```

---

### Task 2.4: Extract Shared buildJSONSchema Utility
**Effort:** 30-45 minutes  
**Priority:** P2 - Medium

**Duplicated in:**
- `GitAnalysisAgent.swift` (lines 517-566)
- `ExperienceDefaultsAgent.swift` (lines 410-452)
- `CardMergeAgent.swift`

**New File:** `Services/Shared/AgentSchemaUtilities.swift`

```swift
import Foundation
import SwiftyJSON

/// Shared utilities for building tool schemas in agents
enum AgentSchemaUtilities {
    
    /// Build JSON schema recursively from dictionary
    /// Used by all multi-turn agents for tool registration
    static func buildJSONSchema(from dict: [String: Any]) -> JSONSchema {
        var schema = JSONSchema()
        
        if let type = dict["type"] as? String {
            schema.type = JSONSchemaType(rawValue: type)
        }
        
        if let description = dict["description"] as? String {
            schema.description = description
        }
        
        if let properties = dict["properties"] as? [String: [String: Any]] {
            schema.properties = properties.mapValues { buildJSONSchema(from: $0) }
        }
        
        if let items = dict["items"] as? [String: Any] {
            schema.items = buildJSONSchema(from: items)
        }
        
        if let required = dict["required"] as? [String] {
            schema.required = required
        }
        
        if let enumValues = dict["enum"] as? [String] {
            schema.enum = enumValues
        }
        
        return schema
    }
    
    /// Convenience for converting tool schema to SwiftOpenAI format
    static func toSwiftOpenAISchema(_ dict: [String: Any]) -> ChatCompletionParameters.Tool.FunctionTool {
        // Implementation
    }
}
```

**Update Agents:**
```swift
// Before (in each agent):
private func buildJSONSchema(from dict: [String: Any]) -> JSONSchema { ... }

// After:
// Just use AgentSchemaUtilities.buildJSONSchema(from:)
```

---

### Task 2.5: Split OnboardingSessionModels.swift
**Effort:** 2-3 hours  
**Priority:** P1 - High

**File:** `Models/OnboardingSessionModels.swift` (390 lines, 7 SwiftData models)

**Current Models:**
1. OnboardingSession
2. OnboardingObjectiveRecord
3. OnboardingMessageRecord (legacy)
4. ConversationEntryRecord (replacement)
5. OnboardingPlanItemRecord
6. PendingToolResponseRecord
7. PendingUserMessageRecord

**Target Structure:**
```
Models/SessionModels/
├── OnboardingSession.swift           (~100 lines)
├── OnboardingObjectiveRecord.swift   (~60 lines)
├── ConversationEntryRecord.swift     (~80 lines)
├── OnboardingPlanItemRecord.swift    (~40 lines)
├── PendingRecords.swift              (~60 lines)  # PendingToolResponseRecord + PendingUserMessageRecord
└── LegacyMessageRecord.swift         (~50 lines)  # Temporary, for migration only
```

#### OnboardingSession.swift
```swift
import Foundation
import SwiftData

/// Primary session model for onboarding interview state
@Model
final class OnboardingSession {
    @Attribute(.unique) var sessionId: String
    var createdAt: Date
    var lastModifiedAt: Date
    var currentPhaseRaw: Int
    var currentSubphaseRaw: Int
    
    // Relationships
    @Relationship(deleteRule: .cascade)
    var objectives: [OnboardingObjectiveRecord] = []
    
    @Relationship(deleteRule: .cascade)
    var conversationEntries: [ConversationEntryRecord] = []
    
    @Relationship(deleteRule: .cascade)
    var planItems: [OnboardingPlanItemRecord] = []
    
    // Computed properties
    var currentPhase: InterviewPhase {
        InterviewPhase(rawValue: currentPhaseRaw) ?? .one
    }
    
    // ... rest of implementation
}
```

#### ConversationEntryRecord.swift (the NEW system)
```swift
import Foundation
import SwiftData
import SwiftyJSON

/// Unified message record replacing OnboardingMessageRecord
/// Supports all message roles: user, assistant, tool_use, tool_result
@Model
final class ConversationEntryRecord {
    var entryId: String
    var roleRaw: String
    var contentJSON: String
    var timestamp: Date
    var turnNumber: Int
    var isEphemeral: Bool
    
    // ... implementation
    
    /// Convert to domain model
    func toConversationEntry() -> ConversationEntry {
        // Implementation
    }
    
    /// Create from domain model
    static func from(_ entry: ConversationEntry) -> ConversationEntryRecord {
        // Implementation
    }
}
```

#### LegacyMessageRecord.swift (TEMPORARY - mark for removal)
```swift
import Foundation
import SwiftData

/// @deprecated - Use ConversationEntryRecord instead
/// Retained temporarily for migration of existing sessions
/// TODO: Remove after migration complete (target: v2.0)
@available(*, deprecated, message: "Use ConversationEntryRecord")
@Model
final class OnboardingMessageRecord {
    // ... minimal implementation for reading old data
}
```

---

### Task 2.6: Remove Legacy Backward Compatibility Markers
**Effort:** 2 hours  
**Priority:** P1 - High

**File:** `Constants/OnboardingConstants.swift` (Lines 88-132)

**Current Code:**
```swift
// Legacy Phase 1 objectives (backwards compatibility)
case applicantProfile = "applicant_profile"
case contactSourceSelected = "contact_source_selected"
// ... more legacy cases
```

**Action Required:**

#### Step 1: Audit Usage
```bash
# Search for each legacy case
grep -r "applicantProfile" --include="*.swift" .
grep -r "contactSourceSelected" --include="*.swift" .
# etc.
```

#### Step 2: Remove or Document

**If unused:** Delete the legacy cases entirely.

**If still used:** Add explicit documentation:
```swift
/// @legacy Required for migration from v1.x sessions
/// Remove after all users have migrated to v2.x objective IDs
case applicantProfile = "applicant_profile"
```

#### Step 3: Create Migration Path
```swift
// If migration needed, add to OnboardingSessionStore
extension OnboardingSessionStore {
    /// Migrate legacy objective IDs to current format
    func migrateObjectiveIds(session: OnboardingSession) {
        for objective in session.objectives {
            if let newId = ObjectiveId.migrationMap[objective.objectiveId] {
                objective.objectiveId = newId.rawValue
            }
        }
    }
}

extension ObjectiveId {
    static let migrationMap: [String: ObjectiveId] = [
        "applicant_profile": .phase1VoiceIntroduction,
        "contact_source_selected": .phase1ContactImport,
        // ... other mappings
    ]
}
```

---

### Task 2.7: Standardize Progress Callback Types
**Effort:** 1-2 hours  
**Priority:** P2 - Medium

**Inconsistent patterns across:**
- `DocumentProcessingService.swift` - `@Sendable (String) -> Void`
- `PDFExtractionRouter.swift` - `@Sendable (String) -> Void`
- `ParallelPageExtractor.swift` - `@Sendable (String) async -> Void`
- `VisionOCRService.swift` - `@Sendable (Int, Int) async -> Void`

**New File:** `Services/Shared/ExtractionProgress.swift`

```swift
import Foundation

/// Unified progress reporting for extraction operations
public struct ExtractionProgressUpdate: Sendable {
    /// Human-readable status message
    public let message: String
    
    /// Optional detailed information
    public let detail: String?
    
    /// Current progress (if countable)
    public let completed: Int?
    
    /// Total items (if known)
    public let total: Int?
    
    /// Progress as percentage (0.0 - 1.0), nil if indeterminate
    public var percentage: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }
    
    public init(
        message: String,
        detail: String? = nil,
        completed: Int? = nil,
        total: Int? = nil
    ) {
        self.message = message
        self.detail = detail
        self.completed = completed
        self.total = total
    }
    
    // Convenience factories
    public static func status(_ message: String) -> ExtractionProgressUpdate {
        ExtractionProgressUpdate(message: message)
    }
    
    public static func progress(_ completed: Int, of total: Int, message: String) -> ExtractionProgressUpdate {
        ExtractionProgressUpdate(message: message, completed: completed, total: total)
    }
}

/// Standard progress handler type
public typealias ExtractionProgressHandler = @Sendable (ExtractionProgressUpdate) async -> Void
```

**Update Services:**
```swift
// Before:
func extract(onProgress: @Sendable (String) -> Void) async throws

// After:
func extract(onProgress: ExtractionProgressHandler) async throws {
    await onProgress(.status("Starting extraction..."))
    
    for (index, page) in pages.enumerated() {
        await onProgress(.progress(index + 1, of: pages.count, message: "Processing page \(index + 1)"))
        // ...
    }
}
```

---

### Task 2.8: Replace Custom Queue with TaskGroup in DocumentArtifactHandler
**Effort:** 4-6 hours  
**Priority:** P1 - High

**File:** `Handlers/DocumentArtifactHandler.swift` (Lines 158-198)

**Current Pattern:**
```swift
private func processQueue() async {
    while !pendingFiles.isEmpty || activeProcessingCount > 0 {
        while activeProcessingCount < maxConcurrentExtractions && !pendingFiles.isEmpty {
            let queuedFile = pendingFiles.removeFirst()
            activeProcessingCount += 1
            Task { [weak self] in
                guard let self else { return }
                await self.processQueuedFile(queuedFile)
            }
        }
        if activeProcessingCount > 0 || !pendingFiles.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
```

**Problem:**
- Manual concurrency management
- Polling with sleep (inefficient)
- Fire-and-forget Tasks with unclear lifecycle

**Solution - TaskGroup:**
```swift
actor DocumentArtifactHandler {
    private let maxConcurrentExtractions: Int
    
    /// Process all pending files with controlled concurrency
    func processAllPendingFiles() async {
        let filesToProcess = pendingFiles
        pendingFiles.removeAll()
        
        await withTaskGroup(of: ProcessingResult.self) { group in
            // Track active count for concurrency limit
            var activeCount = 0
            var fileIterator = filesToProcess.makeIterator()
            
            // Start initial batch up to max concurrency
            while activeCount < maxConcurrentExtractions,
                  let file = fileIterator.next() {
                group.addTask { await self.processFile(file) }
                activeCount += 1
            }
            
            // As tasks complete, start new ones
            for await result in group {
                handleResult(result)
                activeCount -= 1
                
                if let file = fileIterator.next() {
                    group.addTask { await self.processFile(file) }
                    activeCount += 1
                }
            }
        }
    }
    
    private func processFile(_ file: QueuedFile) async -> ProcessingResult {
        // Actual processing logic
    }
}
```

**Benefits:**
- Structured concurrency with automatic cancellation
- No polling/sleeping
- Clear ownership of child tasks
- Better error propagation

---

## Verification Checklist

### Build Verification
- [ ] `swift build` succeeds
- [ ] All unit tests pass
- [ ] Integration tests pass
- [ ] No new SwiftLint warnings

### Architecture Verification
- [ ] No `.shared` singleton references
- [ ] FileSystemTools.swift split into ~7 files
- [ ] OnboardingSessionModels.swift split into ~6 files
- [ ] Progress callbacks use unified type
- [ ] TaskGroup replaces custom queue

### Documentation
- [ ] New files have header documentation
- [ ] Migration notes for model changes
- [ ] CHANGELOG updated

---

## Rollback Plan

1. **Per-task rollback:** Each task produces independent PRs
2. **Model migration:** Keep legacy models until migration verified
3. **Feature flag for TaskGroup:**
   ```swift
   let useTaskGroupProcessing = UserDefaults.standard.bool(forKey: "useTaskGroupProcessing")
   ```

---

## Communication Points

### With Workstream 1 (Core)
- Share `AgentSchemaUtilities` location
- Coordinate on event changes if handlers affected

### With Workstream 3 (UI)
- Notify about model file relocations
- Share progress callback type changes

---

## Definition of Done

- [ ] Singleton removed, DI implemented
- [ ] Large files split appropriately
- [ ] Legacy markers removed or documented
- [ ] Duplicate utilities extracted
- [ ] Code reviewed
- [ ] No regressions
