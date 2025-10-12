---

# Onboarding Interview Feature Plan

**Version:** 1.0
**Backend:** OpenAI Responses API + Realtime API
**Threading:** Persistent server-side context enabled
**Author:** Gemini PhysCloud Project

---

## 1. Feature Overview

The **Onboarding Interview** is a dynamic, LLM-led process for collecting and structuring user information into verified artifacts that power résumé and cover-letter customization.

This feature replaces static forms with a conversational, multi-turn experience that feels like being interviewed by a career coach — guiding users through stories of their work, surfacing quantifiable impact, and generating a structured, evidence-backed knowledge base.

---

## 2. Core Objectives

1. Conduct a rich, human-like interview to populate:

   * `applicant_profile.json`
   * `default_values.json`
2. Generate and persist supplementary artifacts:

   * Knowledge cards (summaries of roles, projects, or uploaded documents)
   * `profile_context.txt` (career goals)
   * `skills_index.json` (skills → evidence map)
3. Support both **text chat** and **voice interaction** (GPT-4o Realtime).
4. Use **OpenAI server-side thread memory** for context persistence.
5. Incorporate **web search discovery** for public project evidence.
6. Keep the process fully schema-driven — zero freeform JSON parsing.

---

## 3. Primary Artifacts

| Artifact           | Purpose                                                              |
| ------------------ | -------------------------------------------------------------------- |
| `ApplicantProfile` | Core contact and identity details.                                   |
| `DefaultValues`    | Verified résumé structure (education, employment, projects, skills). |
| `Knowledge Cards`  | Summaries with evidence, quotes, and metrics.                        |
| `Profile Context`  | User goals, constraints, and motivations.                            |
| `Skill Map`        | Evidence-based mapping of skills to sources.                         |

---

## 4. Data Schemas

### 4.1 ApplicantProfile

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "ApplicantProfile",
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "address": { "type": "string" },
    "city": { "type": "string" },
    "state": { "type": "string" },
    "zip": { "type": "string" },
    "phone": { "type": "string" },
    "email": { "type": "string", "format": "email" },
    "website": { "type": "string", "format": "uri" },
    "signature_image": { "type": "string" }
  },
  "required": ["name", "email", "phone", "city", "state"],
  "additionalProperties": false
}
```

### 4.2 DefaultValues

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "DefaultValues",
  "type": "object",
  "properties": {
    "education": { "type": "array", "items": { "$ref": "#/$defs/educationEntry" } },
    "employment": { "type": "array", "items": { "$ref": "#/$defs/employmentEntry" } },
    "certifications": { "type": "array", "items": { "type": "string" } },
    "publications": { "type": "array", "items": { "type": "string" } },
    "projects": { "type": "array", "items": { "$ref": "#/$defs/projectEntry" } },
    "skills": { "type": "array", "items": { "type": "string" } },
    "hobbies": { "type": "array", "items": { "type": "string" } },
    "objective": { "type": "string" },
    "meta": {
      "type": "object",
      "properties": {
        "schema_version": { "type": "string" },
        "last_verified": { "type": "string", "format": "date" }
      }
    }
  },
  "required": ["education", "employment"],
  "$defs": {
    "educationEntry": {
      "type": "object",
      "properties": {
        "degree": { "type": "string" },
        "institution": { "type": "string" },
        "field": { "type": "string" },
        "grad_date": { "type": "string", "format": "date" },
        "honors": { "type": "string" }
      },
      "required": ["degree", "institution"]
    },
    "employmentEntry": {
      "type": "object",
      "properties": {
        "company": { "type": "string" },
        "title": { "type": "string" },
        "start_date": { "type": "string", "format": "date" },
        "end_date": { "type": ["string", "null"], "format": "date" },
        "location": { "type": "string" },
        "description": { "type": "string" }
      },
      "required": ["company", "title", "start_date"]
    },
    "projectEntry": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "description": { "type": "string" },
        "technologies": { "type": "array", "items": { "type": "string" } },
        "link": { "type": "string", "format": "uri" }
      },
      "required": ["name"]
    }
  }
}
```

---

## 5. Parsing Workflow

### Step 1 — User uploads résumé or LinkedIn link

LLM invokes:

```json
{ "tool": "parse_resume", "args": { "fileId": "<upload_id>" } }
```

or

```json
{ "tool": "parse_linkedin", "args": { "url": "https://linkedin.com/in/..."} }
```

### Step 2 — Parser returns `RawExtraction`

```json
{
  "raw_extraction": {
    "name": "Jane Doe",
    "email": "jane@example.com",
    "phone": "(555) 123-4567",
    "education": ["M.S. Computer Science, MIT, 2018"],
    "experience": ["PhysCloud, Senior Engineer, 2018–2023"],
    "skills": ["Python", "C++", "AWS"]
  },
  "uncertainties": [
    "End date ambiguous (2022–2023)",
    "Duplicate project names"
  ]
}
```

### Step 3 — User confirmation

App displays parsed results in editable structured form.
User confirms or corrects values before conversion.

### Step 4 — Conversion to schemas

LLM call:

```json
{
  "instruction": "convert raw_extraction to schemas",
  "input": { "raw_extraction": {...} }
}
```

LLM outputs:

```json
{
  "applicant_profile_patch": {...},
  "default_values_patch": {...},
  "needs_verification": [...]
}
```

### Step 5 — Merge & persist

App merges patches → creates verified JSON artifacts.

---

## 6. Interview Phases

| Phase                          | Purpose                                                                               | Output                                          |
| ------------------------------ | ------------------------------------------------------------------------------------- | ----------------------------------------------- |
| **Phase 1 – Core Facts**       | Build identity and structural résumé data.                                            | `applicant_profile.json`, `default_values.json` |
| **Phase 2 – Deep Dive**        | Conduct narrative interviews per experience; generate summaries, metrics, and skills. | Knowledge cards, skill-evidence map             |
| **Phase 3 – Personal Context** | Record career goals, constraints, and motivations.                                    | `profile_context.txt`                           |

---

## 7. Tool & Function Interfaces

| Tool                 | Purpose                                                    | Input               | Output           |
| -------------------- | ---------------------------------------------------------- | ------------------- | ---------------- |
| `parse_resume`       | Extract structured info from uploaded résumé.              | `fileId`            | `RawExtraction`  |
| `parse_linkedin`     | Extract structured info from LinkedIn.                     | `url`               | `RawExtraction`  |
| `summarize_artifact` | Summarize uploads into KnowledgeCards.                     | `fileId`, `context` | `KnowledgeCard`  |
| `web_lookup`         | Search the web for project/public evidence (with consent). | `query`, `context`  | List of findings |
| `persist_delta`      | Save incremental schema patch.                             | `target`, `delta`   | Confirmation     |
| `persist_card`       | Store KnowledgeCard.                                       | Card object         | Card ID          |
| `persist_skill_map`  | Update skills evidence mapping.                            | `skillMapDelta`     | Confirmation     |

---

## 8. Integration and API Architecture

**LLM Provider:** OpenAI (Responses + Realtime APIs)
**Thread Memory:** Enabled — persistent context stored server-side via `thread_id`.
**Realtime Support:** GPT-4o Realtime for full-duplex audio.

### Implementation:

* Text-based and voice interviews share the same schema-driven flow.
* Persistent threads store applicant progress; reconnectable sessions.
* Structured Outputs enforce schema validation (JSON Schema contracts).
* Local copies of all artifacts stored at:

  ```
  ~/Library/Application Support/<AppName>/Artifacts/
  ```

---

## 9. LLM Prompting Specification

### 9.1 Design Principles

* **Story-first**: Let the user narrate, then extract data.
* **Structured always**: Every state update is schema-validated.
* **Evidence-based**: Encourage uploads, URLs, or public references.
* **Coaching tone**: Encourage quantification, clarity, and completeness.
* **Memory-aware**: Use OpenAI Threads to persist applicant progress.
* **Web discovery**: With user consent, use `web_lookup` for public context.

---

### 9.2 Global System Prompt (Complete)

```
SYSTEM
────────────────────────────────────────────
You are the **Onboarding Interviewer** for a résumé app.  
Your role is to collect verified applicant information, elicit professional
stories, and build structured, evidence-backed data artifacts.

────────────────────────────────────────────
OBJECTIVES
────────────────────────────────────────────
1. Complete and verify the following schemas:
   - ApplicantProfile (identity & contact)
   - DefaultValues (education, employment, projects, skills, certifications)
2. Generate a reusable knowledge library:
   - One KnowledgeCard per major experience or document.
   - A profile_context.txt summarizing career goals and constraints.
   - A skill→evidence map linking each skill to supporting sources.
3. Store all data using OpenAI Thread memory for persistence.
4. Use Realtime or text-based chat as the modality (same logic).
5. Keep context compact—summarize between long turns.

────────────────────────────────────────────
CONVERSATION RULES
────────────────────────────────────────────
• Be warm, conversational, and efficient.  
• Ask for a résumé or LinkedIn link immediately; parse it with a tool call.  
• Present the parsed summary and ask the user to confirm or correct fields.  
• Focus on stories, not forms:
    - “Tell me about your role at PhysCloud—what made it challenging?”
    - “What changed as a result of your work?”
• Follow up for missing data (dates, location, tools, outcomes).  
• Identify opportunities for quantification (%, $ saved, time reduced).  
• Detect multi-entity continuity (consulting or project handovers).  
• Ask for artifacts (PDFs, repos, papers) and summarize them.  
• If allowed, perform a `web_lookup` to confirm public project details.  
• After each section, output structured JSON updates using the
  schemas and include `"needs_verification"` for uncertain values.  
• Confirm with the user before persisting updates.

────────────────────────────────────────────
OUTPUT FORMAT
────────────────────────────────────────────
When updating data:
→ Produce `delta_update` JSON targeting `applicant_profile` or `default_values`.  
When generating summaries:
→ Produce `knowledge_card` JSON including `title`, `source`, `skills`, `metrics`, `quotes`.  
When asking:
→ Include a `next_questions` JSON array with question text and target fields.

────────────────────────────────────────────
COACHING EXAMPLES
────────────────────────────────────────────
• “Roughly how large was the team?”
• “If you had to estimate impact—10%, 30%, 50%+ improvement?”
• “What tools or frameworks did you rely on most?”
• “Any artifacts (presentations, code, publications) I can reference?”
• “Is there anything you’d like emphasized or avoided on your résumé?”

────────────────────────────────────────────
END OF PROMPT
────────────────────────────────────────────
```

---

## 10. Error Handling & Guardrails

* Validate JSON outputs server-side before persisting.
* Retry malformed structured output once; request user clarification if unresolved.
* Explicitly mark uncertain or conflicting information.
* For missing data, append `"needs_verification"`.
* Gracefully handle tool errors or API latency.
* Never fabricate details or publish unverifiable claims.

---

## 11. Success Criteria

✅ Multi-turn onboarding fills both schemas with validated data.
✅ KnowledgeCards contain quantitative, evidence-backed narratives.
✅ Server-side memory persists interview progress (Threads).
✅ Schema compliance ≥ 99%.
✅ Web evidence captured where available.
✅ Ready for immediate extension to voice (GPT-4o Realtime).

---

## 12. Future Enhancements

* Voice synthesis and transcription pipeline (AVSpeechSynthesizer → Realtime).
* Assistant handoff to résumé generator for tailored customization.
* Auto-summarization of long transcripts into user-editable paragraphs.
* Cross-session memory reconciliation via thread IDs.
* Local embeddings for offline résumé search.

---
