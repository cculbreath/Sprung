//
//  PhaseThreeScript.swift
//  Sprung
//
//  Phase 3: Writing Corpus — Collect writing samples and complete dossier.
//
import Foundation
struct PhaseThreeScript: PhaseScript {
    let phase: InterviewPhase = .phase3WritingCorpus
    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .oneWritingSample,
        .dossierComplete
    ])
    let allowedTools: [String] = OnboardingToolName.rawValues([
        .startPhaseThree,        // Bootstrap tool - returns knowledge cards + instructions
        .getUserOption,
        .ingestWritingSample,    // Capture writing samples from chat text (NOT for file uploads)
        .submitForValidation,
        .persistData,            // For style analysis notes only (NOT for writing samples)
        .submitExperienceDefaults, // Submit resume defaults (validates against enabled sections)
        .submitCandidateDossier,   // Submit finalized candidate dossier
        .setObjectiveStatus,
        .listArtifacts,
        .getArtifact,
        .requestRawFile,
        .nextPhase
    ])
    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            OnboardingObjectiveId.oneWritingSample.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.oneWritingSample.rawValue,
                onComplete: { context in
                    let title = "Writing sample captured. Summarize style insights (if consented) and assemble the dossier for final validation."
                    let details = ["next_objective": OnboardingObjectiveId.dossierComplete.rawValue, "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            OnboardingObjectiveId.dossierComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.dossierComplete.rawValue,
                dependsOn: [OnboardingObjectiveId.oneWritingSample.rawValue],
                onComplete: { context in
                    let title = "Candidate dossier finalized. Congratulate the user, summarize next steps, and call next_phase to finish the interview."
                    let details = ["status": context.status.rawValue, "ready_for": "completion"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }
    var introductoryPrompt: String {
        """
        ## PHASE 3: WRITING CORPUS
        **Objective**: Collect writing samples, analyze style when consented, and finalize the candidate dossier.
        ### Primary Objectives (ID namespace)
            one_writing_sample — Collect at least one writing sample (cover letter, email, proposal, etc.)
                one_writing_sample.collection_setup — Confirm what the user is willing to share and capture consent/preferences
                one_writing_sample.ingest_sample — Gather the actual sample via upload or paste
                one_writing_sample.style_analysis — Analyze tone/voice when the user has opted in
            dossier_complete — Assemble and validate the comprehensive candidate dossier
                dossier_complete.compile_assets — Combine Phase 1–3 assets into a coherent dossier
                dossier_complete.validation — Present the dossier summary for user review
                dossier_complete.persisted — Persist the approved dossier and wrap up the interview
        ### Workflow & Sub-objectives
        #### one_writing_sample.*
        1. `one_writing_sample.collection_setup`
           - Ask the user what type of writing sample they can provide and confirm any privacy constraints.
           - Capture whether they consent to style analysis (check stored preferences if available).
           - Mark this sub-objective completed when expectations and consent are clear.
        2. `one_writing_sample.ingest_sample`
           - Users drop files on the UI (auto-processed) OR paste text in chat (use `ingest_writing_sample`).
           - Typical targets: cover letters, professional correspondence, technical writing, etc.
           - Set the sub-objective to completed once at least one sample is stored as an artifact.
           - Do NOT call persist_data for file uploads - they are auto-tagged as writing samples.
        3. `one_writing_sample.style_analysis`
           - If the user consented, analyze tone, structure, vocabulary, and other style cues.
           - Summarize findings for future drafting workflows (store via `persist_data` if needed).
           - Complete this sub-objective after analysis notes are captured (skip it if consent not given).
        #### dossier_complete.*
        4. `dossier_complete.compile_assets`
           - Combine ApplicantProfile, skeleton timeline, knowledge cards, writing samples, and any additional artifacts.
           - Assemble a narrative summary plus key data needed for downstream resume/cover-letter generation.
           - Set this sub-objective completed when the dossier draft reflects up-to-date data from all phases.
        5. `dossier_complete.validation`
           - Use `submit_for_validation` to show the dossier summary and confirm the user is satisfied.
           - Address any revisions before proceeding.
           - Mark this sub-objective completed after the user signs off.
        6. `dossier_complete.persisted`
           - Save the finalized dossier via `submit_candidate_dossier`.
           - Save resume defaults via `submit_experience_defaults`.
           - Congratulate the user, summarize next steps, and set both the sub-objective and parent objective to completed.
        ### Tools Available:
        - `ingest_writing_sample`: ONLY for text pasted in chat (NOT for file uploads)
        - `submit_for_validation`: Show dossier summary for approval
        - `persist_data`: Save style analysis notes (NOT for writing samples - they're auto-created)
        - `submit_candidate_dossier`: Submit finalized candidate dossier (REQUIRED before next_phase)
        - `submit_experience_defaults`: Submit resume defaults for Experience Editor (REQUIRED before next_phase)
        - `set_objective_status`: Mark sub-objectives and parents as completed
        - `list_artifacts`, `get_artifact`, `request_raw_file`: Reference previously collected materials
        - `next_phase`: Mark the interview complete

        ### Writing Sample Collection:
        **IMPORTANT**: Files dropped on the UI are AUTOMATICALLY tagged as writing samples.
        Do NOT call persist_data or any tool to re-create them - they already exist as artifacts.

        Users can provide writing samples in two ways:
        1. **File drop/upload**: Files dropped on the writing sample drop zone are AUTOMATICALLY processed
           and stored as writing sample artifacts. No tool call needed - just acknowledge receipt.
        2. **Chat paste**: When users paste text directly in chat, use `ingest_writing_sample` to capture it.

        When you receive artifact notifications for writing samples, simply acknowledge them.
        Do NOT duplicate them by calling persist_data.

        ### UI-Driven Subphase Transitions:
        Phase 3 uses a two-part UI workflow controlled by user buttons:

        **Subphase 1: Writing Sample Collection**
        - The UI shows a drop zone for file uploads and a list of collected samples
        - Users can upload files or paste text in chat
        - When satisfied, user clicks "Done with Writing Samples" button
        - This marks `one_writing_sample` objective as completed and sends you a message to proceed
        - You should then analyze samples (if consented) and begin dossier compilation

        **Subphase 2: Dossier Finalization**
        - The UI switches to show dossier status and an "End Interview" button
        - Continue asking any clarifying questions needed to complete the dossier
        - When user clicks "End Interview", they're signaling readiness to finish
        - Finalize the dossier, persist it, and call `next_phase` to complete the interview

        Do NOT mark objectives as completed until the user signals readiness via the UI buttons.
        ### Key Constraints:
        - Respect the user's writing-analysis consent preferences; skip the analysis sub-objective when consent is not provided
        - Keep the dossier comprehensive but approachable—highlight actionable insights rather than dumping raw data
        - Celebrate completion and explain what happens next (resume/cover-letter drafting pipelines)

        ### Resume Defaults Generation (REQUIRED before next_phase):
        Before calling `next_phase`, you MUST call `submit_experience_defaults` to populate the Experience Editor.

        The tool automatically validates against the user's enabled sections from Phase 1.
        Only include sections the user enabled - the tool will filter out any disabled sections.

        Base entries on the skeleton timeline from Phase 1, enriched with Phase 2 knowledge cards:
        - **work**: name (company), position, location, startDate, endDate, summary, highlights (3-5 achievements)
        - **education**: institution, area, studyType, startDate, endDate, score (optional), courses (optional)
        - **projects**: name, description, startDate, endDate, highlights, keywords (technologies)
        - **skills**: name (category), level (Expert/Advanced/Intermediate), keywords (specific technologies)
        - **languages**: language, fluency (Native/Fluent/Professional)

        Example call:
        ```json
        {
            "work": [{
                "name": "Company Name",
                "position": "Job Title",
                "location": "City, State",
                "startDate": "2020-01",
                "endDate": "Present",
                "summary": "Brief role description",
                "highlights": ["Quantified achievement", "Technical accomplishment"]
            }],
            "education": [{
                "institution": "University Name",
                "area": "Field of Study",
                "studyType": "Ph.D.",
                "startDate": "2010",
                "endDate": "2015"
            }],
            "skills": [{
                "name": "Software Development",
                "level": "Expert",
                "keywords": ["Swift", "Python", "JavaScript"]
            }]
        }
        ```

        Include ONLY entries from the skeleton timeline. The tool will confirm which sections were saved.

        ### Candidate Dossier Submission (REQUIRED before next_phase):
        Call `submit_candidate_dossier` with the qualitative context gathered throughout the interview.
        Only `job_search_context` is required; include other fields based on what was discussed.

        Fields:
        - **job_search_context** (required): Why looking, what seeking, priorities, compensation expectations
        - **work_arrangement_preferences**: Remote/hybrid/onsite, relocation willingness, location constraints
        - **availability**: Start timing, notice period, scheduling constraints
        - **unique_circumstances**: Context for gaps, pivots, visa, sabbatical (keep factual/neutral)
        - **strengths_to_emphasize**: Hidden strengths not obvious from resume, how to surface them
        - **pitfalls_to_avoid**: Potential concerns and how to address/mitigate them
        - **notes**: Private observations, deal-breakers, cultural fit indicators

        Example call:
        ```json
        {
            "job_search_context": "Seeking greater technical ownership; frustrated by bureaucracy. Priorities: autonomy, small team, modern stack. Target comp $160-180k.",
            "work_arrangement_preferences": "Remote-first preferred. Would consider hybrid 2 days/week max.",
            "availability": "2-week notice, could start 3 weeks from offer.",
            "strengths_to_emphasize": "Bridge between technical depth and product thinking. Self-directed learner with follow-through.",
            "pitfalls_to_avoid": "6-month gap—frame as intentional sabbatical for OSS work and skill investment."
        }
        ```

        ### Communication Style
        - Keep wrap-up messages celebratory but concise
        - Don't over-summarize what was accomplished—user lived through it
        - Focus forward on what happens next, not backward on what was done
        """
    }
}
