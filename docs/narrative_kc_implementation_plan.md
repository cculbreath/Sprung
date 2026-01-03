# Narrative-First Knowledge Cards + Skill Bank

## Resume Structure Mapping

| Section | Source | Purpose |
|---------|--------|---------|
| **Skills** (3-6 categories) | Skill Bank | ATS matching, keyword density |
| **Objective** (5-6 sentences) | Narratives | Voice, aspirations, framing |
| **Titles** (4 identity words) | Narratives | "Physicist. Developer. Educator. Machinist." |
| **Job highlights** (3-4 per job) | Narratives | Specific details from story |
| **Projects** (2-3 with 2-3 sentences) | Narratives | Context, approach, outcomes |

---

## Two Complementary Systems

### 1. Skill Bank (for ATS matching)
- Large, comprehensive coverage
- Every skill tied to evidence (document + location)
- ATS synonyms and related terms
- Categorizable for resume grouping
- Proficiency signals

### 2. Narrative Cards (for everything else)
- 500-2000 word stories per topic
- WHY/JOURNEY/LESSONS structure
- Voice preservation via verbatim excerpts
- Generate bullets/descriptions on demand

---

## Data Models

### Skill Bank

```swift
struct Skill: Codable, Identifiable, Equatable {
    let id: UUID
    let canonical: String           // "Python" (display name)
    let atsVariants: [String]       // ["python", "Python 3", "python3", "Python programming"]
    let category: SkillCategory
    let proficiency: Proficiency
    let evidence: [SkillEvidence]
    let relatedSkills: [UUID]       // Links to related skills
    let lastUsed: String?           // "2024" or "present"
    
    enum CodingKeys: String, CodingKey {
        case id, canonical
        case atsVariants = "ats_variants"
        case category, proficiency, evidence
        case relatedSkills = "related_skills"
        case lastUsed = "last_used"
    }
}

struct SkillEvidence: Codable, Equatable {
    let documentId: String
    let location: String            // "Pages 45-60", "commit abc123"
    let context: String             // Brief description of how skill was used
    let strength: EvidenceStrength  // primary, supporting, mention
    
    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case location, context, strength
    }
}

enum SkillCategory: String, Codable, CaseIterable {
    case languages = "Programming Languages"
    case frameworks = "Frameworks & Libraries"
    case tools = "Tools & Platforms"
    case hardware = "Hardware & Electronics"
    case fabrication = "Fabrication & Manufacturing"
    case scientific = "Scientific & Analysis"
    case soft = "Leadership & Communication"
    case domain = "Domain Expertise"
}

enum Proficiency: String, Codable {
    case expert      // Years of deep use, can teach others
    case proficient  // Regular use, comfortable independently
    case familiar    // Some experience, would need ramp-up
}

enum EvidenceStrength: String, Codable {
    case primary     // Deep demonstration in source
    case supporting  // Significant use shown
    case mention     // Referenced but not demonstrated
}

struct SkillBank: Codable {
    let skills: [Skill]
    let generatedAt: Date
    let sourceDocumentIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case skills
        case generatedAt = "generated_at"
        case sourceDocumentIds = "source_document_ids"
    }
    
    /// Find skills matching ATS terms from job listing
    func matchingSkills(for terms: [String]) -> [Skill] {
        let normalizedTerms = terms.map { $0.lowercased() }
        return skills.filter { skill in
            let allVariants = ([skill.canonical] + skill.atsVariants).map { $0.lowercased() }
            return normalizedTerms.contains { term in
                allVariants.contains { variant in
                    variant.contains(term) || term.contains(variant)
                }
            }
        }
    }
    
    /// Group skills by category
    func groupedByCategory() -> [SkillCategory: [Skill]] {
        Dictionary(grouping: skills, by: { $0.category })
    }
    
    /// Get top N skills per category (by proficiency, then evidence count)
    func topSkills(perCategory limit: Int) -> [SkillCategory: [Skill]] {
        groupedByCategory().mapValues { skills in
            skills.sorted { a, b in
                if a.proficiency != b.proficiency {
                    return a.proficiency.sortOrder < b.proficiency.sortOrder
                }
                return a.evidence.count > b.evidence.count
            }.prefix(limit).map { $0 }
        }
    }
}

extension Proficiency {
    var sortOrder: Int {
        switch self {
        case .expert: return 0
        case .proficient: return 1
        case .familiar: return 2
        }
    }
}
```

### Narrative Card (unchanged from before)

```swift
struct KnowledgeCard: Codable, Identifiable, Equatable {
    let id: UUID
    let cardType: CardType
    let title: String
    let narrative: String
    let evidenceAnchors: [EvidenceAnchor]
    let extractable: ExtractableMetadata
    let dateRange: String?
    let organization: String?
    let relatedCardIds: [UUID]
}
```

---

## Extraction Prompts

### Skill Bank Extraction

#### `Prompts/skill_bank_extraction.txt`

```markdown
# Skill Bank Extraction

Extract a comprehensive skill inventory with evidence.

## Document
- ID: {DOC_ID}
- Filename: {FILENAME}

## Content
{EXTRACTED_CONTENT}

---

## Task

Extract ALL skills demonstrated in this document. Be exhaustive.

### What Counts as a Skill

- Programming languages (Python, Swift, C++)
- Frameworks and libraries (React, FastAPI, PyTorch)
- Tools and platforms (Git, Docker, AWS, SolidWorks)
- Hardware (Arduino, Raspberry Pi, PLCs, oscilloscopes)
- Fabrication (CNC machining, 3D printing, soldering, welding)
- Scientific methods (spectroscopy, microscopy, statistical analysis)
- Domain expertise (liquid crystals, embedded systems, machine learning)
- Soft skills only if DEMONSTRATED (led team of 5, mentored interns)

### Evidence Requirements

Every skill must have evidence from this document:
- **location**: Where in document (page, section, commit)
- **context**: Brief description of how skill was used (10-30 words)
- **strength**: primary (deep use), supporting (significant), mention (referenced)

### ATS Variants

Include common variations employers might search for:
- "Python" → ["python", "Python 3", "python3", "Python programming"]
- "Machine Learning" → ["ML", "machine learning", "deep learning", "neural networks"]
- "SolidWorks" → ["solidworks", "SolidWorks CAD", "3D CAD"]

### Proficiency Signals

Determine proficiency from evidence:
- **expert**: Years of use, teaching others, deep customization
- **proficient**: Regular use, independent work, solid results
- **familiar**: Some exposure, would need ramp-up

### Categories

Assign each skill to ONE category:
- languages, frameworks, tools, hardware, fabrication, scientific, soft, domain

## Output

```json
{
  "skills": [
    {
      "id": "uuid",
      "canonical": "Python",
      "ats_variants": ["python", "Python 3", "python3"],
      "category": "languages",
      "proficiency": "expert",
      "evidence": [
        {
          "document_id": "{DOC_ID}",
          "location": "Pages 45-60",
          "context": "Developed data analysis pipeline processing 10GB datasets",
          "strength": "primary"
        }
      ],
      "related_skills": [],
      "last_used": "present"
    }
  ]
}
```

### Quality Checklist

- [ ] Every skill has at least one evidence entry
- [ ] ATS variants cover common job listing phrasings  
- [ ] Proficiency matches demonstrated depth
- [ ] Categories are appropriate
- [ ] No duplicate skills (consolidate variants)
```

---

### Narrative Card Extraction

#### `Prompts/kc_extraction.txt`

```markdown
# Knowledge Card Extraction

Extract knowledge cards that capture the STORY, not just facts.

## Document
- ID: {DOC_ID}
- Filename: {FILENAME}

## Content
{EXTRACTED_CONTENT}

---

## Card Types

- **employment**: Role at an organization
- **project**: Specific initiative or deliverable
- **achievement**: Award, publication, recognition
- **education**: Degree or credential

NOTE: Skills are extracted separately into the Skill Bank. 
Do NOT create skill-type cards here.

## Narrative Guidelines

Write 500-2000 words per card capturing:

1. **WHY**: What problem was being solved? What motivated the work?
2. **JOURNEY**: How did understanding evolve? What was tried?
3. **LESSONS**: What worked? What didn't? What would be done differently?
4. **VOICE**: Use the author's own words and phrasing
5. **THINKING**: Design decisions, tradeoffs, insights

### Good vs Bad

**GOOD** (captures thinking):
> "The construction was motivated by earlier hand-rotation experiments that suffered from irregularities. It was clear a custom tool would reduce mechanical noise. I spent several weeks on fabrication—over 50 parts machined from raw materials. The design has been successful mechanically, with vibrational noise at ±60nm. But I learned lessons: I failed to include gaskets, and waterproofing under pressure is hard. Research is fluid—the best experiments can be readily extended and reconfigured."

**BAD** (ATS bullets):
> "Designed precision mechanical system. Achieved ±60nm stability. Used SolidWorks and CNC machining."

## Extractable Metadata

For job matching, extract:
- **domains**: Fields of expertise (not individual skills)
- **scale**: Quantified elements (numbers, metrics, scope)
- **keywords**: High-level terms for job matching

Note: Individual skills go in Skill Bank, not here.

## Evidence Anchors

- Page numbers or section references
- 1-2 verbatim excerpts capturing voice (20-50 words each)

## Output

```json
{
  "document_type": "dissertation",
  "cards": [
    {
      "id": "uuid",
      "card_type": "project",
      "title": "Dynamic Confinement System",
      "narrative": "The construction was motivated by... [500-2000 words]",
      "evidence_anchors": [
        {
          "document_id": "{DOC_ID}",
          "location": "Pages 60-70",
          "verbatim_excerpt": "the best experiments can be readily extended and reconfigured"
        }
      ],
      "extractable": {
        "domains": ["scientific instrumentation", "thermal systems", "liquid crystal physics"],
        "scale": ["50+ parts", "±60nm stability", "sub-micron precision"],
        "keywords": ["mechanical design", "instrumentation", "automation"]
      },
      "date_range": "2010-2015",
      "organization": "Kent State University",
      "related_card_ids": []
    }
  ]
}
```
```

---

## Services

### SkillBankService.swift

```swift
import Foundation

actor SkillBankService {
    private var llmFacade: LLMFacade?
    
    private var modelId: String {
        UserDefaults.standard.string(forKey: "skillBankModelId") ?? "gemini-2.5-flash"
    }
    
    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
    }
    
    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }
    
    /// Extract skills from a single document
    func extractSkills(
        documentId: String,
        filename: String,
        content: String
    ) async throws -> [Skill] {
        guard let facade = llmFacade else {
            throw SkillBankError.llmNotConfigured
        }
        
        let prompt = SkillBankPrompts.extractionPrompt(
            documentId: documentId,
            filename: filename,
            content: content
        )
        
        Logger.info("🔧 Extracting skills from \(filename)", category: .ai)
        
        let jsonString = try await facade.generateStructuredJSON(
            prompt: prompt,
            modelId: modelId,
            maxOutputTokens: 16384,
            jsonSchema: SkillBankPrompts.extractionSchema
        )
        
        guard let data = jsonString.data(using: .utf8) else {
            throw SkillBankError.invalidResponse
        }
        
        struct Response: Codable {
            let skills: [Skill]
        }
        
        let response = try JSONDecoder().decode(Response.self, from: data)
        Logger.info("🔧 Extracted \(response.skills.count) skills", category: .ai)
        
        return response.skills
    }
    
    /// Merge skills from multiple documents into unified bank
    func mergeSkillBank(documentSkills: [[Skill]]) -> SkillBank {
        var merged: [String: Skill] = [:] // canonical -> skill
        
        for skills in documentSkills {
            for skill in skills {
                let key = skill.canonical.lowercased()
                if var existing = merged[key] {
                    // Merge evidence
                    var allEvidence = existing.evidence + skill.evidence
                    // Dedupe by document+location
                    let seen = Set(allEvidence.map { "\($0.documentId):\($0.location)" })
                    allEvidence = allEvidence.enumerated().filter { i, e in
                        let key = "\(e.documentId):\(e.location)"
                        return seen.contains(key)
                    }.map { $0.1 }
                    
                    // Take higher proficiency
                    let proficiency = existing.proficiency.sortOrder < skill.proficiency.sortOrder 
                        ? existing.proficiency : skill.proficiency
                    
                    // Union ATS variants
                    let variants = Array(Set(existing.atsVariants + skill.atsVariants))
                    
                    merged[key] = Skill(
                        id: existing.id,
                        canonical: existing.canonical,
                        atsVariants: variants,
                        category: existing.category,
                        proficiency: proficiency,
                        evidence: allEvidence,
                        relatedSkills: Array(Set(existing.relatedSkills + skill.relatedSkills)),
                        lastUsed: existing.lastUsed ?? skill.lastUsed
                    )
                } else {
                    merged[key] = skill
                }
            }
        }
        
        return SkillBank(
            skills: Array(merged.values).sorted { $0.canonical < $1.canonical },
            generatedAt: Date(),
            sourceDocumentIds: [] // Set by caller
        )
    }
    
    enum SkillBankError: Error, LocalizedError {
        case llmNotConfigured
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .llmNotConfigured: return "LLM not configured"
            case .invalidResponse: return "Invalid response"
            }
        }
    }
}
```

### KnowledgeCardService.swift

```swift
import Foundation

actor KnowledgeCardService {
    private var llmFacade: LLMFacade?
    
    private var modelId: String {
        // Pro for narratives - quality matters
        UserDefaults.standard.string(forKey: "kcExtractionModelId") ?? "gemini-2.5-pro"
    }
    
    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
    }
    
    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }
    
    func extractCards(
        documentId: String,
        filename: String,
        content: String
    ) async throws -> [KnowledgeCard] {
        guard let facade = llmFacade else {
            throw KCError.llmNotConfigured
        }
        
        if content.count > 150_000 {
            return try await extractLargeDocument(
                documentId: documentId,
                filename: filename,
                content: content,
                facade: facade
            )
        }
        
        return try await extractSinglePass(
            documentId: documentId,
            filename: filename,
            content: content,
            facade: facade
        )
    }
    
    private func extractSinglePass(
        documentId: String,
        filename: String,
        content: String,
        facade: LLMFacade
    ) async throws -> [KnowledgeCard] {
        let prompt = KCPrompts.extractionPrompt(
            documentId: documentId,
            filename: filename,
            content: content
        )
        
        Logger.info("📖 Extracting narratives from \(filename)", category: .ai)
        
        let jsonString = try await facade.generateStructuredJSON(
            prompt: prompt,
            modelId: modelId,
            maxOutputTokens: 32768,
            jsonSchema: KCPrompts.extractionSchema
        )
        
        guard let data = jsonString.data(using: .utf8) else {
            throw KCError.invalidResponse
        }
        
        struct Response: Codable {
            let documentType: String
            let cards: [KnowledgeCard]
            enum CodingKeys: String, CodingKey {
                case documentType = "document_type"
                case cards
            }
        }
        
        let response = try JSONDecoder().decode(Response.self, from: data)
        Logger.info("📖 Extracted \(response.cards.count) narrative cards", category: .ai)
        
        return response.cards
    }
    
    private func extractLargeDocument(
        documentId: String,
        filename: String,
        content: String,
        facade: LLMFacade
    ) async throws -> [KnowledgeCard] {
        let chunks = chunkAtSectionBoundaries(content, maxSize: 150_000)
        Logger.info("📖 Large document: \(chunks.count) chunks", category: .ai)
        
        var allCards: [KnowledgeCard] = []
        
        for (i, chunk) in chunks.enumerated() {
            let cards = try await extractSinglePass(
                documentId: documentId,
                filename: "\(filename) (part \(i + 1))",
                content: chunk,
                facade: facade
            )
            allCards.append(contentsOf: cards)
        }
        
        return allCards
    }
    
    private func chunkAtSectionBoundaries(_ content: String, maxSize: Int) -> [String] {
        // Same implementation as before
        let pattern = #"\n(?=---|===|Chapter |\d+\.\s+[A-Z]|#{1,3}\s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [content]
        }
        
        let range = NSRange(content.startIndex..., in: content)
        var sections: [String] = []
        var lastEnd = content.startIndex
        
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            if let match = match, let r = Range(match.range, in: content) {
                sections.append(String(content[lastEnd..<r.lowerBound]))
                lastEnd = r.lowerBound
            }
        }
        sections.append(String(content[lastEnd...]))
        
        var chunks: [String] = []
        var current = ""
        for section in sections {
            if current.count + section.count > maxSize && !current.isEmpty {
                chunks.append(current)
                current = section
            } else {
                current += section
            }
        }
        if !current.isEmpty { chunks.append(current) }
        
        return chunks
    }
    
    enum KCError: Error, LocalizedError {
        case llmNotConfigured
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .llmNotConfigured: return "LLM not configured"
            case .invalidResponse: return "Invalid response"
            }
        }
    }
}
```

---

## Document Processing Integration

### DocumentProcessingService.swift

```swift
// In processDocument():

// Run skill extraction and narrative extraction IN PARALLEL
async let skillsTask = skillBankService.extractSkills(
    documentId: artifactId,
    filename: filename,
    content: extractedText
)

async let cardsTask = kcService.extractCards(
    documentId: artifactId,
    filename: filename,
    content: extractedText
)

let (skills, cards) = try await (skillsTask, cardsTask)

// Store both on artifact
artifactRecord["skills"].string = try JSONEncoder().encode(skills).string
artifactRecord["narrative_cards"].string = try JSONEncoder().encode(cards).string
```

---

## Resume Generation

### Skills Section

```swift
func generateSkillsSection(
    for job: JobListing,
    skillBank: SkillBank,
    categoryLimit: Int = 6,
    skillsPerCategory: Int = 8
) -> [SkillCategory: [String]] {
    // 1. Find skills matching job requirements
    let jobTerms = job.extractedSkillTerms // From job analysis
    let matchedSkills = skillBank.matchingSkills(for: jobTerms)
    let matchedIds = Set(matchedSkills.map { $0.id })
    
    // 2. Group by category, prioritizing matches
    var result: [SkillCategory: [String]] = [:]
    
    for (category, skills) in skillBank.groupedByCategory() {
        let sorted = skills.sorted { a, b in
            let aMatched = matchedIds.contains(a.id)
            let bMatched = matchedIds.contains(b.id)
            if aMatched != bMatched { return aMatched }
            if a.proficiency != b.proficiency {
                return a.proficiency.sortOrder < b.proficiency.sortOrder
            }
            return a.evidence.count > b.evidence.count
        }
        
        let topSkills = sorted.prefix(skillsPerCategory).map { $0.canonical }
        if !topSkills.isEmpty {
            result[category] = Array(topSkills)
        }
    }
    
    // 3. Limit to top N categories (by match density)
    let rankedCategories = result.keys.sorted { cat1, cat2 in
        let match1 = result[cat1]!.filter { name in
            matchedSkills.contains { $0.canonical == name }
        }.count
        let match2 = result[cat2]!.filter { name in
            matchedSkills.contains { $0.canonical == name }
        }.count
        return match1 > match2
    }
    
    return rankedCategories.prefix(categoryLimit).reduce(into: [:]) { dict, cat in
        dict[cat] = result[cat]
    }
}
```

### Objective Statement

```swift
func generateObjective(
    for job: JobListing,
    cards: [KnowledgeCard],
    voice: VoiceProfile
) async throws -> String {
    // Find cards that establish identity/aspirations
    let relevantCards = cards.filter { card in
        card.cardType == .employment || card.cardType == .education
    }.sorted { $0.dateRange ?? "" > $1.dateRange ?? "" }
    .prefix(3)
    
    let prompt = """
    Write a 5-6 sentence objective statement for \(voice.name).
    
    ## Target Role
    \(job.title) at \(job.company)
    
    ## Key Requirements
    \(job.requirements.prefix(5).map { "- \($0.text)" }.joined(separator: "\n"))
    
    ## Career Context (from narratives)
    \(relevantCards.map { "### \($0.title)\n\($0.narrative.prefix(500))..." }.joined(separator: "\n\n"))
    
    ## Voice Reference
    \(voice.samples.prefix(2).joined(separator: "\n\n"))
    
    ## Guidelines
    - Aspirational but grounded in demonstrated experience
    - Match candidate's voice and enthusiasm level
    - Connect past experience to target role naturally
    - No generic phrases like "seeking challenging opportunities"
    - Specific to THIS role at THIS company
    
    Return ONLY the objective statement.
    """
    
    return try await llmFacade.generate(prompt: prompt, maxTokens: 400)
}
```

### Identity Titles

```swift
func generateIdentityTitles(
    cards: [KnowledgeCard],
    count: Int = 4
) async throws -> [String] {
    // Analyze all narratives to extract identity themes
    let allNarratives = cards.map { "\($0.title): \($0.narrative.prefix(300))" }
        .joined(separator: "\n\n")
    
    let prompt = """
    Based on these career narratives, identify \(count) single-word (two-word max) 
    identity titles that capture who this person IS.
    
    ## Narratives
    \(allNarratives)
    
    ## Examples
    - "Physicist. Developer. Educator. Machinist."
    - "Engineer. Leader. Innovator. Mentor."
    
    ## Guidelines
    - Each title should be a NOUN (what they are, not what they do)
    - Titles should span different dimensions of identity
    - Order from most prominent to supporting
    - One word strongly preferred, two words max
    
    Return as JSON array: ["Title1", "Title2", "Title3", "Title4"]
    """
    
    let json = try await llmFacade.generate(prompt: prompt, maxTokens: 100)
    return try JSONDecoder().decode([String].self, from: json.data(using: .utf8)!)
}
```

### Job Highlights

```swift
func generateJobHighlights(
    for employment: KnowledgeCard,
    job: JobListing,
    voice: VoiceProfile,
    count: Int = 4
) async throws -> [String] {
    let prompt = """
    Write \(count) resume bullet points for this role.
    
    ## Role
    \(employment.title) at \(employment.organization ?? "")
    
    ## Full Context (NARRATIVE)
    \(employment.narrative)
    
    ## Target Job Requirements
    \(job.requirements.prefix(5).map { "- \($0.text)" }.joined(separator: "\n"))
    
    ## Voice Reference
    \(voice.samples.first ?? "")
    
    ## Guidelines
    - Each bullet draws SPECIFIC details from the narrative
    - Lead with impact, include metrics from narrative
    - Address job requirements naturally
    - Match candidate's voice
    - Start with action verb, no trailing period
    - Max 25 words per bullet
    
    Return as JSON array of strings.
    """
    
    let json = try await llmFacade.generate(prompt: prompt, maxTokens: 500)
    return try JSONDecoder().decode([String].self, from: json.data(using: .utf8)!)
}
```

### Project Descriptions

```swift
func generateProjectDescription(
    for project: KnowledgeCard,
    job: JobListing,
    voice: VoiceProfile
) async throws -> String {
    let prompt = """
    Write a 2-3 sentence project description.
    
    ## Project
    \(project.title)
    
    ## Full Context (NARRATIVE)
    \(project.narrative)
    
    ## Target Job Requirements
    \(job.requirements.prefix(3).map { "- \($0.text)" }.joined(separator: "\n"))
    
    ## Voice Reference
    \(voice.samples.first ?? "")
    
    ## Guidelines
    - 2-3 sentences total
    - What it was, your role, key outcome
    - Draw specific details from narrative
    - Connect to job requirements naturally
    - Match candidate's voice
    
    Return ONLY the description.
    """
    
    return try await llmFacade.generate(prompt: prompt, maxTokens: 150)
}
```

---

## File Changes Summary

| File | Action |
|------|--------|
| `Models/Skill.swift` | CREATE |
| `Models/SkillBank.swift` | CREATE |
| `Models/KnowledgeCard.swift` | CREATE |
| `Models/DocumentInventory.swift` | DELETE |
| `Services/SkillBankService.swift` | CREATE |
| `Services/KnowledgeCardService.swift` | CREATE |
| `Services/CardInventoryService.swift` | DELETE |
| `Services/CardMergeService.swift` | REWRITE |
| `Prompts/skill_bank_extraction.txt` | CREATE |
| `Prompts/kc_extraction.txt` | CREATE |
| `Prompts/card_inventory_prompt.txt` | DELETE |
| `DocumentProcessingService.swift` | UPDATE |
| `ResumeGenerationService.swift` | UPDATE |

---

## Model Selection

| Task | Model | Rationale |
|------|-------|-----------|
| Skill extraction | `gemini-2.5-flash` | Structured, comprehensive, cost-effective |
| Narrative extraction | `gemini-2.5-pro` | Quality narratives need reasoning depth |
| Card merge | `gpt-4o` | Complex decisions about what to combine |
| Bullet generation | `gpt-4o` | Voice matching, specificity |
| Objective/titles | `gpt-4o` | Creative synthesis |

---

## Success Criteria

1. **Skill Bank**: 100+ skills with evidence, comprehensive ATS coverage
2. **Narratives**: 500+ words each with WHY/JOURNEY/LESSONS
3. **Skills Section**: Top ATS matches surface to resume
4. **Bullets**: Specific details from narratives, not generic
5. **Voice**: Consistent with writing samples throughout
