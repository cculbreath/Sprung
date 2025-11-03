# ExecPlan: Tool Pane Spinner Implementation and Progress Display

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

**IMPORTANT**: Multiple developers are working on this codebase simultaneously. Make frequent atomic commits with clear messages. If you encounter unexpected changes to files you're working on, pull latest changes and merge carefully. Coordinate through commit messages and avoid large, monolithic changes.

## Purpose / Big Picture

After this change, users will see clear visual feedback in the left tool pane during all processing phases. When the assistant is working (extracting PDFs, processing data, generating responses) and no other tool card is displayed, the pane will show the animated Sprung logo spinner with descriptive status messages like "Extracting PDF...", "Saving artifact...", or "Processing resume...". This eliminates the confusing empty pane that makes users think the app has frozen. Additionally, the ApplicantProfileIntakeCard will properly dismiss after saving, revealing the spinner when appropriate.

## Progress

Use a list with checkboxes to summarize granular steps. Every stopping point must be documented here.

- [ ] Set up development environment and verify build
- [ ] Audit existing showSpinner computation logic in OnboardingInterviewToolPane.swift
- [ ] Implement spinner rendering branch with AnimatedThinkingText component
- [ ] Add status message display below spinner
- [ ] Test spinner appears during PDF extraction
- [ ] Test spinner appears when tool pane is free and LLM is active
- [ ] Verify ApplicantProfileIntakeCard dismisses properly after save
- [ ] Add extraction status emission points in coordinator
- [ ] Test status messages update during different phases
- [ ] Create atomic commit for spinner implementation
- [ ] Create atomic commit for status message plumbing
- [ ] Run full acceptance tests
- [ ] Document any merge conflicts encountered

## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during implementation.

- To be filled during implementation

## Decision Log

Record every decision made while working on the plan.

- Decision: Render spinner as the primary branch before other tool pane content
  Rationale: Ensures spinner takes precedence when conditions are met, preventing cards from blocking it
  Date/Author: 2025-11-01 / Planning Phase

- Decision: Reuse existing AnimatedThinkingText component rather than creating new spinner
  Rationale: Maintains visual consistency, component already exists and is tested
  Date/Author: 2025-11-01 / Planning Phase

## Outcomes & Retrospective

To be filled at completion.

## Context and Orientation

The tool pane is the left panel in the onboarding interview that displays various interactive elements: file upload areas, intake cards, prompt cards, and validation buttons. The relevant code lives in `Views/Components/OnboardingInterviewToolPane.swift`.

Currently, the view computes a `showSpinner` boolean that correctly identifies when a spinner should be shown:
- During PDF/file extraction (`service.pendingExtraction != nil`)
- When the LLM is active and the pane is not occupied by another element

However, despite computing this boolean, the view never actually renders any spinner. The pane appears empty during these processing phases, confusing users who think the app has stalled.

The `AnimatedThinkingText` component is the standard Sprung logo animation used throughout the app. The `coordinator.pendingStreamingStatus` property contains status messages that should be displayed during processing.

The ApplicantProfileIntakeCard issue is actually a symptom of the missing spinner - when the card dismisses (which it does correctly via `pendingApplicantProfileIntake = nil`), the pane appears to still show the card because nothing else renders in its place.

## Plan of Work

### Phase 1: Implement Spinner Rendering

We will add a new top-level conditional branch in the tool pane's body that renders the spinner when `showSpinner` is true. This branch must come before the existing conditional chains so it takes precedence. The spinner will include the animated logo and any available status message.

### Phase 2: Status Message Plumbing

We will ensure the extraction and processing pipelines emit appropriate status messages via `setStreamingStatus(...)` calls. These messages should be brief and user-friendly, updating as the process moves through different phases.

### Phase 3: Verify Card Lifecycle

We will confirm that the ApplicantProfileIntakeCard properly dismisses and the spinner appears in its place when appropriate, validating the fix resolves both the dismissal issue and empty pane problem.

## Concrete Steps

Working directory: `./Sprung/Onboarding/`

### Step 1: Implement Spinner Rendering

    cd ./Sprung/Onboarding/
    git pull origin main
    git checkout -b feat/tool-pane-spinner

Edit `Views/Components/OnboardingInterviewToolPane.swift`:

1. Locate the `body` computed property
2. Find where `showSpinner` is computed (should be early in the body)
3. After the computation but before the existing conditional chains, add:

        var body: some View {
            let paneOccupied = isPaneOccupied(...)
            let isLLMActive = service.isProcessing || coordinator.pendingStreamingStatus != nil
            let showSpinner = service.pendingExtraction != nil || (!paneOccupied && isLLMActive)
            
            VStack(spacing: 16) {
                // NEW: Spinner takes precedence when active
                if showSpinner {
                    VStack(spacing: 12) {
                        AnimatedThinkingText()
                            .frame(width: 96, height: 96)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        if let status = coordinator.pendingStreamingStatus {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 20)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .top)
                    .padding(.top, 40)
                } else if let upload = coordinator.pendingFileUpload {
                    // Existing upload UI...
                } else if coordinator.pendingApplicantProfileIntake != nil {
                    // Existing intake card...
                } // ... rest of existing branches
            }
        }

4. Ensure AnimatedThinkingText import is present at top of file

Test by triggering file extraction and confirming spinner appears.

    git add Views/Components/OnboardingInterviewToolPane.swift
    git commit -m "feat: Add spinner and status display to tool pane during processing"

### Step 2: Add Status Emissions During Extraction

Edit the extraction coordinator or handler (likely in `Handlers/` or `Services/`):

1. Locate PDF extraction initiation
2. Add status updates at key points:

        coordinator.setStreamingStatus("Extracting PDF content...")
        // ... extraction logic ...
        coordinator.setStreamingStatus("Processing document...")
        // ... processing ...
        coordinator.setStreamingStatus("Saving extracted text...")
        // ... save artifact ...
        coordinator.setStreamingStatus("Preparing for assistant...")
        // ... finalization ...
        coordinator.setStreamingStatus(nil) // Clear when done

3. Similar pattern for other extraction types (contacts, manual entry)

Test full extraction flow and verify status messages appear and update.

    git add [modified extraction files]
    git commit -m "feat: Add progress status messages during extraction phases"

### Step 3: Verify Card Dismissal

1. Test the ApplicantProfile → Contacts/Manual → Save & Continue flow
2. Add logging if needed to confirm `pendingApplicantProfileIntake` is set to nil
3. Confirm spinner appears immediately after card dismisses
4. Document the interaction in test results

    git push origin feat/tool-pane-spinner

## Validation and Acceptance

No automated tests required. Notify user when code is ready for workflow evaluation.

## Idempotence and Recovery

All changes are safely reversible and idempotent:

- Spinner rendering is purely additive UI - removing the branch reverts to current behavior
- Status message emissions are fire-and-forget - no state corruption possible
- No data model changes or persistence modifications
- Can safely re-run any extraction or processing flow multiple times

If merge conflicts occur:
1. The spinner branch is independent and can be re-added above existing conditionals
2. Status emissions can be added to any extraction flow without affecting logic
3. Use `git stash` and `git stash pop` to manage local changes during merges

Recovery from partial implementation:
- If spinner renders but no status: Still improves UX with visual feedback
- If status emits but no spinner: Logs will show status for debugging
- Both components are independent and gracefully degrade

## Artifacts and Notes


Sample status message progression during PDF extraction:

    "Opening PDF file..."
    "Extracting text content..."
    "Processing 5 pages..."
    "Analyzing document structure..."
    "Saving extracted content..."
    "Preparing timeline data..."



## Interfaces and Dependencies

Required components and properties:
- `AnimatedThinkingText` - Existing Sprung logo animation component
- `coordinator.pendingStreamingStatus: String?` - Status message property
- `coordinator.setStreamingStatus(_: String?)` - Method to update status
- `service.isProcessing: Bool` - LLM processing state
- `service.pendingExtraction: ExtractionTask?` - Current extraction task

No external library dependencies. No API changes required.