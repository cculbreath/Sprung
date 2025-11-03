# ExecPlan: Resume-to-Timeline Tool Steering Implementation

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

**IMPORTANT**: Multiple developers are working on this codebase simultaneously. Make frequent atomic commits with clear messages. If you encounter unexpected changes to files you're working on, pull latest changes and merge carefully. Coordinate through commit messages and avoid large, monolithic changes.

## Purpose / Big Picture

After this change, GPT-5 will reliably convert uploaded resumes into structured timeline cards on the first attempt. When a user uploads a resume PDF, the system will extract the text, validate it contains useful career information, and then force the LLM to immediately create timeline cards (one per job role) using the `create_timeline_card` tool. This eliminates the current issue where the LLM sometimes falls back to generic prompts or shows the section selector instead of creating cards. Users will see their work history instantly transformed into editable timeline cards, making the onboarding process smooth and deterministic.

## Progress

Use a list with checkboxes to summarize granular steps. Every stopping point must be documented here.

- [ ] Set up development environment and verify build
- [ ] Locate orchestrator/service layer where tool choices are made
- [ ] Implement nextToolChoiceOverride storage mechanism
- [ ] Add logic to emit tool_choice: required with restricted tools
- [ ] Implement override clearing after single use
- [ ] Create ResumeHeuristics validation module
- [ ] Implement isUseful() method with text validation logic
- [ ] Add heuristics for minimum content detection
- [ ] Integrate validation into resume extraction flow
- [ ] Add fallback message for invalid/empty resumes
- [ ] Update developer guidance messages for timeline creation
- [ ] Test with valid multi-role resume
- [ ] Test with empty/garbage file
- [ ] Test with single-role resume
- [ ] Create atomic commit for tool steering
- [ ] Create atomic commit for resume validation
- [ ] Run full acceptance tests
- [ ] Document any merge conflicts encountered

## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during implementation.

- To be filled during implementation

## Decision Log

Record every decision made while working on the plan.

- Decision: Use one-shot tool_choice override rather than modifying prompts
  Rationale: Cleaner, more reliable, preserves normal behavior after initial cards created
  Date/Author: 2025-11-01 / Planning Phase

- Decision: Create separate ResumeHeuristics module for validation
  Rationale: Reusable, testable, keeps orchestrator clean
  Date/Author: 2025-11-01 / Planning Phase

- Decision: Require minimum 3 lines and 100 chars for valid resume
  Rationale: Prevents processing of empty or corrupt files while allowing brief resumes
  Date/Author: 2025-11-01 / Planning Phase

## Outcomes & Retrospective

To be filled at completion.

## Context and Orientation

The current resume processing flow extracts text from uploaded PDFs and sends it to GPT-5 with instructions to create timeline cards. However, the LLM sometimes ignores these instructions and either asks clarifying questions in chat or shows the section selector UI instead of immediately creating timeline cards.

Key components in the current system:

- **Tool Registry**: Manages available tools including `create_timeline_card`, `update_timeline_card`, `delete_timeline_card`, and `submit_for_validation`
- **Orchestrator**: Coordinates the conversation flow, manages tool choices, and sends requests to the LLM
- **Resume Extraction**: Extracts text from PDFs and creates artifacts
- **Responses API**: The interface to GPT-5 where we specify available tools and tool_choice parameters

The Phase One script already instructs the model to create timeline cards, but without a forced tool_choice, the model sometimes takes alternative paths. We need to add a one-turn override that requires the timeline tools for the first response after resume text delivery.

## Plan of Work

### Phase 1: Implement One-Shot Tool Choice Override

We will add a mechanism in the orchestrator that can force specific tool usage for exactly one LLM call. This involves storing a temporary override, applying it to the next API call, then clearing it immediately. The override will specify `tool_choice: "required"` with a restricted set of timeline tools.

### Phase 2: Resume Text Validation

We will create a `ResumeHeuristics` module that validates extracted text to ensure it contains meaningful career information. This prevents the system from trying to process empty, corrupted, or unusable files. When validation fails, we'll skip the tool override and provide a friendly message asking for a better file.

### Phase 3: Integration and Developer Guidance

We will integrate the validation and tool steering into the resume extraction flow. When valid resume text is extracted, we'll set the tool choice override and provide clear developer guidance. The LLM will be forced to use timeline tools on its first response, then revert to normal auto tool selection for subsequent interactions.

## Concrete Steps

Working directory: `./Sprung/Onboarding/`

### Step 1: Add Tool Choice Override Mechanism

    cd ./Sprung/Onboarding/
    git pull origin main
    git checkout -b feat/resume-timeline-steering

Locate the orchestrator or service layer (likely `Services/OnboardingOrchestrator.swift` or similar):

1. Add storage for the override at class level:

        private var nextToolChoiceOverride: ToolChoiceOverride?
        
        struct ToolChoiceOverride {
            let choice: String  // "required" or "auto"
            let allowedTools: [String]?  // tool names to restrict to
        }

2. Modify the API call builder method:

        func buildResponsesAPIRequest(...) -> ResponsesAPIRequest {
            var request = ResponsesAPIRequest(...)
            
            // Apply one-shot override if present
            if let override = nextToolChoiceOverride {
                request.toolChoice = override.choice
                if let allowed = override.allowedTools {
                    request.availableTools = request.availableTools.filter { 
                        allowed.contains($0.name) 
                    }
                }
                // Clear override after use
                nextToolChoiceOverride = nil
            }
            
            return request
        }

3. Add method to set the override:

        func requireToolsNextTurn(_ toolNames: [String]) {
            nextToolChoiceOverride = ToolChoiceOverride(
                choice: "required",
                allowedTools: toolNames
            )
        }

    git add Services/OnboardingOrchestrator.swift
    git commit -m "feat: Add one-shot tool choice override mechanism for forced tool usage"

### Step 2: Create Resume Validation Module

Create new file `Utilities/ResumeHeuristics.swift`:

    struct ResumeHeuristics {
        static func isUseful(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check minimum length
            guard trimmed.count >= 100 else { return false }
            
            // Check minimum lines (indicates structure)
            let lines = trimmed.components(separatedBy: .newlines)
            guard lines.count >= 3 else { return false }
            
            // Check for date patterns (years indicate work history)
            let yearPattern = #"\b(19|20)\d{2}\b"#
            let yearRegex = try? NSRegularExpression(pattern: yearPattern)
            let yearMatches = yearRegex?.numberOfMatches(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
            ) ?? 0
            
            // Check for work-related keywords
            let workKeywords = [
                "experience", "work", "job", "position", "role",
                "employment", "company", "manager", "engineer",
                "developer", "analyst", "consultant", "intern"
            ]
            let lowercased = trimmed.lowercased()
            let hasWorkContent = workKeywords.contains { lowercased.contains($0) }
            
            // Valid if: has years OR work keywords, plus minimum content
            return yearMatches > 0 || hasWorkContent
        }
        
        static func extractErrorMessage(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "The file appears to be empty"
            } else if trimmed.count < 100 {
                return "The file contains very little text"
            } else {
                return "The file doesn't appear to contain resume information"
            }
        }
    }

    git add Utilities/ResumeHeuristics.swift
    git commit -m "feat: Add resume text validation heuristics module"

### Step 3: Integrate into Resume Extraction Flow

Locate the resume extraction completion handler (likely in `Handlers/ResumeExtractionHandler.swift`):

1. Import the heuristics module
2. After text extraction, before sending to LLM:

        func handleExtractedResumeText(_ text: String) {
            // Validate the extracted text
            if !ResumeHeuristics.isUseful(text) {
                let errorDetail = ResumeHeuristics.extractErrorMessage(text)
                
                // Skip tool override, send friendly message
                orchestrator.enqueueDeveloperMessage("""
                    The uploaded file could not be processed: \(errorDetail).
                    Inform the user and ask them to try another file or enter their work history manually.
                    Do NOT attempt to create timeline cards.
                """)
                
                orchestrator.enqueueUserVisibleMessage(
                    role: .assistant,
                    content: "I couldn't extract useful information from that file. Could you try uploading a different resume, or would you prefer to enter your work history directly?"
                )
                return
            }
            
            // Valid resume - force timeline tool usage
            let timelineTools = [
                "create_timeline_card",
                "update_timeline_card", 
                "delete_timeline_card",
                "submit_for_validation"
            ]
            orchestrator.requireToolsNextTurn(timelineTools)
            
            // Send extracted text with clear instructions
            orchestrator.enqueueDeveloperMessage("""
                Resume text successfully extracted. You MUST now create timeline cards.
                
                Instructions:
                1. Parse the resume text below
                2. Create one timeline card for each job role found
                3. Use create_timeline_card tool for each role
                4. Include: title, company, dates, and key achievements
                5. After creating all cards, ask any clarifying questions in chat
                
                IMPORTANT: Create cards FIRST, then engage in conversation.
                
                Extracted resume text:
                ---
                \(text)
                ---
            """)
            
            // Also create artifact for reference
            orchestrator.createArtifact(
                type: .extractedText,
                content: text,
                metadata: ["source": "resume_upload"]
            )
        }

    git add Handlers/ResumeExtractionHandler.swift  
    git commit -m "feat: Integrate validation and tool steering into resume extraction flow"
    git push origin feat/resume-timeline-steering

## Validation and Acceptance

No automated tests required. Notify user when code is ready for workflow evaluation.

## Idempotence and Recovery

All changes are idempotent and safely reversible:

- Tool choice override: One-shot by design, clears itself after use
- Resume validation: Pure function, no side effects
- Can re-upload same resume multiple times, same behavior each time
- Failed uploads don't corrupt state, can immediately retry

If implementation is partially complete:
- Without override: Current behavior continues (may not create cards)
- Without validation: Attempts to process all files (may fail on empty)
- Both features are independent but work best together

Rollback procedure:
1. Remove override mechanism: Delete override field and conditional in API builder
2. Remove validation: Skip ResumeHeuristics check, process all text
3. Both can be feature-flagged for gradual rollout if desired

## Artifacts and Notes

Sample tool_choice override in API request:

    {
        "messages": [...],
        "tools": [
            {"name": "create_timeline_card", ...},
            {"name": "update_timeline_card", ...},
            {"name": "delete_timeline_card", ...},
            {"name": "submit_for_validation", ...}
        ],
        "tool_choice": "required"  // Forces use of provided tools
    }

Expected console output during valid resume processing:

    [Orchestrator] Resume text validated: 2450 chars, 45 lines, work content detected
    [Orchestrator] Setting tool choice override: required, tools: [create_timeline_card, ...]
    [API] Sending request with tool_choice: required
    [API] Response used tools: create_timeline_card (3 times)
    [Orchestrator] Tool choice override cleared

The timeline tools should be filtered from ToolRegistry to ensure names match exactly.

## Interfaces and Dependencies

Required components:
- `ToolRegistry`: Must expose timeline tool names
- `ResponsesAPIRequest`: Must support toolChoice and tool filtering
- `OnboardingOrchestrator`: Must track and apply override
- Text extraction must provide String output

No external dependencies. Compatible with existing Phase One script.

Timeline tool signatures (must remain compatible):
- `create_timeline_card(title, company, startDate, endDate, description, achievements)`
- `update_timeline_card(cardId, ...fields...)`
- `delete_timeline_card(cardId)`
- `submit_for_validation()`