
# Onboarding Interview Workflow and Important Ideas

____
## Introduction
The **Onboarding Interview** is a dynamic, LLM-led process for collecting and structuring user information into verified artifacts that power résumé and cover-letter customization.

This feature replaces static forms with a conversational, multi-turn experience that feels like being interviewed by a career coach — guiding users through stories of their work, surfacing quantifiable impact, and generating a structured, evidence-backed knowledge base.

The overall data format is based on the json resume open source schema (with custom attrbute extension) to maximize compatibibility with 3rd party themes and tools.

* * *
## Interview Deliverables

* User-validated ApplicantProfile
* Completed SkeletonTimeline
* Library of experience artifacts
* Knowledge Cards for all prior experience
* ExperienceDefaults completed with broadly applicable default values (used to  seed resumes before customization)
* EnabledSections in ExperienceEditorView set to interview-derived values
* Completed Applicant Dossier
* Corpus of collected Writing Samples


## App Persistent Storage
* ApplicantProfile {Existing}
	* json resume's resume.basics is the foundation of ApplicantProfile
* ExperienceDefaults {Existing}
    * All top-level keys from JSON resume schema except 'basics' key
* KnowledgeCard {New replaces ResRef}
* ArtifactRecord {New replaces ResRef}
* TranscriptRecord {New}
* WritingSample {New Version of CoverRef}
* WritingStyleProfile {New}
* CandidateDossier {New}


## Temporary Interview Scaffold
* SkeletonTimeline {New}
  * Subset of JSON Resume
  * Enable bool for top-level JSON resume keys
* InterviewProgress
  
## Reference Schema
* JSON Resume (with custom-fields extension)

## Local Processing
* Artifact Ingestion
* Code Ingestion
* WritingSample Injestion
* Get macOS Contact Card
	

## LLM tools/functionality
* Orchestrator/Interviewer 
	* GPT-5 (variable verbosity and reasoning?)
	* refererred to herein as LLM or GPT-5
* Knowledge Card Generation
* Query github repo - summarize repo and identify developer strengths/experience

## Planned future Agents
* Transcript Fact Extraction

## Tools
* Get User Option [local execution] {code draft completed}
* Submit to user for validation [local execution] {code draft completed}
	* Surfaces tool pane editor card for user to approve extracted or imported data
	* Tool call triggers card visibility and an immediate response to LLM with "waiting for user" status. When user submits form, a developer message is sent to LLM.
	* Only applied to values extracted from Artifacts, user submitted values are considered user-validated.
* Get User Documement Upload [local execution]
	* Tool call triggers card visibility and an immediate response to LLM with "waiting for user" status. When user submits form, file is proceed through DocumentExtraction sequence via ToolHandlder, and fires an event to which ArtifactRecord subscribes. Complete artifact record event triggers results to be sent to LLM.
	* Support Photo Upload
  		* Import from Photo library 
		* Accept URL or file 
	* Set Objective or Phase status 


## Rules
* Generate and maintain a list of objectives for each phase and do not move until the objectives have been met
* Remember that all artifacts need to be passed to the artifact ingestion agent in order to save them for future reference.
* **[SPEC-TODO]:** this list of rules is incomplete, but I'm drawing a blank right now.


## Workflow Sequence
### Phase 1: Core Facts
#### Objectives
  1. Populate ApplicantProfile object
  2. Construct SkeletonTimeline
  3. Complete EnabledSections object--seed with LLM recommendations, and surface to user for final valies
  4. Start completing CandidateDossier (mix in 2-3 dossier questions this phase-- best to start general)
### Phase 2: Deep Dive
**[SPEC-TODO]** establish specific objectives, prompts and sequence for Phase 2
Still unclear: when do we generate, update, extend Knowledge Cards in this process? How do we know when they're done, how to be steer back towards areas that need more investigation? Do we need to build tools the orchestrator can envoke for this process?

### Phase 3: Writing Corpus
**[SPEC-TODO]** establish specific objectives, prompts and sequence for Phase 3

### All Phases
* Don't forget to make sready progress on CandidateDossier during all phases.
Phase 1 Notes

##Phase 1

---
* Phase 1 is limited to objective core facts only! Only name, location, image, photo number, social profiles, email, website are completed in ApplicantProfile. Values for label and summary in Applicant Profile are not collected at this time (we wait to provide any value for these subjective fields until well-informed, post-interview suggestions can me made)

* Skeleton Timeline entries are limited to job and educational titles and dates only! Descriptions of work, projects and career highlights are the focus of Phase 2.
  
* App-to-agent prompts need are used to acknowledge or advance LLM and keep interviewing progressing.  Many of these prompts sent to the LLM in response to a tool event.


### Phase 1 Sequence of Actions
1. ApplicationProfile
2. Optional Profile Photo
3. Skeleton Timeline
4. EnabledSections
* Mix in 2-3 CandidateDossier questions during phase one

#### Skeleton Timeline Workflow
`
1. User uploads resume, linked-in link, or completes an interview in chat if no docs are provided
2. After automatic document text extraction (via Gemini, discussed below), LLM is used to parse and interpret extracted text and construct draft Skeleton Timeline data
	* Skeleton data is comprised of TimelineEntries. 
	* A timeline entry is created for every significant job, volunteer position, or educational experience.
	* TimelineEntries contain Name, position, dates and locaton only -- other details are added in Phase 2 only
3. Skelton Time line is finalized in feedback loop with user:
	* The LLM surfaces all of the proposed TimelineEntries in the UI using the display_timeline_entries_for_review() tool
	* The user can confirm (checkmark button turns entry border to a glowing green), edit, delete and rearrange timeline entries. 
	* The LLM and user can clarify inconsistencies or discuss entries in the chat interface
4. When the user confirms all entries, LLM asks in chat if timeline is complete.
5. An afirmative response (+all entries confirmed) is the criteria which triggers the Skeleton Timeline interview objective to be marked as complete
6. The confirmed skeleton timeline is used by the LLM to propose the array of json_resume top-level keys which should be enabled (included in Phase 2 investigation)
7. The enabled_sections Tool Pane card is surfaced with LLM proposed toggles. User modifies/confirms to proceed.
8. Phase I complete

#### TimelineEntries

TimelimeEntries (formerly TimelineCards) are a specific set of drag-and-drop user-editable and user-confirmable views and the accompanying LLM tools intended for the construction and verification of the time-sequenced entries in the Skeleton Timelime. The Skelton Timeline is an internal scaffold data structure used by the LLM agent to organize, store and understand the users job and education and stear subsequent Phases of the interview. In later phases, the Skelton Timeline is used to systematically investigate the user's experience and expertise and ultimately generate the final set of knowledge cards used in resume customization.

TimelineEntries are proposed/created by the LLM agent, which surfaces the TimelineEntry Card UI Toolpane. The TimelineEntry Tool Pane card allows the user to confirm, revise and rearrange TimelineEntries to lock in the structure and order of the elements in the Skelton Timeline. While primarily intended for confirming/revising/reordering TimelineEntries proposed by the LLM, a + button allows for adding TimeLineEntries though the Tool Pane UI.

(TODO: Rename TimelineCard-scoped UI Views and LLM tools to TimelineEntry)

---

## SkeletonTimeline LLM Prompt [WIP. Brainstorming included]


You are constructing a SkeletonTimeline—a chronological map of work, 
education, volunteer, and projects.

KEY PRINCIPLES
- **Minimal by design**: Only core identifiers (name, dates, location) — no descriptions, highlights, or details
- **Chronological narrative**: Enables the agent to move through experiences in logical order
- **Section discovery**: The `enabled_sections` object determines which resume areas are relevant for this applicant
- **Foundation for deep dives**: Phase 2 interviews use this structure to select which experiences to explore in detail

LIMITED SCOPE:

json resume schema:        SkeletonTimeline:
━━━━━━━━━━━━━━━━            ━━━━━━━━━━━━━━━━
[Work Entry]               [Work Entry]
├─ name                    ├─ name ✓
├─ position                ├─ position ✓
├─ location                ├─ location ✓
├─ startDate               ├─ startDate ✓
├─ endDate                 ├─ endDate ✓
├─ summary                 └─ url ✓ (optional)
├─ highlights
├─ description
├─ skills         
└─ url

If it's not needed to place an experience in time, exclude it.

RULES:
• Include ONLY: name, position, location, dates, URLs
• Exclude: descriptions, highlights, summaries, skills
• Sort: Chronologically (oldest → newest)
• Dates: ISO 8601 (YYYY-MM-DD or YYYY-MM)
• Current roles: Use null for endDate
• Volunteer: Only if significant
• Projects: Only if structured/substantial/documented and not completed as part of an included job entry

STEPS:
1. If user declines to upload document, proceed with conversation extraction 
2. If uploaded document is provided, extract skeletal data from resume
3. Encode each work, educuation, volunteer or project as a TimelineEntry for user for review using create_timeline_entry() tool.
4. Use display_timeline_entries_for_review() to initiate user review.
5. Update TimelineEntry records in response to developer messages generated by user actions using update_timeline_entry(), rearrange_timeline_entry(), delete_timeline_entry() and create_timeline_entry() as appropriate.
6. Clarify ambiguities (gaps, overlaps, missing dates) with user using chat interface
7. Update TimelineEntry records in response to user messages submitted through chat interface
8. Once TimelineEntry.confirmed = true for all TimelineEntry records, send the user a chat message "Is the presented timeline complete and correct"
9. If the user responds affirmatively SkeletonTime line is complete. Use the request_objective_complete("skeleton_timeline") tool to notify the interview orchestrator and await further instruction.


CONVERSATIONAL EXTRACTION GUIDE (No Résumé Uploaded)

Initial message:
To build your career timeline, I need to understand your work and education history.
Let's start with the basics—we'll dive into details later.

**Let's begin with education:**
• What degree(s) do you have?
• Which institution(s)?
• When did you graduate?

[wait for response, clarify as needed]

**Now your work history:**
Starting from your first job out of school (or first relevant job):
• Company name?
• Your position/title?
• Location (city, state)?
• When did you start and end? (Use "Present" if still there)

[Continue asking for each subsequent role chronologically]

**Any significant volunteer work?**
[Only ask if >6 months or leadership role]

**Any major projects outside of jobs?**
[Only ask if substantial personal/open-source projects]

- Keep the pacing natural, don't spam the user with a list of questions, but be mindful of chat latency and don't pepper the user with short frequent responses
- Restrict the scope -- don't venture into territory that isn't germane to Skeleton Timeline. If user volunteers extra info, retain it in scratchpad for use in later phases

CLARIFYING QUESTIONS GUIDE:

| Scenario | Handling |
|----------|----------|
| **Overlapping dates** | Ask: "Were these concurrent roles?" |
| **Employment gap >6mo** | Ask: "What were you doing during this time?" |
| **Vague dates** | Ask: "Can you be more specific? Month/year?" |
| **Generic title** | Ask: "Software Engineer or Systems Engineer?" |
| **Self-employment** | Add as work entry with name="Freelance" |
| **Bootcamp education** | Include if user considers it significant |
| **Military service** | Ask if they want it as work experience |
| **Consulting gigs** | Option to group as one entry or list separately |

Clarifying Ambiguous Information
────────────────────────────────

I noticed [specific ambiguity]. Can you help clarify?

EXAMPLES:
• "I see two entries for 'Microsoft'—were these different positions or one continuous role?"
• "The end date for PhysCloud says '2023' but your next role started in 'January 2023'—was your last day in December 2022 or later?"
• "Your résumé lists 'Engineer' at TechCorp but doesn't specify the title—was that Software Engineer, Systems Engineer, or something else?"
• "I see a gap between June 2019 and March 2020—were you job searching, freelancing, or taking time off?"
• "You mentioned 'working on a project' during this time—should I add that to the timeline, or was it informal?"



BEFORE FINALIZING, ENSURE:

- [ ] At least 1 work OR education entry exists
- [ ] All dates are ISO 8601 format
- [ ] `endDate ≥ startDate` (when both present)
- [ ] Current positions use `null` for endDate
- [ ] Entries sorted chronologically within arrays
- [ ] enabled_sections align with data presence
- [ ] No descriptions/summaries/highlights present
- [ ] Volunteer only if substantial or candidate has very limited experience
- [ ] Projects only if significant


### Inclusion Criteria

- All user-originated entires received by developer message

### Work Entries
- ✓ All employment (full-time, part-time, contract)
- ✓ Self-employment/freelancing if significant

### Education Entries
- ✓ Degrees (Bachelor, Master, PhD)
- ✓ Bootcamps/certificates if significant to career
- ? Individual online courses (only when signficant or accompanied by Certification)

### Volunteer Entries (Optional)
- ✓ Duration ≥6 months, OR
- ✓ Leadership/board positions, OR
- ✓ Directly career-relevant

#### Project Entries (Optional)
- ✓ Substantial non-job/non-academic projects
- ✓ Open-source with significant adoption
- ✓ Personal ventures demonstrating skills
- ✗ Weekend hackathons, tutorials, hobby projects (unless working with entry-level candidate)

### Exclusion Rules

**Never include:**
- Descriptions, summaries, highlights
- Skills arrays (saved for Phase 2)
- URLs (except in enabled_sections decision)
- Achievements, metrics, accomplishments
- Courses, scores, honors (for education)

**Why?** Phase 1 = Structure. Phase 2 = Substance.
```
##Interview Flow Diagram (only ApplicantProfile flow included)

<div style="font-family: monospace;  width: 80ch;  overflow: hidden;  white-space: pre;">
                                 ___       _                      _ _
                                / _ \ _ _ | |__  ___  __ _ _ _ __| (_)_ _  __ _
                               | (_) | ' \| '_ \/ _ \/ _` | '_/ _` | | ' \/ _` |
                                \___/|_||_|_.__/\___/\__,_|_| \__,_|_|_||_\__, |
┌────────────────┐                                                        |___/
│ Overall goals  ├─────────────────────┐   ___     _               _
└┬───────────────┘                     │░ |_ _|_ _| |_ ___ _ ___ _(_)_____ __ __
 │• User-validated ApplicantProfile    │░  | || ' \  _/ -_) '_\ V / / -_) V  V /
 │• Completed SkeletonTimeline         │░ |___|_||_\__\___|_|  \_/|_\___|\_/\_/
 │• Library of experience artifacts    │░
 │• Knowledge Cards Library            │░       Message styling key ▼
 │• Completed Applicant Dossier        │░       ║ ╔══════════════════════════╗
 │• Corpus of collected Writing Samples│░       ║ ║   LLM message to chat    ║
 │.                                    │░       ║ ╚══════════════════════════╝
 └─────────────────────────────────────┘░       ║ ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░       ║ ┃   User message to chat   ┃
                                                ║ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛
      Start: Phase 1                ╔═══════════╣ ┌──────────────────────────┐
      ╔══════════════════════╗      ║LLM =      ║ │    App message to LLM    │
      ║Greet User            ║      ║Interviewer║ └──────────────────────────┘
      ╚═══════════════ P1:T1 ╝      ╚═╗         ║ ╔══════════════════════════╗
      ╔ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═         ║  Agent =║ ║░░░░░░░LLM to agent░░░░░░░║
       get_user_choice()     ║        ║Sub-agent║ ╚══════════════════════════╝
  ┌───║profile source?        ◀─┐     ╚═════════╣ ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
  │    ═ ═ ═ ═ ═ ═ ═ ═ P1:T2 ╝  │               ║ ┃░░░░░░░Agent to LLM░░░░░░░┃
  │   ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │               ║ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛
  │    Waiting for user      │──┘               ║ ┌──────────────────────────┐
  │   └ ─ ─ ─ ─ ─ ─ ─  P1:T3                    ║ │░░░░░░░App to agent░░░░░░░│
  │   ╔══════════════════════╗                  ║ └──────────────────────────┘
  │   ║Please complete       ║                  ║ ╔ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═
  │   ║form to left          ║                  ║         LLM tool use       ║
  │   ╚═══════════════ P1:T4 ╝                  ║ ╚ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═
  │  ┌───────────────────────────────────────┐  ║ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
  │  │ Multiple choice widget                │░ ║        Tool response       │
  │  │                                       │░ ║ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
  ├──┼──▶A: File Upload ───────────────────┐ │░ ╚═══════════════════════════════
  │  │          ┌────────────────────────┐ │ │░   ┌────────┐      ┌────────────┐
  ├──┼──▶B: URL │User provided url please│ └─┼───▶│Upload  ├─────▶│User        │
  │  │          │fetch and process       │───┼──┐ │widget  │─────┐│uploaded    │
  │  │          └─────────────────P1:TB5 ┘   │░ │ └────────┘░    ││resume file.│
  ├──┼───C: Contacts App──▶ Retrieve         │░ │  ░░░░░░░░░░    ││Please parse│
  │  │                      locally with ──┐ │░ │ ╔ ═ ═ ═ ═ ╗    ││and request │
  └──┼──▶D: Manual Entry ─┐ apple api      │ │░ └▶ URL Fetch─┐   ││validation. │
     │                    │                │ │░ ┌─║         ║│   │└──────P1:TA5┘
     │              ┌─────┘                │ │░ │  ═ ═P1:TB6 │ ┌─▼──────────┐│
     └──────────────┼──────────────────────┼─┘░ │ ┌ ─ ─ ─ ─ ┐└─▶░░Process ░░││
      ░░░░░░░░░░░░░░│░░░░░░░░░░░░░░░░░░░░░░│░░░ └▶ URL Text    │░░Artifact░░││
                    │                      │      │         │─┐└────────────┘│
     ┌──────────────▼─────────────┐        │       ─ P1:TB7─  │              │
     │ Update ApplicantProfile    │◀───────┘      ╔═══════════▼═══════════╗  │
     │ Validate Profile Widget    │◀──────┐       ║    Parsing Profile    ║◀─┘
     │                            │▣━━┓   │       ╚═════════════ P1:TA6B8 ╝
     └────────────────────P1:T11* ┘░  ┃   │ ╔ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═ ═   │
      ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  ┃   └──    user_validate()     ║◀─┘
      ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐  ┌╋─────║
   ┌── Waiting for user            ◀─┘┃      ═ ═ ═ ═ ═ ═ ═ ═P1:TA7B9 ╝
   │  └ ─ ─ ─ ─ ─ ─ ─ ─ P1:TA8B10 ┘   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
   │   ╔═════════════════════════════╗ ██████████████████████            ▼
   │   ║Please complete              ║ █ Objective Complete █     ╔════════════╗
   └──▶║form to left                 ║ █ ApplicationProfile █◀━┓  ║╔══════════╗║
       ╚══════════════════ P1:T12 ═══╝ ██████████████████████  ┃  ║║Queue next║║
       ┌──────────────────────────────────────────┐            ┃  ║║objective:║║
       │Please ask user if they would like to add │            ┗━□║║Include   ║║
       │a photo to their profile.                 │◀━━━━━━━━━━━━━□║║photo?    ║║
       └──────────────────────────────── P1:T13 ──┘               ║╚══════════╝║
                                                                  ║ Objective  ║
                                                                  ║ Monitoring ║
                                                                  ║   Agent    ║
                                                                  ╚════════════╝
</div>
Note: prompts are simplied and approximate and should be adhere to prompt engineering best practices in actual implementation.

App to LLM: Please greet the user, outline process and use the get_user_choice tool to surface a multiple-choice form for the user to determine how we will collect ApplicantProfile info (name, address, etc) to get started.

SIMULATED LLM:
AGENT: Hi {intro and outline}....
TOOL USE: get_user_choice(choices json....)
[Agent is paused awaiting tool response]
---------
APP receives tool-call message with get_user_choice payload. The resulting code path surfaces the multiple choice UI to the user and the app sends the  message: Status: waiting for user input
---------
// Based on user choice we branch into one of four workflow paths -> upload doc, submit url, contact card or manual entry

// Based on system prompt and tool definition LLM has been coached to offer a simple response to "waiting for user"  messages.
SIMULATED LLM:
Once you complete the form to the left we can continue.

// Note that the llm's reply to "waiting for user"  messages is a pre-prompted acknowlegement (defined in system prompt).   This prevents the model's tool-call from encountering a timeout condition.

# Onboarding Interview Deliverables and Data Types

---
## Artifact Record
[Existing Implmenetion requires documentation and possible extension]

---
## Knowledge Cards 

### Format
KnowledgeCard is an @Model SwiftData entity stored in the app’s default ModelContainer. It conforms to Codable and (when needed) encodes/decodes to the LLM-friendly JSON schema below—using CodingKeys and encoder settings to match the schema exactly.

### Purpose
Knowledge Cards are compact, evidence-linked records used to assemble resumes, briefs, and internal dossiers. The schema is intentionally minimal to avoid over-specification, while adding a few high‑leverage fields for retrieval and anti‑hallucination safety.

SYSTEM
────────────────────────────────────────
You are the Knowledge Card Generator.

MISSION
Create ONE rigorously evidenced, information-dense Knowledge Card that can serve as the complete fact source for resumes and cover letters across ANY plausible target role or industry the applicant could pursue (primary field and adjacent pivots). The card must strictly follow the “Knowledge Card v1.1” JSON schema and anti-hallucination rules: no extra fields; all required fields present; every claim that needs support includes a [[ref:...]] that resolves to citations[]. No evidence → no claim.

DEEP-READING PROTOCOL (MANDATORY)
1) Inventory all inputs: interview transcript chunks + every artifact (resume/CV, project docs, PDFs, code repos, papers, presentations, HR docs, public pages).
2) Two-pass reading for EACH artifact:
   • Pass A (skim map): identify purpose, scope, timeframe, stakeholders, constraints, methods, tools/tech, metrics, outcomes, and named entities.
   • Pass B (evidence harvest): extract short quotes (≤200 chars) with precise locators (page/section/line/file:line); assign stable ref_ids with the correct prefix (artf-, trns-, hr-, pub-).
3) Evidence log: maintain a structured set of citation candidates; dedupe near-duplicates; keep the best, most location-specific quotes.
4) Cross-artifact reconciliation: line up timelines, normalize org and tech names, and resolve conflicts by preferring primary sources; push any unresolved gaps to queued_questions_for_user.
5) Resume-readiness augmentation: translate technical impact into business value and vice-versa; capture both granular skills/tech AND their generalized/transferable forms for ATS breadth.

SCOPE & DENSITY REQUIREMENTS
• Be comprehensive: include ALL verifiable skills and technologies you can support—even if the list is long. Long lists are welcome when accurate and evidenced.
• Skills/Tech extraction is hierarchical: (core domain skills) + (methods/algorithms) + (standards/protocols) + (tools/frameworks/languages/platforms) + (soft/leadership/process skills) where supported.
• Prefer measurable outcomes; if exact values are not supported, use evidenced ranges (e.g., ~20–25%).
• Add rich retrieval hooks: domain_tags (normalized topical areas), and keywords (aliases, acronyms, prior org names, problem domains).

TOOL USE (WHEN & WHY)
• summarize_artifact(fileId, context) — run for EVERY artifact; request quotes + metrics + precise locators; mine entities, skills, tech, constraints, methods, outcomes. Repeat if an artifact is large: iterate by section.
• web_lookup(query, context) — only with user consent; corroborate public claims and add public citations with URLs + locators. Never to pad unsupported claims.
• persist_card(card) — only after validation and cross-reference checks pass.
• persist_delta(target, delta) — propose small factual patches (dates, titles, locations) discovered during card creation; ask before persisting if uncertainty is more than low.

OUTPUT
Return ONLY a single JSON object exactly matching “Knowledge Card v1.1”.
Every overview/skills[*].skill_level_or_notes/tech[*].level_of_expertise/achievements[*].achievement MUST include ≥1 [[ref:...]] that resolves to citations[]. Ensure every citations.ref_id is referenced ≥1× in the card.

SAFETY & QUALITY
• Never fabricate metrics, employers, or sources. If uncertain: omit the claim and add a precise follow-up to queued_questions_for_user.
• Normalize names (e.g., PostgreSQL, PyTorch). Keep notes succinct but evidence-linked.


TASK
────────────────────────────────────────
Inputs:
• transcript_chunks: <array of strings>
• artifact_ids: <array of file ids>  // run summarize_artifact on EACH
• context: { audience?: "recruiter|engineering-manager|academic", domain_tags?: [...], target_role?: string, consent_public_lookup?: boolean }

Steps:
1) Build Evidence Log
   a) Parse transcript_chunks for claims and create trns- refs with short quotes + locators (timestamp/speaker if available).
   b) For each artifact_id → call summarize_artifact(fileId, context). If the doc is long, iterate per section to harvest more citations.
   c) Normalize org names, titles, dates, and tech/skill aliases; reconcile conflicts; queue questions for any unresolved discrepancies.

2) Achievements First
   Draft 3–8 verb-first achievements with measurable outcomes or evidenced ranges. Each must contain [[ref:ID]].

3) Overview
   Write a concise, recruiter-safe overview including Org/Dates/Location/Narrative micro-headings. Must include [[ref:...]].

4) Exhaustive Skills & Tech
   • Extract a comprehensive list; long is acceptable when evidenced. Include domain/functional skills, algorithms/methods, standards/protocols, tools/frameworks, languages, platforms, cloud/services, data infra/ML ops, testing/CI/CD, security/compliance, leadership/process skills (if supported).
   • For skills[*].skill_level_or_notes and tech[*].level_of_expertise: add concise notes that include [[ref:...]] and, where useful, brief scope qualifiers (e.g., “productionized,” “intraday,” “p95 SLO,” “N=2k users”).

5) Resume Readiness
   • Translate technical outcomes into business framing (and vice-versa) for cross-industry portability.
   • Populate keywords (aliases, acronyms, generalizations) and domain_tags for later retrieval and resume routing.
   • Write a 1–3 sentence elevator_pitch that captures scope, role, and outcomes; include at least one [[ref:...]].

6) Citations
   • Keep only high-signal quotes/notes with specific locators. Ensure every in-text [[ref:...]] resolves to citations.ref_id; ensure every citations.ref_id is referenced ≥1×.

7) Output
   Return ONLY a JSON object that matches the “Knowledge Card v1.1” schema exactly (no additional properties).

### Achievements (style guidance, not schema rules)
- Prefer a **strong verb + concrete result**, and include a measurable outcome when evidence exists.  
- Avoid forced metrics; if no evidence, see Anti‑hallucination rules below.

### Skill/Tech normalization (guidance only)
- Canonicalize synonyms (e.g., prefer `PostgreSQL` over `Postgres`, `PyTorch` over `torch`).  
- Suggested (tiny) level language for consistency — not enforced:  
  `exposure | working | proficient | advanced | expert`.  
- Keep free‑text notes; include `[[ref:...]]` to support claims.

### Anti‑hallucination guardrails
- **No evidence → no claim.** If a required claim lacks support, **omit the claim** and add a brief item to `queued_questions_for_user`.  
- For numbers, prefer **evidenced ranges** (e.g., `~20–25%`) over fabricated precision.

## CandidateDossier — Coding Spec & LLM Prompt

**Status:** Extension to Onboarding Interview Spec v3  
**Purpose:** Capture qualitative, contextual, and situational aspects of the candidate's job search that are not represented in structured data (employment, education, skills, certifications)  
**Data Type:** Narrative strings and qualitative assessments  
**Collection Method:** Open-ended conversational prompts throughout the onboarding interview

---

### 1) Overview

The **CandidateDossier** is a narrative-focused data object that captures the "human story" behind a job search. While `ApplicantProfile`, `ExperienceDefaults`, and `KnowledgeCards` provide structured, verifiable facts, the dossier records motivations, preferences, constraints, and strategic insights that inform resume customization, cover letter generation, and job fit assessment.

The dossier serves four key functions:
1. **Context**: Why the candidate is searching, what they're leaving behind, what they're seeking
2. **Job Fit Assessment**: Evaluate whether specific opportunities align with the candidate's priorities, constraints, and preferences
3. **Strategic Intelligence**: Strengths to emphasize, pitfalls to avoid, unique positioning opportunities
4. **Personalization Anchor**: Authentic voice and priorities to ground tailored application materials

## 1) Phase 1 — Narrative Prompts (Ask–Synthesize–Persist)

Use a conversational style. Ask **one focused question at a time**. After the candidate answers, **reflect back** a terse summary, confirm, and **persist**.

#### 1.1 Opening
**Assistant→User**
> To tune the rest of the interview, what are you optimizing for in your next role—scope, domain, team shape, or something else?

**Assistant (internal synthesis after user answers)**
- Extract: motivations, what’s missing today, 2–3 priorities, non‑negotiables.
- Draft `job_search_context` as 2–4 crisp sentences.

**Dossier Update (on confirmation)**
- Update `job_search_context`.
- If candidate states no relocation or must‑have remote policy, also update `work_arrangement_preferences`.

#### 1.2 Priorities & Non‑Negotiables
**Assistant→User**
> Top 2–3 priorities for you (e.g., ownership, user impact, compensation band, domain)? Any non‑negotiables?

**Synthesis hints**
- Avoid salary numbers unless volunteered.
- Convert long prose into bullets.

**Persist**
- Upsert `job_search_context` with bullets appended or re‑summarized more crisply.

#### 1.3 Work Arrangement
**Assistant→User**
> What’s your preferred setup—remote, hybrid, or onsite? Any cities you prefer or want to avoid? Would you relocate for the right role?

**Persist**
- Upsert `work_arrangement_preferences` as 2–3 sentences or bullets.

#### 1.4 Availability
**Assistant→User**
> What’s your available start window and notice period? Any interview‑scheduling constraints?

**Persist**
- Upsert `availability`.

#### 1.5 Strengths to Emphasize
**Assistant→User**
> What patterns tend to make you most effective—environments, team size, or strengths you want highlighted?

**Persist**
- Upsert `strengths_to_emphasize` (bulleted list fine).

#### 1.6 Pitfalls to Avoid
**Assistant→User**
> Anything that often gets misread on your resume or in interviews that we should proactively address?

**Persist**
- Upsert `pitfalls_to_avoid`.

#### 1.7 Unique Circumstances (optional, sensitive)
**Assistant→User**
> Any context behind timeline changes—pivots, gaps, visa, sabbatical, non‑compete—worth including? (Totally optional.)

**Persist**
- Upsert `unique_circumstances`. If sensitive, keep wording factual and minimal.
- Ensure `sensitivity` stays `personal` unless explicitly changed.

---

### 2) Phase 2 — Timeline Prompts (Opportunistic Dossier Updates)

During role‑by‑role deep dives, listen for relevant facts to enrich the dossier. Ask only when context makes it natural; otherwise, skip.

#### 2.1 While discussing a role
**Assistant→User (only if not captured in Phase 1)**
> Did this role change your preferences for remote vs. onsite or the kind of team you prefer?

**Persist**
- Append to `work_arrangement_preferences` or `strengths_to_emphasize` if the answer adds new information.

#### 2.2 When departure comes up
**Assistant→User**
> What prompted the move? Anything you want to seek or avoid based on that experience?

**Persist**
- If the answer reframes goals, re‑summarize `job_search_context` more precisely (replace only if strictly clearer).

#### 2.3 Time windows and constraints
**Assistant→User**
> Do you have a target start window or any commitments that affect scheduling over the next month?

**Persist**
- Upsert `availability` with concrete windows if provided.

#### 2.4 Sensitive or special situations
**Assistant→User (optional)**
> Any context that would be helpful to include, like a non‑compete or a planned move? Totally up to you.

**Persist**
- Upsert `unique_circumstances`. Keep neutral tone.

---

### 3) Confirmation Pattern

After each material answer:
1) Mirror back a **one‑sentence** summary.  
2) Ask “**Is that accurate as written?**”  
3) Only then persist the update.

**Assistant (confirmation example)**
> Capturing: *“Remote‑first; will consider Austin hybrid 2–3 days/month; no relocation this year.”* OK?

**If yes → persist. If no → revise and re‑confirm.**


### 2) Data Model (Schema)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "CandidateDossier",
  "type": "object",
  "properties": {
    "dossier_id": {
      "type": "string"
    },
    "created_at": {
      "type": "string",
      "format": "date-time"
    },
    "updated_at": {
      "type": "string",
      "format": "date-time"
    },
    "job_search_context": {
      "type": "string",
      "description": "Free-form narrative: Why looking? What leaving behind? What seeking? Priorities and constraints. Ideal role characteristics. Compensation expectations."
    },
    "work_arrangement_preferences": {
      "type": "string",
      "description": "Remote work preferences, office requirements, hybrid flexibility, relocation willingness and constraints."
    },
    "availability": {
      "type": "string",
      "description": "How soon can start. Notice period requirements. Any timing constraints or flexibility."
    },
    "unique_circumstances": {
      "type": "string",
      "description": "Anything unconventional, unusual, or requiring special explanation in the job search or career trajectory."
    },
    "strengths_to_emphasize": {
      "type": "string",
      "description": "Hidden or under-emphasized strengths not obvious from resume. How to surface these in applications."
    },
    "pitfalls_to_avoid": {
      "type": "string",
      "description": "Potential concerns, vulnerabilities, or red flags. How to address, reframe, or mitigate them."
    },
    "notes": {
      "type": "string",
      "description": "Private interviewer observations, impressions, strategic recommendations."
    }
  },
  "required": [
    "dossier_id",
    "created_at",
    "job_search_context"
  ]
}
```


### 3) Integration with Existing Workflow

#### 3.1 Placement in Interview Flow (incoporate into orchestraor prompts)

The CandidateDossier is populated **throughout the onboarding interview**, with questions naturally woven into Phase 1 (Narrative) and Phase 2 (Timeline Expansion). The interviewer should **opportunistically integrate dossier questions** when context makes them relevant, rather than treating the dossier as a separate section.

**Integration approach:**
- During Phase 1, naturally ask about job search context, priorities, and work preferences
- During Phase 2 timeline discussions, probe for availability, relocation constraints, and unique circumstances as they arise
- When discussing specific roles or artifacts, ask about remote work preferences if relevant
- Synthesize strategic assessments continuously as insights emerge
- Near the end, explicitly ask about any skills or strengths not yet discussed
- A dedicated "dossier completion" section may be needed if key information hasn't surfaced naturally, but the goal is smooth integration

**Example integration points:**
- When discussing departure from previous role → Ask about what they're seeking in next role
- When reviewing location history → Ask about remote work preferences and relocation willingness  
- When discussing current role → Ask about availability and notice period
- When uncovering unique projects or gaps → Probe for unconventional circumstances
- Near end of interview → Ask about unlisted skills and candidate's self-assessment
- Throughout → Observe communication style and identify strengths/pitfalls

The dossier questions can be repeated or revisited as needed to gather complete information, but ideally they flow naturally with the conversation rather than feeling like a checklist.

#### 3.2 Tool Integration

Add a new persistence tool:

```json
{
  "tool": "persist_dossier",
  "purpose": "Save or update the CandidateDossier",
  "input": {
    "dossier": "CandidateDossier object"
  },
  "output": {
    "dossier_id": "string",
    "ok": true
  }
}
```

The dossier can be persisted incrementally as information is gathered, not just at the end of Phase 1.

---

### 4) LLM Prompt for Dossier Collection

#### 4.1 System Prompt (Interview Agent)

```
You are conducting an onboarding interview for a resume and cover letter application. Throughout the interview, you will gather information for the CandidateDossier — a qualitative profile that captures the candidate's job search story beyond resume facts.

The dossier serves two critical purposes:
1. Assess whether specific job opportunities are a good fit for the candidate
2. Inform customization of resumes and cover letters for aligned opportunities

You will collect contextual information about:
- Why they're looking for a new position
- What they're leaving behind and what they're seeking
- Work arrangement preferences (remote, hybrid, relocation)
- Availability and start date constraints
- Priorities, ideal role attributes, and compensation expectations
- Any unique or unconventional circumstances
- Skills, strengths, or experiences not evident from artifacts or discussion

CRITICAL: Integrate dossier questions naturally throughout the interview rather than treating them as a separate section. When context makes a question relevant, ask it. For example:
- When discussing location history → Ask about remote work and relocation preferences
- When reviewing departure timing → Ask about availability and notice period
- When exploring role dissatisfaction → Ask about priorities for next role
- When uncovering gaps or pivots → Probe for unconventional circumstances
- Near end of interview → Ask about any skills or strengths not yet discussed

Your conversation style should be:
- Warm and empathetic, not transactional
- Open-ended but focused (one main question at a time)
- Curious and non-judgmental
- Brief responses that encourage elaboration
- Perceptive about what's unsaid or implied
- Natural and conversational, not checklist-driven

As you gather information, continuously synthesize strategic assessments:
1. Unique strengths not obvious from their resume
2. Potential pitfalls or concerns to navigate carefully
3. Job fit criteria and deal-breakers

Near the end of the interview, explicitly ask: "Do you have any skills, experiences, or strengths you want me to be aware of that haven't come up during our conversation?" This catches important capabilities that may not have been relevant to the timeline discussion but matter for job fit.

Before finalizing your strategic assessment, ask the candidate: "What do you see as your biggest strength and most valuable asset to a new employer?" 

Use their response as a calibration check:
- If it aligns with your assessment → You're likely on track
- If it differs significantly → Probe to understand their reasoning and consider adjusting your assessment
- If they identify something you missed → Add it to strengths_to_emphasize
- If they overvalue a minor skill or miss their true differentiators → Note the discrepancy in your private notes, but trust your evidence-based assessment

The candidate knows themselves, but may have blind spots. Your role is to synthesize their self-perception with your independent observations to create the most accurate and useful assessment.

If key dossier information hasn't emerged naturally by the end of Phase 2, you may dedicate a brief section to gathering missing details. It's acceptable to ask the same question multiple times if needed for completeness.

Use the persist_dossier tool to save or update the dossier as information is gathered.
```


#### 4.2 Conversation Script (Integrated Approach)

```
The dossier questions below can be asked at any point during the interview when context makes them relevant. They do NOT need to be asked in order or all at once.

---

**Job Search Context (often in Phase 1 opening):**

"What's prompting you to look for a new position right now?"

[Listen for push factors (leaving) and pull factors (seeking). Probe gently if superficial.]

Possible follow-ups:
- "What specifically about [current role] isn't working for you anymore?"
- "It sounds like [key theme]. Tell me more about that."
- "How long have you been feeling this way?"

---

**Departure Context (when discussing employment timeline in Phase 2):**

"I see you [left / are leaving] [Company] in [timeframe]. Can you walk me through what led to that decision?"

[For involuntary departures, be especially empathetic:]
- "That must have been difficult. How are you thinking about explaining that in applications?"

[For voluntary departures:]
- "What was the final straw that made you decide to leave?"

---

**Work Arrangement Preferences (when discussing location or current role setup):**

"How do you feel about remote work? What's your ideal work arrangement?"

Follow-ups:
- "Is fully remote a requirement, or are you open to hybrid/office?"
- "How many days per week in-office would be your limit?"

"Are you open to relocating for the right opportunity?"

Follow-ups:
- "Are there specific cities or regions you'd consider?"
- "What would make relocation worth it for you?"
- "Any constraints that would prevent relocation?" (family, property, visa, etc.)

---

**Availability (when timeline context is relevant):**

"When would you be able to start a new position?"

Follow-ups:
- "Do you have a notice period at your current company?"
- "Is there any flexibility around your start date?"
- "Any timing constraints we should be aware of?" (projects wrapping up, personal commitments, etc.)

---

**Forward-Looking Priorities (natural throughout, especially after discussing dissatisfaction):**

"Looking ahead, what matters most to you in your next role?"

[Encourage ranking and specificity:]
- "Of those factors, which are absolute must-haves versus nice-to-haves?"
- "What trade-offs are you willing to make?"

[Probe for: Culture, technical environment, team dynamics, autonomy, growth, impact, work-life balance, industry]

---

**Compensation (can be woven into priorities discussion or asked directly):**

"What are your expectations around salary and total comp?"

[Be direct but respectful:]
- "What's the minimum you'd need to make a move make sense?"
- "Is there flexibility if the role checks other important boxes?"

---

**Unique Circumstances (when something unusual surfaces naturally):**

"Is there anything unconventional or unique about your job search that hiring managers should understand?"

[Examples: Career pivots, time away, geographic constraints, visa complexity, non-traditional background, productive gaps]

---

**Unlisted Skills (near end of interview, before synthesis):**

"Before we wrap up, I want to make sure I haven't missed anything. Do you have any skills, experiences, or strengths you want me to be aware of that haven't come up during our conversation?"

[Listen carefully — this often surfaces:]
- Technical skills not reflected in recent work
- Soft skills or domain knowledge assumed to be obvious
- Side projects, volunteer work, or hobbies with professional relevance
- Languages, certifications, or specialized training

---

**Self-Assessment Validation (near end, before presenting your synthesis):**

"One more question: What do you see as your biggest strength and most valuable asset to a new employer?"

[Listen for alignment or divergence from your assessment:]
- Aligned: Confirms your observations
- Divergent: Probe their reasoning, consider if you missed something
- Overvalued minor skill: Note discrepancy privately
- Missed true differentiator: Gently highlight what you've observed

---

**Synthesis (after gathering all information, including self-assessment):**

"Let me summarize what I'm hearing about what you're looking for..."

[Reflect back key themes, then offer strategic assessment:]

"As I think about how to position your background and identify good-fit opportunities:

**Strengths to emphasize:**
[List 2-3 unique strengths, informed by both your observations and their self-assessment]

**Potential concerns to address:**
[List 1-2 pitfalls and mitigation strategies]

**Job fit criteria:**
[Summarize must-haves, deal-breakers, and trade-offs]

Does that feel accurate? Anything I'm missing or getting wrong?"

[If candidate's self-assessment revealed something you missed, acknowledge it:]
"You mentioned [X] as a key strength — I agree, and we should definitely highlight that."

---

**If information is still missing after natural integration:**

You may ask remaining dossier questions directly: "A few quick questions to round out your profile..." 
Then ask about any missing: availability, remote preferences, relocation, unique circumstances, etc.

```

#### 4.3 Strategic Assessment Guidelines

When populating the strategic assessment fields, the LLM should write clear, narrative assessments:

**For `strengths_to_emphasize`:**
Write 2-4 paragraphs identifying hidden strengths and how to surface them. Look for:
- Skills or experiences mentioned casually that deserve prominence
- Cross-domain expertise (e.g., "technical background + business acumen")
- Leadership or initiative not titled as such
- Adaptability, learning velocity, or resilience from career pivots
- Rare combinations (e.g., "hands-on engineer who can also write/present")
- Skills revealed in the "unlisted skills" question
- Alignment or divergence with candidate's self-assessment

**For `pitfalls_to_avoid`:**
Write 2-4 paragraphs identifying potential concerns and mitigation strategies. Consider:
- Employment gaps → Frame as productive time
- Job changes → Emphasize growth trajectory and consistent impact
- Overqualification → Demonstrate genuine interest and culture fit
- Termination/layoff → Position as external circumstance
- Career pivot → Connect dots between domains; show transferable skills
- Salary mismatch → Emphasize non-monetary motivations

Include specific, actionable recommendations for how to address each concern in applications.

**Note on self-assessment:**
If the candidate's self-assessment diverges significantly from your evidence-based observations, note this in the `notes` field. For example: "Candidate sees [X] as their biggest strength, but evidence suggests [Y] is their true differentiator. May need coaching to recognize and articulate [Y] in interviews."


---

### 5) Usage in Downstream Processes

#### 5.1 Job Fit Assessment (Primary Use)

When evaluating whether a specific job opportunity aligns with the candidate:
- Compare job requirements against `work_arrangement_preferences` (remote/hybrid/office, location)
- Check `availability` against hiring timeline expectations
- Evaluate role characteristics against priorities and ideal attributes in `job_search_context`
- Consider compensation range against expectations in `job_search_context`
- Flag any conflicts with `unique_circumstances` (e.g., visa restrictions, relocation constraints)
- Reference `notes` for cultural fit indicators and deal-breakers

**Output a fit score or assessment:**
- **Strong fit**: Aligns with must-haves, no deal-breakers
- **Moderate fit**: Meets most priorities, minor trade-offs required
- **Weak fit**: Significant misalignment or deal-breaker present
- **Include reasoning**: Why it's a fit or not, based on specific dossier content

#### 5.2 Resume Customization

When tailoring a resume for a specific job:
- Reference `job_search_context` to understand priorities and emphasize aligned experiences
- Surface relevant points from `strengths_to_emphasize` that match job requirements
- Mitigate concerns flagged in `pitfalls_to_avoid` using suggested strategies

#### 5.3 Cover Letter Generation

When generating a cover letter:
- Open with authentic motivation drawn from `job_search_context`
- Weave in positioning themes from `strengths_to_emphasize`
- Address potential concerns from `pitfalls_to_avoid` if likely to surface
- Reference `unique_circumstances` where relevant to demonstrate transparency
- Acknowledge work arrangement if remote/hybrid is important to candidate

#### 5.4 Interview Preparation

- Prepare responses to questions about issues raised in `pitfalls_to_avoid`
- Prepare stories that illustrate points from `strengths_to_emphasize`
- Anticipate cultural fit questions based on information in `job_search_context`
- Have clear answer ready about `availability` and notice period
- Be prepared to discuss `work_arrangement_preferences` and relocation stance



### 6) Privacy and Sensitivity

- The dossier may contain **highly sensitive information** (termination details, health issues, personal circumstances).
- Do not include dossier content in any exported or shared materials without explicit user consent.
- Redact specific sensitive details in `notes` if shown to user.
- Future feature: Store encrypted at rest; limit access to dossier-reading services.

### 7) Example Dossier (Redacted)

```json
{
  "dossier_id": "doss_a8f72b",
  "created_at": "2025-03-15T14:30:00Z",
  "updated_at": "2025-03-15T15:45:00Z",
  "job_search_context": "Seeking a role with more technical ownership and less bureaucracy. Left previous company after 3 years (voluntary, good terms) when a reorg added another management layer. Current company became too process-heavy — spending more time in meetings than building. Frustrated by slow decision-making and lack of autonomy for senior ICs.\n\nTook a 6-month sabbatical to work on open-source projects and learn Rust. Want to be upfront this was intentional downtime, not unemployment.\n\nPriorities moving forward: 1) High autonomy and ownership 2) Small-to-mid size team (10-100 eng) 3) Modern tech stack 4) Meaningful product 5) Flexible remote. Willing to trade comp for mission alignment and technical challenge.\n\nIdeal role: Staff or Principal IC at a growth-stage startup. Close collaboration with product and design. Greenfield projects or significant refactors. Async-first culture. Mission related to dev tools, infra, or climate tech.\n\nCompensation: Current base $180k. Would take modest step back ($160k minimum) for the right role, especially with equity upside. More interested in learning and impact than maximizing TC short-term.",
  "work_arrangement_preferences": "Strong preference for remote-first or fully remote. Would consider hybrid (2 days/week max in office) if the role is exceptional. Not interested in full-time office positions. Open to occasional travel for team gatherings or important meetings.\n\nCurrently based in Austin, TX. Open to relocating to SF Bay Area, Seattle, or NYC for the right opportunity (Staff+ role at mission-aligned company with strong equity package). Would not relocate for anything less than that. Partner is also in tech and location-flexible.",
  "availability": "Currently employed with standard 2-week notice period. Could start 3 weeks from offer acceptance to allow for smooth handoff. Some flexibility if needed for exceptional opportunity. No major timing constraints — not waiting for bonus/vesting or other commitments.",
  "unique_circumstances": "6-month sabbatical between last role and current job search. Used time for open-source contributions and learning Rust. Career gap is intentional skill investment, not unemployment.\n\nWhen asked about unlisted skills, mentioned intermediate Spanish proficiency and previous experience with technical writing/documentation that isn't on recent resume but could be valuable for developer-facing products.",
  "strengths_to_emphasize": "Bridge between deep technical expertise and product thinking — mentioned frustration with pure technical decisions lacking product context; sabbatical projects included UX considerations. Position as 'technical leader with product sense' and highlight examples where technical decisions drove user impact.\n\nSelf-directed learner with demonstrated follow-through — sabbatical learning, OSS contributions, previously self-taught LabVIEW and Python. Emphasize rapid skill acquisition and side projects in resume.\n\nComfortable with ambiguity and building from scratch — expressed desire for greenfield work; past early-stage startup experience. Use language like 'thrives in 0-to-1 environments' and 'comfortable with fast-changing requirements.'\n\nTechnical communication ability — mentioned writing/documentation experience and expressed desire to work on developer tools. This is an undervalued strength that should be highlighted for docs-heavy or API-focused roles.",
  "pitfalls_to_avoid": "6-month employment gap may raise questions. Proactively label as 'sabbatical' on resume with 1-liner: 'Focused on open-source contributions and learning Rust.' In cover letters, frame as intentional investment in skills.\n\nLeaving stable role after 3 years might signal restlessness. Emphasize growth and impact during tenure. Frame departure as seeking next challenge, not fleeing problems. Highlight positive relationships and offer references.\n\nAvoid sounding negative about previous employer when discussing reasons for leaving.",
  "notes": "Candidate is thoughtful and self-aware. Left last role for valid reasons (autonomy, growth ceiling) but may need coaching to avoid sounding negative. Strong cultural preference for startup/scale-up environments; won't be happy at large corp. Consider roles at Series B/C with technical complexity and product ownership. Speaks directly and honestly; slightly self-deprecating but not insecure. Values substance over polish. Professional but conversational communication style.\n\nDeal-breakers for job fit: Full-time office requirement, large bureaucratic orgs (500+ eng), purely managerial track, non-technical product work. Remote-first is nearly a requirement — would need exceptional circumstances to consider hybrid.\n\nSelf-assessment validation: When asked about biggest strength, candidate said 'ability to learn new technologies quickly and dive deep.' This aligns well with our observation of self-directed learning pattern. Good self-awareness."
}
```

---

# Reference Docs

---
## JSON Resume Schema (portable data format for resume generation)
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "http://example.com/example.json",
  "additionalProperties": true,
  "definitions": {
    "iso8601": {
      "type": "string",
      "description": "Similar to the standard date type, but each section after the year is optional. e.g. 2014-06-29 or 2023-04",
      "pattern": "^([1-2][0-9]{3}-[0-1][0-9]-[0-3][0-9]|[1-2][0-9]{3}-[0-1][0-9]|[1-2][0-9]{3})$"
    },
    "custom": {
      "type": "object",
      "description": "Custom field for extensibility. Allows users to add implementation-specific data while maintaining compatibility with existing tools.",
      "additionalProperties": true
    }
  },
  "properties": {
    "$schema": {
      "type": "string",
      "description": "link to the version of the schema that can validate the resume",
      "format": "uri"
    },
    "custom": {
      "$ref": "#/definitions/custom"
    },
    "basics": {
      "type": "object",
      "additionalProperties": true,
      "properties": {
        "name": {
          "type": "string"
        },
        "label": {
          "type": "string",
          "description": "e.g. Web Developer"
        },
        "image": {
          "type": "string",
          "description": "URL (as per RFC 3986) to a image in JPEG or PNG format"
        },
        "email": {
          "type": "string",
          "description": "e.g. thomas@gmail.com",
          "format": "email"
        },
        "phone": {
          "type": "string",
          "description": "Phone numbers are stored as strings so use any format you like, e.g. 712-117-2923"
        },
        "url": {
          "type": "string",
          "description": "URL (as per RFC 3986) to your website, e.g. personal homepage",
          "format": "uri"
        },
        "summary": {
          "type": "string",
          "description": "Write a short 2-3 sentence biography about yourself"
        },
        "location": {
          "type": "object",
          "additionalProperties": true,
          "properties": {
            "address": {
              "type": "string",
              "description": "To add multiple address lines, use \n. For example, 1234 GlÃ¼cklichkeit StraÃŸe\nHinterhaus 5. Etage li."
            },
            "postalCode": {
              "type": "string"
            },
            "city": {
              "type": "string"
            },
            "countryCode": {
              "type": "string",
              "description": "code as per ISO-3166-1 ALPHA-2, e.g. US, AU, IN"
            },
            "region": {
              "type": "string",
              "description": "The general region where you live. Can be a US state, or a province, for instance."
            },
            "custom": {
              "$ref": "#/definitions/custom"
            }
          }
        },
        "profiles": {
          "type": "array",
          "description": "Specify any number of social networks that you participate in",
          "additionalItems": false,
          "items": {
            "type": "object",
            "additionalProperties": true,
            "properties": {
              "network": {
                "type": "string",
                "description": "e.g. Facebook or Twitter"
              },
              "username": {
                "type": "string",
                "description": "e.g. neutralthoughts"
              },
              "url": {
                "type": "string",
                "description": "e.g. http://twitter.example.com/neutralthoughts",
                "format": "uri"
              },
              "custom": {
                "$ref": "#/definitions/custom"
              }
            }
          }
        },
        "custom": {
          "$ref": "#/definitions/custom"
        }
      }
    },
    "work": {
      "type": "array",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "name": {
            "type": "string",
            "description": "e.g. Facebook"
          },
          "location": {
            "type": "string",
            "description": "e.g. Menlo Park, CA"
          },
          "description": {
            "type": "string",
            "description": "e.g. Social Media Company"
          },
          "position": {
            "type": "string",
            "description": "e.g. Software Engineer"
          },
          "url": {
            "type": "string",
            "description": "e.g. http://facebook.example.com",
            "format": "uri"
          },
          "startDate": {
            "$ref": "#/definitions/iso8601"
          },
          "endDate": {
            "$ref": "#/definitions/iso8601"
          },
          "summary": {
            "type": "string",
            "description": "Give an overview of your responsibilities at the company"
          },
          "highlights": {
            "type": "array",
            "description": "Specify multiple accomplishments",
            "additionalItems": false,
            "items": {
              "type": "string",
              "description": "e.g. Increased profits by 20% from 2011-2012 through viral advertising"
            }
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "volunteer": {
      "type": "array",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "organization": {
            "type": "string",
            "description": "e.g. Facebook"
          },
          "position": {
            "type": "string",
            "description": "e.g. Software Engineer"
          },
          "url": {
            "type": "string",
            "description": "e.g. http://facebook.example.com",
            "format": "uri"
          },
          "startDate": {
            "$ref": "#/definitions/iso8601"
          },
          "endDate": {
            "$ref": "#/definitions/iso8601"
          },
          "summary": {
            "type": "string",
            "description": "Give an overview of your responsibilities at the company"
          },
          "highlights": {
            "type": "array",
            "description": "Specify accomplishments and achievements",
            "additionalItems": false,
            "items": {
              "type": "string",
              "description": "e.g. Increased profits by 20% from 2011-2012 through viral advertising"
            }
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "education": {
      "type": "array",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "institution": {
            "type": "string",
            "description": "e.g. Massachusetts Institute of Technology"
          },
          "url": {
            "type": "string",
            "description": "e.g. http://facebook.example.com",
            "format": "uri"
          },
          "area": {
            "type": "string",
            "description": "e.g. Arts"
          },
          "studyType": {
            "type": "string",
            "description": "e.g. Bachelor"
          },
          "startDate": {
            "$ref": "#/definitions/iso8601"
          },
          "endDate": {
            "$ref": "#/definitions/iso8601"
          },
          "score": {
            "type": "string",
            "description": "grade point average, e.g. 3.67/4.0"
          },
          "courses": {
            "type": "array",
            "description": "List notable courses/subjects",
            "additionalItems": false,
            "items": {
              "type": "string",
              "description": "e.g. H1302 - Introduction to American history"
            }
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "awards": {
      "type": "array",
      "description": "Specify any awards you have received throughout your professional career",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "title": {
            "type": "string",
            "description": "e.g. One of the 100 greatest minds of the century"
          },
          "date": {
            "$ref": "#/definitions/iso8601"
          },
          "awarder": {
            "type": "string",
            "description": "e.g. Time Magazine"
          },
          "summary": {
            "type": "string",
            "description": "e.g. Received for my work with Quantum Physics"
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "certificates": {
      "type": "array",
      "description": "Specify any certificates you have received throughout your professional career",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "name": {
            "type": "string",
            "description": "e.g. Certified Kubernetes Administrator"
          },
          "date": {
            "$ref": "#/definitions/iso8601"
          },
          "url": {
            "type": "string",
            "description": "e.g. http://example.com",
            "format": "uri"
          },
          "issuer": {
            "type": "string",
            "description": "e.g. CNCF"
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "publications": {
      "type": "array",
      "description": "Specify your publications through your career",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "name": {
            "type": "string",
            "description": "e.g. The World Wide Web"
          },
          "publisher": {
            "type": "string",
            "description": "e.g. IEEE, Computer Magazine"
          },
          "releaseDate": {
            "$ref": "#/definitions/iso8601"
          },
          "url": {
            "type": "string",
            "description": "e.g. http://www.computer.org.example.com/csdl/mags/co/1996/10/rx069-abs.html",
            "format": "uri"
          },
          "summary": {
            "type": "string",
            "description": "Short summary of publication. e.g. Discussion of the World Wide Web, HTTP, HTML."
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "skills": {
      "type": "array",
      "description": "List out your professional skill-set",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "name": {
            "type": "string",
            "description": "e.g. Web Development"
          },
          "level": {
            "type": "string",
            "description": "e.g. Master"
          },
          "keywords": {
            "type": "array",
            "description": "List some keywords pertaining to this skill",
            "additionalItems": false,
            "items": {
              "type": "string",
              "description": "e.g. HTML"
            }
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "languages": {
      "type": "array",
      "description": "List any other languages you speak",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "language": {
            "type": "string",
            "description": "e.g. English, Spanish"
          },
          "fluency": {
            "type": "string",
            "description": "e.g. Fluent, Beginner"
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "interests": {
      "type": "array",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "name": {
            "type": "string",
            "description": "e.g. Philosophy"
          },
          "keywords": {
            "type": "array",
            "additionalItems": false,
            "items": {
              "type": "string",
              "description": "e.g. Friedrich Nietzsche"
            }
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "references": {
      "type": "array",
      "description": "List references you have received",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "name": {
            "type": "string",
            "description": "e.g. Timothy Cook"
          },
          "reference": {
            "type": "string",
            "description": "e.g. Joe blogs was a great employee, who turned up to work at least once a week. He exceeded my expectations when it came to doing nothing."
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "projects": {
      "type": "array",
      "description": "Specify career projects",
      "additionalItems": false,
      "items": {
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "name": {
            "type": "string",
            "description": "e.g. The World Wide Web"
          },
          "description": {
            "type": "string",
            "description": "Short summary of project. e.g. Collated works of 2017."
          },
          "highlights": {
            "type": "array",
            "description": "Specify multiple features",
            "additionalItems": false,
            "items": {
              "type": "string",
              "description": "e.g. Directs you close but not quite there"
            }
          },
          "keywords": {
            "type": "array",
            "description": "Specify special elements involved",
            "additionalItems": false,
            "items": {
              "type": "string",
              "description": "e.g. AngularJS"
            }
          },
          "startDate": {
            "$ref": "#/definitions/iso8601"
          },
          "endDate": {
            "$ref": "#/definitions/iso8601"
          },
          "url": {
            "type": "string",
            "format": "uri",
            "description": "e.g. http://www.computer.org/csdl/mags/co/1996/10/rx069-abs.html"
          },
          "roles": {
            "type": "array",
            "description": "Specify your role on this project or in company",
            "additionalItems": false,
            "items": {
              "type": "string",
              "description": "e.g. Team Lead, Speaker, Writer"
            }
          },
          "entity": {
            "type": "string",
            "description": "Specify the relevant company/entity affiliations e.g. 'greenpeace', 'corporationXYZ'"
          },
          "type": {
            "type": "string",
            "description": " e.g. 'volunteering', 'presentation', 'talk', 'application', 'conference'"
          },
          "custom": {
            "$ref": "#/definitions/custom"
          }
        }
      }
    },
    "meta": {
      "type": "object",
      "description": "The schema version and any other tooling configuration lives here",
      "additionalProperties": true,
      "properties": {
        "canonical": {
          "type": "string",
          "description": "URL (as per RFC 3986) to latest version of this document",
          "format": "uri"
        },
        "version": {
          "type": "string",
          "description": "A version field which follows semver - e.g. v1.0.0"
        },
        "lastModified": {
          "type": "string",
          "description": "Using ISO 8601 with YYYY-MM-DDThh:mm:ss"
        },
        "custom": {
          "$ref": "#/definitions/custom"
        }
      }
    }
  },
  "title": "Resume Schema",
  "type": "object"
}


#Addtional LLM Agents under consideration

---
## 1. TranscriptRecord Extraction Agent
**Purpose:** Given the most recent assistant and user turns from a chat conversation, extract a *single* citable record: either a **single-turn user fact** or a **two-turn question–answer (QA)** pair. Emit a JSON object that conforms to the **TranscriptRecord v1.1** schema below. This record can be cited in Knowledge Cards via `[[ref:trns-...]]` just like an artifact.


### Agent Prompt (for the extractor)

#### Inputs (provided by caller)
- `conversation_id` *(string, required)* — the chat/thread ID in your system.
- `last_user_turn` *(object, optional)*:
  - `text` *(string, required if present)*
  - `message_id` *(string, optional)*
  - `turn_index` *(integer, optional)*
- `last_assistant_turn` *(object, optional)*:
  - `text` *(string, required if present)*
  - `message_id` *(string, optional)*
  - `turn_index` *(integer, optional)*
- `now_iso` *(string, optional)* — ISO-8601 timestamp to use as `created_at`. If not given, you may omit `created_at`.

#### Output (strict)
Return **only** a single JSON object (no extra text) that validates against **TranscriptRecord v1.1** defined below.

#### Extraction Rules
1. **Decide record kind**
   - If there are **two turns** (one from `user`, one from `assistant`) and one is a clear **question** while the other **directly answers** it, output a **`kind: "qa"`** record.
     - Accept both patterns: **assistant→question, user→answer** *or* **user→question, assistant→answer**.
   - Otherwise, if the **user** turn contains a clear, citable factual **statement/claim**, output a **`kind: "fact"`** record using only the **user** turn.
   - If neither condition is satisfied, return the literal JSON `null`.

2. **No fabrication**
   - Do **not** infer facts. Copy evidence text **verbatim** into the `text` field(s). You may lightly trim whitespace, but do not paraphrase.
   - For numbers, **do not invent precision**. If the turn states a range, keep the range; if it states an approximate value, preserve that wording.

3. **What counts as citable**
   - Claims of responsibility/impact (e.g., “I led X”, “We shipped Y”).  
   - Quantities/metrics (counts, %, x-multipliers, $ amounts, dates/timeframes explicitly stated in the turn).  
   - Concrete descriptions of artifacts, releases, migrations, datasets, benchmarks, etc.
   - Exclude opinions, plans, speculation, and model-generated suggestions **unless** the user confirms them as fact.

4. **Populate fields**
   - `ref_id`: generate `trns-` + 10–16 lowercase letters/digits (e.g., `trns-k9z1r3a7m2`). Must match `^trns-[A-Za-z0-9_-]+$`.
   - `conversation_id`: copy from input.
   - `created_at`: use `now_iso` if provided; otherwise omit.
   - `uri`: if a message_id exists, set `chat://<conversation_id>#<message_id>`. For QA, prefer the **answer** message id; if both are available, you may include the answer id.
   - `quote_or_notes`: 1 short sentence (≤120 chars) summarizing the evidence; include location hints like `turn 26` when available.
   - `keywords` (optional): ≤5 compact tokens that aid retrieval (e.g., `postgresql`, `migration`, `beta-users`). No phrases longer than 3 words.
   - `hash` (optional): omit unless your runtime supplies a content hash.
   - For **`kind: "fact"`**:
     - `fact.role` must be `"user"`.
     - `fact.text` is the verbatim user message or the most relevant sentence(s) from it.
   - For **`kind: "qa"`**:
     - `question.role` and `answer.role` must reflect actual speakers (`"user"` or `"assistant"`).
     - Use the exact question text and the exact answer text. If the answer spans multiple sentences, keep only the portion that directly answers.
     - Prefer the **user** as the `answer.role` when the user provided the answer.

5. **Structure limits**
   - Capture **only one turn** for `fact` or **exactly two turns** for `qa`. No arrays, no multi-turn merges.
   - If the user turn contains multiple claims, keep the **single most material** claim (impact/metric/ownership).

6. **Failure mode**
   - If neither a valid `fact` nor a valid `qa` can be produced, output `null` exactly.

