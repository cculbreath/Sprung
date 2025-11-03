# ExecPlan: Phase‑1 fixes for Onboarding UX (scroll, summaries, spinner, intake card) + stricter tool steering for resume→timeline

This ExecPlan is a living document and must be maintained in accordance with `Plans.md` (repo reference: `Soruce Index and RefDocs.txt` → "Plans.md"). It is self‑contained so a novice can implement it end‑to‑end. :contentReference[oaicite:2]{index=2}

## Purpose / Big Picture

From the user’s perspective, this plan delivers two concrete gains:

1) **Chat stays readable and informative while the assistant streams.**  
   - The transcript auto‑scrolls *only* when a full assistant message completes, not on every token.  
   - The short *reasoning summary* line appears in italics under the assistant message when available; otherwise a tasteful “Thinking…” placeholder shows.  
   - When the tool area is free and the LLM is actively working, the left pane shows your animated Sprung spinner with a clear status line such as “Extracting PDF… Saving artifact…”. :contentReference[oaicite:3]{index=3} :contentReference[oaicite:4]{index=4}

2) **GPT‑5 reliably builds a skeleton timeline from an uploaded resume via the timeline card tools.**  
   The first turn after resume extraction is forced to call `create_timeline_card` (one card per role), with a safe fallback if the extracted text is empty/garbage. After the initial cards exist, we revert to normal auto tool choice so the conversation continues naturally. This aligns the runtime with the Phase One script. :contentReference[oaicite:5]{index=5} :contentReference[oaicite:6]{index=6}

Acceptance is expressed as user‑visible behavior in *Validation and Acceptance* below.

## Context and Orientation

Key files that govern today’s behavior:

- **Chat panel & reasoning line**: `Views/Components/OnboardingInterviewChatPanel.swift` (scroll behavior) and `Views/Components/OnboardingInterviewChatComponents.swift` (message bubble & reasoning line). The chat currently scrolls on *every* delta via `onChange(of: coordinator.messages.last?.text)` and also on end‑of‑processing; the per‑delta hook is the source of jitter. :contentReference[oaicite:7]{index=7} :contentReference[oaicite:8]{index=8}

- **Reasoning summary storage**: `Stores/ChatTranscriptStore.swift` mutates fields on an array element in place (e.g., `messages[index].reasoningSummary = ...`). With Swift’s new Observation model, mutating a property of an element in an array does not always trigger a view update unless the element is reassigned, resulting in the summary never appearing even when logs confirm it arrived. :contentReference[oaicite:9]{index=9}

- **Spinner site**: `Views/Components/OnboardingInterviewToolPane.swift` already computes `showSpinner`, but never actually renders the spinner or the streaming status; the left pane remains empty during long phases like PDF extraction. The annotated transcript requested exactly this behavior. :contentReference[oaicite:10]{index=10} :contentReference[oaicite:11]{index=11}

- **ApplicantProfile intake card lifecycle**: `Handlers/ProfileInteractionHandler.swift` clears `pendingApplicantProfileIntake` when intake completes, and the tool pane shows that card whenever `pendingApplicantProfileIntake != nil`. So the card *should* dismiss after “Save & Continue”; if it doesn’t, the bug is that the tool pane never becomes free for the spinner because we never render the spinner even when `showSpinner == true`. Fixing spinner rendering solves both symptoms. 

- **Tool steering for resume → timeline**: Phase One script tells the LLM to parse the resume text and create timeline cards via the card tools. Today, we *also* have an orchestrator path that synthesizes a skeleton timeline without first forcing `create_timeline_card`—leading GPT‑5 to fall back to generic prompts or the section selector. We need a one‑shot “require tool X” override on the *first* turn after resume text is delivered. :contentReference[oaicite:14]{index=14} :contentReference[oaicite:15]{index=15}

## Plan of Work

We will address the five reported issues and the bigger steering problem with small, testable edits.

### A. Auto‑scroll only at message completion (and not per delta)

1. **Remove the per‑delta scroll trigger** in `Views/Components/OnboardingInterviewChatPanel.swift`.  
   Find the `onChange(of: coordinator.messages.last?.text ?? "", initial: false)` block inside `messageScrollView` and delete it. Rely on the existing hooks:
   - `onChange(of: coordinator.messages.count)` (when a *new* message is appended)  
   - `onChange(of: service.isProcessing)` (fires to `false` after the assistant finishes)  
   This matches the “scroll at end of message” requirement. Evidence of current per‑delta hook: the `onChange` reading `messages.last?.text`. :contentReference[oaicite:16]{index=16}

2. **Keep the bottom‑button affordance** (`scrollToLatestButton`) driven by proximity logic so users can opt out if they’ve scrolled up. No code changes needed here. :contentReference[oaicite:17]{index=17}

### B. Reasoning summaries: show the italic line reliably when the LLM provides it

1. **Make array element updates observable** in `Stores/ChatTranscriptStore.swift`.  
   For each mutator (`updateAssistantStream`, `finalizeAssistantStream`, `updateReasoningSummary`, `finalizeReasoningSummariesIfNeeded`) rewrite the pattern from:
   
       messages[index].reasoningSummary = value
       messages[index].showReasoningPlaceholder = false
   
   to:
   
       var msg = messages[index]
       msg.reasoningSummary = value
       msg.showReasoningPlaceholder = false
       messages[index] = msg

   This reassignment makes Swift’s Observation emit a change for views bound to `messages`. Today the code writes fields in place on the array element; views do not reliably re‑render. Evidence of current pattern: in‑place mutation in `updateReasoningSummary`. :contentReference[oaicite:18]{index=18}

2. **No view changes required**: the bubble already renders either the summary line (italic) or the shimmering “Thinking…” placeholder (`ReasoningSummaryPlaceholderView`). :contentReference[oaicite:19]{index=19}

### C. ApplicantProfileIntakeCard should dismiss after save

1. **Confirm lifecycle**: `ProfileInteractionHandler.completeIntake(...)` sets `pendingApplicantProfileIntake = nil`. That should remove the card. Evidence: `completeIntake` clears both `pendingApplicantProfileIntake` and the continuation id. :contentReference[oaicite:20]{index=20}

2. **Root cause & fix**: The left pane feels “stuck” because the spinner layer is never rendered when the pane becomes free; the user only sees the prior card and assumes it persisted. Implement spinner rendering (Section D) and the symptom disappears.

### D. Spinner and progress/status messages in the left pane

1. **Render the spinner when `showSpinner == true`** in `Views/Components/OnboardingInterviewToolPane.swift`. The view already computes:

   - `paneOccupied = isPaneOccupied(...)`  
   - `isLLMActive = service.isProcessing || coordinator.pendingStreamingStatus != nil`  
   - `showSpinner = service.pendingExtraction != nil || (!paneOccupied && isLLMActive)`  

   but it never displays anything for `showSpinner`. Add a top‑level branch so that **before** we check for uploads/intake/prompts/etc., we render the spinner when `showSpinner` is true:

       if showSpinner {
           VStack(spacing: 12) {
               AnimatedThinkingText()   // Sprung logo
                   .frame(maxWidth: .infinity, alignment: .center)
               if let status = coordinator.pendingStreamingStatus {
                   Text(status)
                       .font(.footnote)
                       .foregroundStyle(.secondary)
               }
           }
           .frame(maxWidth: .infinity, minHeight: 220, alignment: .top)
       } else {
           // existing branches for uploads, intake, prompts, validation…
       }

   This matches the annotated transcript request (“AI spinner while we wait… show a clear progress line”). Evidence: variable definitions exist but spinner is not rendered anywhere. :contentReference[oaicite:21]{index=21} :contentReference[oaicite:22]{index=22}

2. **Drive status text from orchestration**: You already expose `coordinator.pendingStreamingStatus` and an extraction progress callback (`updateExtractionProgress`). Use these to set short messages such as “Identified PDF (3 pages)… Extracting… Saving artifact…”. No schema changes required—just ensure the extraction service emits a few succinct `setStreamingStatus(...)` updates that the pane can display. Hooks exist in `OnboardingInterviewCoordinator` callbacks and `DocumentExtractionService`. :contentReference[oaicite:23]{index=23} :contentReference[oaicite:24]{index=24}

3. **Requested Polish**: swap the `Text(status)` for a tiny checklist animation later; out‑of‑scope for this fix but aligned with the annotated request. :contentReference[oaicite:25]{index=25}

### E. Prompt adherence: force timeline card creation after resume extraction

**Goal**: The *first* LLM turn after pushing the extracted resume text *must* create timeline cards via the card tools. After that, revert to normal `auto` tool choice.

1. **Add a one‑shot tool‑choice override** in `InterviewOrchestrator` (or the request layer you use for Responses API calls). Introduce a transient field:

       private var nextToolChoiceOverride: ToolChoiceOverride?
       private struct ToolChoiceOverride {
           enum Mode { case require(tools: [String]), case auto }
           let mode: Mode
       }

   And modify the code that builds the OpenAI response parameters so that if `nextToolChoiceOverride` is present, you emit:
   - `tool_choice: { type: "tool", name: "create_timeline_card" }` **and** `available_tools` = only the timeline card tools (`create_timeline_card`, `update_timeline_card`, `reorder_timeline_cards`, `delete_timeline_card`) **for that one call**, then immediately clear `nextToolChoiceOverride`.  
   - Otherwise keep your current per‑phase allowed tools map and `auto` choice.

   This mirrors the idea in your notes and aligns with Phase One’s instructions. :contentReference[oaicite:26]{index=26}

2. **Set the override after successful extraction**: When `DocumentExtractionService` returns text and you enqueue the serialized, binary‑free artifact developer message to GPT‑5, set:

       orchestrator.nextToolChoiceOverride = .init(mode: .require(
           tools: ["create_timeline_card", "update_timeline_card", "reorder_timeline_cards", "delete_timeline_card"]
       ))

   If the extracted text is empty or useless, **do not** set the override; instead, send a short assistant message asking for a better resume or to proceed via manual entry, and let the normal flow continue.
   

Use a hueristic test to determine if extracted resume text is likely legidimate:
```

struct ResumeHeuristics {
    static func isUseful(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 400 else { return false }

        let words = cleaned.split { !$0.isLetter }
        let wordCount = words.count
        if wordCount < 80 { return false }

        let letters = cleaned.filter(\.isLetter).count
        let letterRatio = Double(letters) / Double(cleaned.count)
        if letterRatio < 0.55 { return false }

        let spaceRatio = Double(cleaned.filter(\.isWhitespace).count) / Double(cleaned.count)
        if spaceRatio > 0.40 { return false }

        // Expanded section / keyword list
        let sectionTerms = [
            // resume section headers
            "experience", "work experience", "education", "skills",
            "projects", "employment", "summary", "objective", "achievements",
            "certifications", "certification", "training", "awards", "languages",
            "publications", "references", "activities", "interests",
            
            // degree abbreviations
            "bs", "b.s.", "ba", "b.a.", "bfa", "b.e.", "beng",
            "ms", "m.s.", "ma", "m.a.", "mba", "phd", "ph.d.",
            "jd", "mfa", "msc", "md", "btech", "mtech", "associate",
            
            // common professional titles
            "manager", "assistant", "developer", "engineer", "analyst", "consultant",
            "designer", "scientist", "specialist", "technician", "coordinator",
            "director", "supervisor", "administrator", "architect", "intern",
            "teacher", "professor", "researcher", "lead", "principal",
            
            // technical skill clusters
            "python", "java", "c++", "swift", "javascript", "sql", "aws", "azure",
            "docker", "kubernetes", "linux", "git", "machine learning", "data analysis",
            "cloud", "ios", "android", "full stack", "frontend", "backend"
        ]

        let lower = cleaned.lowercased()
        let found = sectionTerms.filter { lower.contains($0) }
        if found.count < 3 { return false }

        // check for date-like patterns
        let yearMatches = matches(for: #"\b(19|20)\d{2}\b"#, in: cleaned)
        if yearMatches.count < 2 { return false }

        // resume formatting hints
        if !cleaned.contains("•") && !cleaned.contains("- ") && !cleaned.contains("\n") {
            return false
        }

        return true
    }

    private static func matches(for regex: String, in text: String) -> [String] {
        (try? NSRegularExpression(pattern: regex))?
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } } ?? []
    }
}
```
and bail out of tool-enforcement if needed:
```
let text = try await extractor.extractText(from: pdf)
if !ResumeHeuristics.isUseful(text) {
    orchestrator.enqueueDeveloperMessage("""
        The uploaded resume text was too short or lacked recognizable structure.
        Inform the user that the resume could not be read and ask for another file or manual entry.
        Do NOT attempt timeline card creation.
    """)
    orchestrator.enqueueUserVisibleMessage(
        role: .assistant,
        content: "Hmm, I couldn’t read much from that file. Could you try another resume, or type your job history manually?"
    )
    return
}
```
3. **Keep system/developer guidance consistent**: The Phase One script already tells the model to build cards and then call `submit_for_validation`. Ensure the developer message that accompanies the extracted text says, plainly: “**Use the timeline card tools now**. Create one card per role you find in the text; then ask clarifying questions in chat.” This reduces ambiguity. :contentReference[oaicite:27]{index=27}

## Validation and Acceptance

Run the app and exercise the flows below.

1) **Auto‑scroll**  
   - Start an interview, send a user message that prompts a long assistant response.  
   - Observe: the chat *does not* jump while tokens stream; it snaps to bottom once the assistant finishes (glow border turns off).  
   - Manual scroll away from bottom; the down‑arrow button appears; click it to restore auto‑scroll. Evidence the current per‑delta hook existed and is now removed is in the chat panel file. :contentReference[oaicite:28]{index=28}

2) **Reasoning summary line**  
   - Trigger a response where logs show a reasoning summary (you already see these in console).  
   - Observe: a small italic line appears under the finished assistant message. If the model withholds a final summary, the shimmering “Thinking…” placeholder disappears when the message completes. The code path now reassigns the array element, so SwiftUI updates. :contentReference[oaicite:29]{index=29} :contentReference[oaicite:30]{index=30}

3) **Applicant profile intake card and spinner**  
   - Go through Applicant Profile -> pick Contacts or Manual -> Save & Continue.  
   - Observe: the intake card dismisses; if the LLM is still working and no other tool card is present, the left pane shows the Sprung spinner plus the status line (e.g., “Awaiting assistant…”). This validates the new `showSpinner` branch. :contentReference[oaicite:31]{index=31}

4) **Resume upload → forced timeline card creation**  
   - Upload a resume (PDF). While extraction runs, the left pane shows spinner + statuses (“Extracting… Saving artifact… Transmitting to assistant…”).  
   - As soon as GPT‑5 receives the extracted text, the *first* reply must be `create_timeline_card` calls (visible in your tool logging), producing cards in the new timeline editor. No section selector appears until later; the assistant can ask clarifying questions in chat but *facts* go into cards. This demonstrates the one‑shot `tool_choice: required` override then reversion to `auto`. :contentReference[oaicite:32]{index=32} :contentReference[oaicite:33]{index=33}

## Interfaces and Dependencies

- No external library changes are required.  
- The override uses your existing Responses API call site (where allowed tools are constructed per phase); we’re adding a narrow, one‑turn override and clearing it after use. Align names with your existing tool registry (`ToolRegistry` exposes the timeline tools). :contentReference[oaicite:34]{index=34}

## Concrete Steps

All paths repository‑relative to ./Sprung/Onboarding/

1. **Chat scroll jitter**  
   - Edit: `Views/Components/OnboardingInterviewChatPanel.swift` inside `messageScrollView(proxy:)`.  
   - Remove the block that reads `onChange(of: coordinator.messages.last?.text ?? "", initial: false)`. Keep the `messages.count` and `service.isProcessing` hooks.

2. **Reasoning summary updates**  
   - Edit: `Stores/ChatTranscriptStore.swift`.  
   - In `updateAssistantStream`, `finalizeAssistantStream`, `updateReasoningSummary`, `finalizeReasoningSummariesIfNeeded`: copy the array element to a var, mutate, and write it back (`messages[index] = msg`).

3. **Spinner & status line**  
   - Edit: `Views/Components/OnboardingInterviewToolPane.swift`.  
   - At the top of `var body: some View`, before branching into uploads/intake/prompts/etc., add an `if showSpinner { ... }` that renders `AnimatedThinkingText()` and `Text(coordinator.pendingStreamingStatus)` when present. Ensure `AnimatedThinkingText` scales to ~96×96 as already coded. :contentReference[oaicite:35]{index=35}

4. **One‑shot tool choice override**  
   - Edit: the Responses API call builder in your orchestrator/service layer (where you currently pass allowed tools).  
   - Add `nextToolChoiceOverride` storage and logic to emit `tool_choice: required` with `available_tools` restricted to the timeline tools for exactly one call, then clear it.  
   - On resume extraction success (where you enqueue the artifact and developer message), set the override to require `create_timeline_card` et al.; when text is empty/unusable, skip the override and send a short assistant message that requests a better resume or offers manual entry.

5. **Status plumbing (light)**  
   - Ensure extraction emits short `setStreamingStatus(...)` updates already supported by callbacks (`updateExtractionProgress`, `setExtractionStatus`). The pane will display them immediately.

## Idempotence and Recovery

- Removing the per‑delta scroll hook is safe and reversible.  
- Reassigning array elements is safe; no schema changes.  
- The one‑shot override is additive; if the LLM cannot comply (empty text), we skip it and present a friendly fallback in chat.  
- Spinner rendering is purely presentational; if `showSpinner` logic regresses, the pane still renders cards as before.

## Surprises & Discoveries

- The left pane already computed `showSpinner` but never rendered it; this is why users never saw progress during deterministic local work. :contentReference[oaicite:36]{index=36}  
- Reasoning summaries were likely arriving (per logs) but the in‑place mutation on `messages[index]` prevented SwiftUI from refreshing; reassigning the element is the minimal fix. :contentReference[oaicite:37]{index=37}

## Progress

- [ ] Remove per‑delta auto‑scroll; keep end‑of‑message scroll only. (ChatPanel) :contentReference[oaicite:38]{index=38}  
- [ ] Reassign array elements when updating summaries/streams. (ChatTranscriptStore) :contentReference[oaicite:39]{index=39}  
- [ ] Render spinner + status when `showSpinner` is true. (ToolPane) :contentReference[oaicite:40]{index=40}  
- [ ] Add one‑shot `tool_choice: required` override and clear it post‑call. (Orchestrator)  
- [ ] Emit brief extraction status strings for display. (Extraction/Coordinator)

## Decision Log

- **Decision**: Prefer one‑shot forced tool call over heavier prompt surgery to ensure initial card creation.  
  **Rationale**: Minimal intrusion; preserves normal auto behavior after the initial skeleton; aligns with Phase One script.  
  **Date/Author**: 2025‑11‑01 / Assistant

- **Decision**: Fix reasoning summary rendering via reassignment in the store rather than adding more view `onChange` hooks.  
  **Rationale**: Correct fix at the data source; fewer UI workarounds.  
  **Date/Author**: 2025‑11‑01 / Assistant

## Outcomes & Retrospective (to fill in after implementation)

- Evidence of smooth scrolling, consistent reasoning line, visible spinner/status, and immediate timeline card creation after resume upload.