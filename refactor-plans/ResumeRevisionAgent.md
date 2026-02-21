# Refactor Plan: ResumeRevisionAgent.swift

**File:** `Sprung/Resumes/AI/RevisionAgent/ResumeRevisionAgent.swift`
**Lines:** 1,150
**Date assessed:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`ResumeRevisionAgent` is an agentic loop that drives multi-turn LLM-based resume revision. It:

- Sets up a file-based workspace of resume materials
- Sends an initial request (with a PDF attachment) to Anthropic
- Runs a `while` loop calling the LLM, processing streamed tool calls, executing those tools, and feeding results back
- Implements human-in-the-loop pauses (proposal review, freeform questions, completion confirmation)
- Auto-renders the resume PDF after every write and optionally sends rendered page images back to the LLM
- Builds and persists a new `Resume` from workspace state when the session ends

---

## 2. Distinct Logical Sections

| Lines | MARK | What it does |
|-------|------|--------------|
| 1–68 | Agent Status / Agent Error / Revision Message | **Module-level types** consumed by views (`RevisionToolbar`, `RevisionChatView`) and by the agent itself |
| 70–138 | Class declaration + Init | Dependencies, all state properties, constructor |
| 140–482 | `run(...)` – Public API | The entire agent loop: workspace setup, prompt building, PDF attachment, stream dispatch, turn management, tool dispatch, completion detection |
| 484–607 | User Response Methods | External API called by the UI: `respondToProposal`, `respondToQuestion`, `respondToCompletion`, `sendUserMessage`, `interruptWithMessage`, `cancelActiveStream`, `acceptCurrentState`, `cancel` |
| 608–636 | Tool Building + inner structs | `buildAnthropicTools()`, `ToolExecutionResult`, `StreamResult` |
| 638–693 | Tool Execution | `executeTool(name:arguments:)` – dispatch switch over all tool names |
| 695–804 | Auto-Render | `autoRenderResume()`, `countPDFPages()`, `renderPDFPageImages()` – PDF rendering and image encoding for the LLM |
| 806–929 | Human-in-the-Loop Tools | `executeProposal`, `executeAskUser`, `handleCompleteRevision`, `handleExitCleanup`, `buildAndActivateResumeFromWorkspace` |
| 931–1020 | Conversation Repair | `repairOrphanedToolUse()` – repairs broken tool_use/tool_result pairs in the Anthropic message history |
| 1022–1083 | Message & Formatting Helpers | `appendOrUpdateAssistantMessage`, `formatReadResult`, `formatGlobResult`, `formatGrepResult`, `parseToolArguments`, `toolDisplayName` |
| 1085–1149 | Transcript Logging | `logTurnRequest`, `logTurnResponse` |

---

## 3. SRP Assessment

The class violates SRP. It currently has **five distinct reasons to change**:

1. **Agent loop logic changes** — timeout policy, turn limits, interruption handling, message injection
2. **PDF rendering changes** — page image encoding format, scale factor, JPEG quality, page count method
3. **Conversation protocol changes** — orphaned tool repair, Anthropic message alternation rules
4. **Transcript/logging changes** — what to log, how to summarize messages, which logger to use
5. **UI type changes** — `RevisionAgentStatus`, `RevisionAgentError`, `RevisionMessage`, `RevisionMessageRole` are consumed by views and would change when the UI contracts change

The `run(...)` method alone is 342 lines and contains the stream task, per-turn timeout task, stream result accumulation, interrupted-stream recovery, no-tool-call nudge logic, completion detection, and tool dispatch — all interleaved. This is the primary concentration of mixed responsibilities.

The PDF rendering section (`autoRenderResume` + `renderPDFPageImages`) has zero coupling to the agent loop internals — it only needs a workspace path and a PDF generator. It belongs in its own unit.

The conversation repair section (`repairOrphanedToolUse`) is a self-contained algorithm operating on `[AnthropicMessage]`. It has no awareness of workspace, tools, or UI state.

---

## 4. Verdict: Should Be Split

1,150 lines with five distinct responsibilities is not justified. The `run(...)` method alone exceeds the size threshold for a single function and is difficult to test or reason about in isolation. The PDF rendering code in particular is a cohesive, independently testable unit that has nothing to do with agentic loop control.

The split below is conservative — it extracts only the clearly separable units and leaves the main `run` loop and human-in-the-loop handlers together (they share too many continuations and state fields to safely split without a larger redesign).

---

## 5. Concrete Refactoring Plan

### New Files

#### 5.1 `RevisionAgentTypes.swift`

**Path:** `Sprung/Resumes/AI/RevisionAgent/RevisionAgentTypes.swift`

**Purpose:** Module-level types shared between the agent and views. Moving them out of the agent file makes them independently findable and breaks the implicit dependency the view layer has on the agent implementation file.

**Line ranges to move:**
- Lines 8–16: `RevisionAgentStatus`
- Lines 18–53: `RevisionAgentError`
- Lines 55–68: `RevisionMessage` + `RevisionMessageRole`

**Resulting file contents:**
```swift
import Foundation

// MARK: - Agent Status

enum RevisionAgentStatus: Equatable { ... }

// MARK: - Agent Error

enum RevisionAgentError: LocalizedError { ... }

// MARK: - Revision Message (for UI)

struct RevisionMessage: Identifiable { ... }

enum RevisionMessageRole { ... }
```

**No imports change in consumers** — these types are already at module scope; views (`RevisionChatView`, `RevisionToolbar`) import nothing from the agent file directly, they just use the types by name.

**Access level changes:** None. All types are already internal.

---

#### 5.2 `RevisionPDFRenderer.swift`

**Path:** `Sprung/Resumes/AI/RevisionAgent/RevisionPDFRenderer.swift`

**Purpose:** All logic for converting a live resume into a PDF and then into JPEG page images for the LLM, plus the PDF page-count utility. This is pure data transformation with no agent state.

**Line ranges to move:**
- Lines 697–701: `RenderInfo` struct (currently private inner struct — promote to `internal` so it can be the return type of a non-private method)
- Lines 703–742: `autoRenderResume()` — promote to a `static` or standalone function that takes explicit parameters instead of using `self`
- Lines 744–750: `countPDFPages(_:)`
- Lines 752–804: `renderPDFPageImages(_:)`

**Resulting structure:**
```swift
import AppKit
import CoreGraphics
import Foundation
import SwiftOpenAI

// MARK: - Render Info

struct RevisionRenderInfo {
    let success: Bool
    let pageCount: Int
    let pdfData: Data?
}

// MARK: - Revision PDF Renderer

struct RevisionPDFRenderer {
    let workspaceService: ResumeRevisionWorkspaceService
    let pdfGenerator: NativePDFGenerator
    let modelContext: ModelContext

    func autoRenderResume(from resume: Resume) async -> RevisionRenderInfo { ... }
    func renderPDFPageImages(_ pdfData: Data) -> [AnthropicContentBlock] { ... }
    static func countPDFPages(_ data: Data) -> Int { ... }
}
```

**Changes in `ResumeRevisionAgent`:**
- Replace the three method bodies with delegation to a `RevisionPDFRenderer` instance created in `init`
- Replace usages of `RenderInfo` with `RevisionRenderInfo`
- Remove `CoreGraphics` and `AppKit` imports from `ResumeRevisionAgent.swift` (they'll only be needed in the renderer file)

**Access level changes:**
- `RenderInfo` promoted from `private struct` nested in the class to `internal struct RevisionRenderInfo` at module scope

---

#### 5.3 `AnthropicConversationRepairer.swift`

**Path:** `Sprung/Resumes/AI/RevisionAgent/AnthropicConversationRepairer.swift`

**Purpose:** The orphaned-tool-use repair algorithm. This is a pure function over `[AnthropicMessage]` — it has no dependency on agent state, workspace, or UI. It can be tested in isolation and may be useful in other agentic contexts in the future.

**Line ranges to move:**
- Lines 931–1020: `repairOrphanedToolUse()` — the entire method

**Resulting structure:**
```swift
import Foundation
import SwiftOpenAI

// MARK: - Anthropic Conversation Repairer

/// Repairs an Anthropic message history that contains tool_use blocks with
/// no matching tool_result responses. Injects synthetic "cancelled" results
/// so the API accepts the conversation.
struct AnthropicConversationRepairer {
    /// Mutates `messages` in-place, returning true if any repairs were made.
    @discardableResult
    static func repairOrphanedToolUse(in messages: inout [AnthropicMessage]) -> Bool { ... }
}
```

**Changes in `ResumeRevisionAgent`:**
- Replace the call to `repairOrphanedToolUse()` (line 258) with:
  ```swift
  AnthropicConversationRepairer.repairOrphanedToolUse(in: &conversationMessages)
  ```
- Remove the `repairOrphanedToolUse()` method entirely from the agent class

**Access level changes:** None needed. The repairer can be `internal`.

---

#### 5.4 `RevisionTranscriptLogger.swift`

**Path:** `Sprung/Resumes/AI/RevisionAgent/RevisionTranscriptLogger.swift`

**Purpose:** The two logging methods. These only read from `conversationMessages`, `modelId`, and tool metadata — they have no write access to agent state. Extracting them removes the logging concern from the already-busy agent class.

**Line ranges to move:**
- Lines 1085–1149: `logTurnRequest(turn:messageCount:)` and `logTurnResponse(turn:messageCount:toolNames:result:interrupted:durationMs:)`

**Resulting structure:**
```swift
import Foundation
import SwiftOpenAI

// MARK: - Revision Transcript Logger

struct RevisionTranscriptLogger {
    let modelId: String

    func logTurnRequest(
        turn: Int,
        messageCount: Int,
        lastMessage: AnthropicMessage?
    ) { ... }

    func logTurnResponse(
        turn: Int,
        messageCount: Int,
        toolNames: [String],
        result: RevisionAgentStreamResult,
        interrupted: Bool,
        durationMs: Int
    ) { ... }
}
```

Note: `StreamResult` should be renamed `RevisionAgentStreamResult` and moved to module scope (currently a `private struct` at line 632) so it can be a parameter type visible to the transcript logger.

**Changes in `ResumeRevisionAgent`:**
- Add a `private let transcriptLogger: RevisionTranscriptLogger` property initialized in `init`
- Replace `logTurnRequest(...)` calls with `transcriptLogger.logTurnRequest(...)`
- Replace `logTurnResponse(...)` calls with `transcriptLogger.logTurnResponse(...)`
- Remove the two log methods from the agent class

**Access level changes:**
- `StreamResult` renamed `RevisionAgentStreamResult`, promoted from `private struct` (line 632) to `internal struct` at module scope, kept in `ResumeRevisionAgent.swift` or moved to `RevisionAgentTypes.swift`

---

### What Stays in `ResumeRevisionAgent.swift`

After the extractions, `ResumeRevisionAgent.swift` retains:

- `import` block (reduced: remove `AppKit`, `CoreGraphics`)
- `@Observable @MainActor class ResumeRevisionAgent` with:
  - All properties (dependencies, state, continuations, conversation state)
  - `init`
  - `run(...)` — the full agent loop (still the largest section, but now all loop control)
  - User response methods (lines 484–607) — tightly coupled to continuations
  - `buildAnthropicTools()` (line 610)
  - `ToolExecutionResult` inner struct (line 626)
  - `executeTool(name:arguments:)` (lines 638–693)
  - `handleExitCleanup()`, `buildAndActivateResumeFromWorkspace()` (lines 872–929)
  - `appendOrUpdateAssistantMessage(_:)` (lines 1024–1035)
  - Formatting helpers: `formatReadResult`, `formatGlobResult`, `formatGrepResult`, `parseToolArguments`, `toolDisplayName` (lines 1037–1083)

Estimated remaining line count: approximately 650–700 lines. Still not small, but it now has a single coherent responsibility: managing agent control flow and tool dispatch.

---

## 6. File Interaction Map

```
RevisionAgentTypes.swift
    ← used by: ResumeRevisionAgent.swift (status, error, messages)
    ← used by: RevisionChatView.swift (RevisionMessage, RevisionMessageRole)
    ← used by: RevisionToolbar.swift (RevisionAgentStatus)

RevisionPDFRenderer.swift
    ← used by: ResumeRevisionAgent.swift (autoRender, renderPageImages)
    ← imports: ResumeRevisionWorkspaceService (existing file)
    ← imports: NativePDFGenerator (existing type)

AnthropicConversationRepairer.swift
    ← used by: ResumeRevisionAgent.swift (repairOrphanedToolUse call)
    ← no other dependencies

RevisionTranscriptLogger.swift
    ← used by: ResumeRevisionAgent.swift (logTurnRequest, logTurnResponse)
    ← depends on RevisionAgentStreamResult (needs to be promoted to module scope)
```

---

## 7. Implementation Order

Do these in sequence to keep the build green at each step:

1. **Create `RevisionAgentTypes.swift`** — copy the four top-level types, then delete them from `ResumeRevisionAgent.swift`. Build to confirm no ambiguity.

2. **Create `AnthropicConversationRepairer.swift`** — convert the private method to a static function on a struct, update the call site in `run(...)`. Build.

3. **Create `RevisionPDFRenderer.swift`** — promote `RenderInfo` to `RevisionRenderInfo`, convert the three methods to instance methods on the struct, add a `RevisionPDFRenderer` property to `ResumeRevisionAgent`, update call sites. Build.

4. **Promote `StreamResult` to `RevisionAgentStreamResult`** — rename and move to module scope (either `RevisionAgentTypes.swift` or keep in `ResumeRevisionAgent.swift` at the top). Build.

5. **Create `RevisionTranscriptLogger.swift`** — extract the two log methods, add `transcriptLogger` property to agent, update call sites. Build.

6. **Final build** with the result bundle path to refresh the LSP index:
   ```bash
   rm -rf .bundle; xcodebuild -project Sprung.xcodeproj -scheme Sprung -resultBundlePath .bundle build
   ```

---

## 8. What Not to Split

- **`run(...)` internals** — the stream task, per-turn timeout task, interruption recovery, and tool dispatch all share local state (`streamWasInterrupted`, `hadWriteCall`, `pendingToolCalls`). Pulling any of these into sub-methods would require threading multiple mutable locals or introducing a new struct to carry them. The complexity cost exceeds the clarity gain.
- **Human-in-the-loop handlers** (`executeProposal`, `executeAskUser`, `handleCompleteRevision`) — these are tightly coupled to the continuation properties and to `currentProposal`, `currentQuestion`, `currentCompletionSummary`. They should stay on the class.
- **Formatting helpers** — they are small (1–5 lines each) and directly tied to tool result types. Not worth a separate file.
