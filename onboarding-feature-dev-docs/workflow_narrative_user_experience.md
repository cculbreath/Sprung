## **Onboarding Interview: The Workflow Narrative & User Experience**
Implementation note: submit_for_validation schema now uses snake_case and includes skeleton_timeline (updated in Tool Spec v1.1). Adjust tool calls accordingly.
In M1, the Contacts tool returns a “not configured” message until permission flow is wired (see Milestone 1 Stubs). The manual entry and resume upload remain the working paths.
Clarification: The LLM may propose objective completions, but the InterviewState actor validates and performs all phase transitions.

This document outlines the qualitative flow of the onboarding interview, mapping the conversational "career coach" persona to the technical implementation defined in the new "Clean Slate" architecture.

### **Guiding Principles**

* **Persona:** The LLM is a **supportive and insightful career coach**. It's not a chatbot or a form. Its tone is encouraging, curious, and professional. It asks "why" and "how," not just "what."  
* **Goal:** To build trust with the user so they share more than just resume bullet points. The objective is to uncover the *stories, impact, and evidence* behind their career.  
* **Pacing:** The interview is user-driven. It pauses when the user needs to upload, write, or validate (waiting state). It never rushes.  
* **Transparency:** The coach explains *why* it's asking for certain information. (e.g., "This helps me understand your writing style," "This timeline will be our map for the deep dive.")

## **Phase 1: Core Facts (The First 5 Minutes)**

**Technical Goal:** Complete M1 objectives: applicant\_profile, skeleton\_timeline, and enabled\_sections. Transition state from phase1CoreFacts to phase2DeepDive.

### **1\. The Greeting & Automatic Profile Draft**

The user starts the interview.  
**Coach (LLM):** "Welcome. I'm here to help you build a comprehensive, evidence-backed profile of your career. This isn't a test; it's a collaborative session to uncover the great work you've done. We'll use this profile to create perfectly tailored resumes and cover letters later."

Before asking the user to pick a path, the app quietly looks for data it can pre-fill.

* **Technical Link:**  
  1. The InterviewOrchestrator immediately calls **get\_macos\_contact\_card**. If permission is available, the tool returns the "Me" contact; otherwise it fails gracefully.  
  2. The returned values are merged into an applicant-profile draft.  
  3. The orchestrator then calls **submit\_for\_validation** with the draft (even if it is mostly empty).  
  4. The InterviewState actor sets `session.waiting = .validation`, prompting the profile review card.

The user can edit anything, add missing fields, or overwrite the draft entirely. When Contacts access is unavailable, the card simply starts from a blank template.

### **2\. Uploading a Résumé or LinkedIn Export**

After contact details are confirmed, the coach explains the next step:  
**Coach (LLM):** "Next, let's build a high-level timeline of your career. Upload your most recent résumé or a PDF of LinkedIn and I'll map out the roles we'll dig into later."

* **Technical Link:**  
  1. The orchestrator calls **get\_user\_upload** with `uploadType = resume`.  
  2. The InterviewState waits in `.upload` until the user provides a file (or skips).  
  3. When a file arrives, the orchestrator calls **extract_document** with the uploaded `file_url`.  
  4. The extraction service returns an `artifact_record` containing semantically enhanced text. The orchestrator stores the artifact, then generates a naive skeleton timeline using **ModelProvider.forTask(.extract)**.  
  5. The generated timeline is sent to **submit\_for\_validation** so the user can approve or modify it.  
  6. The InterviewState sets `session.waiting = .validation` while the card is on screen.

If the user declines to upload a résumé, the coach can prompt again or guide them through manual entry—still via the same validation surface.

### **3\. Completing the First Objective**

Once the user approves the applicant profile, the coach acknowledges the milestone.  
**Coach (LLM):** "Excellent. Contact information is set."

* **Technical Link:**  
  1. The validation card returns the approved JSON.  
  2. The orchestrator calls **persist\_data** to save the profile.  
  3. It then calls **set\_objective\_status** with `objectiveId = "applicant_profile"` and `status = "completed"`.  
  4. `session.waiting` is cleared and the interview proceeds to the résumé upload prompt described above.

### **4\. Building the Skeleton Timeline**

This extraction pass is the core of M1.  
**Coach (LLM):** "Thanks for that file—I'm mapping out the major milestones now. Give me just a moment."

While the LLM waits for `extract_document`, the UI shows a compact spinner inside the message input area so the user understands the system is working.

* **Technical Link:**  
  1. The orchestrator calls **extract_document** with the uploaded `file_url`.  
  2. The local extraction service (Gemini 2.0 Flash by default, or whatever the user selected in Settings) returns an `artifact_record` containing semantically enhanced Markdown. Vendor names never surface to the model.  
  3. The orchestrator stores the artifact, then feeds the enriched text to **ModelProvider.forTask(.extract)** to produce a naive skeleton timeline JSON object.

### **5\. Validating the Timeline & Phase Transition**

**Coach (LLM):** "Okay, I’ve extracted a high-level timeline. Please take a look—just confirm companies, titles, and dates for now. We’ll go deeper next."

* **Technical Link:**  
  1. The orchestrator calls **submit_for_validation** with the skeleton_timeline data created in step 4.  
  2. The session.waiting is set to .validation.  
  3. The user approves (or edits) the timeline.  
  4. The orchestrator calls **persist_data** to save the skeleton_timeline.  
  5. It then calls **set_objective_status** with objectiveId: "skeleton_timeline" and status: "completed".  
  6. Finally, the orchestrator (or the model via reasoning) determines the enabled_sections based on the confirmed timeline (e.g., work: true, education: true, projects: false) and calls **set_objective_status** for objectiveId: "enabled_sections".  
  7. The **InterviewState** actor, seeing applicant_profile, skeleton_timeline, and enabled_sections are all in session.objectivesDone, automatically advances the state: session.phase = .phase2DeepDive.

## **Phase 2: The Deep Dive (The "Coach" at Work)**

**Technical Goal:** Complete M2 objectives. Loop through SkeletonTimeline experiences, conduct conversational interviews, and generate at least one KnowledgeCard.

### **1\. The Transition**

**Coach (LLM):** "Great, we have our map. Now for the most important part.  
We're going to walk through your timeline, starting with your role at \[First Company from Timeline\]. My goal here is to understand the *story* behind your title. I'll ask you about challenges, your accomplishments, and the impact you had. This is where we'll find the evidence that makes your resume stand out."

### **2\. The Interview Loop**

**Coach (LLM):** "So, let's talk about \[Company\]. It says you were a \[Title\] from \[Date\] to \[Date\]. Can you tell me what the team's main goal was when you first joined?"  
**User:** "We were trying to refactor an old monolith into microservices..."  
**Coach (LLM):** "That's a major undertaking. What was the biggest technical challenge you personally faced during that migration?"  
**User:** "Probably convincing the team to use gRPC instead of REST..."  
**Coach (LLM):** "Interesting. How did you measure the success of that project? Were there any specific metrics you tracked?"  
**User:** "Oh yeah, we cut p95 latency by 60% and... I think I have the performance report somewhere."  
**Coach (LLM):** "That's fantastic evidence. If you have that report handy, please feel free to upload it. I can use it to pull out the exact numbers."

* **Technical Link:**  
  * This is a pure conversational loop with the InterviewOrchestrator (using gpt-5 for high-quality, multi-step reasoning).  
  * The "upload" prompt is an inline call to the **get\_user\_upload** tool. The orchestrator associates the uploaded ArtifactRecord with this specific experience.

### **3\. Synthesizing the Knowledge Card**

**Coach (LLM):** "This is all incredibly helpful. Give me a moment to synthesize this conversation and the performance report you uploaded into a 'Knowledge Card.' This card will act as the 'single source of truth' for this role."

* **Technical Link:**  
  1. The InterviewOrchestrator calls the **KnowledgeCardAgent** (as defined in your plan).  
  2. It passes the Experience record, the relevant ArtifactRecord(s), and the interview transcript chunk.  
  3. The agent uses gpt-5 (or o1 if escalated) with .jsonObject response format to generate the structured KnowledgeCard JSON.

### **4\. Validating the Card**

**Coach (LLM):** "Okay, I've drafted this card. It summarizes your achievements, like 'Reduced p95 latency by 60%,' and links it directly to the evidence you provided. How does this look?"

* **Technical Link:**  
  1. The orchestrator calls **submit\_for\_validation** with the knowledgeCard data.  
  2. User approves.  
  3. The orchestrator calls **persist\_data** (for the card) and **set\_objective\_status** (for one\_card\_generated and interviewed\_one\_experience).  
  4. The InterviewState actor advances to phase3WritingCorpus.

## **Phase 3: Writing & Qualitative Context (The "Dossier")**

**Technical Goal:** Complete M3 objectives. Collect WritingSamples and populate the CandidateDossier.

### **1\. Writing Sample Collection**

**Coach (LLM):** "We're almost done. The final piece is understanding your personal writing style. This helps me generate cover letters that sound authentically like *you*, not like a robot.  
Could you please upload one or two samples of your professional writing? This could be a cover letter you're proud of, a team-wide email, or a public blog post."

* **Technical Link:**  
  * Calls **get\_user\_upload** tool.  
  * Saves the file as an ArtifactRecord.  
  * Calls **set\_objective\_status** for one\_writing\_sample.

### **2\. The Candidate Dossier (The Missing Qualitative Piece)**

This is the part from your old spec (candidate-dossier.md) that is essential for the "coach" persona.  
**Coach (LLM):** "Thank you. Finally, I'd like to understand your broader career goals. The facts are essential, but the *context* is what helps us target the right opportunities.  
First, what are you really optimizing for in your next role? Is it scope, a specific domain, team culture, or something else?"  
**User:** "I really want to work on something with a positive social impact, even if the pay is a bit less."  
**Coach (LLM):** "That's great to know. And what about work arrangements? Are you looking for remote, hybrid, or in-office?"  
**User:** "Fully remote is a must-have for me."  
**Coach (LLM):** "Got it. What's your ideal availability or notice period?"  
**Coach (LLM):** "And one last, important question: Are there any key strengths you feel your resume doesn't fully capture, or any potential 'pitfalls'—like a career gap or a pivot—that you'd like me to be aware of so we can frame them in the best possible light?"

* **Technical Link:**  
  * This is a conversational loop with the InterviewOrchestrator.  
  * As the user answers, the orchestrator builds the CandidateDossier object in memory.  
  * After the conversation, it calls **persist\_data** with dataType: "candidate\_dossier" and the completed object.  
  * It then calls **set\_objective\_status** for dossier\_complete.

### **4\. The Conclusion**

**Coach (LLM):** "Thank you. This has been an incredibly productive session. I now have a comprehensive, evidence-backed profile that captures not just *what* you did, but *how* you did it and *why* it matters.  
Your profile is complete. We can now move on to building your first application materials."

* **Technical Link:** The InterviewState actor sees all Phase 3 objectives are done and transitions the state to session.phase \= .complete. The interview flow is finished.
