# SGM Round 2: Generation Quality Improvements

## Problem Statement

The initial SGM implementation produces resume bullets that suffer from:

1. **Fabricated metrics** - Percentages and numbers invented by the LLM ("reduced time by 40%", "improved by 25%")
2. **LinkedIn madlib voice** - Generic corporate phrasing that doesn't match the candidate's actual writing style
3. **Formulaic structure** - Every bullet follows `[Action verb] [thing] that [metric]% improvement`
4. **Ignored voice data** - Writing samples and voice primer analysis exist but aren't used effectively

### Example of Bad Output

```
• Developed custom PhysicsCloud learning management system, increasing student 
  engagement by 40% through interactive visualizations and adaptive problem sets
  
• Mentored 15+ undergraduate researchers in experimental physics projects, 
  resulting in 3 peer-reviewed publications and enhanced laboratory capabilities
  
• Redesigned introductory physics curriculum using evidence-based pedagogical 
  methods, improving student success rates by 25% over two academic years
```

Problems: "40%", "25%" are fabricated. "Enhanced capabilities" is meaningless filler. Every bullet has identical structure.

### Example of Good Output

```
• Built PhysicsCloud, a custom learning management system featuring interactive 
  visualizations and adaptive problem sets for introductory physics courses
  
• Mentored undergraduate researchers through experimental physics projects, 
  with three students co-authoring peer-reviewed publications
  
• Redesigned the introductory curriculum around evidence-based pedagogy, 
  replacing traditional lectures with active learning modules
```

Differences: No fabricated metrics. Narrative structure. Specific details from actual work.

---

## Changes Required

### 1. PromptCacheService.swift

#### 1.1 Rewrite `buildRolePreamble()`

**Current:** Generic resume writer instructions that encourage quantification

**New:**

```swift
private func buildRolePreamble() -> String {
    """
    # Role: Resume Content Generator

    You are generating resume content for a specific candidate based on their documented experiences.

    ## CRITICAL CONSTRAINTS

    ### 1. NO FABRICATED METRICS
    
    You may ONLY include quantitative claims that appear VERBATIM in the Knowledge Cards.
    If no metric exists in the source material, describe the work narratively without inventing numbers.
    
    FORBIDDEN (unless exact figures appear in a Knowledge Card):
    - "reduced time by 40%"
    - "improved efficiency by 25%"
    - "increased engagement by 3x"
    - "significantly improved"
    - Any percentage or multiplier not directly quoted from evidence
    
    ALLOWED:
    - "resulted in 3 peer-reviewed publications" (if KC states exactly this)
    - "built a system that..." (narrative description)
    - "developed novel approach to..." (qualitative impact)

    ### 2. NO GENERIC RESUME VOICE
    
    Do NOT write in formulaic LinkedIn/corporate style. Avoid:
    - "Spearheaded initiatives that drove..."
    - "Leveraged expertise to deliver..."
    - "Collaborated cross-functionally to..."
    - "Proven track record of..."
    
    Instead, write in the candidate's actual voice as demonstrated in their writing samples.
    Match their vocabulary, sentence structure, and professional register.

    ### 3. EVIDENCE-BASED ONLY
    
    Every factual claim must trace to a Knowledge Card. If you cannot cite evidence for a claim, do not include it.

    ## Role-Appropriate Framing

    Tailor bullet structure to the position type:

    **For R&D / Academic / Research positions:**
    - What problem or gap existed?
    - What novel approach was taken?
    - What was created, discovered, or published?
    - Who uses it or what opportunities did it open?

    **For Industry / Engineering / Corporate positions:**
    - What system or process did they own?
    - What was their specific technical contribution?
    - What concrete outcome resulted? (only if documented)

    **For Teaching / Education positions:**
    - What did they build or redesign?
    - What pedagogical approach did they use?
    - What was the scope and impact on students?

    Below is comprehensive context about the candidate. Use this to generate content that authentically represents them.
    """
}
```

#### 1.2 Rewrite `buildVoiceSection()`

**Current:** Placeholder text saying samples were "analyzed" without including actual content

**New:**

```swift
private func buildVoiceSection(_ writingSamples: [CoverRef], voicePrimer: CoverRef?) -> String {
    var lines = ["## Voice & Style Reference"]

    // Include structured voice primer analysis if available
    if let primer = voicePrimer, let analysis = primer.voicePrimer {
        lines.append("""
            
            ### Analyzed Voice Characteristics
            
            The following voice profile was extracted from the candidate's writing samples.
            Generated content MUST match these characteristics.
            """)

        if let tone = analysis["tone"]["description"].string, !tone.isEmpty {
            lines.append("**Tone:** \(tone)")
        }
        if let structure = analysis["structure"]["description"].string, !structure.isEmpty {
            lines.append("**Sentence Structure:** \(structure)")
        }
        if let vocab = analysis["vocabulary"]["description"].string, !vocab.isEmpty {
            lines.append("**Vocabulary:** \(vocab)")
        }
        if let rhetoric = analysis["rhetoric"]["description"].string, !rhetoric.isEmpty {
            lines.append("**Rhetoric Style:** \(rhetoric)")
        }

        let strengths = analysis["markers"]["strengths"].arrayValue.compactMap { $0.string }
        if !strengths.isEmpty {
            lines.append("**Writing Strengths:** \(strengths.joined(separator: ", "))")
        }

        let quirks = analysis["markers"]["quirks"].arrayValue.compactMap { $0.string }
        if !quirks.isEmpty {
            lines.append("**Distinctive Traits:** \(quirks.joined(separator: ", "))")
        }

        let recommendations = analysis["markers"]["recommendations"].arrayValue.compactMap { $0.string }
        if !recommendations.isEmpty {
            lines.append("**Style Notes:** \(recommendations.joined(separator: "; "))")
        }
    }

    // Include actual writing sample text for voice matching
    if !writingSamples.isEmpty {
        lines.append("""
            
            ### Writing Samples (Full Text)
            
            The following are actual writing samples from this candidate.
            Study these carefully and match their:
            - Vocabulary choices and technical terminology
            - Sentence length and structure patterns
            - Level of formality
            - How they describe technical work
            - How they frame achievements (narrative vs. metric-focused)
            """)

        for (index, sample) in writingSamples.prefix(3).enumerated() {
            lines.append("")
            lines.append("#### Sample \(index + 1): \(sample.name)")
            lines.append("")
            lines.append(sample.content)
        }

        if writingSamples.count > 3 {
            lines.append("")
            lines.append("*(\(writingSamples.count - 3) additional samples available but omitted for context length)*")
        }
    }

    return lines.joined(separator: "\n")
}
```

#### 1.3 Update `buildPreamble()` Call Site

**Change the voice section call to pass voice primer:**

```swift
// In buildPreamble(), replace:
if !context.writingSamples.isEmpty {
    sections.append(buildVoiceSection(context.writingSamples))
}

// With:
if !context.writingSamples.isEmpty || context.voicePrimer != nil {
    sections.append(buildVoiceSection(context.writingSamples, voicePrimer: context.voicePrimer))
}
```

#### 1.4 Update Method Signature

```swift
// Change from:
private func buildVoiceSection(_ writingSamples: [CoverRef]) -> String

// To:
private func buildVoiceSection(_ writingSamples: [CoverRef], voicePrimer: CoverRef?) -> String
```

---

### 2. WorkHighlightsGenerator.swift

#### 2.1 Rewrite Task Prompt

**Current prompt encourages fabrication:**
```swift
// REMOVE these instructions:
"Include specific, quantifiable achievements when possible"
"Quantify impact where evidence supports it"
```

**New task prompt:**

```swift
let taskPrompt = """
    ## Task: Generate Work Highlights

    Generate resume bullet points for this position.

    ## Position Context

    \(taskContext)

    ## Requirements

    Generate 3-4 bullet points that:
    
    1. **Use ONLY facts from the Knowledge Cards** - Every claim must have evidence in the KCs provided above
    
    2. **Match the candidate's voice** - Write in their style as shown in the writing samples, not generic resume-speak
    
    3. **Describe work narratively** - Focus on what was built, created, discovered, or accomplished
    
    4. **Vary sentence structure** - Don't start every bullet the same way

    ## FORBIDDEN

    - Inventing metrics, percentages, or numbers not explicitly stated in KCs
    - Generic phrases: "spearheaded", "leveraged", "drove results", "cross-functional"
    - Vague impact claims: "significantly improved", "enhanced capabilities", "streamlined processes"
    - Formulaic structure: "[Verb] [thing] resulting in [X]% improvement"

    ## Output Format

    Return JSON with 3-4 bullets:
    ```json
    {
        "highlights": [
            "First bullet point",
            "Second bullet point", 
            "Third bullet point",
            "Fourth bullet point (optional)"
        ]
    }
    ```
    """
```

#### 2.2 Update Section Prompt

**Replace `buildSectionPrompt()`:**

```swift
override func buildSectionPrompt() -> String {
    """
    Generate resume bullet points for a work experience entry.

    Your bullets should:
    - Describe specific work and contributions
    - Use the candidate's natural voice (see writing samples)
    - Include only facts that appear in the Knowledge Cards
    - Frame achievements narratively rather than with fabricated metrics

    Do NOT:
    - Invent percentages or quantitative improvements
    - Use generic corporate/LinkedIn language
    - Write every bullet with the same structure
    """
}
```

---

### 3. Other Generators

Apply the same pattern to all generators that produce prose content:

#### Files to Update

| Generator | Key Changes |
|-----------|-------------|
| `EducationGenerator.swift` | Remove metric encouragement, add KC-only constraint |
| `VolunteerGenerator.swift` | Remove metric encouragement, add KC-only constraint |
| `ProjectsGenerator.swift` | Remove metric encouragement, add KC-only constraint |
| `ObjectiveGenerator.swift` | Add voice matching requirement, remove generic phrasing |

#### Template for Generator Prompt Updates

Each generator's task prompt should include:

```swift
"""
## CONSTRAINTS

1. Use ONLY facts from the provided Knowledge Cards
2. Do NOT invent metrics, percentages, or quantitative claims
3. Match the candidate's writing voice from the samples
4. Avoid generic resume phrases

## FORBIDDEN

- Fabricated numbers ("increased by X%", "reduced by Y%")
- Generic phrases ("spearheaded", "leveraged", "drove")
- Vague claims ("significantly improved", "enhanced")
"""
```

---

### 4. SeedGenerationOrchestrator.swift

#### 4.1 Verify Voice Primer Loading

Ensure the orchestrator loads the voice primer when building context:

```swift
// In loadFromOnboarding() or context building method:

// Get voice primer from CoverRefStore
let voicePrimer = coverRefStore.storedCoverRefs.first { $0.type == .voicePrimer }

// Get writing samples
let writingSamples = coverRefStore.storedCoverRefs.filter { $0.type == .writingSample }

// Build context with both
let context = SeedGenerationContext.build(
    from: artifacts,
    knowledgeCards: knowledgeCards,
    skills: skills,
    writingSamples: writingSamples,
    voicePrimer: voicePrimer,  // <-- Ensure this is passed
    dossier: dossier
)
```

---

### 5. SeedGenerationContext.swift

#### 5.1 Verify Voice Primer Field Exists

The field should already exist:

```swift
struct SeedGenerationContext {
    // ... other fields ...
    
    /// Writing samples for voice/style guidance
    let writingSamples: [CoverRef]

    /// Voice primer for style guidance (if available)
    let voicePrimer: CoverRef?
    
    // ... rest of struct ...
}
```

#### 5.2 Verify Builder Passes Voice Primer

```swift
static func build(
    from artifacts: OnboardingArtifacts,
    knowledgeCards: [KnowledgeCard],
    skills: [Skill],
    writingSamples: [CoverRef],
    voicePrimer: CoverRef?,  // <-- Must be a parameter
    dossier: JSON?
) -> SeedGenerationContext {
    // ... building logic ...
    
    return SeedGenerationContext(
        // ... other fields ...
        writingSamples: writingSamples.filter { $0.type == .writingSample },
        voicePrimer: voicePrimer,  // <-- Must be assigned
        dossier: dossier
    )
}
```

---

## Summary of File Changes

| File | Change Type | Description |
|------|-------------|-------------|
| `PromptCacheService.swift` | Rewrite | New `buildRolePreamble()` with anti-hallucination rules |
| `PromptCacheService.swift` | Rewrite | New `buildVoiceSection()` with full sample text + voice primer |
| `PromptCacheService.swift` | Modify | Update call site to pass voice primer |
| `WorkHighlightsGenerator.swift` | Rewrite | New task prompt forbidding fabrication |
| `WorkHighlightsGenerator.swift` | Rewrite | New section prompt with constraints |
| `EducationGenerator.swift` | Modify | Add anti-hallucination constraints to prompts |
| `VolunteerGenerator.swift` | Modify | Add anti-hallucination constraints to prompts |
| `ProjectsGenerator.swift` | Modify | Add anti-hallucination constraints to prompts |
| `ObjectiveGenerator.swift` | Modify | Add voice matching + anti-hallucination constraints |
| `SeedGenerationOrchestrator.swift` | Verify | Ensure voice primer is loaded and passed to context |
| `SeedGenerationContext.swift` | Verify | Ensure voice primer field exists and is populated |

---

## Verification

After implementation, regenerate highlights for a work position and verify:

1. **No fabricated metrics** - No percentages or numbers that don't appear in KCs
2. **Voice match** - Language matches the writing samples, not generic resume-speak
3. **Varied structure** - Bullets don't all follow the same pattern
4. **Evidence-based** - Every claim can be traced to a KC fact

### Test Case

For a Senior Lecturer position with KCs mentioning:
- "Built PhysicsCloud learning management system"
- "Mentored undergraduate researchers"
- "Three students co-authored publications"

**Bad output (reject):**
```
• Developed custom PhysicsCloud LMS, increasing student engagement by 40%
```

**Good output (accept):**
```
• Built PhysicsCloud, a custom learning management system with interactive 
  visualizations and adaptive problem sets for introductory physics
```
