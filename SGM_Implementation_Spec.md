# Seed Generation Module (SGM) Implementation Specification

## Overview

The Seed Generation Module generates ExperienceDefaults to populate the skeleton timeline with content elements for general-purpose resumes. It replaces Phase 4 content generation in the Sprung onboarding workflow.

**Location**: `Sprung/SeedGeneration/`

**Purpose**: Transform OI-captured facts (timeline, KCs, skills) into LLM-generated content (highlights, descriptions, grouped skills) that seeds the user's general resume.

---

## Architecture

### Module Structure

```
Sprung/SeedGeneration/
├── Core/
│   ├── SeedGenerationContext.swift       # Captures all OI outputs
│   ├── SeedGenerationOrchestrator.swift  # Main coordinator
│   ├── GenerationTask.swift              # Atomic LLM generation unit
│   ├── ReviewQueue.swift                 # Batch review accumulator
│   └── SeedGenerationActivityTracker.swift # Progress/status tracking
├── Models/
│   ├── SectionConfig.swift               # EnabledSections + CustomFieldDefinitions
│   ├── GeneratedContent.swift            # LLM output wrapper
│   └── ReviewItem.swift                  # User review queue item
├── Generators/
│   ├── SectionGenerator.swift            # Protocol for all generators
│   ├── WorkHighlightsGenerator.swift     # 3-4 bullets per job
│   ├── EducationGenerator.swift
│   ├── VolunteerGenerator.swift
│   ├── AwardsGenerator.swift
│   ├── CertificatesGenerator.swift
│   ├── PublicationsGenerator.swift
│   ├── LanguagesGenerator.swift
│   ├── InterestsGenerator.swift
│   ├── ReferencesGenerator.swift
│   ├── ObjectiveGenerator.swift
│   └── CustomFieldGenerator.swift
├── SpecialGenerators/
│   ├── ProjectsGenerator.swift           # Two-phase curation workflow
│   ├── SkillsGroupingGenerator.swift     # Group & categorize skills
│   └── TitleOptionsGenerator.swift       # Library-based title curation
├── Services/
│   ├── PromptCacheService.swift          # Shared preamble for caching
│   └── ParallelLLMExecutor.swift         # Concurrent LLM calls
├── Views/
│   ├── SeedGenerationView.swift          # Main navigation split view
│   ├── SeedGenerationStatusBar.swift     # Bottom status bar (monitor)
│   ├── ReviewQueueView.swift             # Scrollable review list
│   ├── ReviewItemCard.swift              # Individual review card
│   ├── TitleOptionsLibraryView.swift     # HSplitView editor + library
│   ├── ProjectCurationView.swift         # Approve/reject proposals
│   └── SkillsGroupingView.swift          # Preview skill groups
└── Prompts/
    ├── work_highlights_prompt.txt
    ├── project_description_prompt.txt
    ├── skills_grouping_prompt.txt
    ├── title_options_prompt.txt
    └── [other section prompts]
```

---

## Data Flow

```
OI Completion
    │
    ▼
SeedGenerationOrchestrator.loadFromOnboarding()
    │
    ├── Read: ArtifactRepository (timeline, KCs, profile, sectionConfig)
    ├── Read: SkillStore (skill bank)
    ├── Read: OnboardingSession (persisted sectionConfigJSON)
    │
    ▼
Build task list from enabled sections
    │
    ▼
Generate all (parallel with prompt caching)
    │
    ▼
ReviewQueue accumulates results
    │
    ▼
User reviews/approves via ReviewQueueView
    │
    ▼
saveApprovedContent() → ExperienceDefaultsStore (SwiftData)
```

---

## Core Models

### SectionConfig (New - Replaces enabledSectionsCSV)

```swift
/// Bundled section configuration: enabled sections + custom field definitions
/// Persisted as JSON in OnboardingSession.sectionConfigJSON
struct SectionConfig: Codable {
    var enabledSections: Set<String>
    var customFields: [CustomFieldDefinition]
    
    /// Decode from JSON string
    static func from(json: String) throws -> SectionConfig
    
    /// Encode to JSON string for persistence
    func toJSON() throws -> String
}
```

**Persistence Changes Required**:
- `OnboardingSession`: Replace `enabledSectionsCSV: String?` with `sectionConfigJSON: String?`
- `OnboardingSessionStore`: Update methods to handle `SectionConfig`
- `ArtifactRepository`: Combine `setEnabledSections` and `setCustomFieldDefinitions` into single `setSectionConfig` method

### SeedGenerationContext

```swift
/// Immutable snapshot of all OI outputs needed for generation
struct SeedGenerationContext {
    let applicantProfile: ApplicantProfile
    let skeletonTimeline: [TimelineEntry]
    let sectionConfig: SectionConfig
    let knowledgeCards: [KnowledgeCard]
    let skills: [Skill]
    let writingSamples: [WritingSample]
    let dossier: Dossier?
    
    /// Get KCs relevant to a specific timeline entry (by org/title/dates)
    func relevantKCs(for entry: TimelineEntry) -> [KnowledgeCard]
    
    /// Get all timeline entries for a section type
    func timelineEntries(for section: ExperienceSectionKey) -> [TimelineEntry]
}
```

### GenerationTask

```swift
/// Atomic unit of LLM generation work
struct GenerationTask: Identifiable {
    let id: UUID
    let section: ExperienceSectionKey
    let targetId: String?              // Timeline entry ID if applicable
    let displayName: String            // e.g., "Work highlights: Anthropic"
    var status: TaskStatus
    var result: GeneratedContent?
    var error: String?
    var tokenUsage: TokenUsage?
    
    enum TaskStatus {
        case pending
        case running
        case completed
        case failed
        case approved
        case rejected
    }
}
```

### ReviewItem

```swift
/// Item in the review queue awaiting user action
struct ReviewItem: Identifiable {
    let id: UUID
    let task: GenerationTask
    let generatedContent: GeneratedContent
    var userAction: UserAction?
    var editedContent: String?
    
    enum UserAction {
        case approved
        case rejected
        case rejectedWithComment(String)
        case edited
    }
}
```

---

## Section Generators

### Protocol

```swift
protocol SectionGenerator {
    var sectionKey: ExperienceSectionKey { get }
    
    /// Generate tasks for this section based on context
    func createTasks(context: SeedGenerationContext) -> [GenerationTask]
    
    /// Execute a single task, returning generated content
    func execute(task: GenerationTask, context: SeedGenerationContext, llm: LLMService) async throws -> GeneratedContent
    
    /// Apply approved content to ExperienceDefaults
    func apply(content: GeneratedContent, to defaults: inout ExperienceDefaults)
}
```

### Standard Generators

| Generator | Input | Output | Tasks Per |
|-----------|-------|--------|-----------|
| `WorkHighlightsGenerator` | Timeline work entries + relevant KCs | 3-4 bullet highlights | 1 per job |
| `EducationGenerator` | Timeline education entries | Description, courses | 1 per school |
| `VolunteerGenerator` | Timeline volunteer entries | Description, highlights | 1 per org |
| `AwardsGenerator` | Timeline awards | Summary text | 1 per award |
| `CertificatesGenerator` | Timeline certs | (mostly facts, minimal LLM) | 1 per cert |
| `PublicationsGenerator` | Timeline publications | Summary text | 1 per pub |
| `LanguagesGenerator` | Profile languages | Fluency descriptions | 1 total |
| `InterestsGenerator` | KCs, profile | Interest descriptions | 1 total |
| `ReferencesGenerator` | Timeline references | (mostly facts) | 1 per ref |
| `ObjectiveGenerator` | Full context | 3-5 sentence objective | 1 total |
| `CustomFieldGenerator` | Per custom field definition | Field-specific content | 1 per field |

---

## Special Generators

### ProjectsGenerator (Two-Phase Workflow)

**Phase 1: Project Discovery**
- Analyze timeline for existing project entries
- Scan KCs and skill bank for project-worthy content
- LLM proposes additional projects with rationale

**Phase 2: User Curation**
- Present proposed projects in `ProjectCurationView`
- User approves/rejects each proposal
- Only approved projects proceed to content generation

**Phase 3: Content Generation**
- Generate descriptions, highlights for approved projects
- One task per approved project

```swift
class ProjectsGenerator: SectionGenerator {
    func discoverProjects(context: SeedGenerationContext, llm: LLMService) async throws -> [ProjectProposal]
    func createTasks(for approvedProjects: [ProjectProposal], context: SeedGenerationContext) -> [GenerationTask]
}
```

### SkillsGroupingGenerator

**Constraints**:
- ONLY use skills from the skill bank (no fabrication)
- Create 4-6 groups of 4-8 skills each
- Generate category titles (e.g., "Data Engineering")
- Maximize coverage across potential job types

**Output Structure** (maps to JSON Resume skills):
```swift
struct SkillExperienceDraft {
    var name: String       // Category title
    var keywords: [String] // Individual skills
}
```

```swift
class SkillsGroupingGenerator: SectionGenerator {
    func execute(...) async throws -> GeneratedContent {
        // LLM analyzes skill bank
        // Groups by theme/category
        // Returns 4-6 SkillExperienceDraft entries
    }
}
```

### TitleOptionsGenerator (Library System)

**UI Components**:
- **Editor (left)**: 4 editable word fields, each with lock/unlock toggle
- **Generation Controls**: "Generate" button, guidance popover for user instructions
- **Library (right)**: Saved title sets, one marked as default

**Workflow**:
1. User clicks "Generate" → LLM produces 5 four-word sets
2. Sets appear in editor area for review
3. User can:
   - Edit individual words
   - Lock words (preserved on regenerate)
   - Regenerate single word or entire set
   - Save set to library
4. Context menu on library items: "Set as Default"
5. Default set written to `custom.jobTitles` in ExperienceDefaults

```swift
class TitleOptionsGenerator {
    struct TitleSet: Identifiable, Codable {
        let id: UUID
        var words: [String]  // Exactly 4
        var isDefault: Bool
    }
    
    func generate(locked: [Int: String], guidance: String?, llm: LLMService) async throws -> [TitleSet]
    func regenerateWord(at index: Int, current: TitleSet, guidance: String?, llm: LLMService) async throws -> String
}
```

---

## Services

### PromptCacheService

Builds shared preamble for Anthropic/OpenAI prompt caching:

```swift
class PromptCacheService {
    /// Build cacheable preamble from context
    func buildPreamble(context: SeedGenerationContext) -> String {
        // Includes:
        // - KC summaries (all cards)
        // - Skill bank listing
        // - Voice/style guidelines from writing samples
        // - Applicant profile summary
    }
    
    /// Combine preamble with section-specific instructions
    func buildPrompt(preamble: String, sectionPrompt: String, taskContext: String) -> String
}
```

### ParallelLLMExecutor

```swift
actor ParallelLLMExecutor {
    private let maxConcurrent = 5
    private var runningCount = 0
    
    func execute(tasks: [GenerationTask], generator: SectionGenerator, context: SeedGenerationContext) -> AsyncStream<(GenerationTask, Result<GeneratedContent, Error>)>
}
```

---

## Orchestrator

```swift
@Observable
@MainActor
class SeedGenerationOrchestrator {
    // MARK: - State
    private(set) var context: SeedGenerationContext?
    private(set) var tasks: [GenerationTask] = []
    private(set) var reviewQueue: ReviewQueue = ReviewQueue()
    private(set) var activityTracker: SeedGenerationActivityTracker
    
    // MARK: - Services
    private let promptCacheService: PromptCacheService
    private let llmExecutor: ParallelLLMExecutor
    private let generators: [ExperienceSectionKey: SectionGenerator]
    
    // MARK: - Lifecycle
    
    /// Load context from completed OI session
    func loadFromOnboarding(
        artifactRepository: ArtifactRepository,
        skillStore: SkillStore,
        session: OnboardingSession
    ) async
    
    /// Generate all content for enabled sections
    func generateAll() async
    
    /// Handle special generators that need user curation first
    func runProjectDiscovery() async throws -> [ProjectProposal]
    func confirmProjects(_ approved: [ProjectProposal]) async
    
    /// Save approved content to ExperienceDefaults
    func saveApprovedContent(to store: ExperienceDefaultsStore) async throws
}
```

---

## Activity Tracking & Status Bar

### SeedGenerationActivityTracker

Similar to `AgentActivityTracker`, but simpler (no transcript, just status):

```swift
@Observable
@MainActor
class SeedGenerationActivityTracker {
    // MARK: - State
    private(set) var activeTasks: [TrackedGenerationTask] = []
    
    struct TrackedGenerationTask: Identifiable {
        let id: String
        let displayName: String
        var status: TaskStatus
        var statusMessage: String?
        let startTime: Date
        var endTime: Date?
    }
    
    // MARK: - Computed
    var runningCount: Int { activeTasks.filter { $0.status == .running }.count }
    var completedCount: Int { activeTasks.filter { $0.status == .completed }.count }
    var failedCount: Int { activeTasks.filter { $0.status == .failed }.count }
    var totalCount: Int { activeTasks.count }
    var isAnyRunning: Bool { runningCount > 0 }
    
    // MARK: - Lifecycle
    func trackTask(id: String, displayName: String)
    func markRunning(id: String, message: String?)
    func markCompleted(id: String)
    func markFailed(id: String, error: String)
    func updateStatus(id: String, message: String)
}
```

### SeedGenerationStatusBar

Full-width status bar at bottom of SGM window (matches `BackgroundAgentStatusBar` pattern):

```swift
struct SeedGenerationStatusBar: View {
    let tracker: SeedGenerationActivityTracker
    
    private let maxVisibleItems = 3
    
    var body: some View {
        HStack(spacing: 4) {
            if tracker.isAnyRunning {
                // Show running tasks with spinners
                ForEach(tracker.activeTasks.filter { $0.status == .running }.prefix(maxVisibleItems)) { task in
                    TaskStatusItem(task: task)
                }
                
                // Overflow indicator
                if tracker.runningCount > maxVisibleItems {
                    Text("+\(tracker.runningCount - maxVisibleItems) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                // Progress summary
                Text("\(tracker.completedCount)/\(tracker.totalCount) complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Idle or complete state
                if tracker.totalCount > 0 {
                    Image(systemName: tracker.failedCount > 0 ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(tracker.failedCount > 0 ? .orange : .green)
                    Text("\(tracker.completedCount) generated, \(tracker.failedCount) failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ready")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        )
        .overlay {
            if tracker.isAnyRunning {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .intelligenceStroke(
                        lineWidths: [1.5, 2.5, 3.5],
                        blurs: [4, 8, 14],
                        updateInterval: 0.5,
                        animationDurations: [0.6, 0.8, 1.0]
                    )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: tracker.isAnyRunning)
    }
}

private struct TaskStatusItem: View {
    let task: SeedGenerationActivityTracker.TrackedGenerationTask
    
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            
            Text(task.statusMessage ?? task.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
```

---

## Views

### SeedGenerationView (Main Container)

```swift
struct SeedGenerationView: View {
    @State var orchestrator: SeedGenerationOrchestrator
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            NavigationSplitView {
                // Sidebar: Section progress list
                SectionProgressSidebar(orchestrator: orchestrator)
            } detail: {
                // Detail: Current section view or review queue
                if orchestrator.reviewQueue.hasItems {
                    ReviewQueueView(queue: orchestrator.reviewQueue)
                } else {
                    // Section-specific views (projects, skills, titles)
                    currentSectionView
                }
            }
            
            // Bottom status bar
            SeedGenerationStatusBar(tracker: orchestrator.activityTracker)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }
}
```

### ReviewQueueView

```swift
struct ReviewQueueView: View {
    @Bindable var queue: ReviewQueue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with batch actions
            HStack {
                Text("Review Generated Content")
                    .font(.headline)
                Spacer()
                Button("Approve All") {
                    queue.approveAll()
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Scrollable review items
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(queue.pendingItems) { item in
                        ReviewItemCard(item: item, onAction: { action in
                            queue.setAction(for: item.id, action: action)
                        })
                    }
                }
            }
        }
        .padding()
    }
}
```

### TitleOptionsLibraryView

```swift
struct TitleOptionsLibraryView: View {
    @State var generator: TitleOptionsGenerator
    @State private var currentSet: TitleOptionsGenerator.TitleSet
    @State private var lockedIndices: Set<Int> = []
    @State private var guidance: String = ""
    @State private var showGuidancePopover = false
    
    var body: some View {
        HSplitView {
            // Left: Editor
            VStack(alignment: .leading, spacing: 16) {
                Text("Title Options")
                    .font(.headline)
                
                // Four word fields
                ForEach(0..<4, id: \.self) { index in
                    TitleWordField(
                        word: $currentSet.words[index],
                        isLocked: lockedIndices.contains(index),
                        onToggleLock: { toggleLock(index) },
                        onRegenerate: { regenerateWord(index) }
                    )
                }
                
                // Generation controls
                HStack {
                    Button("Generate New Set") {
                        generateNewSet()
                    }
                    
                    Button {
                        showGuidancePopover.toggle()
                    } label: {
                        Image(systemName: "text.bubble")
                    }
                    .popover(isPresented: $showGuidancePopover) {
                        GuidanceInputView(guidance: $guidance)
                    }
                    
                    Spacer()
                    
                    Button("Save to Library") {
                        saveToLibrary()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(minWidth: 300)
            .padding()
            
            // Right: Library
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved Sets")
                    .font(.headline)
                
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(generator.library) { set in
                            TitleSetLibraryItem(
                                set: set,
                                isDefault: set.isDefault,
                                onSetDefault: { generator.setDefault(set.id) },
                                onDelete: { generator.deleteFromLibrary(set.id) },
                                onSelect: { currentSet = set }
                            )
                        }
                    }
                }
            }
            .frame(minWidth: 200)
            .padding()
        }
    }
}
```

---

## Phase 4 Removal (Clean Breaks)

### Files to DELETE Entirely

```
Sprung/Onboarding/Services/ExperienceDefaultsAgent/
├── ExperienceDefaultsAgent.swift
├── ExperienceDefaultsAgentService.swift
└── ExperienceDefaultsWorkspaceService.swift

Sprung/Onboarding/Tools/Implementations/GenerateExperienceDefaultsTool.swift
Sprung/Onboarding/Views/Components/TitleSetCurationView.swift
Sprung/Onboarding/Services/TitleSetService.swift
Sprung/Onboarding/Resources/Prompts/experience_defaults_agent_system.txt
```

### Files to Modify

**`PhaseFourScript.swift`**:
- Remove `experienceDefaultsSet` objective
- Remove title curation todos
- Simplify to dossier completion only
- Add hook to present SGM on phase completion

**`ToolBundlePolicy.swift`**:
- Remove `generate_experience_defaults` from Phase 4 bundle

**`OnboardingToolRegistrar.swift`**:
- Remove `GenerateExperienceDefaultsTool` registration

**`PromptLibrary.swift`**:
- Remove `experienceDefaultsAgentSystem` property

**`OnboardingSession.swift`**:
- Replace `enabledSectionsCSV: String?` with `sectionConfigJSON: String?`

**`OnboardingSessionStore.swift`**:
- Replace `updateEnabledSections`/`getEnabledSections` with `updateSectionConfig`/`getSectionConfig`

**`ArtifactRepository.swift`**:
- Combine `setEnabledSections` + `setCustomFieldDefinitions` into `setSectionConfig`
- Update `getEnabledSections` and `getCustomFieldDefinitions` to read from unified config

**`ResumeSectionsToggleCard.swift`**:
- Update `onConfirm` to pass `SectionConfig` instead of tuple

### Verification

After removal, grep the codebase for these terms (all should return zero results):
- `ExperienceDefaultsAgent`
- `GenerateExperienceDefaultsTool`
- `TitleSetCurationView`
- `TitleSetService`
- `experience_defaults_agent_system`
- `enabledSectionsCSV`

---

## Integration Points

### Entry Point

After OI Phase 4 completion, present SGM:

```swift
// In PhaseFourScript.swift or similar
func onPhaseComplete() async {
    // Present SGM window/sheet
    await MainActor.run {
        appState.presentSeedGeneration(
            artifactRepository: coordinator.artifactRepository,
            skillStore: coordinator.skillStore,
            session: coordinator.session
        )
    }
}
```

### Reads From

| Source | Data |
|--------|------|
| `ArtifactRepository` | Skeleton timeline, KCs, applicant profile, section config |
| `SkillStore` | Skill bank |
| `OnboardingSession` | Persisted `sectionConfigJSON` |
| `CoverRefStore` | Writing samples, dossier |

### Writes To

| Destination | Data |
|-------------|------|
| `ExperienceDefaultsStore` | Approved generated content |

---

## Implementation Phases

### Phase 1: Foundation (Week 1)

1. Create directory structure under `Sprung/SeedGeneration/`
2. Implement `SectionConfig` model and persistence changes:
   - Add `sectionConfigJSON` to `OnboardingSession`
   - Update `OnboardingSessionStore` methods
   - Update `ArtifactRepository` to use unified config
   - Update `ResumeSectionsToggleCard` callback
3. Implement core models: `SeedGenerationContext`, `GenerationTask`, `ReviewItem`
4. Implement `SeedGenerationActivityTracker`
5. Delete Phase 4 ExperienceDefaults files (clean break)
6. Simplify `PhaseFourScript` to dossier-only

### Phase 2: Core Generators (Week 2)

1. Implement `SectionGenerator` protocol
2. Implement `PromptCacheService`
3. Implement `ParallelLLMExecutor`
4. Implement standard generators:
   - `WorkHighlightsGenerator`
   - `EducationGenerator`
   - `ObjectiveGenerator`
   - `CustomFieldGenerator`
5. Create prompt templates for each generator

### Phase 3: Special Generators (Week 3)

1. Implement `ProjectsGenerator` with two-phase workflow
2. Implement `SkillsGroupingGenerator`
3. Implement `TitleOptionsGenerator` with library system
4. Create prompt templates for special generators

### Phase 4: UI (Week 4)

1. Implement `SeedGenerationStatusBar`
2. Implement `ReviewQueue` and `ReviewQueueView`
3. Implement `ReviewItemCard` with approve/reject/edit actions
4. Implement `TitleOptionsLibraryView` (HSplitView)
5. Implement `ProjectCurationView`
6. Implement `SkillsGroupingView`
7. Implement `SeedGenerationView` (main container)

### Phase 5: Integration (Week 5)

1. Implement `SeedGenerationOrchestrator`
2. Wire entry point in `PhaseFourScript.onComplete`
3. Wire persistence to `ExperienceDefaultsStore`
4. Verify all old code references removed (grep verification)
5. End-to-end manual testing

---

## Verification Checklist

- [ ] All ExperienceDefaultsAgent files deleted
- [ ] GenerateExperienceDefaultsTool deleted
- [ ] TitleSetService/View deleted
- [ ] Phase 4 script simplified to dossier-only
- [ ] Tool registry updated (no generate_experience_defaults)
- [ ] `enabledSectionsCSV` replaced with `sectionConfigJSON` throughout
- [ ] No old code references remain (grep returns zero)
- [ ] New SGM module functional
- [ ] Status bar displays running/completed tasks
- [ ] Review queue accumulates and presents items
- [ ] Title options library saves/loads correctly
- [ ] Project curation workflow functions
- [ ] Skills grouping produces valid output
- [ ] Approved content persists to ExperienceDefaultsStore
