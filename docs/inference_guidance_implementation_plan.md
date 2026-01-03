# Inference Guidance System: Implementation Plan

## Overview

A general-purpose mechanism for attaching node-specific prompting to resume tree nodes. Applied at inference time to guide customization without special-casing individual fields.

**Parallel to KC rewrite—no dependencies.**

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  InferenceGuidanceStore (@Observable, @MainActor)           │
│  - CRUD for InferenceGuidance records                       │
│  - Injected via @Environment                                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  InferenceGuidance (@Model)                                 │
│  - nodeKey: String                                          │
│  - prompt: String                                           │
│  - attachmentsJSON: String?                                 │
│  - source: GuidanceSource                                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Supporting Types (Codable, stored in attachmentsJSON)      │
│  - TitleSet, IdentityTerm, VoiceProfile                     │
└─────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
Sprung/
├── DataManagers/
│   └── InferenceGuidanceStore.swift      # NEW
├── Models/
│   └── InferenceGuidance.swift           # NEW (@Model)
├── Shared/
│   └── InferenceGuidanceTypes.swift      # NEW (TitleSet, VoiceProfile, etc.)
├── Onboarding/
│   └── Services/
│       └── GuidanceGenerationService.swift  # NEW (auto-generation during onboarding)
├── Resources/
│   └── Prompts/
│       ├── identity_vocabulary_extraction.txt   # NEW
│       ├── title_set_generation.txt             # NEW
│       └── voice_profile_extraction.txt         # NEW
└── Views/
    └── InferenceGuidanceEditor/          # NEW (UI panel)
        ├── InferenceGuidanceListView.swift
        ├── GuidanceDetailView.swift
        └── TitleSetEditorView.swift
```

---

## Phase 1: Data Model

### `Models/InferenceGuidance.swift`

```swift
import Foundation
import SwiftData

/// Source of guidance: auto-generated or user-edited
enum GuidanceSource: String, Codable {
    case auto   // Generated during onboarding
    case user   // Manually created or edited
}

/// Node-specific inference guidance, injected at resume customization time
@Model
final class InferenceGuidance {
    var id: UUID
    
    /// Tree node key this guidance applies to
    /// Examples: "custom.jobTitles", "objective", "skills", "experience.*.bullets"
    var nodeKey: String
    
    /// Human-readable name for UI
    var displayName: String
    
    /// Prompt text injected during customization
    /// Can reference {ATTACHMENTS} placeholder for structured data
    var prompt: String
    
    /// Structured data as JSON string (TitleSet[], VoiceProfile, etc.)
    var attachmentsJSON: String?
    
    /// Source: auto-generated or user-edited
    var source: GuidanceSource
    
    /// When created/updated
    var updatedAt: Date
    
    /// Whether this guidance is active (can be disabled without deleting)
    var isEnabled: Bool
    
    init(
        id: UUID = UUID(),
        nodeKey: String,
        displayName: String,
        prompt: String,
        attachmentsJSON: String? = nil,
        source: GuidanceSource = .auto,
        updatedAt: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.nodeKey = nodeKey
        self.displayName = displayName
        self.prompt = prompt
        self.attachmentsJSON = attachmentsJSON
        self.source = source
        self.updatedAt = updatedAt
        self.isEnabled = isEnabled
    }
    
    /// Render prompt with attachments substituted
    func renderedPrompt() -> String {
        guard let json = attachmentsJSON else { return prompt }
        return prompt.replacingOccurrences(of: "{ATTACHMENTS}", with: json)
    }
}
```

### `Shared/InferenceGuidanceTypes.swift`

```swift
import Foundation

// MARK: - Title Sets

/// Pre-validated 4-title combination
struct TitleSet: Codable, Identifiable, Equatable {
    let id: UUID
    var titles: [String]          // Exactly 4
    var emphasis: TitleEmphasis
    var suggestedFor: [String]    // Job types: ["R&D", "software", "academic"]
    var isFavorite: Bool
    
    init(
        id: UUID = UUID(),
        titles: [String],
        emphasis: TitleEmphasis = .balanced,
        suggestedFor: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.titles = titles
        self.emphasis = emphasis
        self.suggestedFor = suggestedFor
        self.isFavorite = isFavorite
    }
    
    /// Display string: "Physicist. Developer. Educator. Machinist."
    var displayString: String {
        titles.joined(separator: ". ") + "."
    }
}

enum TitleEmphasis: String, Codable, CaseIterable {
    case technical
    case research
    case leadership
    case balanced
    
    var displayName: String {
        rawValue.capitalized
    }
}

/// Identity vocabulary term extracted from documents
struct IdentityTerm: Codable, Identifiable, Equatable {
    let id: UUID
    var term: String              // "Physicist", "Developer"
    var evidenceStrength: Double  // 0-1
    var sourceDocumentIds: [String]
    
    init(
        id: UUID = UUID(),
        term: String,
        evidenceStrength: Double = 0.5,
        sourceDocumentIds: [String] = []
    ) {
        self.id = id
        self.term = term
        self.evidenceStrength = evidenceStrength
        self.sourceDocumentIds = sourceDocumentIds
    }
}

// MARK: - Voice Profile

/// Extracted voice characteristics for objective/narrative generation
struct VoiceProfile: Codable, Equatable {
    var enthusiasm: EnthusiasmLevel
    var useFirstPerson: Bool
    var connectiveStyle: String         // "causal", "sequential", "contrastive"
    var aspirationalPhrases: [String]   // "What excites me...", "I want to build..."
    var avoidPhrases: [String]          // "leverage", "utilize", "synergy"
    var sampleExcerpts: [String]        // Verbatim voice samples
    
    init(
        enthusiasm: EnthusiasmLevel = .moderate,
        useFirstPerson: Bool = true,
        connectiveStyle: String = "causal",
        aspirationalPhrases: [String] = [],
        avoidPhrases: [String] = [],
        sampleExcerpts: [String] = []
    ) {
        self.enthusiasm = enthusiasm
        self.useFirstPerson = useFirstPerson
        self.connectiveStyle = connectiveStyle
        self.aspirationalPhrases = aspirationalPhrases
        self.avoidPhrases = avoidPhrases
        self.sampleExcerpts = sampleExcerpts
    }
}

enum EnthusiasmLevel: String, Codable, CaseIterable {
    case measured   // "I'm interested in..."
    case moderate   // "I'm drawn to...", "What appeals to me..."
    case high       // "I'm excited by...", "I love..."
    
    var displayName: String {
        switch self {
        case .measured: return "Measured"
        case .moderate: return "Moderate"
        case .high: return "Enthusiastic"
        }
    }
    
    var examplePhrases: [String] {
        switch self {
        case .measured: return ["I'm interested in", "I find value in", "I appreciate"]
        case .moderate: return ["I'm drawn to", "What appeals to me", "I enjoy"]
        case .high: return ["I'm excited by", "I love", "I'm passionate about"]
        }
    }
}

// MARK: - Attachment Container

/// Container for structured attachments stored in InferenceGuidance.attachmentsJSON
struct GuidanceAttachments: Codable {
    var titleSets: [TitleSet]?
    var vocabulary: [IdentityTerm]?
    var voiceProfile: VoiceProfile?
    
    init(
        titleSets: [TitleSet]? = nil,
        vocabulary: [IdentityTerm]? = nil,
        voiceProfile: VoiceProfile? = nil
    ) {
        self.titleSets = titleSets
        self.vocabulary = vocabulary
        self.voiceProfile = voiceProfile
    }
    
    func asJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func from(json: String?) -> GuidanceAttachments? {
        guard let json = json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GuidanceAttachments.self, from: data)
    }
}
```

---

## Phase 2: Store

### `DataManagers/InferenceGuidanceStore.swift`

```swift
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class InferenceGuidanceStore: SwiftDataStore {
    unowned let modelContext: ModelContext
    
    /// All guidance records
    var allGuidance: [InferenceGuidance] {
        let descriptor = FetchDescriptor<InferenceGuidance>(
            sortBy: [SortDescriptor(\.nodeKey)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Only enabled guidance
    var enabledGuidance: [InferenceGuidance] {
        allGuidance.filter { $0.isEnabled }
    }
    
    init(context: ModelContext) {
        modelContext = context
    }
    
    // MARK: - CRUD
    
    func add(_ guidance: InferenceGuidance) {
        modelContext.insert(guidance)
        saveContext()
        Logger.info("📝 Added inference guidance: \(guidance.nodeKey)", category: .data)
    }
    
    func update(_ guidance: InferenceGuidance) {
        guidance.updatedAt = Date()
        saveContext()
        Logger.info("📝 Updated inference guidance: \(guidance.nodeKey)", category: .data)
    }
    
    func delete(_ guidance: InferenceGuidance) {
        modelContext.delete(guidance)
        saveContext()
        Logger.info("🗑️ Deleted inference guidance: \(guidance.nodeKey)", category: .data)
    }
    
    func toggleEnabled(_ guidance: InferenceGuidance) {
        guidance.isEnabled.toggle()
        guidance.updatedAt = Date()
        saveContext()
    }
    
    // MARK: - Queries
    
    /// Get guidance for a specific node key
    func guidance(for nodeKey: String) -> InferenceGuidance? {
        enabledGuidance.first { $0.nodeKey == nodeKey }
    }
    
    /// Get guidance matching a pattern (e.g., "experience.*" matches "experience.job1.bullets")
    func guidanceMatching(pattern: String) -> InferenceGuidance? {
        // Handle wildcard patterns like "experience.*.bullets"
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: "[^.]+")
        
        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$") else {
            return nil
        }
        
        return enabledGuidance.first { guidance in
            let range = NSRange(guidance.nodeKey.startIndex..., in: guidance.nodeKey)
            return regex.firstMatch(in: guidance.nodeKey, range: range) != nil
        }
    }
    
    /// Get rendered prompt for a node key (returns nil if no guidance)
    func renderedPrompt(for nodeKey: String) -> String? {
        guidance(for: nodeKey)?.renderedPrompt()
    }
    
    // MARK: - Title Set Helpers
    
    /// Get title sets from custom.jobTitles guidance
    func titleSets() -> [TitleSet] {
        guard let guidance = guidance(for: "custom.jobTitles"),
              let attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) else {
            return []
        }
        return attachments.titleSets ?? []
    }
    
    /// Get favorited title sets
    func favoriteTitleSets() -> [TitleSet] {
        titleSets().filter { $0.isFavorite }
    }
    
    /// Update title sets (preserves other attachments)
    func updateTitleSets(_ sets: [TitleSet]) {
        guard let guidance = guidance(for: "custom.jobTitles") else {
            Logger.warning("⚠️ No guidance found for custom.jobTitles", category: .data)
            return
        }
        
        var attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) ?? GuidanceAttachments()
        attachments.titleSets = sets
        guidance.attachmentsJSON = attachments.asJSON()
        guidance.updatedAt = Date()
        saveContext()
    }
    
    /// Toggle favorite status on a title set
    func toggleTitleSetFavorite(_ setId: UUID) {
        var sets = titleSets()
        guard let idx = sets.firstIndex(where: { $0.id == setId }) else { return }
        sets[idx].isFavorite.toggle()
        updateTitleSets(sets)
    }
    
    // MARK: - Voice Profile Helpers
    
    /// Get voice profile from objective guidance
    func voiceProfile() -> VoiceProfile? {
        guard let guidance = guidance(for: "objective"),
              let attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) else {
            return nil
        }
        return attachments.voiceProfile
    }
    
    /// Update voice profile
    func updateVoiceProfile(_ profile: VoiceProfile) {
        guard let guidance = guidance(for: "objective") else {
            Logger.warning("⚠️ No guidance found for objective", category: .data)
            return
        }
        
        var attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) ?? GuidanceAttachments()
        attachments.voiceProfile = profile
        guidance.attachmentsJSON = attachments.asJSON()
        guidance.updatedAt = Date()
        saveContext()
    }
    
    // MARK: - Vocabulary Helpers
    
    /// Get identity vocabulary from custom.jobTitles guidance
    func identityVocabulary() -> [IdentityTerm] {
        guard let guidance = guidance(for: "custom.jobTitles"),
              let attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) else {
            return []
        }
        return attachments.vocabulary ?? []
    }
    
    /// Update identity vocabulary
    func updateIdentityVocabulary(_ terms: [IdentityTerm]) {
        guard let guidance = guidance(for: "custom.jobTitles") else {
            Logger.warning("⚠️ No guidance found for custom.jobTitles", category: .data)
            return
        }
        
        var attachments = GuidanceAttachments.from(json: guidance.attachmentsJSON) ?? GuidanceAttachments()
        attachments.vocabulary = terms
        guidance.attachmentsJSON = attachments.asJSON()
        guidance.updatedAt = Date()
        saveContext()
    }
    
    // MARK: - Bulk Operations
    
    /// Delete all auto-generated guidance (for re-running onboarding)
    func deleteAutoGenerated() {
        let autoGuidance = allGuidance.filter { $0.source == .auto }
        for guidance in autoGuidance {
            modelContext.delete(guidance)
        }
        saveContext()
        Logger.info("🗑️ Deleted \(autoGuidance.count) auto-generated guidance records", category: .data)
    }
}
```

---

## Phase 3: Resume Inference Integration

### Injection Point

In `ResumePhaseService` or equivalent, when customizing a node:

```swift
// Add to dependencies
@Environment(InferenceGuidanceStore.self) private var guidanceStore

// In customization method:
func customizeNode(key: String, basePrompt: String, ...) async throws -> String {
    var prompt = basePrompt
    
    // Inject guidance if present
    if let guidance = guidanceStore.guidance(for: key) 
        ?? guidanceStore.guidanceMatching(pattern: key) {
        
        prompt += """
        
        ## Inference Guidance
        \(guidance.renderedPrompt())
        """
        
        Logger.info("📝 Injected guidance for \(key)", category: .ai)
    }
    
    return try await llm.generate(prompt: prompt)
}
```

### Title Selection (not generation)

```swift
func selectTitleSet(for job: JobListing) -> TitleSet? {
    let favorites = guidanceStore.favoriteTitleSets()
    let allSets = favorites.isEmpty ? guidanceStore.titleSets() : favorites
    
    guard !allSets.isEmpty else { return nil }
    
    // Match job type to suggestedFor
    let jobType = job.inferredJobType // "R&D", "software", etc.
    
    // Prefer sets that match job type
    if let match = allSets.first(where: { $0.suggestedFor.contains(jobType) }) {
        return match
    }
    
    // Fall back to balanced or first available
    return allSets.first { $0.emphasis == .balanced } ?? allSets.first
}
```

---

## Phase 4: Onboarding Auto-Generation

### `Onboarding/Services/GuidanceGenerationService.swift`

```swift
import Foundation

actor GuidanceGenerationService {
    private var llmFacade: LLMFacade?
    
    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
    }
    
    /// Generate all guidance from processed documents
    /// Called after document processing completes
    func generateAllGuidance(
        narrativeCards: [KnowledgeCard],
        writingSamples: [String],
        guidanceStore: InferenceGuidanceStore
    ) async throws {
        
        // 1. Extract identity vocabulary
        let vocabulary = try await extractIdentityVocabulary(from: narrativeCards)
        
        // 2. Generate title sets from vocabulary
        let titleSets = try await generateTitleSets(from: vocabulary)
        
        // 3. Extract voice profile from writing samples
        let voiceProfile = try await extractVoiceProfile(from: writingSamples)
        
        // 4. Create guidance records
        await MainActor.run {
            // Title guidance
            let titleAttachments = GuidanceAttachments(
                titleSets: titleSets,
                vocabulary: vocabulary
            )
            
            let titleGuidance = InferenceGuidance(
                nodeKey: "custom.jobTitles",
                displayName: "Identity Titles",
                prompt: """
                SELECT from these pre-validated title sets based on job fit.
                Do NOT generate new titles—pick the best matching set.
                If user has favorited sets, prefer those.
                
                Available sets:
                {ATTACHMENTS}
                
                Return exactly 4 single-word titles as JSON array.
                """,
                attachmentsJSON: titleAttachments.asJSON(),
                source: .auto
            )
            guidanceStore.add(titleGuidance)
            
            // Objective guidance
            let objectiveAttachments = GuidanceAttachments(voiceProfile: voiceProfile)
            
            let objectiveGuidance = InferenceGuidance(
                nodeKey: "objective",
                displayName: "Objective Voice",
                prompt: """
                Voice profile for objective statement:
                - Enthusiasm: \(voiceProfile.enthusiasm.displayName)
                - Person: \(voiceProfile.useFirstPerson ? "First person (I built, I discovered)" : "Third person")
                - Connectives: \(voiceProfile.connectiveStyle)
                - Aspirational phrases: \(voiceProfile.aspirationalPhrases.joined(separator: ", "))
                - NEVER use: \(voiceProfile.avoidPhrases.joined(separator: ", "))
                
                Structure:
                1. Where you've been (1-2 sentences)
                2. What draws you to THIS role (1-2 sentences)
                3. What you want to build (1-2 sentences)
                
                Voice samples:
                {ATTACHMENTS}
                """,
                attachmentsJSON: objectiveAttachments.asJSON(),
                source: .auto
            )
            guidanceStore.add(objectiveGuidance)
            
            Logger.info("✅ Generated inference guidance: \(vocabulary.count) terms, \(titleSets.count) sets", category: .ai)
        }
    }
    
    // MARK: - Extraction Methods
    
    private func extractIdentityVocabulary(from cards: [KnowledgeCard]) async throws -> [IdentityTerm] {
        guard let facade = llmFacade else { throw GuidanceError.llmNotConfigured }
        
        let cardSummaries = cards.map { "\($0.title): \($0.narrative.prefix(300))..." }
            .joined(separator: "\n\n")
        
        let prompt = PromptLibrary.substitute(
            template: PromptLibrary.identityVocabularyTemplate,
            replacements: ["NARRATIVE_CARDS": cardSummaries]
        )
        
        let json = try await facade.generateStructuredJSON(
            prompt: prompt,
            modelId: "gemini-2.5-flash",
            maxOutputTokens: 4096,
            jsonSchema: IdentityVocabularySchema.schema
        )
        
        struct Response: Codable {
            let terms: [IdentityTerm]
        }
        
        let response = try JSONDecoder().decode(Response.self, from: json.data(using: .utf8)!)
        return response.terms
    }
    
    private func generateTitleSets(from vocabulary: [IdentityTerm]) async throws -> [TitleSet] {
        guard let facade = llmFacade else { throw GuidanceError.llmNotConfigured }
        
        // Only use strong terms
        let strongTerms = vocabulary
            .filter { $0.evidenceStrength >= 0.5 }
            .sorted { $0.evidenceStrength > $1.evidenceStrength }
        
        let termsJSON = try JSONEncoder().encode(strongTerms)
        
        let prompt = PromptLibrary.substitute(
            template: PromptLibrary.titleSetGenerationTemplate,
            replacements: ["VOCABULARY_JSON": String(data: termsJSON, encoding: .utf8)!]
        )
        
        let json = try await facade.generateStructuredJSON(
            prompt: prompt,
            modelId: "gemini-2.5-flash",
            maxOutputTokens: 8192,
            jsonSchema: TitleSetSchema.schema
        )
        
        struct Response: Codable {
            let sets: [TitleSet]
        }
        
        let response = try JSONDecoder().decode(Response.self, from: json.data(using: .utf8)!)
        return response.sets
    }
    
    private func extractVoiceProfile(from samples: [String]) async throws -> VoiceProfile {
        guard let facade = llmFacade else { throw GuidanceError.llmNotConfigured }
        
        let samplesText = samples.joined(separator: "\n\n---\n\n")
        
        let prompt = PromptLibrary.substitute(
            template: PromptLibrary.voiceProfileTemplate,
            replacements: ["WRITING_SAMPLES": samplesText]
        )
        
        let json = try await facade.generateStructuredJSON(
            prompt: prompt,
            modelId: "gemini-2.5-flash",
            maxOutputTokens: 4096,
            jsonSchema: VoiceProfileSchema.schema
        )
        
        return try JSONDecoder().decode(VoiceProfile.self, from: json.data(using: .utf8)!)
    }
    
    enum GuidanceError: Error {
        case llmNotConfigured
    }
}
```

---

## Phase 5: UI

### List View

```swift
struct InferenceGuidanceListView: View {
    @Environment(InferenceGuidanceStore.self) private var store
    @State private var selectedGuidance: InferenceGuidance?
    
    var body: some View {
        List(selection: $selectedGuidance) {
            Section("Active Guidance") {
                ForEach(store.enabledGuidance) { guidance in
                    GuidanceRow(guidance: guidance)
                }
            }
            
            Section("Disabled") {
                ForEach(store.allGuidance.filter { !$0.isEnabled }) { guidance in
                    GuidanceRow(guidance: guidance)
                        .opacity(0.6)
                }
            }
        }
        .navigationTitle("Inference Guidance")
    }
}

struct GuidanceRow: View {
    let guidance: InferenceGuidance
    @Environment(InferenceGuidanceStore.self) private var store
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(guidance.displayName)
                    .font(.headline)
                Text(guidance.nodeKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Source badge
            Text(guidance.source.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(guidance.source == .auto ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                .cornerRadius(4)
            
            // Enable toggle
            Toggle("", isOn: Binding(
                get: { guidance.isEnabled },
                set: { _ in store.toggleEnabled(guidance) }
            ))
            .labelsHidden()
        }
    }
}
```

### Title Set Editor

```swift
struct TitleSetEditorView: View {
    @Environment(InferenceGuidanceStore.self) private var store
    @State private var titleSets: [TitleSet] = []
    @State private var vocabulary: [IdentityTerm] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Vocabulary section
            Section {
                FlowLayout(spacing: 8) {
                    ForEach(vocabulary) { term in
                        TermChip(term: term)
                    }
                }
            } header: {
                Text("Identity Vocabulary")
                    .font(.headline)
            }
            
            Divider()
            
            // Title sets
            Section {
                ForEach($titleSets) { $set in
                    TitleSetRow(set: $set, onToggleFavorite: {
                        store.toggleTitleSetFavorite(set.id)
                    })
                }
            } header: {
                Text("Title Sets")
                    .font(.headline)
            }
        }
        .padding()
        .onAppear {
            titleSets = store.titleSets()
            vocabulary = store.identityVocabulary()
        }
    }
}

struct TitleSetRow: View {
    @Binding var set: TitleSet
    let onToggleFavorite: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggleFavorite) {
                Image(systemName: set.isFavorite ? "star.fill" : "star")
                    .foregroundColor(set.isFavorite ? .yellow : .gray)
            }
            .buttonStyle(.plain)
            
            Text(set.displayString)
                .font(.body)
            
            Spacer()
            
            Text(set.emphasis.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

---

## Phase 6: Prompts

### `Prompts/identity_vocabulary_extraction.txt`

```markdown
# Identity Vocabulary Extraction

Extract single-word identity nouns from career narratives.

## Narratives
{NARRATIVE_CARDS}

---

## Task

Extract 10-20 single-word nouns that capture WHO this person IS.

### Guidelines
- Single word only: "Physicist", "Developer", "Machinist"
- Nouns, not adjectives: "Engineer" not "Engineering"
- Identity, not skill: "Builder" not "Building"
- Evidence-based: Rate strength 0.0-1.0

## Output

```json
{
  "terms": [
    {"term": "Physicist", "evidence_strength": 0.95, "source_document_ids": []},
    {"term": "Developer", "evidence_strength": 0.85, "source_document_ids": []}
  ]
}
```
```

### `Prompts/title_set_generation.txt`

```markdown
# Title Set Generation

Generate 4-title combinations from vocabulary.

## Vocabulary
{VOCABULARY_JSON}

---

## Rules

1. Exactly 4 titles per set
2. Single words only (from vocabulary)
3. Vary rhythm—mix syllable counts
4. Each set has emphasis: technical, research, leadership, balanced
5. Generate 12-15 sets

### Good: "Physicist. Developer. Educator. Machinist."
### Bad: "Engineer. Developer. Programmer. Coder." (redundant)

## Output

```json
{
  "sets": [
    {
      "titles": ["Physicist", "Developer", "Educator", "Machinist"],
      "emphasis": "balanced",
      "suggested_for": ["R&D", "interdisciplinary"],
      "is_favorite": false
    }
  ]
}
```
```

### `Prompts/voice_profile_extraction.txt`

```markdown
# Voice Profile Extraction

Analyze writing samples to extract voice characteristics.

## Writing Samples
{WRITING_SAMPLES}

---

## Extract

1. **Enthusiasm level**: measured, moderate, or high
2. **Person**: First person (I/we) or third person
3. **Connective style**: How ideas link (causal, sequential, contrastive)
4. **Aspirational phrases**: How they talk about future/goals
5. **Avoid phrases**: Corporate speak they never use

## Output

```json
{
  "enthusiasm": "moderate",
  "use_first_person": true,
  "connective_style": "causal",
  "aspirational_phrases": ["What excites me", "I want to build"],
  "avoid_phrases": ["leverage", "utilize", "synergy"],
  "sample_excerpts": ["I've amended my design philosophy..."]
}
```
```

---

## File Changes Summary

| File | Action |
|------|--------|
| `Models/InferenceGuidance.swift` | CREATE |
| `Shared/InferenceGuidanceTypes.swift` | CREATE |
| `DataManagers/InferenceGuidanceStore.swift` | CREATE |
| `Onboarding/Services/GuidanceGenerationService.swift` | CREATE |
| `Prompts/identity_vocabulary_extraction.txt` | CREATE |
| `Prompts/title_set_generation.txt` | CREATE |
| `Prompts/voice_profile_extraction.txt` | CREATE |
| `Views/InferenceGuidanceEditor/InferenceGuidanceListView.swift` | CREATE |
| `Views/InferenceGuidanceEditor/TitleSetEditorView.swift` | CREATE |
| `ResumePhaseService.swift` (or equivalent) | UPDATE (inject guidance) |
| `App setup` | UPDATE (register store in environment) |

---

## Success Criteria

1. **Title Selection**: Inference picks from pre-validated sets, not generates
2. **Voice Consistency**: Objectives match candidate's writing style
3. **User Curation**: Favorites respected, edits preserved
4. **Graceful Defaults**: System works without curation, better with it
