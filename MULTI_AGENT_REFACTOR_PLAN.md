# Plan: Token-Efficient Multi-Agent Onboarding Architecture

## Getting Started (For New Session)

### Before You Begin

1. **Create a new branch**:
   ```bash
   git checkout -b feature/multi-agent-onboarding
   ```

2. **Commit regularly** - Make atomic commits after completing each logical unit of work. Don't wait until the end.

3. **Read these files first** to understand the current architecture:

#### Core Architecture (READ FIRST)
- `Sprung/Onboarding/Core/StateCoordinator.swift` - Central state management (single-agent design)
- `Sprung/Onboarding/Core/LLMStateManager.swift` - LLM state tracking (responseId, tool gating)
- `Sprung/Onboarding/Core/OnboardingEvents.swift` - Event definitions and EventCoordinator
- `Sprung/Onboarding/Core/ArtifactRepository.swift` - Artifact storage (will add summary field)

#### Tool Execution (Critical for Sub-Agent Design)
- `Sprung/Onboarding/Tools/ToolExecutor.swift` - How tools are executed
- `Sprung/Onboarding/Handlers/ToolExecutionCoordinator.swift` - Tool call routing
- `Sprung/Onboarding/Tools/Implementations/GetArtifactTool.swift` - Artifact retrieval pattern

#### Existing Isolated Agent Pattern (Reference Implementation)
- `Sprung/Onboarding/Services/GitIngestionKernel.swift` - Already uses isolated Tasks
- `Sprung/Onboarding/Services/GitAgent/GitAnalysisAgent.swift` - Isolated conversation pattern

#### Phase 2 Workflow (Being Modified)
- `Sprung/Onboarding/Phase/PhaseTwoScript.swift` - Current Phase 2 prompts
- `Sprung/Onboarding/Tools/Implementations/StartPhaseTwoTool.swift` - Phase 2 bootstrap
- `Sprung/Onboarding/Tools/Implementations/SubmitKnowledgeCardTool.swift` - Card persistence

#### Document Ingestion (Being Enhanced)
- `Sprung/Onboarding/Services/ArtifactIngestionCoordinator.swift` - Current ingestion flow
- `Sprung/Shared/AI/Services/GoogleAIService.swift` - Gemini integration (add summarization)
- `Sprung/Onboarding/Handlers/DocumentArtifactMessenger.swift` - Sends docs to LLM

#### UI Components (Adding Agent Tabs)
- `Sprung/Onboarding/Views/Components/OnboardingInterviewToolPane.swift` - Tool pane tabs
- `Sprung/Onboarding/Core/OnboardingUIState.swift` - UI state management

---

## Executive Summary

**Problem**: >12M input tokens due to 200K+ in raw documents sent to main conversation, accumulating via `previous_response_id`.

**Solution**: Multi-agent architecture with parallel processing and disposable threads.

**Key Principles**:
1. **Summarize during ingestion** - Gemini Flash-Lite generates summaries, stored in artifact
2. **Main coordinator sees only summaries** - lightweight context (~2K vs 200K)
3. **KC agents run in parallel** - disposable threads with full doc access
4. **Explicit gaps assessment** - coordinator identifies missing docs after initial review
5. **Docs can serve multiple cards** - one doc → multiple KC assignments

---

## Architectural Assessment: Current Single-Agent Design

### Critical Finding

**The current onboarding architecture is fundamentally single-agent by design.** Key blockers identified:

| Component | Blocker | Location |
|-----------|---------|----------|
| LLMStateManager | Single `lastResponseId`, `pendingUIToolCall` | `LLMStateManager.swift:10-23` |
| StreamQueueManager | Single serial queue, global batch tracking | `StreamQueueManager.swift:10-15` |
| StateCoordinator | Single `phase`, `dossierTracker`, `excludedTools` | `StateCoordinator.swift:24-30` |
| CoordinatorEventRouter | Single `pendingKnowledgeCard` | `CoordinatorEventRouter.swift:20-21` |
| OnboardingUIState | Single timeline, message list, phase | `OnboardingUIState.swift:10-25` |
| Event schema | No `agentId` in events | `OnboardingEvents.swift` |
| ToolExecutionCoordinator | Global `waitingState` blocks all tools | `ToolExecutionCoordinator.swift` |

### Architectural Constraint

**Sub-agents CANNOT share the main coordinator's infrastructure.** They must be completely isolated:

```
┌─────────────────────────────────────────────────────────────────┐
│  MAIN COORDINATOR (existing single-agent infrastructure)        │
│  ├── EventCoordinator (main only)                               │
│  ├── StateCoordinator (main only)                               │
│  ├── StreamQueueManager (main only)                             │
│  ├── ToolExecutor (main only) - UI tools, phase tools           │
│  ├── OnboardingUIState (main only)                              │
│  └── ArtifactRepository (SHARED - read OK, write via main only) │
└─────────────────────────────────────────────────────────────────┘
         │                                          ▲
         │ dispatch                                 │ results returned
         ▼                                          │
┌─────────────────────────────────────────────────────────────────┐
│  SUB-AGENTS (completely isolated from main infrastructure)      │
│                                                                 │
│  Each sub-agent has:                                            │
│  ├── Own AgentRunner (manages LLM conversation loop)            │
│  ├── Own responseId chain (never touches main's)                │
│  ├── Own message history (built locally)                        │
│  ├── Own SubAgentToolExecutor (limited tool set)                │
│  │   ├── get_artifact → reads from shared repo (safe)           │
│  │   └── Returns JSON results (does NOT persist directly)       │
│  └── Transcript logged to AgentActivityTracker                  │
│                                                                 │
│  Sub-agents DO NOT:                                             │
│  ✗ Emit events to main EventCoordinator                         │
│  ✗ Call UI tools (get_user_option, get_user_upload)             │
│  ✗ Write directly to ArtifactRepository                         │
│  ✗ Share StreamQueueManager or batch tracking                   │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow Pattern

```
1. Main Coordinator calls dispatch_kc_agents tool
2. Tool spawns AgentRunner instances (parallel Tasks)
3. Each AgentRunner:
   - Creates fresh OpenAI conversation (no previous_response_id)
   - Runs isolated tool calls (get_artifact reads only)
   - Builds knowledge card in memory
   - Returns completed card JSON to caller
4. dispatch_kc_agents collects all results (failed agents don't spoil batch)
5. Main Coordinator persists cards via its own ArtifactRepository access
6. UI updated through main coordinator's event bus
```

This architecture respects the single-agent design of the main coordinator while allowing parallel sub-agents that are completely isolated.

### What We're Actually Building (Clarified)

**Two complementary changes that work together:**

#### Part A: Token Reduction (Primary Goal - Solves the 12M Token Problem)

| Step | What | Token Impact |
|------|------|--------------|
| 1. Summarize during ingestion | Gemini Flash-Lite generates ~500 word summary per doc | Stored in artifact |
| 2. Main coordinator sees summaries | Not full 50K document text | 200K → ~10K |
| 3. Tool-based full retrieval | `get_artifact(id)` returns full text on demand | Only when needed |
| 4. KC agent conversations isolated | Don't accumulate in main thread | Prevents unbounded growth |

**This alone solves the token problem** even without parallelization.

#### Part B: Parallel Processing (Efficiency Goal - Faster Completion)

| Step | What | Latency Impact |
|------|------|----------------|
| 1. Parallelize doc ingestion | Multiple docs extract+summarize simultaneously | 5 docs: 5min → 1min |
| 2. Parallelize git ingestion | Non-blocking adds, runs alongside doc ingestion | No waiting |
| 3. Offload KC generation | Parallel sub-agents with isolated conversations | 10 cards: 20min → 4min |

**These work together:**
- Summaries make it practical to show coordinator ALL docs at once (fits in context)
- Coordinator assigns docs to cards intelligently
- KC agents get summaries + can fetch full text as needed
- Each KC agent's conversation dies when card completes (no accumulation)

### Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Sub-agent reads stale artifact data** | Low | ArtifactRepository is actor-isolated; reads are consistent at point in time |
| **Main coordinator overwhelmed by parallel results** | Medium | Results collected by `dispatch_kc_agents` tool before returning; main coordinator processes sequentially |
| **Sub-agent fails silently** | High | AgentActivityTracker monitors all tasks; errors surfaced in Agent Tabs UI |
| **Race condition on artifact writes** | Low | Only main coordinator writes; sub-agents return data, don't persist |
| **OpenAI rate limits hit** | Medium | Configurable parallelism limit (default 3 concurrent KC agents) |
| **Single KC agent failure** | Medium | Failed agents don't spoil batch - collect successful cards, report failures separately |
| **Memory pressure from parallel agents** | Medium | Each agent's transcript stored incrementally; completed agents can be pruned |
| **User confusion about parallel activity** | Low | Agent Tabs UI shows all activity with status; main chat explains what's happening |

### What We're NOT Changing

To minimize risk, these components remain unchanged:
- Main coordinator's event bus, state management, UI state
- Existing tool registration and execution for main conversation
- Phase management and objective tracking
- Chat transcript storage and display
- Session persistence and restoration

The new multi-agent capability is **additive** - it doesn't modify the core single-agent architecture.

---

## New Phase 2 Workflow

### Phase 2A: Parallel Ingestion (Docs + Git Repos)

**CRITICAL REQUIREMENTS**:
1. Doc ingestion runs in parallel (multiple docs simultaneously)
2. Git ingestion runs in parallel with doc ingestion
3. Multiple git repos can be added in sequence (non-blocking add)
4. All parallel tasks monitored with error handling (no silent failures)

```
┌─────────────────────────────────────────────────────────────────┐
│  PARALLEL INGESTION ORCHESTRATOR                                │
│                                                                 │
│  ┌─────────────────────────────────┐  ┌─────────────────────────┐
│  │  DOC INGESTION POOL             │  │  GIT INGESTION POOL     │
│  │  ┌──────┐ ┌──────┐ ┌──────┐    │  │  ┌──────┐ ┌──────┐     │
│  │  │Doc A │ │Doc B │ │Doc C │    │  │  │Repo 1│ │Repo 2│     │
│  │  │Extr. │ │Extr. │ │Extr. │    │  │  │Agent │ │Agent │     │
│  │  │Summ. │ │Summ. │ │Summ. │    │  │  │      │ │      │     │
│  │  └──────┘ └──────┘ └──────┘    │  │  └──────┘ └──────┘     │
│  └─────────────────────────────────┘  └─────────────────────────┘
│                                                                 │
│  TASK MONITOR: Tracks all active tasks, surfaces errors         │
└─────────────────────────────────────────────────────────────────┘
```

**Git Repo Add Flow (non-blocking)**:
```swift
// OLD: Blocking - can't add second repo while first processes
func addGitRepo(url: URL) async throws -> Result

// NEW: Non-blocking - returns immediately, task tracked
func addGitRepo(url: URL) -> PendingTask {
    let task = PendingTask(id: UUID(), type: .gitIngest, name: url.lastPathComponent)
    taskMonitor.track(task)
    Task { await processGitRepo(url, taskId: task.id) }
    return task  // UI can immediately accept another repo
}
```

**During ingestion**: Coordinator works dossier questions (existing pattern preserved)

### Existing Git Ingestion: Already Aligned

**Good news**: `GitIngestionKernel` is already an actor with isolated task tracking:

```swift
// GitIngestionKernel.swift - ALREADY EXISTS
actor GitIngestionKernel: ArtifactIngestionKernel {
    private var activeTasks: [String: Task<Void, Never>] = [:]  // Already tracks parallel tasks

    func startIngestion(...) async throws -> PendingArtifact {
        let task = Task { [weak self] in
            await self.analyzeRepository(...)  // Already runs in isolated Task
        }
        activeTasks[pendingId] = task
        return pending
    }
}
```

**What needs to change for non-blocking adds**:
1. Currently `startIngestion` is called via event, but UI waits for response
2. Need to make folder selection immediately dismiss and allow another selection
3. Task tracking already exists - just need UI to not block on first task

**Git Analysis Agent already isolated**:
- `GitAnalysisAgent` runs in its own conversation thread
- Has own `modelId` from settings
- Returns `GitAnalysisResult` to kernel
- Kernel then notifies coordinator via `handleIngestionCompleted`

**Pattern to replicate for KC agents**:
- KC agents should follow same pattern as GitAnalysisAgent
- Isolated conversation, returns result, main coordinator persists

### Phase 2B: Document Assignment & Gaps Assessment
```
┌─────────────────────────────────────────────────────────────────┐
│  COORDINATOR (sees summaries only, uses previous_response_id)   │
│                                                                 │
│  Has: skeleton_timeline + all artifact summaries                │
│                                                                 │
│  1. Reviews all summaries against timeline entries              │
│  2. Proposes card assignments:                                  │
│     "Doc A (resume) → Job X, Job Y, Skills"                     │
│     "Doc B (perf review) → Job X"                               │
│     "Doc C (project doc) → Project Z"                           │
│  3. GAPS ASSESSMENT: "I notice no documentation for Job W       │
│     or the 2019-2021 period. Do you have any docs for these?"   │
│  4. User provides more docs → repeat ingestion                  │
│  5. When ready, dispatches KC agents                            │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 2C: Parallel Knowledge Card Generation
```
┌─────────────────────────────────────────────────────────────────┐
│  PARALLEL KC AGENTS (disposable threads)                        │
│                                                                 │
│  Each agent receives:                                           │
│  • Card proposal (timeline entry + type)                        │
│  • Assigned artifact IDs (can fetch full text)                  │
│  • ALL artifact summaries (can request additional docs)         │
│                                                                 │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │ KC Agent 1  │ │ KC Agent 2  │ │ KC Agent 3  │               │
│  │ Job X Card  │ │ Job Y Card  │ │ Project Z   │               │
│  │             │ │             │ │             │               │
│  │ get_artifact│ │ get_artifact│ │ get_artifact│               │
│  │ for full    │ │ for full    │ │ for full    │               │
│  │ doc text    │ │ doc text    │ │ doc text    │               │
│  │             │ │             │ │             │               │
│  │ Can request │ │ Can request │ │ Can request │               │
│  │ more docs   │ │ more docs   │ │ more docs   │               │
│  │ from summary│ │ from summary│ │ from summary│               │
│  │ list        │ │ list        │ │ list        │               │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘               │
│         │              │              │                         │
│         ▼              ▼              ▼                         │
│    Card returned   Card returned   Card returned                │
│    Thread dies     Thread dies     Thread dies                  │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 2D: LLM Coordinator Validates & Persists
```
┌─────────────────────────────────────────────────────────────────┐
│  MAIN LLM COORDINATOR receives cards from dispatch_kc_agents    │
│                                                                 │
│  1. Reviews returned cards for completeness/quality             │
│  2. Identifies gaps or overlaps between cards                   │
│  3. For each valid card: calls submit_knowledge_card            │
│     → Flows through existing event system                       │
│     → UI updates automatically                                  │
│  4. For incomplete cards: may spawn new KC agent with feedback  │
│  5. When all cards persisted → Phase 3                          │
│                                                                 │
│  NOTE: No user validation step - LLM coordinator is the gate    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Agent Visibility UI

New **Tool Pane Tab** for agent management with list-detail pattern:

**Features**:
- List box showing all running/completed agents
- Selecting an agent displays its full transcript
- Kill button for running agents
- Status indicators (running/complete/failed)
- Agent type labels (Doc Ingest, Git Ingest, KC Agent)

```
┌─────────────────────────────────────────────────────────────────┐
│  [Timeline] [Artifacts] [Agents] [Debug]           Tool Pane    │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────┐                            │
│  │ 🔄 Doc: resume.pdf              │  ← List of all agents      │
│  │ ✓  Doc: perf_review.pdf         │                            │
│  │ 🔄 Git: MyProject               │                            │
│  │ ✓  KC: Senior Engineer @ X      │  ← Selected                │
│  │ 🔄 KC: Project Lead @ Y         │                            │
│  └─────────────────────────────────┘                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ KC Agent: Senior Engineer @ Company X            [Kill ✕]  ││
│  │ Status: Complete ✓                                         ││
│  │ Duration: 12.3s                                            ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │ TRANSCRIPT:                                                ││
│  │                                                            ││
│  │ [System] Card proposal: Senior Engineer at Company X       ││
│  │ [System] Assigned docs: resume.pdf, perf_2023.pdf          ││
│  │ [Tool] get_artifact("doc_123") → 48,230 chars              ││
│  │ [Tool] get_artifact("doc_456") → 12,100 chars              ││
│  │ [Assistant] Analyzing role scope and achievements...       ││
│  │ [Tool] submit_card({...}) → Success                        ││
│  │                                                            ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

**Agent List Item States**:
- 🔄 Running (animated spinner)
- ✓ Complete (green checkmark)
- ✕ Failed (red X, shows error on select)
- ⏹ Killed (grey, user-cancelled)

### Activity Indicators (Rethinking for Parallel)

**Current state** (single-agent assumption):
- `OnboardingUIState.isProcessing: Bool` - single flag
- Chat input glow when processing
- Single spinner

**New approach** (parallel-aware):

```swift
// In OnboardingUIState or AgentActivityTracker
struct ProcessingState {
    var mainCoordinatorActive: Bool = false
    var activeAgentCount: Int = 0  // KC agents, git agents, doc ingest
    var activeAgentTypes: Set<AgentType> = []

    var isAnyProcessing: Bool {
        mainCoordinatorActive || activeAgentCount > 0
    }

    var statusSummary: String {
        if mainCoordinatorActive && activeAgentCount == 0 {
            return "Processing..."
        } else if activeAgentCount > 0 {
            let types = activeAgentTypes.map(\.displayName).joined(separator: ", ")
            return "\(activeAgentCount) background tasks (\(types))"
        }
        return ""
    }
}
```

**UI Changes**:
| Element | Current | New |
|---------|---------|-----|
| Chat input glow | On when `isProcessing` | On when `mainCoordinatorActive` |
| Spinner | Single | Badge showing count: "⏳ 3" |
| Status text | "Processing..." | "Processing... (3 background tasks)" |
| Agent Tabs badge | N/A | Shows count of running agents |

**Key insight**: Chat glow should only indicate MAIN coordinator activity (user is waiting for response). Background agents shouldn't glow the chat - they're shown in Agent Tabs instead.

**Transcript View**:
- Shows all messages in the agent's conversation thread
- Tool calls with arguments and response summaries
- Reasoning/thinking blocks (collapsed by default)
- Timestamps for performance analysis
- Error details for failed agents

---

## Implementation Changes

### 1. Artifact Model Changes

Add `summary` field to artifact records in `ArtifactRepository`:

```swift
// Current artifact JSON structure
{
  "id": "...",
  "filename": "resume.pdf",
  "content_type": "application/pdf",
  "size_bytes": 123456,
  "sha256": "...",
  "extracted_text": "...",  // Full text (existing)
  "metadata": {...}
}

// NEW: Add summary field
{
  ...
  "summary": "3-page resume for software engineer with 8 years experience at 3 companies. Key skills: Swift, Python, ML. Notable: Led team of 5, shipped 3 major products.",
  "summary_generated_at": "2024-...",
  ...
}
```

**File**: `Sprung/Onboarding/Core/ArtifactRepository.swift`
- Add `summary` to `listArtifactSummaries()`

### 2. Ingestion Pipeline Enhancement

**CRITICAL: Parallelize ingestion** (currently serialized batch uploads)

```swift
// NEW: Parallel ingestion pipeline
func ingestDocuments(_ files: [URL]) async {
    await withTaskGroup(of: ArtifactRecord?.self) { group in
        for file in files {
            group.addTask {
                // Each doc processed independently in parallel
                let extracted = await self.extractText(from: file)
                let summary = await self.summarize(extracted)
                return ArtifactRecord(file: file, text: extracted, summary: summary)
            }
        }
        for await record in group {
            if let record { await store(record) }
        }
    }
}
```

**Two-Call Architecture** (preserve extraction quality):

```
Call 1: Extraction (existing - Gemini 2.0 Flash)
├── Prompt: Verbatim transcription, detailed, inclusive
├── Output: Full content + title (50K+ tokens)
└── Store: artifact.extracted_text

Call 2: Summarization (NEW - Gemini Flash-Lite)
├── Input: extracted_text from Call 1
├── Prompt: Structured 500-word summary
├── Output: Summary + metadata
└── Store: artifact.summary
```

**Why NOT combine into one call**:
- Current extraction prompt emphasizes "errs heavily on inclusion, not abridgement"
- Adding summary instructions would create competing goals
- Risk degrading verbatim transcription quality
- Output limits when trying to do both

**Summarization Model**: Use **Gemini Flash-Lite** (same provider as extraction)
- Simpler: one API key, one SDK
- Context caching: 10% input price if extracted text is cached
- Cost: $0.10/1M input, $0.40/1M output → ~$0.005/doc

**Summarization prompt**:
```
Analyze this document and provide a structured summary for job application context.

Output as JSON:
{
  "document_type": "resume|performance_review|project_doc|job_description|other",
  "summary": "~500 word narrative summary",
  "time_period": "2019-2023" or null,
  "companies": ["Company A", "Company B"],
  "skills": ["Swift", "Python", "Leadership"],
  "achievements": ["Led team of 5", "Shipped 3 products"],
  "relevance_hints": "Covers senior engineering role, strong on technical leadership"
}
```

**Implementation**: Reuse existing `GoogleAIService` for summarization:

```swift
// In ArtifactIngestionCoordinator - after extraction completes
let summary = try await googleAIService.generateSummary(
    content: extractedText,
    modelId: "gemini-2.5-flash-lite"  // Cheaper model for summaries
)
artifact.summary = summary
```

**Files**:
- `Sprung/Onboarding/Services/ArtifactIngestionCoordinator.swift` - Parallelize + add summary step
- `Sprung/Shared/AI/Services/GoogleAIService.swift` - Add `generateSummary()` method
- `Sprung/Onboarding/Core/ArtifactRepository.swift` - Add summary field

### 3. New Phase 2 Bootstrap Tool

Replace/enhance `StartPhaseTwoTool` to support new workflow:

```swift
// start_phase_two now returns:
{
  "timeline_entries": [...],           // From Phase 1
  "artifact_summaries": [              // NEW: All doc summaries
    {
      "id": "doc_123",
      "filename": "resume.pdf",
      "summary": "3-page resume...",
      "content_type": "application/pdf"
    },
    ...
  ],
  "instructions": "Review the timeline and available documents.
                   Propose card assignments and identify gaps..."
}
```

**File**: `Sprung/Onboarding/Tools/Implementations/StartPhaseTwoTool.swift`

### 4. New Tools for Multi-Agent Flow

#### `propose_card_assignments` tool
Coordinator uses this to map docs to cards:
```json
{
  "assignments": [
    {
      "card_id": "uuid1",
      "card_title": "Senior Engineer at Company X",
      "card_type": "job",
      "artifact_ids": ["doc_123", "doc_456"],
      "notes": "Resume covers this role, perf review adds detail"
    }
  ],
  "gaps": [
    {
      "card_id": "uuid2",
      "card_title": "Developer at Startup Y",
      "gap_description": "No documentation found for 2019-2021 period"
    }
  ]
}
```

#### `request_additional_docs` tool
Coordinator asks user for missing docs:
```json
{
  "message": "I notice gaps in documentation for your time at Startup Y (2019-2021). Do you have any of these: performance reviews, project docs, or the job description?",
  "target_cards": ["uuid2"]
}
```

#### `dispatch_kc_agents` tool
Triggers parallel KC generation:
```json
{
  "cards_to_generate": [
    {
      "card_id": "uuid1",
      "card_proposal": {...},
      "assigned_artifacts": ["doc_123", "doc_456"],
      "all_summaries": [...]  // Full summary list for agent reference
    }
  ]
}
```

### 5. KC Agent Implementation

New service: `KnowledgeCardAgentService`

```swift
actor KnowledgeCardAgentService {
    /// Spawns a disposable conversation thread for card generation
    func generateCard(
        proposal: CardProposal,
        assignedArtifacts: [String],
        allSummaries: [ArtifactSummary]
    ) async throws -> KnowledgeCard {
        // 1. Create fresh OpenAI thread (no previous_response_id)
        // 2. Send system prompt for KC generation
        // 3. Include assigned artifact IDs + all summaries
        // 4. Agent can call get_artifact for full text
        // 5. Agent can request additional docs from summary list
        // 6. Returns completed card
        // 7. Thread discarded
    }
}
```

**Files**:
- NEW: `Sprung/Onboarding/Services/KnowledgeCardAgentService.swift`
- NEW: `Sprung/Onboarding/Agents/KCAgentPrompts.swift`

### 5a. Tool Response Routing (Agent Isolation)

**CRITICAL**: With multiple agents running in parallel, tool responses must be routed to the correct requesting agent.

**Architecture: Agent-Scoped Tool Execution**

Each agent operates in complete isolation with its own:
- Conversation thread (unique `responseId`, no `previous_response_id` sharing)
- Tool executor instance
- Response handling

```swift
/// Each agent gets its own isolated execution context
struct AgentExecutionContext {
    let agentId: String
    let agentType: AgentType
    let toolExecutor: ToolExecutor  // Agent-scoped instance
    var responseId: String?  // This agent's conversation thread only

    /// Execute tool and route response back to this agent
    func executeTool(_ call: ToolCall) async throws -> ToolResult {
        let result = try await toolExecutor.execute(call)
        // Result stays within this agent's context
        // Logged to this agent's transcript
        return result
    }
}

/// Agent runner manages isolated execution
actor AgentRunner {
    private let context: AgentExecutionContext
    private let tracker: AgentActivityTracker

    func run() async throws -> AgentOutput {
        while !isComplete {
            // 1. Send to OpenAI with THIS agent's responseId
            let response = try await openai.responses(
                input: messages,
                previousResponseId: context.responseId  // Agent-isolated
            )
            context.responseId = response.id

            // 2. Handle tool calls within THIS agent's context
            for toolCall in response.toolCalls {
                let result = try await context.executeTool(toolCall)
                // Log to THIS agent's transcript
                tracker.appendTranscript(agentId: context.agentId, ...)
                // Add result to THIS agent's message history
                messages.append(toolResult)
            }
        }
    }
}
```

**Key Isolation Points**:

| Component | Isolation Level | Notes |
|-----------|----------------|-------|
| Conversation thread | Per-agent | Each agent has unique `responseId` chain |
| Tool executor | Per-agent | No shared state between agents |
| Message history | Per-agent | Built locally, not from shared source |
| Transcript logging | Per-agent | Routed via `agentId` to correct tracker entry |
| `previous_response_id` | Per-agent | Never shared across agents |

**Sub-Agent Tool Set (Limited)**:

Sub-agents have access to a RESTRICTED tool set that avoids infrastructure conflicts:

| Tool | Sub-Agent Access | Notes |
|------|------------------|-------|
| `get_artifact` | ✅ READ-ONLY | Reads from shared ArtifactRepository (actor-safe) |
| `get_artifact_summary` | ✅ READ-ONLY | Returns summary only |
| `return_knowledge_card` | ✅ NEW | Returns card JSON to AgentRunner (does NOT persist) |
| `get_user_option` | ❌ BLOCKED | Requires UI, sets global waitingState |
| `get_user_upload` | ❌ BLOCKED | Requires UI, sets global waitingState |
| `submit_knowledge_card` | ❌ BLOCKED | Writes to shared state, requires main coordinator |
| `persist_data` | ❌ BLOCKED | Writes to shared state |
| `set_objective_status` | ❌ BLOCKED | Modifies global phase state |
| `next_phase` | ❌ BLOCKED | Modifies global phase state |

**Sub-Agent Tool Implementation**:
```swift
/// Minimal tool executor for isolated sub-agents
actor SubAgentToolExecutor {
    private let artifactRepository: ArtifactRepository  // Read-only access

    func execute(_ call: ToolCall) async throws -> ToolResult {
        switch call.name {
        case "get_artifact":
            // Safe: Actor-isolated read from shared repository
            let artifact = await artifactRepository.getArtifactRecord(id: call.arguments["id"].stringValue)
            return .immediate(artifact ?? JSON.null)

        case "get_artifact_summary":
            let artifact = await artifactRepository.getArtifactRecord(id: call.arguments["id"].stringValue)
            return .immediate(artifact?["summary"] ?? JSON.null)

        case "return_knowledge_card":
            // Returns to AgentRunner, NOT persisted here
            return .immediate(call.arguments)

        default:
            throw SubAgentError.toolNotAvailable(call.name)
        }
    }
}
```

**Why This Works**:
- `get_artifact` reads are actor-isolated - multiple concurrent reads are serialized safely
- No writes to shared state from sub-agents
- No UI tool calls that would conflict with main coordinator's waitingState
- No event emissions that would confuse the main EventCoordinator
- Results returned to main coordinator for persistence (single writer)

**Main Coordinator vs. Sub-Agents**:
```
┌─────────────────────────────────────────────────────────────────┐
│  MAIN COORDINATOR (uses previous_response_id for continuity)    │
│  - Owns the user-facing conversation                            │
│  - Dispatches sub-agents                                        │
│  - Receives results when sub-agents complete                    │
└─────────────────────────────────────────────────────────────────┘
        │ dispatch               │ dispatch              │ dispatch
        ▼                        ▼                       ▼
┌──────────────┐         ┌──────────────┐        ┌──────────────┐
│ KC Agent 1   │         │ KC Agent 2   │        │ Git Agent    │
│ responseId:A │         │ responseId:B │        │ responseId:C │
│ (isolated)   │         │ (isolated)   │        │ (isolated)   │
└──────┬───────┘         └──────┬───────┘        └──────┬───────┘
       │                        │                       │
       ▼                        ▼                       ▼
  Card returned            Card returned           Analysis returned
  to coordinator           to coordinator          to coordinator
```

**Files**:
- NEW: `Sprung/Onboarding/Services/AgentRunner.swift` - Isolated agent execution loop
- NEW: `Sprung/Onboarding/Services/AgentExecutionContext.swift` - Per-agent context
- MODIFY: `Sprung/Onboarding/Tools/ToolExecutor.swift` - Support agent-scoped execution

### 6. Agent Visibility UI

New Tool Pane tab with list-detail agent management:

```swift
/// Tracks all agent activity with full transcript storage
@Observable
class AgentActivityTracker {
    var agents: [TrackedAgent] = []
    var selectedAgentId: String?

    struct TrackedAgent: Identifiable {
        let id: String
        let type: AgentType  // .docIngest, .gitIngest, .knowledgeCard
        let name: String
        var status: AgentStatus  // .running, .complete, .failed, .killed
        var startTime: Date
        var endTime: Date?
        var transcript: [TranscriptEntry] = []
        var error: String?
    }

    struct TranscriptEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let type: EntryType  // .system, .tool, .assistant, .error
        let content: String
        let details: String?  // Tool args, response summary, etc.
    }

    func trackAgent(_ agent: TrackedAgent) { ... }
    func appendTranscript(agentId: String, entry: TranscriptEntry) { ... }
    func markComplete(agentId: String) { ... }
    func markFailed(agentId: String, error: String) { ... }
    func killAgent(agentId: String) async { ... }  // Cancels task + updates status
}

/// Tool pane tab showing agent list + transcript viewer
struct AgentsPaneView: View {
    @Environment(AgentActivityTracker.self) var tracker

    var body: some View {
        HSplitView {
            // Left: Agent list
            AgentListView(agents: tracker.agents,
                         selectedId: $tracker.selectedAgentId)

            // Right: Transcript detail
            if let selected = tracker.selectedAgent {
                AgentTranscriptView(agent: selected,
                                   onKill: { tracker.killAgent(selected.id) })
            } else {
                Text("Select an agent to view transcript")
            }
        }
    }
}
```

**Files**:
- NEW: `Sprung/Onboarding/Core/AgentActivityTracker.swift` - Central tracking + transcript storage
- NEW: `Sprung/Onboarding/Views/Components/AgentsPaneView.swift` - Tool pane tab container
- NEW: `Sprung/Onboarding/Views/Components/AgentListView.swift` - Selectable agent list
- NEW: `Sprung/Onboarding/Views/Components/AgentTranscriptView.swift` - Transcript viewer + kill button

### 7. Updated Phase 2 Script

```swift
// PhaseTwoScript.swift - new workflow stages

### Objectives (revised)
- **docs_ingested**: All uploaded docs have summaries
- **assignments_proposed**: Cards mapped to docs, gaps identified
- **gaps_addressed**: User provided additional docs or confirmed none available
- **cards_generated**: All KC agents completed

### Workflow
1. START: Call `start_phase_two` → get timeline + summaries
2. If no docs: prompt for bulk upload, work dossier questions while waiting
3. Review summaries, call `propose_card_assignments`
4. If gaps: call `request_additional_docs`, wait for user
5. When ready: call `dispatch_kc_agents` for parallel generation
6. Review returned cards with user
7. next_phase when approved
```

### 8. Local Prompting Patterns (Preserve & Adapt)

**Current Pattern** (from `CoordinatorEventRouter.handleDoneButtonClicked`):
```swift
// When user clicks "Done with this card":
1. Ungate submit_knowledge_card tool
2. Inject system-generated user message: "I'm done with the 'X' card..."
3. Force toolChoice to submitKnowledgeCard
→ LLM immediately generates and submits card
```

**New Pattern for Multi-Agent Flow**:

The "Done" button meaning changes:
- **Old**: "I'm done providing info, generate the card now"
- **New**: "I'm done uploading docs, dispatch KC agents"

```swift
// When user clicks "Ready to Generate Cards":
1. Validate all docs have summaries
2. Show confirmation: "Generate N cards from M documents?"
3. Inject system message: "User has approved card generation..."
4. Coordinator calls dispatch_kc_agents
5. UI shows agent progress tabs
6. Cards arrive in parallel, displayed for review
```

**Card Persistence Flow** (LLM coordinator manages, not user):
```swift
// dispatch_kc_agents returns array of cards to main LLM coordinator
// Coordinator then processes each card:

1. LLM reviews card for completeness/quality
2. If valid: calls submit_knowledge_card(card)
   → Existing event flow handles persistence + UI update
3. If incomplete: may spawn new KC agent with specific feedback
4. Repeat until all cards persisted
5. Proceed to Phase 3
```

**Dossier Collection During Ingestion** (preserve existing):
```swift
// Current pattern works well:
case .extractionStateChanged(inProgress: true):
    if !hasDossierTriggeredThisExtraction {
        await triggerDossierCollection()  // "While we wait..."
    }
// Keep this - coordinator can do dossier while docs ingest
```

---

## Files to Modify

### Core Infrastructure
- **NEW**: `Sprung/Onboarding/Services/DocumentSummarizer.swift` - Gemini Flash-Lite summarization
- **NEW**: `Sprung/Onboarding/Services/KnowledgeCardAgentService.swift` - Parallel KC agent spawner
- **NEW**: `Sprung/Onboarding/Services/AgentRunner.swift` - Isolated agent execution loop
- **NEW**: `Sprung/Onboarding/Services/AgentExecutionContext.swift` - Per-agent context + tool routing
- **NEW**: `Sprung/Onboarding/Agents/KCAgentPrompts.swift` - KC agent system prompts
- **NEW**: `Sprung/Onboarding/Core/AgentActivityTracker.swift` - Central tracking + transcript storage + kill
- **MODIFY**: `Sprung/Onboarding/Tools/ToolExecutor.swift` - Support agent-scoped execution

### Agent Visibility UI (Tool Pane Tab)
- **NEW**: `Sprung/Onboarding/Views/Components/AgentsPaneView.swift` - Tool pane tab container (list + detail)
- **NEW**: `Sprung/Onboarding/Views/Components/AgentListView.swift` - Selectable agent list with status icons
- **NEW**: `Sprung/Onboarding/Views/Components/AgentTranscriptView.swift` - Transcript viewer + kill button

### Artifact & Ingestion
- `Sprung/Onboarding/Core/ArtifactRepository.swift` - Add `summary` field to records
- `Sprung/Onboarding/Services/ArtifactIngestionCoordinator.swift` - Add summarization step
- `Sprung/Onboarding/Tools/Implementations/GetArtifactTool.swift` - Return full text on demand

### Phase 2 Workflow
- `Sprung/Onboarding/Phase/PhaseTwoScript.swift` - New workflow, objectives, prompts
- `Sprung/Onboarding/Tools/Implementations/StartPhaseTwoTool.swift` - Return summaries + new instructions
- **NEW**: `Sprung/Onboarding/Tools/Implementations/ProposeCardAssignmentsTool.swift`
- **NEW**: `Sprung/Onboarding/Tools/Implementations/RequestAdditionalDocsTool.swift`
- **NEW**: `Sprung/Onboarding/Tools/Implementations/DispatchKCAgentsTool.swift`

### UI Updates
- `Sprung/Onboarding/Views/Components/KnowledgeCardCollectionView.swift` - New card review flow
- `Sprung/Onboarding/Views/Components/OnboardingInterviewToolPane.swift` - Add agent tabs

### Event Handling
- `Sprung/Onboarding/Core/OnboardingEvents.swift` - New events for multi-agent flow
- `Sprung/Onboarding/Core/Coordinators/CoordinatorEventRouter.swift` - Handle new events

### Optional (if needed later)
- `SwiftOpenAI-ttsfork/.../OpenAIService.swift` - Add compact endpoint for tool bloat
