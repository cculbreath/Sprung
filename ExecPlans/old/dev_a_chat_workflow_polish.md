# Purpose

Deliver a more informative and schema-compliant Phase 1 loader experience. After completing this work, users will clearly see when résumé extraction is running, track progress through animated checklist stages, and choose JSON Resume-compliant sections within a correctly sized selector.

# Scope

All changes are local to the macOS onboarding UI and supporting services. No backend work is required.

# Background and Context

Current issues:
• The bouncing spring spinner is too small and often hidden behind other cards.
• Users receive no feedback during long extraction steps performed locally.
• The section selector overflows its overlay bounds and includes “Teaching Portfolio,” which is not part of the JSON Resume schema.

# High-Level Strategy

Increase spinner visibility and keep it on screen during long-running operations. Emit deterministic extraction stage updates and render them as an animated checklist. Tighten the section selector layout and align the default section list with JSON Resume.

# Detailed Plan

## Milestone 1 – Loader Polish

1. Update the spinner component in OnboardingInterviewToolPane.swift to double its size and ensure it is visible when cards such as the résumé upload finish (dismiss mutually exclusive cards when extraction starts).
2. Extend UploadInteractionHandler and OnboardingPendingExtraction to capture staged progress events (file analysis, AI extraction, artifact save, assistant handoff). Render these stages via a new ExtractionProgressChecklistView that animates checkboxes in sequence.
3. Hook stage updates into DocumentExtractionService.extract; publish events at each deterministic step so the checklist reflects real work (including retries when necessary).
4. Acceptance: run Phase 1 with a sample résumé, observe the larger spinner and staged progress updates, and capture screenshots. Inspect consolelog.txt afterward to confirm no unexpected warnings.

## Milestone 2 – Section Selector Layout

1. Adjust the section selector view to respect overlay bounds (reduce vertical padding, enable scrolling, or adopt a two-column grid if needed). Test with various window heights.
2. Audit section names against JSON Resume. Remove or rename unsupported entries (e.g., “Teaching Portfolio”) and update the default configuration in the data store.
3. Acceptance: open the section selector, confirm it fits without clipping, and verify only schema-compliant sections remain. Review consolelog.txt to ensure no validation errors were logged.

# Progress

- [ ] Milestone 1 – Loader Polish
- [ ] Milestone 2 – Section Selector Layout

# Validation and Acceptance

Complete a Phase 1 run. Confirm the spinner is noticeably larger and always visible during extraction, the checklist animates through staged updates aligned with real extraction steps, the section selector fits the overlay and lists only JSON Resume-compliant sections, and consolelog.txt contains only expected informational messages.

# Risks and Mitigations

Ensure checklist updates run on the main actor to avoid UI race conditions. Spinner visibility depends on card dismissal; verify no regressions occur when multiple uploads run sequentially. Schema changes must keep stored data compatible with existing resumes.

# Notes

Coordinate with developers working on later milestones to avoid conflicting edits to shared UI files. Use consolelog.txt to verify diagnostic output after each milestone.
