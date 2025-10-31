# Purpose

Enhance Phase 1 conversational flow so the assistant acknowledges saved applicant data at the appropriate time, builds timeline entries collaboratively through cards, and allows users to draft replies during streaming. After this work, users experience warm, accurate messaging that only mentions their name once the ApplicantProfile is confirmed, and they can manipulate timeline cards instead of reading long chat dumps.

# Scope

All modifications stay within the macOS onboarding UI, prompt configuration, and tooling registration.

# Background and Context

Current issues:
• The assistant greets generically and never explicitly notes that applicant data is stored for future use.
• Timeline edits arrive as long chat messages, not structured cards.
• Chat scrolling jumps during streaming, the composer is disabled, and Shift+Enter does not insert a newline.
• There is no quick way to export the chat transcript.

# High-Level Strategy

Update prompts and developer status messages so the assistant greets warmly, uses the applicant’s name only after the profile is persisted, and acknowledges stored data. Provide timeline card tools so GPT‑5 and the user cooperatively edit structured entries. Polish the chat experience (typing during streaming, Shift+Enter newline, stable scrolling) and add transcript export.

# Detailed Plan

## Milestone 1 – Conversational Prompts

1. Update the Phase 1 system prompt to instruct GPT‑5 to greet generically at the start and to switch to name-based greetings only after receiving a developer status that the ApplicantProfile is saved.
2. Modify DeveloperMessageTemplates and coordinator logic so, immediately after persistApplicantProfile, we send a developer message containing the user’s name and confirming that the data is now stored for later resume/cover-letter generation.
3. Replace rigid phrases such as “lock it in” with softer wording that keeps the door open for later edits.
4. Acceptance: run Phase 1 with a résumé. Confirm the initial greeting is generic, the assistant starts using the applicant’s name only after profile persistence, and it acknowledges data reuse explicitly. Verify consolelog.txt captures the new developer messages without errors.

## Milestone 2 – Timeline Tools and Chat Ergonomics

1. Introduce tool definitions (create_timeline_card, update_timeline_card, reorder_timeline_cards, delete_timeline_card) registered in OnboardingInterviewService. Each tool should manipulate card IDs and structured fields (title, organization, location, dates, highlights).
2. Render timeline cards via the existing experience editor component, enabling drag-and-drop ordering and inline edits. When the user edits a card, send a developer message back to GPT‑5 describing the change so the assistant respects manual updates.
3. Update the chat composer to remain enabled during streaming (disable only the Send button until completion), support Shift+Enter newlines, and adjust scroll logic so the chat remains at user-selected positions until a message finishes.
4. Add a transcript export action accessible via a context menu in the chat view.
5. Acceptance: run the interview, confirm GPT‑5 uses the new card tools instead of raw text dumps, the chat input behaves as described, and transcript export works. Inspect consolelog.txt to ensure the timeline tool calls and chat actions log cleanly.

# Progress

- [ ] Milestone 1 – Conversational Prompts
- [ ] Milestone 2 – Timeline Tools and Chat Ergonomics

# Validation and Acceptance

Complete Phase 1 with a résumé: observe proper greeting behavior and data acknowledgements, watch GPT‑5 create/update timeline cards via tools, draft text during streaming using Shift+Enter for new lines, export the transcript, and confirm consolelog.txt records the sequence of tool calls without unexpected warnings.

# Risks and Mitigations

Card tooling must synchronize model and user edits; keep the coordinator as the single source of truth and broadcast every change. Prompt tweaks must preserve existing workflow steps; review transcripts to ensure no regression. Ensure chat-scroll adjustments don’t break accessibility (test with long transcripts).

# Notes

Coordinate with Developer A to avoid conflicts in shared UI files. Use consolelog.txt after each test run to verify the new tool interactions and developer status messages.
