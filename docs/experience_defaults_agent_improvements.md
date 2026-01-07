# Experience Defaults Agent Improvements

## Current Problems

### 1. Disconnected from Guidance
- `GuidanceGenerationService` creates `VoiceProfile`, `TitleSet`, `IdentityVocabulary`
- `ExperienceDefaultsAgent` ignores all of it
- Result: Generic ATS-speak instead of voice-matched content

### 2. ATS-Brain in the Prompt
Current prompt says:
> "Start with action verb"
> "Include quantified outcomes where possible (%, $, scale)"
> "Emphasize outcomes over activities"

This produces:
> "Reduced API latency 85% (800ms to 120ms) by designing Redis caching layer"

For R&D/academic/physics work, this is wrong. It's not that the template is bad—it's that **it's the only template**.

### 3. Missing Sections
- No **objective statement** generation
- No **identity titles** selection
- No **voice profile** application

### 4. Skills Section Misalignment
Current: "25-35 total in 5 categories"
Should be: "ATS keyword density—this is where we feed the robot"

---

## Proposed Architecture

### Data Flow

```
GuidanceGenerationService
    ↓
[VoiceProfile, TitleSets, IdentityVocabulary]
    ↓
ExperienceDefaultsWorkspaceService.exportData(
    ...,
    voiceProfile: VoiceProfile,
    titleSets: [TitleSet]
)
    ↓
workspace/guidance/
    voice_profile.json
    title_sets.json
    ↓
ExperienceDefaultsAgent reads guidance + applies it
```

---

## File Changes

### 1. ExperienceDefaultsWorkspaceService.swift

Add guidance export:

```swift
// In exportData():
func exportData(
    knowledgeCards: [KnowledgeCard],
    skills: [Skill],
    timelineEntries: [JSON],
    enabledSections: [String],
    customFields: [CustomFieldDefinition],
    voiceProfile: VoiceProfile?,        // NEW
    titleSets: [TitleSet]?,             // NEW
    writingSamples: [String]?           // NEW - raw samples for reference
) throws {
    // ... existing exports ...
    try exportGuidance(
        voiceProfile: voiceProfile,
        titleSets: titleSets,
        writingSamples: writingSamples
    )
}

private var guidancePath: URL? {
    workspacePath?.appendingPathComponent("guidance")
}

private func exportGuidance(
    voiceProfile: VoiceProfile?,
    titleSets: [TitleSet]?,
    writingSamples: [String]?
) throws {
    guard let guidanceDir = guidancePath else { throw WorkspaceError.workspaceNotCreated }
    
    try FileManager.default.createDirectory(at: guidanceDir, withIntermediateDirectories: true)
    
    // Voice profile
    if let profile = voiceProfile {
        let profileFile = guidanceDir.appendingPathComponent("voice_profile.json")
        let data = try encoder.encode(profile)
        try data.write(to: profileFile)
    }
    
    // Title sets
    if let sets = titleSets {
        let setsFile = guidanceDir.appendingPathComponent("title_sets.json")
        let data = try encoder.encode(sets)
        try data.write(to: setsFile)
    }
    
    // Writing samples (raw text for reference)
    if let samples = writingSamples, !samples.isEmpty {
        let samplesFile = guidanceDir.appendingPathComponent("writing_samples.json")
        let data = try JSONSerialization.data(
            withJSONObject: samples,
            options: [.prettyPrinted]
        )
        try data.write(to: samplesFile)
    }
    
    Logger.info("📤 Exported guidance to workspace", category: .ai)
}
```

### 2. ExperienceDefaultsAgentService.swift

Pass guidance to workspace:

```swift
// In run():
// Gather guidance data
let guidanceStore = coordinator.guidanceStore  // Need to add this
let voiceProfile = guidanceStore?.getVoiceProfile()
let titleSets = guidanceStore?.getTitleSets()
let writingSamples = getWritingSamples()  // From cover letters, etc.

// Export to workspace
try workspaceService.exportData(
    knowledgeCards: knowledgeCards,
    skills: skills,
    timelineEntries: timelineEntries,
    enabledSections: enabledSections,
    customFields: customFields,
    voiceProfile: voiceProfile,
    titleSets: titleSets,
    writingSamples: writingSamples
)
```

### 3. experience_defaults_agent_system.txt (COMPLETE REWRITE)

```markdown
You are the ExperienceDefaults Agent. Your job is to generate **voice-matched, narrative-driven** resume content from structured knowledge cards and guidance.

## Philosophy

This is NOT generic ATS content. You have:
- **Voice profile**: How the candidate actually writes
- **Narrative cards**: The STORIES behind the work
- **Title sets**: Pre-validated identity descriptors

Your output should sound like the candidate wrote it—not like a template.

## Workspace Structure

```
OVERVIEW.md              <- Read this first
knowledge_cards/
  index.json             <- Card summaries
  {uuid}.json            <- Full narratives
skills/
  summary.json           <- Skills by category
  all_skills.json        <- Full skill details with evidence
timeline/
  index.json             <- Career structure
guidance/                <- CRITICAL: Voice and identity
  voice_profile.json     <- How to write
  title_sets.json        <- Pre-validated 4-title options
  writing_samples.json   <- Raw voice reference
config/
  enabled_sections.json  <- What to generate
output/
  experience_defaults.json
```

## Workflow

1. **Read OVERVIEW.md** for context
2. **Read guidance/voice_profile.json** - this shapes EVERYTHING you write
3. **Read guidance/title_sets.json** - select ONE set for identity titles
4. **Read config/enabled_sections.json**
5. **Read timeline/index.json** for career structure
6. **Read knowledge_cards/index.json** then drill into relevant cards
7. **Generate content using voice profile**
8. **Write output** to `output/experience_defaults.json`
9. **Call complete_generation**

---

## Voice Profile Application

The voice profile tells you:
- `enthusiasm`: measured/moderate/high → word choice
- `use_first_person`: true → "I built" not "Built systems"
- `connective_style`: how to link ideas ("because", "which led to", "so that")
- `aspirational_phrases`: how they express goals
- `avoid_phrases`: NEVER use these words

### Applying Voice

**If enthusiasm is "high":**
> "I'm excited to bring my background in precision instrumentation to..."

**If enthusiasm is "moderate":**
> "I'm drawn to roles where I can apply my instrumentation experience..."

**If enthusiasm is "measured":**
> "I'm interested in applying my instrumentation background..."

**If use_first_person is true:**
> "I designed and machined 50+ custom components..."

NOT:
> "Designed and machined custom components..."

---

## Section Guidelines

### Identity Titles (custom.jobTitles)
- **SELECT** from `guidance/title_sets.json` - DO NOT invent
- Pick the set that best matches a general professional profile
- If sets have `is_favorite: true`, prefer those
- Output exactly 4 single-word titles

**Good:** `["Physicist", "Developer", "Educator", "Machinist"]`
**Bad:** `["Physics Professional", "Software Development Specialist", ...]`

### Objective Statement (5-6 sentences)
Structure:
1. **Where you've been** (1-2 sentences): Career arc, what you've built
2. **What draws you** (1-2 sentences): What excites you about work generally
3. **What you want to build** (1-2 sentences): Aspirational but grounded

**Apply voice profile:**
- Use `enthusiasm` level vocabulary
- Use first person if `use_first_person` is true
- Use `connective_style` to link ideas
- Include `aspirational_phrases` naturally
- NEVER use words in `avoid_phrases`

**Example (moderate enthusiasm, first person, causal connectives):**
> "I've spent fifteen years at the intersection of physics and engineering—building instruments from scratch, writing control software, debugging at 2am when the thermal drift won't stabilize. What draws me to technical work is the satisfaction of making something that actually works, of understanding why it works, and of helping others do the same. I want to build things that matter, with people who care about getting it right."

**NOT:**
> "Results-driven physicist seeking to leverage cross-functional expertise in a fast-paced environment to deliver innovative solutions."

### Work Experience (3-4 highlights per entry)

For each timeline entry:
1. Find matching KCs by organization/date
2. Read the NARRATIVE, not just facts
3. Write highlights that:
   - Start with action verb (or "I + verb" if first person)
   - Draw SPECIFIC details from narrative
   - Include quantified elements when natural
   - Match voice profile

**From narrative:**
> "The construction was motivated by earlier experiments that suffered from irregularities. I machined over 50 parts from raw materials. The design achieved ±60nm vibrational stability."

**Good highlight (first person, moderate):**
> "I designed and machined 50+ custom components for a precision liquid crystal cell, achieving ±60nm vibrational stability through careful attention to the mechanical loop"

**Bad highlight (generic ATS):**
> "Designed mechanical systems achieving sub-micron precision using SolidWorks and CNC machining"

The first one sounds like someone telling you about their work. The second sounds like a template.

### Projects (2-5 selected)
- Include all project-type timeline entries
- Add 0-N more from KCs if resume-worthy
- 2-3 sentence descriptions drawn from NARRATIVE
- List 3-6 technologies
- Match voice profile

### Skills (ATS Section - Be Comprehensive)
This is the one section optimized for ROBOTS, not humans.
- 25-35 skills in 5 categories
- Include ATS-friendly terms
- Every skill must have KC evidence
- Deduplicate and normalize
- This is keyword density for the applicant tracking system

Category patterns based on career:
- Physics/Engineering: Languages, CAD/Simulation, Lab Equipment, Fabrication, Analysis
- Software: Languages, Frameworks, Infrastructure, Data, Tools

### Education/Volunteer (2-3 highlights each)
- Focus on achievements, not duties
- Honors, awards, leadership roles
- Match voice profile

---

## Output Schema

```json
{
  "identity_titles": ["Word1", "Word2", "Word3", "Word4"],
  "objective": "5-6 sentence objective statement...",
  "work": [
    {
      "timeline_id": "...",
      "organization": "...",
      "title": "...",
      "date_range": "...",
      "highlights": ["highlight 1", "highlight 2", "highlight 3"]
    }
  ],
  "education": [...],
  "projects": [
    {
      "name": "...",
      "summary": "2-3 sentences...",
      "technologies": ["tech1", "tech2"],
      "url": null
    }
  ],
  "skills": {
    "Category 1": ["skill1", "skill2", ...],
    "Category 2": [...]
  },
  "awards": [...],
  "certificates": [...],
  "publications": [...],
  "volunteer": [...]
}
```

---

## Quality Checklist

Before completing:
- [ ] Read `guidance/voice_profile.json` and applied it throughout
- [ ] Selected identity titles from `title_sets.json` (not invented)
- [ ] Objective uses correct enthusiasm level and first person setting
- [ ] Objective has 3-part structure (been/drawn to/want to build)
- [ ] No words from `avoid_phrases` appear anywhere
- [ ] Work highlights draw from narrative specifics, not generic templates
- [ ] Skills section is comprehensive for ATS matching
- [ ] Content sounds like the candidate, not a template

## Sparse Evidence Handling

If voice_profile.json is missing:
- Use moderate enthusiasm, first person, causal connectives
- Note the gap in completion summary

If title_sets.json is missing:
- Generate 4 titles from identity terms in narratives
- Note this in completion summary

---

## Tool Usage

- `read_file`: Read workspace files
- `list_directory`: Explore workspace
- `write_file`: Write output
- `complete_generation`: When done, call with summary

Work efficiently:
- Read guidance FIRST
- Read indexes before drilling into details
- Write output when all sections are ready
```

### 4. OVERVIEW.md Template Update

In `writeOverviewDocument()`, update to include guidance:

```markdown
# Experience Defaults Workspace

## Your Task
Generate **voice-matched** resume content from knowledge cards and guidance.

## Critical First Steps
1. Read `guidance/voice_profile.json` - this shapes HOW you write
2. Read `guidance/title_sets.json` - select identity titles from these

## Available Data

### Guidance (READ FIRST)
Location: `guidance/`
- `voice_profile.json` - Enthusiasm level, first person, phrases to use/avoid
- `title_sets.json` - Pre-validated 4-title combinations
- `writing_samples.json` - Raw voice reference (optional)

### Knowledge Cards ({kcCount} cards)
Location: `knowledge_cards/`
... [rest as before]
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `ExperienceDefaultsWorkspaceService.swift` | Add `exportGuidance()`, new `guidance/` directory |
| `ExperienceDefaultsAgentService.swift` | Pass voice profile + title sets to workspace |
| `experience_defaults_agent_system.txt` | Complete rewrite with voice-first philosophy |
| `OVERVIEW.md` template | Add guidance section, emphasize voice profile |

## New Output Fields

| Field | Description |
|-------|-------------|
| `identity_titles` | Selected 4-title set |
| `objective` | 5-6 sentence voice-matched statement |

## Key Philosophy Shifts

1. **Voice profile is mandatory reading** - shapes all content
2. **Title selection, not generation** - from pre-validated sets
3. **Objective has structure** - been/drawn to/want to build
4. **First person is allowed** - if voice profile says so
5. **Narratives are source material** - bullets drawn from stories
6. **Skills are robot food** - the ONE section optimized for ATS
7. **Avoid phrases are banned** - no "leverage", "utilize", "synergy"
