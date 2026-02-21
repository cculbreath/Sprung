# LLMFacade.swift Refactoring Analysis

**File:** `Sprung/Shared/AI/Models/Services/LLMFacade.swift`
**Lines:** 1,036
**Date assessed:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`LLMFacade` is the single public entry point for all LLM operations in Sprung. Its declared purpose is to:

- Route LLM requests to the correct backend (OpenRouter, OpenAI, Gemini, Anthropic)
- Validate model capabilities before each request
- Expose a stable, unified API surface to all callers
- Log every call to `LLMTranscriptLogger`

This is a well-conceived design. The class is intended to be a thin routing/coordination layer.

---

## 2. Distinct Logical Sections

| Lines | MARK / Section | What it contains |
|-------|---------------|-----------------|
| 13–17 | (top-level struct) | `LLMStreamingHandle` value type |
| 35–63 | `Backend` enum | Enum with display names and `infer(from:)` routing helper |
| 65–124 | Properties + init + registration | Stored properties, initializer, `registerClient/ConversationService/OpenAIService/GoogleAIService/AnthropicService`, `resolveClient` |
| 125–168 | Text Execution | `executeText`, `executeTextWithImages` |
| 170–368 | Structured Execution | `executeStructured`, `executeStructuredWithImages`, `executeStructuredWithSchema`, `executeStructuredWithDictionarySchema`, `executeFlexibleJSON`, `executeStructuredStreaming` |
| 369–487 | Conversation Streaming | `startConversationStreaming` (x2 overloads), `continueConversationStreaming` |
| 489–589 | Conversation Non-Streaming | `continueConversation`, `continueConversationStructured`, `startConversation`, `cancelAllRequests` |
| 596–775 | Tool Calling | `executeWithTools`, **`executeToolsViaOpenAI`** (private), **`convertResponseToCompletion`** (private) |
| 777–811 | OpenAI Responses API | `executeWithWebSearch`, `responseCreateStream` (thin pass-through to `specializedAPIs`) |
| 813–936 | Anthropic Messages API | `anthropicMessagesStream`, `anthropicListModels`, **`executeTextWithAnthropicCaching`**, **`executeStructuredWithAnthropicCaching`** |
| 938–1021 | Gemini Document Extraction | `generateFromPDF`, `generateDocumentSummary`, `analyzeImagesWithGemini`, `analyzeImagesWithGeminiStructured` |
| 1023–1027 | Text-to-Speech | `createTTSClient` |
| 1029–1036 | Transcript Timing | `elapsedMs` private helper |

---

## 3. SRP Assessment

### What is genuinely "facade" work (appropriate to keep here)

Every method that follows this pattern is legitimate facade responsibility:

1. Validate capabilities via `capabilityValidator`
2. Route to correct backend client or service
3. Log the call via `LLMTranscriptLogger`
4. Return the result

The thin pass-through methods (`executeWithWebSearch`, `responseCreateStream`, `anthropicMessagesStream`, `anthropicListModels`, `generateFromPDF`, `generateDocumentSummary`, `analyzeImagesWithGemini`, `analyzeImagesWithGeminiStructured`, `createTTSClient`) are all correctly implemented this way.

### What violates SRP (should NOT be in a facade)

**Violation 1: OpenAI Responses API adapter logic (lines 657–775)**

`executeToolsViaOpenAI` (lines 657–729) and `convertResponseToCompletion` (lines 731–775) are not facade behavior. They contain:
- Mapping from `ChatCompletionParameters.Message` role strings to OpenAI Responses API roles
- Translating `ChatCompletionParameters.Tool` to `Tool.FunctionTool`
- Translating `ToolChoice` to `ToolChoiceMode`
- Constructing a `ModelResponseParameter`
- Driving a streaming loop to collect the final response
- Converting a `ResponseModel` back to `ChatCompletionObject` by hand-building JSON dictionaries and decoding them

This is a **protocol adapter / format converter** — a distinct responsibility. The facade is supposed to delegate to `specializedAPIs`, not contain dozens of lines of request assembly and response conversion. This code belongs in a dedicated adapter type.

**Violation 2: Anthropic streaming execution logic (lines 832–936)**

`executeTextWithAnthropicCaching` and `executeStructuredWithAnthropicCaching` both:
- Build `AnthropicMessageParameter` objects inline
- Drive an `AsyncThrowingStream` event loop to accumulate `resultText`
- Parse and decode the result

This is the same pattern as `executeToolsViaOpenAI`: the facade is doing the work of an executor, not just routing to one. The Anthropic stream-driving logic belongs alongside the other Anthropic-specific behavior. The natural home is `LLMFacadeSpecializedAPIs`, which already owns `anthropicMessagesStream` and `anthropicListModels`.

### Why the length is partly, but not entirely, justified

The quantity of public API surface methods is defensible — callers across the codebase use `executeWithTools` (8 call sites), `executeTextWithAnthropicCaching` / `executeStructuredWithAnthropicCaching` (3 call sites), `executeStructuredWithDictionarySchema` (used from `TitleSetsBrowserTab` and `SectionGenerator`). Broad API surface in a unified entry point is expected.

However, approximately **180 lines** (lines 657–775 + the inner bodies of lines 837–935) are implementation logic that should be owned by collaborator types. The facade should hold only the routing/validation/logging shell for those operations.

---

## 4. Refactoring Recommendation: SPLIT

The refactoring is surgical — it is NOT a full restructuring. Two specific pieces of implementation logic need to move out. The public API contract of `LLMFacade` does not change at all; callers are unaffected.

---

## 5. Concrete Refactoring Plan

### New file 1: `LLMFacadeOpenAIToolsAdapter.swift`

**Path:** `Sprung/Shared/AI/Models/Services/LLMFacadeOpenAIToolsAdapter.swift`

**Purpose:** Owns the logic for translating a tool-calling request (expressed in OpenRouter/ChatCompletion terms) into an OpenAI Responses API call, driving the streaming event loop, and converting the result back to `ChatCompletionObject`. This is a pure format adapter with no UI state.

**Lines to move from `LLMFacade.swift`:**

| Line range | Content |
|-----------|---------|
| 657–729 | `private func executeToolsViaOpenAI(...)` |
| 731–775 | `private func convertResponseToCompletion(...)` |

**New type:**

```swift
// LLMFacadeOpenAIToolsAdapter.swift

import Foundation
import SwiftOpenAI

/// Translates tool-calling requests (in ChatCompletion format) to the OpenAI
/// Responses API and converts the result back to ChatCompletionObject.
@MainActor
struct LLMFacadeOpenAIToolsAdapter {
    private let specializedAPIs: LLMFacadeSpecializedAPIs

    init(specializedAPIs: LLMFacadeSpecializedAPIs) {
        self.specializedAPIs = specializedAPIs
    }

    func execute(
        messages: [ChatCompletionParameters.Message],
        tools: [ChatCompletionParameters.Tool],
        toolChoice: ToolChoice?,
        modelId: String,
        reasoningEffort: String?
    ) async throws -> ChatCompletionObject {
        // Body of current executeToolsViaOpenAI (lines 664–729)
    }

    private func convertResponseToCompletion(
        _ response: ResponseModel
    ) throws -> ChatCompletionObject {
        // Body of current convertResponseToCompletion (lines 732–775)
    }
}
```

**How `LLMFacade` changes:**

- Add `private let openAIToolsAdapter: LLMFacadeOpenAIToolsAdapter` as a stored property, initialized in `init` after `specializedAPIs` is created.
- Replace the `else` branch in `executeWithTools` (lines 633–642) with:
  ```swift
  result = try await openAIToolsAdapter.execute(
      messages: messages,
      tools: tools,
      toolChoice: toolChoice,
      modelId: modelId,
      reasoningEffort: reasoningEffort
  )
  ```
- Delete `executeToolsViaOpenAI` and `convertResponseToCompletion` from `LLMFacade`.

**Net change to `LLMFacade.swift`:** Remove ~120 lines of implementation, add ~5 lines (property declaration + delegation call).

---

### New file 2: Move Anthropic execution into `LLMFacadeSpecializedAPIs.swift`

**Path:** `Sprung/Shared/AI/Models/Services/LLMFacadeSpecializedAPIs.swift` (existing file — add to it)

**Purpose:** `LLMFacadeSpecializedAPIs` already owns the Anthropic service reference and the thin wrappers `anthropicMessagesStream` and `anthropicListModels`. The stream-driving execution logic for cached Anthropic calls is a natural extension of that responsibility.

**Lines to move from `LLMFacade.swift`:**

| Line range | Content |
|-----------|---------|
| 837–869 | Inner body of `executeTextWithAnthropicCaching` (stream loop + logging omitted — see below) |
| 887–935 | Inner body of `executeStructuredWithAnthropicCaching` (stream loop + logging omitted — see below) |

**Important:** The public method signatures `executeTextWithAnthropicCaching` and `executeStructuredWithAnthropicCaching` **stay on `LLMFacade`** because they are public API with call sites across the codebase. The internal stream-driving work is what moves.

Add two new internal methods to `LLMFacadeSpecializedAPIs`:

```swift
// Inside LLMFacadeSpecializedAPIs

func executeTextWithAnthropicCaching(
    systemContent: [AnthropicSystemBlock],
    userPrompt: String,
    modelId: String
) async throws -> String {
    // Build parameters + drive stream loop (current lines 838–860 of LLMFacade)
    // Return resultText
}

func executeStructuredWithAnthropicCaching<T: Codable>(
    systemContent: [AnthropicSystemBlock],
    userPrompt: String,
    modelId: String,
    responseType: T.Type,
    schema: [String: Any]
) async throws -> T {
    // Build parameters + drive stream loop + decode (current lines 888–935 of LLMFacade)
}
```

**How `LLMFacade` changes for these methods:**

`executeTextWithAnthropicCaching` on `LLMFacade` (lines 832–869) becomes:

```swift
func executeTextWithAnthropicCaching(
    systemContent: [AnthropicSystemBlock],
    userPrompt: String,
    modelId: String
) async throws -> String {
    let start = ContinuousClock.now
    let result = try await specializedAPIs.executeTextWithAnthropicCaching(
        systemContent: systemContent,
        userPrompt: userPrompt,
        modelId: modelId
    )
    LLMTranscriptLogger.logAnthropicCall(
        method: "executeTextWithAnthropicCaching", modelId: modelId,
        systemBlockCount: systemContent.count, userPrompt: userPrompt,
        response: result, durationMs: elapsedMs(from: start)
    )
    return result
}
```

`executeStructuredWithAnthropicCaching` on `LLMFacade` (lines 880–936) becomes:

```swift
func executeStructuredWithAnthropicCaching<T: Codable>(
    systemContent: [AnthropicSystemBlock],
    userPrompt: String,
    modelId: String,
    responseType: T.Type,
    schema: [String: Any]
) async throws -> T {
    let start = ContinuousClock.now
    let result = try await specializedAPIs.executeStructuredWithAnthropicCaching(
        systemContent: systemContent,
        userPrompt: userPrompt,
        modelId: modelId,
        responseType: responseType,
        schema: schema
    )
    LLMTranscriptLogger.logAnthropicCall(
        method: "executeStructuredWithAnthropicCaching", modelId: modelId,
        systemBlockCount: systemContent.count, userPrompt: userPrompt,
        response: String(describing: result), durationMs: elapsedMs(from: start)
    )
    return result
}
```

**Note on the `Logger.info` calls inside the stream loops (lines 862, 917):** Move them into the `LLMFacadeSpecializedAPIs` implementations, since they are part of the execution logic, not the facade's logging contract. The facade's logging contract is `LLMTranscriptLogger`, which stays on `LLMFacade`.

**Net change to `LLMFacade.swift`:** Remove ~80 lines of stream-driving implementation, replace with ~25 lines of delegation. `LLMFacadeSpecializedAPIs.swift` grows by ~70 lines.

---

## 6. File Interaction and Dependencies

```
LLMFacade
  ├── delegates generic execution to → LLMClient (via backendClients dict)
  ├── delegates capability checks to → LLMFacadeCapabilityValidator
  ├── delegates streaming lifecycle to → LLMFacadeStreamingManager
  ├── delegates specialized APIs to → LLMFacadeSpecializedAPIs
  │     └── (new) also delegates Anthropic stream execution here
  └── (new) delegates OpenAI tool format conversion to → LLMFacadeOpenAIToolsAdapter
        └── calls back into specializedAPIs.responseCreateStream(...)
```

`LLMFacadeOpenAIToolsAdapter` needs:
- `import SwiftOpenAI` (already present in the module)
- Access to `LLMFacadeSpecializedAPIs` (inject via init)
- Access to `LLMError`, `ToolChoice`, `ChatCompletionParameters`, `ChatCompletionObject` — all already in scope

`LLMFacadeSpecializedAPIs` new methods need:
- `AnthropicSystemBlock`, `AnthropicMessageParameter`, `AnthropicStreamEvent`, `AnthropicOutputFormat` — already imported via `AnthropicService`
- `LLMError`, `Logger` — already in scope

No access control changes are needed. All new types are `internal` (the Swift default), which is correct since they are implementation details of the facade layer.

---

## 7. Summary: Before / After Line Counts

| File | Before | After |
|------|--------|-------|
| `LLMFacade.swift` | 1,036 | ~840 |
| `LLMFacadeSpecializedAPIs.swift` | 267 | ~340 |
| `LLMFacadeOpenAIToolsAdapter.swift` | (new) | ~130 |
| Total | 1,303 | ~1,310 |

Total line count is roughly unchanged — the refactoring redistributes logic, it does not eliminate it.

---

## 8. What to Leave Alone

The following sections are correctly sized and appropriately located in `LLMFacade`:

- All `executeText`, `executeStructured*`, `executeFlexibleJSON`, `executeStructuredStreaming` methods — these are thin routing shells with capability validation and logging. That is exactly what a facade should contain.
- All conversation methods (`startConversation`, `continueConversation`, `startConversationStreaming`, `continueConversationStreaming`) — same pattern, same justification.
- The `Backend` enum — it is tightly coupled to routing decisions made in `LLMFacade` and belongs here.
- `LLMStreamingHandle` struct — it is the public return type for streaming operations. It could theoretically move to a separate file but there is no maintainability benefit to doing so; it is small and tightly related.
- The `cancelAllRequests` method — correctly delegates to `streamingManager` and `llmService`.
- `elapsedMs` — a private timing utility used uniformly across all logging calls. It is appropriate where it is.

---

## 9. Implementation Order

1. Create `LLMFacadeOpenAIToolsAdapter.swift` with the extracted adapter logic.
2. Add `openAIToolsAdapter` property to `LLMFacade`, initialize in `init` after `specializedAPIs` is initialized.
3. Delete `executeToolsViaOpenAI` and `convertResponseToCompletion` from `LLMFacade`; replace the call site in `executeWithTools`.
4. Add `executeTextWithAnthropicCaching` and `executeStructuredWithAnthropicCaching` to `LLMFacadeSpecializedAPIs`.
5. Slim down the corresponding methods in `LLMFacade` to delegation + logging shells.
6. Build and verify. No callers need changes — the public API surface of `LLMFacade` is identical.
