# Onboarding Interview Issues - Implementation Plan

## Overview

This plan addresses 13 issues identified during onboarding interview testing. Issues are grouped by complexity and dependencies.

---

## Issue 1: Duplicate Status Bar Entries for Merge Agent

**Problem**: When clicking "Done with Uploads", two status bar entries appear:
- "Card Merge: Processing" (from KnowledgeCardWorkflowService)
- "Card Merge Agent:" (from NarrativeDeduplicationService)

**Root Cause**: `CardMergeService.getAllNarrativeCardsDeduped()` calls `deduplicateCards()` without passing `parentAgentId`, so `NarrativeDeduplicationService` creates a second agent.

**Files to Modify**:
- `Sprung/Onboarding/Services/CardMergeService.swift`
- `Sprung/Onboarding/Services/KnowledgeCardWorkflowService.swift`

**Changes**:
1. Add `parentAgentId` parameter to `CardMergeService.getAllNarrativeCardsDeduped()`
2. Pass the `cardMergeAgentId` from `KnowledgeCardWorkflowService` through to `deduplicateCards()`
3. Remove duplicate agent creation in `NarrativeDeduplicationService` when parent ID is provided

**Code Sketch**:
```swift
// CardMergeService.swift
func getAllNarrativeCardsDeduped(parentAgentId: String? = nil) async throws -> DeduplicationResult {
    // ...
    let service = await getDeduplicationService()
    return try await service.deduplicateCards(allCards, parentAgentId: parentAgentId)
}

// KnowledgeCardWorkflowService.swift (line ~120)
let dedupeResult = try await cardMergeService.getAllNarrativeCardsDeduped(parentAgentId: cardMergeAgentId)
```

---

## Issue 2: 15-Second Delay Before Merge Agent Surfaces

**Problem**: ProgressView shows immediately but merge agent doesn't appear in status bar for ~15 seconds.

**Root Cause**: The delay is likely in artifact processing before the agent is actually started. The `ui.isMergingCards = true` triggers the ProgressView, but actual agent registration happens later.

**Files to Modify**:
- `Sprung/Onboarding/Services/KnowledgeCardWorkflowService.swift`

**Changes**:
1. Register the agent immediately after setting `isMergingCards = true`
2. Add initial status message "Aggregating cards from documents..."
3. Update status as each phase completes

**Code Sketch**:
```swift
// In handleDoneWithUploadsClicked(), register agent BEFORE any async work
let cardMergeAgentId = agentActivityTracker.trackAgent(
    id: UUID().uuidString,
    type: .cardMerge,
    name: "Card Merge",
    task: nil as Task<Void, Never>?
)
agentActivityTracker.markRunning(agentId: cardMergeAgentId)
agentActivityTracker.updateStatus(agentId: cardMergeAgentId, message: "Aggregating cards...")

// Then proceed with getAllNarrativeCardsFlat(), etc.
```

---

## Issue 3: LLM Asking Experience Specifics in Phase 1 & 2

**Problem**: LLM asks about specific job accomplishments in Phase 1 and Phase 2, when those details should come from documents in Phase 3.

**Files to Modify**:
- `Sprung/Resources/Prompts/phase1_intro_prompt.txt`
- `Sprung/Resources/Prompts/phase2_intro_prompt.txt`

**Changes**:
Add stronger prohibition language to BOTH prompts:

```markdown
### CRITICAL: What NOT to Ask in Phase 1/2

⛔ **NEVER ask these questions:**
- "What did you accomplish at [company]?"
- "Tell me about a project you worked on"
- "What were your key achievements?"
- "Can you describe your responsibilities?"
- "What technologies did you use at [job]?"
- "What impact did you have?"
- "Can you quantify your results?"

These details come from DOCUMENTS in Phase 3, not from interview questions. Asking now just makes the user type information that their resume/docs already contain.

✅ **DO ask about:**
- Motivations, priorities, preferences (soft context)
- Work style, collaboration preferences
- What they're looking for in next role
- Why they're searching now
- Why they left/joined companies (narrative framing, not accomplishments)

The interview captures WHO they are and their STORY. Documents capture WHAT they did.
```

For Phase 2 specifically, add after the "Enrich Each Position" section:

```markdown
**⚠️ IMPORTANT: Don't Ask for Specifics**

When probing about positions, ask about CONTEXT and MOTIVATION, not accomplishments:

✅ GOOD: "What drew you to [Company]?" / "What made you leave?"
❌ BAD: "What did you accomplish there?" / "What projects did you work on?"

Specific achievements, metrics, and project details will come from documents in Phase 3. Your job here is to understand the STORY—why they made choices, what they learned, how they frame their career—not to collect resume bullet points.
```

---

## Issue 4: Queued Messages Display

**Problem**: Queued messages appear in chat immediately. They should show at bottom with watch icon until sent, then move to proper chronological position.

**Files to Modify**:
- `Sprung/Onboarding/Models/OnboardingMessage.swift` - Add `isQueued` flag
- `Sprung/Onboarding/Views/Components/OnboardingChatMessageList.swift` - Handle queued display
- `Sprung/Onboarding/Views/Components/MessageBubble.swift` - Add dimmed styling
- `Sprung/Onboarding/Core/Coordinators/UIResponseCoordinator.swift` - Track queued state
- `Sprung/Onboarding/Core/UserActionQueue.swift` - Expose queue state

**Changes**:

1. Add `isQueued: Bool` property to `OnboardingMessage`
2. Split message list into two sections: sent messages (chronological) + queued messages (at bottom)
3. When message is dequeued and sent, update `isQueued = false` and let it sort chronologically
4. Add dimmed styling with clock icon for queued messages

**UI Sketch**:
```
┌─────────────────────────────┐
│ [User message 1]            │
│        [Assistant response] │
│ [User message 2]            │
│        [Assistant response] │
│ ─────────────────────────── │
│ 🕐 [Queued: message 3] dim  │  ← Cancelable
│ 🕐 [Queued: message 4] dim  │
└─────────────────────────────┘
```

---

## Issue 5: Stop Command (Drain Queue + Delete Orphan Tool Calls + Silence Incoming)

**Problem**: Need a way to stop processing, drain the queue, clean up orphan tool calls, AND silence any incoming tool calls from the model until user takes purposeful action.

**Files to Modify**:
- `Sprung/Onboarding/Views/Components/OnboardingChatComposerView.swift` - Add Stop button
- `Sprung/Onboarding/Core/OnboardingInterviewCoordinator.swift` - Add `stopProcessing()` method
- `Sprung/Onboarding/Core/UserActionQueue.swift` - Add `drainAndClear()` method
- `Sprung/Onboarding/Core/OnboardingUIState.swift` - Add `isStopped: Bool` flag
- `Sprung/Onboarding/LLM/AnthropicHistoryBuilder.swift` - Add orphan cleanup
- `Sprung/Onboarding/Core/Coordinators/ToolExecutionCoordinator.swift` - Check stopped flag

**Changes**:

1. Add "Stop" button (appears when processing, separate from Interrupt)
2. Add `ui.isStopped: Bool` flag that silences all incoming processing
3. `stopProcessing()` method that:
   - Sets `isStopped = true`
   - Cancels current LLM operation
   - Clears all gate blocks
   - Drains message queue (deletes queued messages)
   - Scans conversation history for orphan tool_use without tool_result
   - Removes orphan entries or adds placeholder tool_result
4. Check `isStopped` before processing incoming tool calls - discard if stopped
5. Clear `isStopped` flag when user takes purposeful action:
   - Sends chatbox message
   - Clicks "Done with Uploads" or "Skip"
   - Drags and drops a file
   - Clicks any UI button that triggers LLM interaction

**Code Sketch**:
```swift
// OnboardingUIState.swift
@Published var isStopped: Bool = false

// OnboardingInterviewCoordinator.swift
func stopProcessing() async {
    Logger.info("🛑 Stop requested - entering stopped state", category: .ai)

    // 1. Enter stopped state - silences all incoming
    ui.isStopped = true

    // 2. Cancel LLM
    await requestCancelLLM()

    // 3. Clear blocks
    drainGate.clearAllBlocks()

    // 4. Drain queue
    userActionQueue.drainAndClear()

    // 5. Clean orphan tool calls from history
    await conversationHistory.removeOrphanToolCalls()

    // 6. Remove queued messages from UI
    ui.messages.removeAll { $0.isQueued }

    Logger.info("🛑 Stopped - waiting for user action to resume", category: .ai)
}

// Called before any purposeful user action
func clearStoppedState() {
    if ui.isStopped {
        Logger.info("▶️ Resuming from stopped state", category: .ai)
        ui.isStopped = false
    }
}

// ToolExecutionCoordinator.swift - in tool execution handler
func handleToolCall(_ toolCall: ToolCall) async {
    guard !coordinator.ui.isStopped else {
        Logger.info("🛑 Discarding tool call - stopped state active", category: .ai)
        return  // Silently discard
    }
    // ... normal processing
}
```

---

## Issue 6: Timeline Tab Focus on Tool Use

**Problem**: When LLM uses timeline tools, the tool pane should switch to Timeline tab.

**Files to Modify**:
- `Sprung/Onboarding/Views/Components/ToolPaneTabsView.swift`
- `Sprung/Onboarding/Core/OnboardingUIState.swift` - Add `lastTimelineToolUsed` flag

**Changes**:

1. Add observable property `ui.timelineToolWasUsed: Bool`
2. Set this flag when any timeline CRUD tool executes
3. Add `onChange` handler in `ToolPaneTabsView` to switch to timeline tab

**Code Sketch**:
```swift
// ToolPaneTabsView.swift
.onChange(of: coordinator.ui.timelineToolWasUsed) { _, wasUsed in
    if wasUsed && selectedTab != .timeline {
        withAnimation(OnboardingAnimations.ToolPane.tabAutoSwitch) {
            selectedTab = .timeline
        }
        coordinator.ui.timelineToolWasUsed = false  // Reset
    }
}
```

---

## Issue 7: Remove Redundant Custom Fields Checkbox

**Problem**: "Include identity title set" checkbox above the divider is redundant to the custom field mechanism below.

**Files to Modify**:
- `Sprung/Onboarding/Views/Components/ResumeSectionsToggleCard.swift`

**Changes**:
Remove lines 129-138 (the special checkbox) and adjust layout. Users who want `custom.jobTitles` can add it via "+ Add" button.

---

## Issue 8: Writing Samples Cleanup + Interview Completion State

**Problem**: Writing samples persist indefinitely. Need "interview complete" state so Start Over dialog doesn't appear every time.

**Files to Modify**:
- `Sprung/Onboarding/Models/OnboardingSession.swift` - Add `isCompleted: Bool`
- `Sprung/Onboarding/Services/OnboardingPersistenceService.swift` - Mark complete after Phase 4
- `Sprung/Onboarding/Services/OnboardingDataResetService.swift` - Delete artifacts on reset
- `Sprung/Onboarding/Views/OnboardingIntroView.swift` - Check completion state

**Changes**:

1. Add `isCompleted` flag to `OnboardingSession`
2. When Phase 4 finishes (experience defaults validated), set `isCompleted = true`
3. Delete writing sample artifacts when interview completes OR on "Start Over"
4. "Begin Interview" button:
   - If no session exists → start fresh
   - If session exists and `isCompleted` → start fresh (no dialog)
   - If session exists and NOT completed → show resume/start over dialog

**Code Sketch**:
```swift
// OnboardingPersistenceService - on interview completion
func markInterviewComplete() async {
    // 1. Persist to CoverRef (existing logic)
    await persistWritingCorpusOnComplete()

    // 2. Delete writing sample artifacts (they're now in CoverRef)
    await deleteWritingSampleArtifacts()

    // 3. Mark session complete
    session.isCompleted = true
}
```

---

## Issue 9: Skills Review Trash Button Not Working

**Problem**: Trash button in interview tab (after merge) doesn't delete skills.

**Investigation Needed**: The pending skills view in `PendingSkillsCollectionView.swift` has trash buttons that call `coordinator.skillStore.delete(skill)`. Need to verify:
1. Is `showDeleteButton` actually true? It requires `isReadyForApproval && !isGenerating`
2. Is the view being passed the correct coordinator?

**Files to Check**:
- `Sprung/Onboarding/Views/Components/PendingSkillsCollectionView.swift`
- Where this view is instantiated in interview tab

**Likely Fix**: Ensure `isReadyForApproval` is true after merge completes. May need to explicitly set this state.

---

## Issue 10: De-dupe and ATS-Expand Buttons in Event Dump View

**Problem**: Need buttons to de-dupe skills and run ATS expansion from event dump view.

**Files to Modify**:
- `Sprung/Onboarding/Views/EventDumpView.swift`
- `Sprung/Onboarding/Services/SkillsProcessingService.swift` - Expose methods

**Changes**:
Add two buttons in the debug actions section:

```swift
Button("Dedupe Skills") {
    Task {
        await coordinator.deduplicateSkills()
    }
}

Button("ATS Expand Skills") {
    Task {
        await coordinator.atsExpandSkills()
    }
}
```

---

## Issue 11: Skills Agent MAX_TOKENS + Retry Mechanism

**Problem**: Skills agent failed with MAX_TOKENS error (65536 tokens wasn't enough). Need:
1. Chunking strategy to handle large skill sets
2. Retry button in UI for failed agents

**Root Cause Analysis**:
The skills deduplication sends ALL skills in a single LLM call. With very large skill sets (100+ skills from multiple documents), the output exceeds 65536 tokens.

**Files to Modify**:
- `Sprung/Onboarding/Services/SkillsProcessingService.swift` - Add chunked processing
- `Sprung/Onboarding/Views/Components/AgentsTabContent.swift` - Add Retry button
- `Sprung/Onboarding/Core/AgentActivityTracker.swift` - Store retry config

**Changes**:

### Part A: Chunked Skills Processing

Modify deduplication to process skills in chunks of ~100:

```swift
// SkillsProcessingService.swift
private let chunkSize = 100

func deduplicateSkills(_ skills: [Skill]) async throws -> [Skill] {
    guard skills.count > chunkSize else {
        // Small enough for single call
        return try await deduplicateSingleBatch(skills)
    }

    // Chunk into groups of 100
    var chunks = skills.chunked(into: chunkSize)
    var results: [[Skill]] = []

    // Process each chunk
    for (index, chunk) in chunks.enumerated() {
        Logger.info("🔧 Processing skill chunk \(index + 1)/\(chunks.count)", category: .ai)
        let deduped = try await deduplicateSingleBatch(chunk)
        results.append(deduped)
    }

    // Final pass: dedupe across chunk results (if needed)
    let combined = results.flatMap { $0 }
    if combined.count > chunkSize {
        // Do a final merge pass with chunk representatives
        return try await deduplicateSingleBatch(combined)
    }
    return combined
}
```

Also add instruction to LLM prompt for skills processing:
```
When the skill list is very large, process in batches. Output no more than 100 skills per response to avoid token limits. If there are more skills to process, indicate this in your response.
```

### Part B: Retry Button in UI

1. Add "Retry" button in `AgentTranscriptView` for failed agents
2. Store agent configuration in `TrackedAgent` so it can be retried
3. Implement `retryAgent(agentId:)` that re-runs the agent

**Code Sketch**:
```swift
// TrackedAgent - add retry configuration
struct TrackedAgent {
    // ... existing fields
    var retryConfiguration: AgentRetryConfig?
}

struct AgentRetryConfig {
    let agentType: AgentType
    let parameters: [String: Any]  // Captured at agent start
}

// AgentTranscriptView - for failed agents
if agent.status == .failed {
    HStack {
        Text(agent.error ?? "Unknown error")
            .foregroundColor(.red)
        Button("Retry") {
            Task {
                await coordinator.retryAgent(agent.id)
            }
        }
        .buttonStyle(.borderedProminent)
    }
}

// OnboardingInterviewCoordinator
func retryAgent(_ agentId: String) async {
    guard let agent = agentActivityTracker.agents.first(where: { $0.id == agentId }),
          let config = agent.retryConfiguration else {
        Logger.warning("⚠️ Cannot retry - no configuration found", category: .ai)
        return
    }

    // Reset agent status
    agentActivityTracker.resetForRetry(agentId: agentId)

    // Re-run based on agent type
    switch config.agentType {
    case .skillsProcessing:
        await knowledgeCardWorkflowService.retrySkillsProcessing()
    case .cardMerge:
        await knowledgeCardWorkflowService.retryCardMerge()
    // ... other types
    }
}
```

---

## Issue 12: KC Regeneration Duplicates

**Problem**: When KCs are regenerated for an artifact:
- The artifact's `narrativeCardsJSON` IS replaced (correct)
- But the OLD persisted KC objects in `KnowledgeCardStore` remain
- When user approves NEW pending KCs, they are APPENDED to the store
- Result: duplicates (old + new)

**Clarification**: The issue is NOT at regeneration time, but at APPROVAL time. Old stored KCs should be deleted when approving new ones that replace them.

**Files to Modify**:
- `Sprung/Onboarding/Services/KnowledgeCardWorkflowService.swift` - Delete old KCs on approval

**Current Flow (broken)**:
```
1. Artifact has KCs → extracted to narrativeCardsJSON
2. "Done with Uploads" → KCs merged, added to store as isPending=true
3. User approves → isPending=false, KCs now permanent
4. User regenerates artifact → new KCs in narrativeCardsJSON
5. "Dedupe/Merge" from event dump → new KCs added as isPending=true
6. User approves → NEW KCs appended, OLD KCs still there → DUPLICATES
```

**Correct Flow**:
```
1-3. Same as above
4. User regenerates artifact → new KCs in narrativeCardsJSON
5. "Dedupe/Merge" → Before adding new pending KCs:
   - Identify which artifacts are being merged
   - Delete old stored KCs from those artifacts
   - Then add new pending KCs
6. User approves → Only new KCs exist
```

**Changes**:

In `KnowledgeCardWorkflowService.handleDoneWithUploadsClicked()` or wherever merge is triggered:

```swift
// BEFORE adding new pending cards, delete old cards from affected artifacts
func handleMergeKnowledgeCards() async {
    // Get artifact IDs that will contribute to this merge
    let artifactIds = await cardMergeService.getArtifactIdsWithCards()

    // Delete any existing (non-pending) KCs from these artifacts
    for artifactId in artifactIds {
        knowledgeCardStore.deleteCardsFromArtifact(artifactId)
    }

    // Clear pending cards (already done)
    knowledgeCardStore.deletePendingCards()

    // Now proceed with merge and add new pending cards
    let allCards = await cardMergeService.getAllNarrativeCardsFlat()
    // ... rest of merge logic
}
```

**Alternative - Delete on Approval**:

If we want to be more conservative, delete old KCs only when user clicks "Approve":

```swift
func approveKnowledgeCards() {
    let pendingCards = knowledgeCardStore.pendingKnowledgeCards

    // Get artifact IDs from pending cards
    let artifactIds = Set(pendingCards.flatMap { card in
        card.evidenceAnchors.map { $0.documentId }
    })

    // Delete old (non-pending) cards from those artifacts
    for artifactId in artifactIds {
        // This deletes cards where isPending=false
        knowledgeCardStore.deleteNonPendingCardsFromArtifact(artifactId)
    }

    // Now approve pending cards (sets isPending=false)
    knowledgeCardStore.approveAllPendingCards()
}
```

---

## Issue 13: Web Extraction Agent (URL → Artifact Pipeline)

**Problem**: User provides URLs in profile but they're not automatically processed. Need a full URL→artifact pipeline similar to how `DocumentProcessingService` handles PDFs.

**Discovery**:
- `CreateWebArtifactTool` already exists but only creates artifact record - doesn't run KC/skill extraction
- `DocumentProcessingService` has `generateSkills()` and `generateNarrativeCards()` methods that only need `artifactId`, `filename`, and `extractedText` - no file needed
- We can reuse these methods for web artifacts

**Solution**: Create a `WebExtractionAgent` tool/service that:
1. LLM calls it with a URL
2. Agent fetches URL content (using existing `WebResourceService`)
3. Creates artifact with fetched content
4. Runs KC and skill extraction (reusing `DocumentProcessingService` methods)
5. Results flow into normal merge pipeline

**Files to Create/Modify**:
- `Sprung/Onboarding/Services/WebExtractionService.swift` (new) - Orchestrates web → artifact flow
- `Sprung/Onboarding/Tools/Implementations/ExtractWebContentTool.swift` (new or modify `CreateWebArtifactTool`)
- `Sprung/Onboarding/Services/DocumentProcessingService.swift` - Expose KC/skill generation for web content

**Changes**:

### Part A: Expose KC/Skill Generation for External Content

Add method to `DocumentProcessingService` that takes already-extracted text:

```swift
// DocumentProcessingService.swift
/// Process pre-extracted content (for web artifacts, pasted text, etc.)
func processExtractedContent(
    artifactId: String,
    filename: String,
    extractedText: String,
    documentType: String,
    statusCallback: (@Sendable (String) -> Void)? = nil
) async throws -> (skills: [Skill]?, narrativeCards: [KnowledgeCard]?, summary: DocumentSummary?) {

    let isWritingSample = documentType == "writing_sample"

    if isWritingSample {
        return (nil, nil, nil)
    }

    // Run extraction in parallel (same as processDocument)
    async let skillsTask = generateSkills(artifactId: artifactId, filename: filename, extractedText: extractedText)
    async let cardsTask = generateNarrativeCards(artifactId: artifactId, filename: filename, extractedText: extractedText)
    async let summaryTask = generateSummary(extractedText: extractedText, filename: filename, facade: llmFacade)

    let (skills, cards, summary) = await (skillsTask, cardsTask, summaryTask)
    return (skills, cards, summary)
}
```

### Part B: Web Extraction Service (Sequential Steps)

The service should follow the same pattern as document processing - explicit sequential steps:

```swift
// WebExtractionService.swift
actor WebExtractionService {
    private let webResourceService: WebResourceService
    private let documentProcessingService: DocumentProcessingService
    private let artifactRecordStore: ArtifactRecordStore
    private let eventBus: EventCoordinator
    private let agentActivityTracker: AgentActivityTracker

    /// Full pipeline: URL → Verbatim Capture → KC Extraction → Skill Extraction
    func extractFromURL(
        _ urlString: String,
        documentType: String = "web_content",
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> ArtifactRecord {
        guard let url = URL(string: urlString) else {
            throw WebExtractionError.invalidURL
        }

        let agentId = UUID().uuidString
        agentActivityTracker.trackAgent(id: agentId, type: .webExtraction, name: "Web Extraction")
        agentActivityTracker.markRunning(agentId: agentId)

        do {
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // STEP 1: VERBATIM CAPTURE - Fetch and store raw content
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            statusCallback?("Fetching web content...")
            agentActivityTracker.updateStatus(agentId: agentId, message: "Fetching \(url.host ?? "URL")...")

            let content = try await webResourceService.fetchPage(url)
            Logger.info("🌐 Fetched \(content.text.count) characters from \(urlString)", category: .ai)

            // Create artifact with verbatim content
            let artifactId = UUID()
            let filename = "web_\(documentType)_\(artifactId.uuidString.prefix(8)).txt"

            let artifact = ArtifactRecord(
                id: artifactId,
                filename: filename,
                sourceType: "web_content",
                extractedContent: content.text,
                sourceURL: urlString,
                ingestedAt: Date()
            )

            // Save artifact immediately (verbatim capture complete)
            await MainActor.run {
                artifactRecordStore.add(artifact)
            }
            await eventBus.publish(.artifact(.recordProduced(record: artifact.toJSON())))

            Logger.info("📄 Artifact created: \(artifactId)", category: .ai)
            agentActivityTracker.appendTranscript(
                agentId: agentId,
                entryType: .toolResult,
                content: "Verbatim capture complete",
                details: "\(content.text.count) characters saved"
            )

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // STEP 2: NARRATIVE KC EXTRACTION
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            statusCallback?("Extracting knowledge cards...")
            agentActivityTracker.updateStatus(agentId: agentId, message: "Extracting knowledge cards...")

            let narrativeCards = await documentProcessingService.generateNarrativeCards(
                artifactId: artifactId.uuidString,
                filename: filename,
                extractedText: content.text
            )

            // Update artifact with KCs
            await MainActor.run {
                artifact.narrativeCardsJSON = narrativeCards?.toJSON()
            }

            let kcCount = narrativeCards?.count ?? 0
            Logger.info("📚 Extracted \(kcCount) knowledge cards", category: .ai)
            agentActivityTracker.appendTranscript(
                agentId: agentId,
                entryType: .toolResult,
                content: "KC extraction complete",
                details: "\(kcCount) narrative cards"
            )

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // STEP 3: SKILL EXTRACTION
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            statusCallback?("Extracting skills...")
            agentActivityTracker.updateStatus(agentId: agentId, message: "Extracting skills...")

            let skills = await documentProcessingService.generateSkills(
                artifactId: artifactId.uuidString,
                filename: filename,
                extractedText: content.text
            )

            // Update artifact with skills
            await MainActor.run {
                artifact.skillsJSON = skills?.toJSON()
            }

            let skillCount = skills?.count ?? 0
            Logger.info("🔧 Extracted \(skillCount) skills", category: .ai)
            agentActivityTracker.appendTranscript(
                agentId: agentId,
                entryType: .toolResult,
                content: "Skill extraction complete",
                details: "\(skillCount) skills"
            )

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // COMPLETE
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            statusCallback?("Web extraction complete")
            agentActivityTracker.markCompleted(agentId: agentId)

            Logger.info("✅ Web extraction complete: \(kcCount) KCs, \(skillCount) skills", category: .ai)
            return artifact

        } catch {
            agentActivityTracker.markFailed(agentId: agentId, error: error.localizedDescription)
            throw error
        }
    }
}
```

This follows the same pattern as `DocumentProcessingService.processDocument()`:
1. **Verbatim capture** - Fetch and store raw content immediately
2. **Narrative KC extraction** - LLM call to extract knowledge cards
3. **Skill extraction** - LLM call to extract skills

Each step updates the artifact, so partial progress is preserved even if later steps fail.

### Part C: LLM Tool

Either modify existing `CreateWebArtifactTool` or create new `ExtractWebContentTool`:

```swift
// ExtractWebContentTool.swift
struct ExtractWebContentTool: InterviewTool {
    var name: String { "extract_web_content" }
    var description: String {
        """
        Fetch a URL and create an artifact with full knowledge card and skill extraction.
        Use this for websites, LinkedIn profiles, portfolios, etc. that should be analyzed
        like uploaded documents.
        """
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let url = params["url"].string else {
            return ToolResultHelpers.invalidParameters("url is required")
        }

        let documentType = params["document_type"].string ?? "web_content"

        // This runs in background
        Task {
            do {
                let artifact = try await webExtractionService.extractFromURL(url, documentType: documentType)
                Logger.info("✅ Web extraction complete: \(artifact.id)", category: .ai)
            } catch {
                Logger.error("❌ Web extraction failed: \(error)", category: .ai)
            }
        }

        // Return immediately - extraction happens in background
        var response = JSON()
        response["status"].string = "processing"
        response["message"].string = "Web content extraction started for \(url). Knowledge cards and skills will be extracted automatically."
        return .immediate(response)
    }
}
```

### Part D: Profile URL Auto-Fetch

In `ProfileInteractionHandler`, after profile is validated:

```swift
private func triggerProfileURLFetch(draft: ApplicantProfileDraft) async {
    var urlsToExtract: [(label: String, url: String)] = []

    if !draft.website.isEmpty {
        urlsToExtract.append(("personal_website", draft.website))
    }

    for profile in draft.socialProfiles where !profile.url.isEmpty {
        let type = profile.network.lowercased().contains("linkedin") ? "linkedin_profile" : "social_profile"
        urlsToExtract.append((type, profile.url))
    }

    // Launch extraction for each URL
    for (documentType, url) in urlsToExtract {
        Task {
            do {
                try await webExtractionService.extractFromURL(url, documentType: documentType)
            } catch {
                Logger.warning("⚠️ Failed to extract \(documentType): \(error)", category: .ai)
            }
        }
    }
}
```

**Integration**: Once artifact is created with KCs/skills, it automatically flows into the merge pipeline when user clicks "Done with Uploads".

---

## Implementation Order

**Phase 1 - Quick Wins** (can be done independently, low risk):
1. Issue 3: LLM prompt update for Phase 1 & 2 (prompt only)
2. Issue 7: Remove redundant "Include identity title set" checkbox (UI only)
3. Issue 6: Timeline tab auto-focus on tool use (simple onChange)

**Phase 2 - Core Bug Fixes** (address root causes):
4. Issue 1 + 2: Merge agent duplicate + delay (pass parentAgentId, register earlier)
5. Issue 12: KC regeneration duplicates (delete old KCs before approval)
6. Issue 9: Skills trash button (investigate `isReadyForApproval` state)

**Phase 3 - Queue & Stop System** (related changes):
7. Issue 4: Queued messages display (dimmed + icon, cancelable)
8. Issue 5: Stop command (drain queue, clean orphans, silence incoming)

**Phase 4 - Event Dump & Agent Improvements**:
9. Issue 10: De-dupe and ATS-expand buttons in event dump
10. Issue 11: Skills agent chunking + retry mechanism

**Phase 5 - New Features**:
11. Issue 8: Interview completion state + writing samples cleanup
12. Issue 13: Web extraction agent (URL → artifact → KC/skill pipeline)

---

## Summary of Key Changes

| Issue | Root Cause | Fix |
|-------|------------|-----|
| Duplicate status bar | `parentAgentId` not passed to deduplication | Pass ID through call chain |
| LLM asks specifics | Prompt not explicit enough | Add stronger prohibitions to P1 & P2 |
| Skills MAX_TOKENS | All skills in single LLM call | Chunk into groups of ~100 |
| KC duplicates | Old KCs not deleted on re-merge | Delete old KCs before approval |
| Stop command | No way to silence after cancel | Add `isStopped` flag, check before processing |
| Web artifacts | No KC/skill extraction | Reuse `DocumentProcessingService` methods |

---

## Questions Resolved

| Question | Answer |
|----------|--------|
| Queued message styling | Dimmed + clock icon, cancelable optional |
| Stop vs Interrupt | Separate button, cleans orphan tool calls, silences incoming |
| Writing samples deletion | On interview completion + Start Over |
| Custom fields checkbox | Remove it (redundant) |
| Website fetch approach | Web extraction agent with full KC/skill pipeline |
| Skills trash location | Interview tab after merge - investigate `isReadyForApproval` |
| Phase 2 prompts | Also add admonishment against asking specifics |
| Skills MAX_TOKENS | Chunk processing in groups of ~100 |
| KC extraction for web | Reuse existing `generateSkills()`/`generateNarrativeCards()` methods |
