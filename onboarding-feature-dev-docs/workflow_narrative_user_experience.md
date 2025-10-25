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

### **1\. The Greeting & Initial Scaffolding**

The user starts the interview.  
**Coach (LLM):** "Welcome. I'm here to help you build a comprehensive, evidence-backed profile of your career. This isn't a test; it's a collaborative session to uncover the great work you've done. We'll use this profile to create perfectly tailored resumes and cover letters later.  
To get started, let's pull in your basic contact information. What's the easiest way for you to provide that?"

* **Technical Link:** The InterviewOrchestrator calls the **get\_user\_option** tool with choices like:  
  * \[ "id": "contacts", "label": "Import from my macOS Contacts" \]  
  * \[ "id": "resume", "label": "Extract from my resume/LinkedIn PDF" \]  
  * \[ "id": "manual", "label": "Enter it manually" \]  
* The InterviewState actor's session.waiting property is set to .selection.

### **2\. Path A: Import from Contacts**

**User:** Clicks "Import from my macOS Contacts."  
**Coach (LLM):** "Great. Your system will ask for permission to access your Contacts. I'll only look for your personal 'Me' card."  
**Coach (LLM):** (After data is pulled) "Okay, I've imported the following. Please take a moment to confirm or correct any details."

* **Technical Link:**  
  1. The UI selection triggers the **get\_macos\_contact\_card** tool.  
  2. The tool fetches the data and returns it to the InterviewOrchestrator.  
  3. The orchestrator calls the **submit\_for\_validation** tool with the applicantProfile data.  
  4. The session.waiting property is set to .validation.

### **2\. Path B: Extract from Resume**

**User:** Clicks "Extract from my resume/LinkedIn PDF."  
**Coach (LLM):** "Perfect. Please upload your most recent resume or a PDF of your LinkedIn profile. I'll extract *both* your contact info and your career timeline from it."

* **Technical Link:**  
  1. The InterviewOrchestrator calls the **get\_user\_upload** tool.  
  2. The session.waiting property is set to .upload.  
  3. The user uploads a file. The tool returns the file's local storageUrl to the orchestrator.  
  4. The LLM immediately calls **extract_document** with the uploaded `file_url`. If a résumé is detected, the tool returns both `applicant_profile` and a `skeleton_timeline`.  
  5. The LLM then calls **submit_for_validation** with the returned profile (and later the timeline).
  6. The session.waiting property is set to .validation.

### **3\. The First Validation & Objective**

**User:** Reviews the data from Path A or B and clicks "Approve."  
**Coach (LLM):** "Excellent. Contact information is set."

* **Technical Link:**  
  1. The validation UI returns the approved data.  
  2. The InterviewOrchestrator calls the **persist\_data** tool to save the applicantProfile.  
  3. The orchestrator then calls the **set\_objective\_status** tool with objectiveId: "applicant\_profile" and status: "completed".  
  4. The session.waiting property is set to nil.

### **4\. Building the Skeleton Timeline**

This step is the core of M1 and uses your new PDF extraction spec.  
**Coach (LLM):** (If resume was just uploaded) "Thanks for that file. Now, I'll use it to build a high-level timeline of your career. This will be our map for the 'deep dive' part of our interview. This may take a moment."  
**Coach (LLM):** (If no resume was uploaded yet) "Next, let's build that career map. Please upload a resume or LinkedIn PDF so I can extract your timeline." (This triggers the get\_user\_upload flow from Path B).

* **Technical Link:**  
   1. This is a crucial step. The **LLM calls the `extract_document` tool** with the `file_url`.  
   2. The app executes extraction gemini based llm extraction (model specified in SettingsView) and returns structured results without exposing vendor details.  
   3. The LLM proceeds to validation and persistence.

### **5\. Validating the Timeline & Phase Transition**

**Coach (LLM):** "Okay, I’ve extracted a high-level timeline. Please take a look—just confirm companies, titles, and dates for now. We’ll go deeper next."

* **Technical Link:**  
  1. The orchestrator parses the extracted PDF tex from extraction tool.  
  2. It calls the **submit\_for\_validation** tool with the skeleton\_timeline data.  
  3. The session.waiting is set to .validation.  
  4. The user approves the timeline.  
  5. The orchestrator calls **persist\_data** to save the skeleton\_timeline.  
  6. The orchestrator calls **set\_objective\_status** with objectiveId: "skeleton\_timeline" and status: "completed".  
  7. Finally, the orchestrator (or the model itself) determines the enabled\_sections based on the timeline (e.g., work: true, education: true, projects: false) and calls **set\_objective\_status** for objectiveId: "enabled\_sections".  
  8. The **InterviewState** actor, seeing applicant\_profile, skeleton\_timeline, and enabled\_sections are all in session.objectivesDone, automatically advances the state: session.phase \= .phase2DeepDive.

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