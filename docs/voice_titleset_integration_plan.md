# Voice Profile & Title Set Integration Plan

## Overview

This plan wires up the `InferenceGuidanceStore` with voice profile extraction (Phase 1) and title set generation (Phase 4). Currently, `GuidanceGenerationService` exists but is dead code—never instantiated or called.

### Current State

| Component | Status |
|-----------|--------|
| Narrative KCs | ✅ 14 cards with rich narratives |
| Skill Bank | ✅ 420 skills with categories |
| CardMergeAgent | ✅ Full multi-turn agent |
| InferenceGuidance table | ❌ 0 records |
| VoiceProfile extraction | ❌ Dead code |
| TitleSet generation | ❌ Not wired |
| ExperienceDefaultsAgent reads guidance | ❌ Ignores guidance store |

### Goal State

| Component | Status |
|-----------|--------|
| VoiceProfile | Extracted in Phase 1 after writing samples |
| TitleSets | Generated in Phase 4 from skill bank, interactively curated |
| ExperienceDefaultsAgent | Reads guidance, SELECTs title set, applies voice profile |

---

## Part 0: Todo List Refactoring

### 0.1 Update PhaseScript Protocol

**Location**: `/Sprung/Onboarding/Phase/PhaseScript.swift`

**Current Issue**: Todo items are hardcoded in `StateCoordinator.swift` around line 115-170 in `populateTodoList(for:)`. They should live with their respective phase scripts.

**Add to protocol**:

```swift
protocol PhaseScript {
    // ... existing properties ...
    
    /// Initial todo items pre-populated when this phase starts.
    /// The LLM sees these in <todo-list> tags and tracks progress.
    var initialTodoItems: [InterviewTodoItem] { get }
}

// Default implementation (empty)
extension PhaseScript {
    var initialTodoItems: [InterviewTodoItem] { [] }
    // ... existing defaults ...
}
```

### 0.2 Update PhaseOneScript.swift

**Add property**:

```swift
var initialTodoItems: [InterviewTodoItem] {
    [
        InterviewTodoItem(
            content: "Validate applicant profile (name, email, location)",
            status: .pending,
            activeForm: "Validating applicant profile"
        ),
        InterviewTodoItem(
            content: "Offer profile photo upload",
            status: .pending,
            activeForm: "Offering profile photo"
        ),
        InterviewTodoItem(
            content: "Collect writing samples (cover letters, proposals, emails)",
            status: .pending,
            activeForm: "Collecting writing samples"
        ),
        InterviewTodoItem(
            content: "Capture job search context (motivation, priorities)",
            status: .pending,
            activeForm: "Capturing job search context"
        )
        // Note: voice_primers_extracted runs in background - not in todo list
    ]
}
```

### 0.3 Update PhaseTwoScript.swift

**Add property**:

```swift
var initialTodoItems: [InterviewTodoItem] {
    [
        InterviewTodoItem(
            content: "Offer resume/LinkedIn upload or conversational timeline",
            status: .pending,
            activeForm: "Offering timeline input options"
        ),
        InterviewTodoItem(
            content: "Generate timeline cards from input",
            status: .pending,
            activeForm: "Generating timeline cards"
        ),
        InterviewTodoItem(
            content: "Tune timeline cards based on user feedback",
            status: .pending,
            activeForm: "Tuning timeline cards"
        ),
        InterviewTodoItem(
            content: "Submit timeline for validation",
            status: .pending,
            activeForm: "Submitting timeline for validation"
        ),
        InterviewTodoItem(
            content: "Configure enabled resume sections",
            status: .pending,
            activeForm: "Configuring resume sections"
        ),
        InterviewTodoItem(
            content: "Advance to Phase 3",
            status: .pending,
            activeForm: "Advancing to Phase 3"
        )
    ]
}
```

### 0.4 Update PhaseThreeScript.swift

**Add property**:

```swift
var initialTodoItems: [InterviewTodoItem] {
    [
        InterviewTodoItem(
            content: "Open document collection UI",
            status: .pending,
            activeForm: "Opening document collection"
        ),
        InterviewTodoItem(
            content: "Suggest documents to upload based on timeline",
            status: .pending,
            activeForm: "Suggesting documents"
        ),
        InterviewTodoItem(
            content: "Interview about each role (while uploads process)",
            status: .pending,
            activeForm: "Interviewing about roles"
        ),
        InterviewTodoItem(
            content: "Capture work preferences and unique circumstances",
            status: .pending,
            activeForm: "Capturing work preferences"
        ),
        InterviewTodoItem(
            content: "Wait for document processing and card generation",
            status: .pending,
            activeForm: "Waiting for card generation"
        ),
        InterviewTodoItem(
            content: "Review merged knowledge cards with user",
            status: .pending,
            activeForm: "Reviewing knowledge cards"
        )
    ]
}
```

### 0.5 Update PhaseFourScript.swift

**Add property**:

```swift
var initialTodoItems: [InterviewTodoItem] {
    [
        InterviewTodoItem(
            content: "Synthesize strategic strengths with evidence",
            status: .pending,
            activeForm: "Synthesizing strengths"
        ),
        InterviewTodoItem(
            content: "Document pitfalls with mitigation strategies",
            status: .pending,
            activeForm: "Documenting pitfalls"
        ),
        InterviewTodoItem(
            content: "Fill remaining dossier gaps",
            status: .pending,
            activeForm: "Completing dossier"
        ),
        InterviewTodoItem(
            content: "Generate and curate identity title sets",
            status: .pending,
            activeForm: "Generating title sets"
        ),
        InterviewTodoItem(
            content: "Generate experience defaults",
            status: .pending,
            activeForm: "Generating experience defaults"
        ),
        InterviewTodoItem(
            content: "Submit dossier for validation",
            status: .pending,
            activeForm: "Submitting dossier"
        ),
        InterviewTodoItem(
            content: "Summarize interview and complete onboarding",
            status: .pending,
            activeForm: "Completing interview"
        )
    ]
}
```

### 0.6 Update StateCoordinator.swift

**Remove**: The entire `populateTodoList(for:)` method (lines ~115-170)

**Replace call site** (in `transitionToPhase` or wherever it's called):

```swift
// OLD:
await populateTodoList(for: phase)

// NEW:
if let script = phaseScriptRegistry.script(for: phase) {
    await todoStore.setItems(script.initialTodoItems)
    Logger.info("📋 Pre-populated todo list for \(phase.rawValue): \(script.initialTodoItems.count) items", category: .ai)
}
```

---

## Part 1: Service Restructuring

### 1.1 Create VoiceProfileService.swift (NEW)

**Location**: `/Sprung/Onboarding/Services/VoiceProfileService.swift`

**Purpose**: Extract voice profile from writing samples. Runs in Phase 1 after `writingSamplesCollected`.

```swift
import Foundation

/// Extracts voice characteristics from writing samples.
/// Called after Phase 1 writing sample collection completes.
actor VoiceProfileService {
    private var llmFacade: LLMFacade?
    
    private var modelId: String {
        UserDefaults.standard.string(forKey: "voiceProfileModelId") ?? DefaultModels.gemini
    }
    
    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
    }
    
    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }
    
    /// Extract voice profile from writing samples
    /// - Parameter samples: Array of writing sample text content
    /// - Returns: Extracted VoiceProfile
    func extractVoiceProfile(from samples: [String]) async throws -> VoiceProfile {
        guard let facade = llmFacade else {
            throw VoiceProfileError.llmNotConfigured
        }
        
        guard !samples.isEmpty else {
            Logger.warning("🎤 No writing samples provided, returning default profile", category: .ai)
            return VoiceProfile()
        }
        
        let samplesText = samples.joined(separator: "\n\n---\n\n")
        
        let prompt = PromptLibrary.substitute(
            template: PromptLibrary.voiceProfileTemplate,
            replacements: ["WRITING_SAMPLES": samplesText]
        )
        
        Logger.info("🎤 Extracting voice profile from \(samples.count) samples", category: .ai)
        
        let profile: VoiceProfile = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: VoiceProfile.self,
            schema: GuidanceSchemas.voiceProfileSchema,
            schemaName: "voice_profile",
            maxOutputTokens: 4096,
            keyDecodingStrategy: .convertFromSnakeCase,
            backend: .gemini
        )
        
        Logger.info("🎤 Extracted voice profile: \(profile.enthusiasm.displayName), first person: \(profile.useFirstPerson)", category: .ai)
        return profile
    }
    
    /// Store extracted voice profile in guidance store
    @MainActor
    func storeVoiceProfile(_ profile: VoiceProfile, in guidanceStore: InferenceGuidanceStore) {
        let attachments = GuidanceAttachments(voiceProfile: profile)
        
        let guidance = InferenceGuidance(
            nodeKey: "objective",
            displayName: "Voice Profile",
            prompt: """
            Voice profile for content generation:
            - Enthusiasm: \(profile.enthusiasm.displayName)
            - Person: \(profile.useFirstPerson ? "First person (I built, I discovered)" : "Third person")
            - Connectives: \(profile.connectiveStyle)
            - Aspirational phrases: \(profile.aspirationalPhrases.joined(separator: ", "))
            - NEVER use: \(profile.avoidPhrases.joined(separator: ", "))
            
            Sample excerpts preserving voice:
            \(profile.sampleExcerpts.map { "• \"\($0)\"" }.joined(separator: "\n"))
            """,
            attachmentsJSON: attachments.asJSON(),
            source: .auto
        )
        
        guidanceStore.add(guidance)
        Logger.info("🎤 Voice profile stored in guidance store", category: .ai)
    }
    
    enum VoiceProfileError: Error, LocalizedError {
        case llmNotConfigured
        case extractionFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade not configured"
            case .extractionFailed(let msg):
                return "Voice profile extraction failed: \(msg)"
            }
        }
    }
}
```

### 1.2 Create TitleSetService.swift (NEW)

**Location**: `/Sprung/Onboarding/Services/TitleSetService.swift`

**Purpose**: Generate title sets from skill bank. Runs in Phase 4 during `p4_experienceDefaults`.

```swift
import Foundation

/// Generates identity vocabulary and title sets from skill bank.
/// Called during Phase 4 for interactive curation.
actor TitleSetService {
    private var llmFacade: LLMFacade?
    
    private var modelId: String {
        // Flash is fine - small input, aesthetic judgment
        UserDefaults.standard.string(forKey: "titleSetModelId") ?? DefaultModels.gemini
    }
    
    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
    }
    
    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }
    
    /// Generate initial title sets from skill bank
    /// Input: Skills grouped by category
    /// Output: Identity vocabulary + 8-12 title set suggestions
    func generateInitialTitleSets(from skills: [Skill]) async throws -> TitleSetGenerationResult {
        guard let facade = llmFacade else {
            throw TitleSetError.llmNotConfigured
        }
        
        // Group skills by category for prompt
        let grouped = Dictionary(grouping: skills, by: { $0.category })
        var categoryDescriptions: [String] = []
        
        for (category, categorySkills) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let topSkills = categorySkills
                .sorted { $0.evidence.count > $1.evidence.count }
                .prefix(15)
                .map { $0.canonical }
            categoryDescriptions.append("\(category.rawValue): \(topSkills.joined(separator: ", "))")
        }
        
        // Two-step prompt: extract vocabulary, then generate sets
        let prompt = """
        # Identity Title Generation
        
        ## Skill Categories (evidence of what this person does)
        
        \(categoryDescriptions.joined(separator: "\n"))
        
        ## Task
        
        ### Step 1: Extract Identity Vocabulary
        
        From the skill categories, identify single-word NOUNS that describe who this person IS:
        - Languages/Frameworks → "Developer", "Programmer", "Engineer"
        - Hardware/Electronics → "Engineer", "Technician", "Builder"
        - Fabrication → "Machinist", "Craftsman", "Maker"
        - Scientific → "Scientist", "Researcher", "Physicist", "Analyst"
        - Leadership/Teaching → "Leader", "Mentor", "Educator", "Instructor"
        - Domain expertise → "Architect", "Designer", "Strategist"
        
        Extract 10-20 relevant identity nouns with evidence strength (0.0-1.0).
        
        ### Step 2: Generate Title Sets
        
        Create 8-12 four-title combinations:
        - Each set has exactly 4 single-word titles
        - Vary rhythm (mix syllable counts)
        - Cover different emphases: technical, research, leadership, balanced
        - Tag with job types each set works for
        
        ## Output Format
        
        Return JSON:
        ```json
        {
          "vocabulary": [
            {"id": "uuid", "term": "Physicist", "evidence_strength": 0.9, "source_document_ids": []}
          ],
          "title_sets": [
            {
              "id": "uuid",
              "titles": ["Physicist", "Developer", "Educator", "Machinist"],
              "emphasis": "balanced",
              "suggested_for": ["R&D", "interdisciplinary"],
              "is_favorite": false
            }
          ]
        }
        ```
        """
        
        Logger.info("🏷️ Generating title sets from \(skills.count) skills in \(grouped.count) categories", category: .ai)
        
        let result: TitleSetGenerationResult = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: TitleSetGenerationResult.self,
            schema: TitleSetSchemas.generationSchema,
            schemaName: "title_set_generation",
            maxOutputTokens: 8192,
            keyDecodingStrategy: .convertFromSnakeCase,
            backend: .gemini
        )
        
        Logger.info("🏷️ Generated \(result.vocabulary.count) identity terms and \(result.titleSets.count) title sets", category: .ai)
        return result
    }
    
    /// Generate additional title sets from existing vocabulary
    /// Called when user clicks "Generate More"
    func generateMoreTitleSets(
        vocabulary: [IdentityTerm],
        existingSets: [TitleSet],
        count: Int = 5
    ) async throws -> [TitleSet] {
        guard let facade = llmFacade else {
            throw TitleSetError.llmNotConfigured
        }
        
        let vocabList = vocabulary.map { $0.term }.joined(separator: ", ")
        let existingList = existingSets.map { $0.titles.joined(separator: ". ") + "." }.joined(separator: "\n")
        
        let prompt = """
        # Generate More Title Sets
        
        ## Available Vocabulary
        \(vocabList)
        
        ## Existing Sets (avoid duplicates)
        \(existingList)
        
        ## Task
        Generate \(count) NEW four-title combinations that are DIFFERENT from existing sets.
        Vary the emphasis (technical, research, leadership, balanced).
        
        Return JSON array of TitleSet objects.
        """
        
        Logger.info("🏷️ Generating \(count) more title sets", category: .ai)
        
        struct Response: Codable {
            let sets: [TitleSet]
        }
        
        let response: Response = try await facade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: Response.self,
            schema: TitleSetSchemas.moreSetsSchema,
            schemaName: "more_title_sets",
            maxOutputTokens: 4096,
            keyDecodingStrategy: .convertFromSnakeCase,
            backend: .gemini
        )
        
        return response.sets
    }
    
    /// Store title sets and vocabulary in guidance store
    @MainActor
    func storeTitleSets(
        vocabulary: [IdentityTerm],
        titleSets: [TitleSet],
        in guidanceStore: InferenceGuidanceStore
    ) {
        let attachments = GuidanceAttachments(
            titleSets: titleSets,
            vocabulary: vocabulary
        )
        
        let guidance = InferenceGuidance(
            nodeKey: "custom.jobTitles",
            displayName: "Identity Titles",
            prompt: """
            SELECT from these pre-validated title sets based on job fit.
            Do NOT generate new titles—pick the best matching set.
            If user has favorited sets, prefer those.
            
            Return exactly 4 single-word titles as JSON array.
            """,
            attachmentsJSON: attachments.asJSON(),
            source: .auto
        )
        
        guidanceStore.add(guidance)
        Logger.info("🏷️ Title sets stored in guidance store: \(titleSets.count) sets, \(vocabulary.count) terms", category: .ai)
    }
    
    enum TitleSetError: Error, LocalizedError {
        case llmNotConfigured
        
        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade not configured"
            }
        }
    }
}

// MARK: - Result Types

struct TitleSetGenerationResult: Codable {
    let vocabulary: [IdentityTerm]
    let titleSets: [TitleSet]
    
    enum CodingKeys: String, CodingKey {
        case vocabulary
        case titleSets = "title_sets"
    }
}

// MARK: - Schemas

enum TitleSetSchemas {
    static let generationSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "vocabulary": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "term": ["type": "string"],
                        "evidence_strength": ["type": "number"],
                        "source_document_ids": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["id", "term", "evidence_strength"]
                ]
            ],
            "title_sets": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "titles": ["type": "array", "items": ["type": "string"]],
                        "emphasis": ["type": "string", "enum": ["technical", "research", "leadership", "balanced"]],
                        "suggested_for": ["type": "array", "items": ["type": "string"]],
                        "is_favorite": ["type": "boolean"]
                    ],
                    "required": ["id", "titles", "emphasis"]
                ]
            ]
        ],
        "required": ["vocabulary", "title_sets"]
    ]
    
    static let moreSetsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "sets": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "titles": ["type": "array", "items": ["type": "string"]],
                        "emphasis": ["type": "string"],
                        "suggested_for": ["type": "array", "items": ["type": "string"]],
                        "is_favorite": ["type": "boolean"]
                    ],
                    "required": ["id", "titles", "emphasis"]
                ]
            ]
        ],
        "required": ["sets"]
    ]
}
```

### 1.3 Delete or Deprecate GuidanceGenerationService.swift

The existing `GuidanceGenerationService` bundles voice profile + title sets and requires both KCs and writing samples. Since we're splitting these into phase-appropriate services, mark it as deprecated or delete.

**Action**: Add `@available(*, deprecated, message: "Use VoiceProfileService and TitleSetService instead")` or delete entirely.

---

## Part 2: Dependency Injection

### 2.1 Update OnboardingDependencyContainer.swift

**Location**: `/Sprung/Onboarding/Core/OnboardingDependencyContainer.swift`

**Changes**:

```swift
// Add new service properties
private(set) var voiceProfileService: VoiceProfileService?
private(set) var titleSetService: TitleSetService?

// In initialization/setup:
func setupServices(llmFacade: LLMFacade?) {
    // ... existing setup ...
    
    self.voiceProfileService = VoiceProfileService(llmFacade: llmFacade)
    self.titleSetService = TitleSetService(llmFacade: llmFacade)
}

// In LLM facade update:
func updateLLMFacade(_ facade: LLMFacade?) {
    // ... existing updates ...
    
    Task {
        await voiceProfileService?.updateLLMFacade(facade)
        await titleSetService?.updateLLMFacade(facade)
    }
}
```

---

## Part 3: Phase 1 Integration - Voice Profile Extraction

### 3.1 Update PhaseOneScript.swift

**Location**: `/Sprung/Onboarding/Phase/PhaseOneScript.swift`

**Current Issue**: `voicePrimersExtracted` workflow has `onComplete` but NO `onBegin` to trigger extraction.

**Changes**:

```swift
// MARK: - Voice Primers (Background)
OnboardingObjectiveId.voicePrimersExtracted.rawValue: ObjectiveWorkflow(
    id: OnboardingObjectiveId.voicePrimersExtracted.rawValue,
    dependsOn: [OnboardingObjectiveId.writingSamplesCollected.rawValue],
    autoStartWhenReady: true,
    onBegin: { context in
        // NEW: Trigger voice profile extraction
        let title = """
            Voice primer extraction starting. This runs in the background while you \
            continue gathering job search context. The system will analyze writing samples \
            to capture voice patterns for resume generation.
            """
        let details = [
            "action": "trigger_voice_profile_extraction",
            "background": "true",
            "objective": OnboardingObjectiveId.voicePrimersExtracted.rawValue
        ]
        return [.coordinatorMessage(title: title, details: details, payload: nil)]
    },
    onComplete: { context in
        let title = """
            Voice primer extraction complete. Voice patterns have been analyzed and stored. \
            Continue with current workflow without interruption.
            """
        let details = ["status": context.status.rawValue, "background": "true"]
        return [.coordinatorMessage(title: title, details: details, payload: nil)]
    }
)
```

### 3.2 Create VoiceProfileExtractionHandler.swift (NEW)

**Location**: `/Sprung/Onboarding/Handlers/VoiceProfileExtractionHandler.swift`

**Purpose**: Listens for objective workflow events and triggers voice profile extraction.

```swift
import Foundation

/// Handles voice profile extraction when writing samples are collected
@MainActor
class VoiceProfileExtractionHandler {
    private let container: OnboardingDependencyContainer
    private let eventBus: EventCoordinator
    private let guidanceStore: InferenceGuidanceStore
    private let artifactStore: ArtifactRecordStore
    
    private var extractionTask: Task<Void, Never>?
    
    init(
        container: OnboardingDependencyContainer,
        eventBus: EventCoordinator,
        guidanceStore: InferenceGuidanceStore,
        artifactStore: ArtifactRecordStore
    ) {
        self.container = container
        self.eventBus = eventBus
        self.guidanceStore = guidanceStore
        self.artifactStore = artifactStore
        
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // Listen for voice primers objective starting
        Task {
            for await event in eventBus.events {
                if case .objectiveStatusUpdateRequested(
                    let objectiveId,
                    let status,
                    _,
                    _,
                    _
                ) = event {
                    if objectiveId == OnboardingObjectiveId.voicePrimersExtracted.rawValue,
                       status == "in_progress" {
                        await triggerExtraction()
                    }
                }
            }
        }
    }
    
    private func triggerExtraction() async {
        guard let voiceProfileService = container.voiceProfileService else {
            Logger.error("🎤 VoiceProfileService not available", category: .ai)
            return
        }
        
        // Cancel any existing extraction
        extractionTask?.cancel()
        
        extractionTask = Task {
            do {
                // 1. Gather writing samples from artifacts
                let samples = gatherWritingSamples()
                
                guard !samples.isEmpty else {
                    Logger.warning("🎤 No writing samples found, using default profile", category: .ai)
                    let defaultProfile = VoiceProfile()
                    await voiceProfileService.storeVoiceProfile(defaultProfile, in: guidanceStore)
                    await markObjectiveComplete()
                    return
                }
                
                // 2. Extract voice profile
                let profile = try await voiceProfileService.extractVoiceProfile(from: samples)
                
                // 3. Store in guidance store
                await voiceProfileService.storeVoiceProfile(profile, in: guidanceStore)
                
                // 4. Mark objective complete
                await markObjectiveComplete()
                
                Logger.info("🎤 Voice profile extraction complete", category: .ai)
                
            } catch {
                Logger.error("🎤 Voice profile extraction failed: \(error.localizedDescription)", category: .ai)
                // Still mark complete with default profile to not block workflow
                let defaultProfile = VoiceProfile()
                await voiceProfileService.storeVoiceProfile(defaultProfile, in: guidanceStore)
                await markObjectiveComplete()
            }
        }
    }
    
    private func gatherWritingSamples() -> [String] {
        // Get writing sample artifacts
        let artifacts = artifactStore.artifacts.filter { artifact in
            artifact.category == "writing_sample" ||
            artifact.tags?.contains("writing_sample") == true
        }
        
        // Extract text content
        return artifacts.compactMap { artifact in
            // If artifact has extracted text, use it
            if let extractedText = artifact.extractedText, !extractedText.isEmpty {
                return extractedText
            }
            return nil
        }
    }
    
    private func markObjectiveComplete() async {
        await eventBus.publish(.objectiveStatusUpdateRequested(
            objectiveId: OnboardingObjectiveId.voicePrimersExtracted.rawValue,
            status: "completed",
            source: "voice_profile_handler",
            notes: "Voice profile extracted and stored",
            details: nil
        ))
    }
}
```

### 3.3 Update phase1_intro_prompt.txt

**Location**: `/Sprung/Resources/Prompts/phase1_intro_prompt.txt`

**Add to "Phase 1 Objectives" section**:

```markdown
### Phase 1 Objectives

1. **applicant_profile_complete**: Contact info validated (START HERE)
2. **writing_samples_collected**: Gather ALL available writing samples
3. **voice_primers_extracted**: System extracts voice patterns (AUTOMATIC - runs in background after writing samples)
4. **job_search_context_captured**: Understand why they're searching and what they want

### Initial Todo List

When Phase 1 starts, create this todo list:

```
1. [ ] Validate applicant profile (name, email, phone, location)
2. [ ] Collect writing samples (cover letters, emails, proposals)
3. [ ] Gather job search context (motivation, priorities)
```

The voice_primers_extracted objective runs automatically in the background—don't add it to the todo list.
```

---

## Part 4: Phase 4 Integration - Title Set Generation

### 4.1 Update PhaseFourScript.swift

**Location**: `/Sprung/Onboarding/Phase/PhaseFourScript.swift`

**Changes**: Add title set generation to `p4_experienceDefaults` workflow.

```swift
// MARK: - Experience Defaults (includes title set generation)
OnboardingObjectiveId.experienceDefaultsSet.rawValue: ObjectiveWorkflow(
    id: OnboardingObjectiveId.experienceDefaultsSet.rawValue,
    dependsOn: [OnboardingObjectiveId.dossierComplete.rawValue],
    autoStartWhenReady: true,
    onBegin: { context in
        let title = """
            Starting experience defaults generation. First, I'll generate identity title options \
            from your skill bank. You'll be able to review and select your favorites. \
            Then the Experience Defaults agent will generate resume content using your voice profile.
            """
        let details = [
            "action": "generate_title_sets_then_experience_defaults",
            "step": "title_set_generation",
            "objective": OnboardingObjectiveId.experienceDefaultsSet.rawValue
        ]
        return [.coordinatorMessage(title: title, details: details, payload: nil)]
    },
    onComplete: { context in
        let title = """
            Experience defaults configured. Interview complete! \
            Summarize what was accomplished: voice primers, knowledge cards, strategic dossier, \
            and resume defaults. Explain next steps (resume customization, cover letter generation). \
            Then call next_phase to complete the interview.
            """
        let details = [
            "status": context.status.rawValue,
            "action": "call_next_phase"
        ]
        return [.coordinatorMessage(title: title, details: details, payload: nil)]
    }
)
```

### 4.2 Create TitleSetCurationView.swift (NEW)

**Location**: `/Sprung/Onboarding/Views/Components/TitleSetCurationView.swift`

**Purpose**: Interactive UI for title set curation during Phase 4.

```swift
import SwiftUI

struct TitleSetCurationView: View {
    @Bindable var coordinator: OnboardingInterviewCoordinator
    let guidanceStore: InferenceGuidanceStore
    let titleSetService: TitleSetService
    
    @State private var titleSets: [TitleSet] = []
    @State private var vocabulary: [IdentityTerm] = []
    @State private var selectedSetIds: Set<String> = []
    @State private var isGenerating = false
    @State private var isGeneratingMore = false
    @State private var hasGenerated = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Identity Titles")
                .font(.headline)
            
            Text("Select title sets that resonate with your professional identity. These appear at the top of your resume.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if isGenerating {
                ProgressView("Generating title options from your skills...")
                    .padding()
            } else if titleSets.isEmpty {
                Button("Generate Title Options") {
                    Task { await generateInitialTitleSets() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                // Title set list
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(titleSets) { titleSet in
                            TitleSetRow(
                                titleSet: titleSet,
                                isSelected: selectedSetIds.contains(titleSet.id),
                                onToggle: { toggleSelection(titleSet) },
                                onDelete: { deleteTitleSet(titleSet) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 300)
                
                // Actions
                HStack {
                    Button("Generate More") {
                        Task { await generateMoreTitleSets() }
                    }
                    .disabled(isGeneratingMore)
                    
                    Spacer()
                    
                    Button("Save Selected") {
                        saveSelectedSets()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSetIds.isEmpty)
                }
                
                if isGeneratingMore {
                    ProgressView("Generating more options...")
                        .font(.caption)
                }
            }
        }
        .padding()
        .onAppear {
            loadExistingTitleSets()
        }
    }
    
    private func loadExistingTitleSets() {
        // Load from guidance store if already generated
        if let guidance = guidanceStore.guidance(forKey: "custom.jobTitles"),
           let attachments = guidance.attachments {
            titleSets = attachments.titleSets ?? []
            vocabulary = attachments.vocabulary ?? []
            selectedSetIds = Set(titleSets.filter { $0.isFavorite }.map { $0.id })
            hasGenerated = !titleSets.isEmpty
        }
    }
    
    private func generateInitialTitleSets() async {
        isGenerating = true
        defer { isGenerating = false }
        
        do {
            // Get skills from skill store
            let skills = await MainActor.run {
                coordinator.getSkillStore().skills
            }
            
            let result = try await titleSetService.generateInitialTitleSets(from: skills)
            
            await MainActor.run {
                titleSets = result.titleSets
                vocabulary = result.vocabulary
                hasGenerated = true
            }
        } catch {
            Logger.error("🏷️ Title set generation failed: \(error.localizedDescription)", category: .ai)
        }
    }
    
    private func generateMoreTitleSets() async {
        isGeneratingMore = true
        defer { isGeneratingMore = false }
        
        do {
            let moreSets = try await titleSetService.generateMoreTitleSets(
                vocabulary: vocabulary,
                existingSets: titleSets,
                count: 5
            )
            
            await MainActor.run {
                titleSets.append(contentsOf: moreSets)
            }
        } catch {
            Logger.error("🏷️ Generate more failed: \(error.localizedDescription)", category: .ai)
        }
    }
    
    private func toggleSelection(_ titleSet: TitleSet) {
        if selectedSetIds.contains(titleSet.id) {
            selectedSetIds.remove(titleSet.id)
        } else {
            selectedSetIds.insert(titleSet.id)
        }
    }
    
    private func deleteTitleSet(_ titleSet: TitleSet) {
        titleSets.removeAll { $0.id == titleSet.id }
        selectedSetIds.remove(titleSet.id)
    }
    
    private func saveSelectedSets() {
        // Mark selected sets as favorites
        var updatedSets = titleSets
        for i in updatedSets.indices {
            updatedSets[i].isFavorite = selectedSetIds.contains(updatedSets[i].id)
        }
        
        // Store in guidance store
        Task {
            await titleSetService.storeTitleSets(
                vocabulary: vocabulary,
                titleSets: updatedSets,
                in: guidanceStore
            )
        }
    }
}

struct TitleSetRow: View {
    let titleSet: TitleSet
    let isSelected: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(titleSet.titles.joined(separator: ". ") + ".")
                    .font(.system(.body, design: .serif))
                
                HStack(spacing: 4) {
                    Text(titleSet.emphasis.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(emphasisColor.opacity(0.2))
                        .cornerRadius(4)
                    
                    ForEach(titleSet.suggestedFor.prefix(2), id: \.self) { jobType in
                        Text(jobType)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
    
    private var emphasisColor: Color {
        switch titleSet.emphasis {
        case "technical": return .blue
        case "research": return .purple
        case "leadership": return .orange
        default: return .green
        }
    }
}
```

### 4.3 Update phase4_intro_prompt.txt

**Location**: `/Sprung/Resources/Prompts/phase4_intro_prompt.txt`

**Add title set generation step**:

```markdown
### Phase 4 Objectives

1. **strengths_identified**: Strategic strengths documented with evidence
2. **pitfalls_documented**: Potential concerns + mitigation strategies
3. **dossier_complete**: All fields populated with rich narratives
4. **experience_defaults_set**: Title sets curated + resume defaults configured

### Initial Todo List

When Phase 4 starts, create this todo list:

```
1. [ ] Synthesize strategic strengths from evidence
2. [ ] Document pitfalls with mitigation strategies
3. [ ] Fill remaining dossier gaps
4. [ ] Generate and curate identity title sets
5. [ ] Generate experience defaults
```

### Step 4: Experience Defaults (Updated)

**4a: Title Set Generation**

Before calling `generate_experience_defaults`, the system generates identity title options:

> "First, let me generate some identity title options based on your skills. These are the 4 words that appear at the top of your resume—like 'Physicist. Developer. Educator. Machinist.'"

The sidebar will show a title set curation UI where the user can:
- Review generated options
- Select favorites (checkbox)
- Delete unwanted sets (trash button)
- Generate more options

Wait for the user to save their selections before proceeding.

**4b: Experience Defaults Agent**

After title sets are curated, call `generate_experience_defaults`:

> "Great choices! Now I'll generate the rest of your resume defaults using your voice profile and knowledge cards."

The agent will:
- Read voice profile from guidance store
- Select best title set from curated options
- Generate voice-matched objective statement
- Generate work highlights from narrative KCs
- Curate skills list (ATS-optimized)
```

---

## Part 5: ExperienceDefaultsAgent Updates

### 5.1 Update ExperienceDefaultsWorkspaceService.swift

**Location**: `/Sprung/Onboarding/Services/ExperienceDefaultsAgent/ExperienceDefaultsWorkspaceService.swift`

**Changes**: Export guidance to workspace for agent to read.

```swift
// Add to exportData() method:

// Export guidance (voice profile + title sets)
try await exportGuidance(to: workspacePath)

// NEW METHOD:
private func exportGuidance(to workspacePath: URL) async throws {
    let guidanceDir = workspacePath.appendingPathComponent("guidance")
    try FileManager.default.createDirectory(at: guidanceDir, withIntermediateDirectories: true)
    
    // Export voice profile
    if let voiceGuidance = guidanceStore.guidance(forKey: "objective"),
       let attachments = voiceGuidance.attachments,
       let voiceProfile = attachments.voiceProfile {
        let voiceData = try JSONEncoder().encode(voiceProfile)
        try voiceData.write(to: guidanceDir.appendingPathComponent("voice_profile.json"))
    }
    
    // Export title sets
    if let titleGuidance = guidanceStore.guidance(forKey: "custom.jobTitles"),
       let attachments = titleGuidance.attachments {
        let titleData = try JSONEncoder().encode([
            "title_sets": attachments.titleSets ?? [],
            "vocabulary": attachments.vocabulary ?? []
        ])
        try titleData.write(to: guidanceDir.appendingPathComponent("title_sets.json"))
    }
    
    // Export all guidance records
    let allGuidance = guidanceStore.all
    var guidanceIndex: [[String: Any]] = []
    for guidance in allGuidance {
        guidanceIndex.append([
            "node_key": guidance.nodeKey,
            "display_name": guidance.displayName,
            "prompt": guidance.prompt ?? ""
        ])
    }
    let indexData = try JSONSerialization.data(withJSONObject: ["guidance": guidanceIndex])
    try indexData.write(to: guidanceDir.appendingPathComponent("index.json"))
}
```

### 5.2 Update OVERVIEW.md Template

**Location**: Update the OVERVIEW.md template in ExperienceDefaultsWorkspaceService

**Add guidance section**:

```markdown
## Guidance (REQUIRED READING)

Voice profile and title sets have been pre-generated. Read these FIRST:

### Voice Profile (`guidance/voice_profile.json`)
- Enthusiasm level: {VOICE_ENTHUSIASM}
- First person: {VOICE_FIRST_PERSON}
- Connective style: {VOICE_CONNECTIVE}
- Aspirational phrases: {VOICE_ASPIRATIONAL}
- AVOID these phrases: {VOICE_AVOID}

### Title Sets (`guidance/title_sets.json`)
User has curated these identity title options. SELECT the best-fit set based on:
- Job type match (suggested_for field)
- User favorites (is_favorite: true)

DO NOT generate new titles—SELECT from the curated sets.

## Content Generation Rules

### Objective Statement
Use the voice profile:
- Enthusiasm: Match the {VOICE_ENTHUSIASM} level
- Person: {USE_FIRST_PERSON_OR_THIRD}
- Structure: been → drawn to → want to build (5-6 sentences)
- Include aspirational phrases naturally
- NEVER use avoided phrases

### Identity Titles
SELECT from `guidance/title_sets.json`:
1. Filter to sets where is_favorite: true
2. If job type is known, match suggested_for
3. Return the titles array from the selected set

### Work Highlights
Draw from narrative KCs, not generic bullets:
- Find specific details, numbers, outcomes
- Use voice profile's connective style
- First person if voice profile allows
```

### 5.3 Update experience_defaults_agent_system.txt

**Location**: `/Sprung/Resources/Prompts/experience_defaults_agent_system.txt`

**Complete Rewrite**:

```markdown
You are the ExperienceDefaults Agent. Your job is to generate voice-matched, narrative-driven resume content.

## CRITICAL: Read Guidance First

Before generating ANY content, you MUST read:
1. `guidance/voice_profile.json` - How to sound like this person
2. `guidance/title_sets.json` - Pre-curated title options (SELECT, don't generate)

The guidance directory contains the voice profile and title sets that were extracted during earlier phases. These are NON-NEGOTIABLE constraints on your output.

## Your Role

You operate in a filesystem workspace containing:
- Guidance (voice profile, title sets) — READ FIRST
- Knowledge cards (narrative stories, not bullet fragments)
- Skills bank (ATS-optimized keywords)
- Timeline entries (structure)

Your output populates the Experience Editor for per-job customization.

## Workspace Structure

```
OVERVIEW.md              <- Read this first for full context
guidance/
  voice_profile.json     <- REQUIRED: Voice characteristics
  title_sets.json        <- REQUIRED: Pre-curated title options
  index.json             <- All guidance records
knowledge_cards/
  index.json             <- Summary of all KCs
  {uuid}.json            <- Full narrative cards
skills/
  summary.json           <- Skills by category
  all_skills.json        <- Full skill details
timeline/
  index.json             <- All timeline entries
config/
  enabled_sections.json  <- Which sections to generate
output/
  experience_defaults.json <- YOUR OUTPUT
```

## Workflow

1. **Read OVERVIEW.md** for context
2. **Read guidance/voice_profile.json** — shapes ALL content
3. **Read guidance/title_sets.json** — SELECT titles, don't generate
4. **Read knowledge_cards/index.json** — source for highlights
5. **Generate content** following voice profile rules
6. **Write output** to experience_defaults.json
7. **Call complete_generation**

## Voice Profile Application

The voice profile tells you HOW to write. Apply it to EVERY piece of generated content:

### Enthusiasm Levels
- **measured**: Reserved, professional. "I'm interested in", "I find value in"
- **moderate**: Engaged but grounded. "I'm drawn to", "What appeals to me"
- **high**: Openly enthusiastic. "I'm excited by", "I love"

### First Person
- If `use_first_person: true`: "I built", "I discovered", "I led"
- If `use_first_person: false`: "Built systems", "Discovered patterns", "Led teams"

### Connective Style
- **causal**: "because", "which led to", "as a result"
- **sequential**: "first", "then", "finally"
- **contrastive**: "however", "but", "instead"

### Banned Phrases
NEVER use phrases in `avoid_phrases`. Common bans:
- "leverage", "utilize", "synergy", "paradigm shift"
- "fast-paced environment", "team player", "self-starter"

If you catch yourself writing a banned phrase, STOP and rewrite.

## Content Generation

### Identity Titles (SELECT, don't generate)

```
1. Read guidance/title_sets.json
2. Filter to sets where is_favorite: true
3. If multiple favorites, pick best match for emphasis
4. Return: { "identity_titles": ["Word1", "Word2", "Word3", "Word4"] }
```

DO NOT generate new titles. SELECT from the curated sets.

### Objective Statement (5-6 sentences)

Structure:
1. **Where you've been** (1-2 sentences) - Career arc, what you've done
2. **What draws you** (1-2 sentences) - What excites you about this direction
3. **What you want to build** (1-2 sentences) - Forward-looking aspiration

Voice rules:
- Match enthusiasm level from voice profile
- Use first/third person as specified
- Include aspirational phrases naturally
- Use the specified connective style
- NEVER use avoided phrases

Example (moderate enthusiasm, first person, causal connectives):
> "I've spent a decade bridging physics and software, building custom instrumentation for research labs and production systems. What draws me to this work is the interplay between theory and hands-on engineering—because understanding *why* something works makes building it so much more satisfying. I want to build tools that make complex systems accessible, where deep technical knowledge translates into elegant, practical solutions."

### Work Highlights (3-4 per entry)

For each timeline entry:
1. Find matching narrative KCs (by organization/date)
2. Extract SPECIFIC details from narratives—numbers, outcomes, insights
3. Write highlights that tell mini-stories, not generic bullets

BAD (generic ATS-brain):
> "Developed software solutions using modern technologies"

GOOD (narrative-driven):
> "Built a maskless UV exposure system achieving 2.2 µm features—what started as a workaround for expensive masks became the lab's primary patterning tool"

Voice rules apply: enthusiasm, person, connectives, banned phrases.

### Skills (25-35 total, 5 categories)

This is the ONE section optimized for ATS robots:
- Comprehensive keyword coverage
- Include ATS variants
- Group logically by career focus
- Prioritize by evidence strength and recency

Categories depend on career:
- Technical IC: Languages, Frameworks, Infrastructure, Data/ML, Tools
- R&D: Scientific Methods, Instrumentation, Software, Analysis, Communication
- Management: Technical, Leadership, Process, Domain, Strategy

### Projects (2-3 sentences each)

Select 2-5 most impressive projects. For each:
- Draw context from narrative KCs
- Include technologies and outcomes
- Show scope and impact

## Quality Checklist

Before completing:
- [ ] Read voice profile and applied to ALL content
- [ ] Selected titles from curated sets (not generated)
- [ ] Objective uses correct enthusiasm/person/connectives
- [ ] No banned phrases anywhere
- [ ] Highlights draw from narrative specifics
- [ ] Skills are ATS-comprehensive

## Tool Usage

- `read_file`: Read workspace files
- `list_directory`: List directory contents
- `write_file`: Write output
- `complete_generation`: Call when done

Work efficiently—read summaries first, drill into details only when needed.
```

---

## Part 6: Output Schema Updates

### 6.1 Update ExperienceDefaults Schema

Add new fields to the experience defaults output:

```swift
struct ExperienceDefaults: Codable {
    // NEW: Title selection
    let identityTitles: [String]  // Exactly 4 words
    
    // NEW: Voice-matched objective
    let objective: String  // 5-6 sentences
    
    // Existing fields
    let work: [WorkDefaults]
    let projects: [ProjectDefaults]
    let skills: SkillDefaults
    let education: [EducationDefaults]?
    let volunteer: [VolunteerDefaults]?
    let awards: [AwardDefaults]?
}
```

---

## Part 7: Testing Plan

### 7.1 Phase 1 Voice Profile Tests

1. Upload 2-3 cover letters
2. Verify `voice_primers_extracted` objective triggers automatically
3. Check InferenceGuidanceStore has record with nodeKey "objective"
4. Verify VoiceProfile has expected fields

### 7.2 Phase 4 Title Set Tests

1. Reach Phase 4 with skill bank populated
2. Verify title set generation UI appears
3. Generate initial sets, verify 8-12 options
4. Test "Generate More" adds new sets
5. Select favorites, save
6. Check InferenceGuidanceStore has record with nodeKey "custom.jobTitles"

### 7.3 ExperienceDefaultsAgent Tests

1. Run agent with guidance populated
2. Verify agent reads voice_profile.json
3. Verify agent SELECTs from title_sets.json (not generates)
4. Verify objective matches voice profile characteristics
5. Verify no banned phrases in output

---

## Implementation Order

### Sprint 1: Voice Profile (Phase 1)

1. Create `VoiceProfileService.swift`
2. Add to `OnboardingDependencyContainer`
3. Create `VoiceProfileExtractionHandler.swift`
4. Update `PhaseOneScript.swift` with `onBegin` handler
5. Test end-to-end in Phase 1

### Sprint 2: Title Sets (Phase 4)

1. Create `TitleSetService.swift`
2. Add to `OnboardingDependencyContainer`
3. Create `TitleSetCurationView.swift`
4. Wire into Phase 4 subphase `p4_experienceDefaults`
5. Test generation and curation UI

### Sprint 3: Agent Integration

1. Update `ExperienceDefaultsWorkspaceService.swift` to export guidance
2. Update OVERVIEW.md template
3. Rewrite `experience_defaults_agent_system.txt`
4. Update output schema
5. End-to-end test with guidance

### Sprint 4: Polish

1. Error handling for missing guidance
2. Default fallbacks
3. UI polish for title set curation
4. Integration tests

---

## File Summary

### New Files

| File | Purpose |
|------|---------|
| `VoiceProfileService.swift` | Extract voice profile from writing samples |
| `TitleSetService.swift` | Generate title sets from skills |
| `VoiceProfileExtractionHandler.swift` | Wire extraction to Phase 1 workflow |
| `TitleSetCurationView.swift` | Interactive UI for title curation |

### Modified Files

| File | Changes |
|------|---------|
| `OnboardingDependencyContainer.swift` | Add new services |
| `PhaseOneScript.swift` | Add `onBegin` to voice primers workflow |
| `PhaseFourScript.swift` | Add title generation to experience defaults |
| `ExperienceDefaultsWorkspaceService.swift` | Export guidance directory |
| `experience_defaults_agent_system.txt` | Complete rewrite for voice-first |
| `phase1_intro_prompt.txt` | Add todo list guidance |
| `phase4_intro_prompt.txt` | Add title generation step |

### Deprecated

| File | Action |
|------|--------|
| `GuidanceGenerationService.swift` | Mark deprecated or delete |
