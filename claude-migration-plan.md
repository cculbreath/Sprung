# Migration Plan: OpenAI Responses API → Anthropic Claude (Direct API)

## Overview

Migrate the onboarding interview agent from OpenAI GPT-5.2 (Responses API with `previous_response_id`) to Anthropic Claude.

### Recommended Approach: Direct Anthropic API

After research, **direct Anthropic API** is recommended over OpenRouter because:
1. **Server-side tools**: Native `web_search_20250305` and `web_fetch_20250910` support
2. **No translation layer**: Full API compatibility without intermediary
3. **Future-proof**: Automatic access to new Anthropic features
4. **Prompt caching**: Native `cache_control` breakpoints

OpenRouter does NOT appear to pass through Anthropic's server-side tools - it has its own web search plugin wrapper instead.

### Key Insight: Token Billing is Equivalent

OpenAI bills for the full in-context chat history with every request, regardless of `previous_response_id`. The threading mechanism only affects:
- **Payload size** (network bandwidth, not tokens)
- **State management** (server-side vs client-side)
- **Convenience** (OpenAI reconstructs context; OpenRouter requires explicit history)

**No token cost increase from this migration.**

---

## Existing Infrastructure (Can Be Reused)

The codebase already has infrastructure that can be leveraged:

### SwiftOpenAI Library (`~/devlocal/codebase/SwiftOpenAI-ttsfork`)

The library already supports **Anthropic Messages API** format (used by onboarding):
| Component | File | Capability |
|-----------|------|------------|
| `InputMessage`, `InputItem` | Parameter types | Anthropic message format |
| `Tool.function()` | Tool definitions | Function calling schema |
| `ResponseStreamEvent` | Stream events | Already handles streaming |

**Key Difference:** Anthropic Messages API is similar to OpenAI Responses API - both use:
- Message arrays with roles (system/user/assistant)
- Tool definitions with JSON schemas
- Streaming with content deltas

### Onboarding Infrastructure (Sprung/Onboarding/)
| Component | File | Capability |
|-----------|------|------------|
| `ChatTranscriptStore` | `ChatTranscriptStore.swift` | Client-managed message history |
| `OnboardingRequestBuilder` | `OnboardingRequestBuilder.swift` | Request construction |
| `NetworkRouter` | `NetworkRouter.swift` | Stream event handling |
| Tool schemas | `Onboarding/Tools/Schemas/` | Already defined tools |

### What Needs to Change
1. **API endpoint**: OpenAI → Anthropic (`api.anthropic.com/v1/messages`)
2. **Message format**: `developer` role → `system` role
3. **Tool type for web search**: Add `web_search_20250305` server-side tool
4. **Stream events**: Map Anthropic events to existing domain events
5. **Remove `previous_response_id`**: Always send full message history

---

## Current Architecture Analysis

### How `previous_response_id` Works Today

| Component | File | Role |
|-----------|------|------|
| `ChatTranscriptStore` | `Onboarding/Core/ChatTranscriptStore.swift` | Stores `previousResponseId: String?` at runtime |
| `ConversationContextAssembler` | `Onboarding/Core/ConversationContextAssembler.swift` | Gets/stores PRI, builds full history when PRI is nil |
| `OnboardingRequestBuilder` | `Onboarding/Core/OnboardingRequestBuilder.swift` | Builds `ModelResponseParameter` with `previousResponseId` |
| `LLMMessenger` | `Onboarding/Core/LLMMessenger.swift` | Orchestrates LLM calls via `LLMFacade.responseCreateStream()` |
| `NetworkRouter` | `Onboarding/Core/NetworkRouter.swift` | Processes `ResponseStreamEvent` from OpenAI |
| `SwiftDataSessionPersistenceHandler` | `Onboarding/Handlers/SwiftDataSessionPersistenceHandler.swift` | Persists PRI to SwiftData |

### Current Request Flow

```
User types message
    ↓
LLMMessenger.executeUserMessage()
    ↓
OnboardingRequestBuilder.buildUserMessageRequest()
    ├── If previousResponseId == nil:
    │   ├── Include base developer message (system prompt)
    │   └── Include full conversation history (if restoring)
    └── If previousResponseId exists:
        └── Only send new user message (OpenAI reconstructs context)
    ↓
LLMFacade.responseCreateStream(ModelResponseParameter)
    ↓
NetworkRouter.handleResponseEvent(ResponseStreamEvent)
    ↓
On completion: store new responseId as previousResponseId
```

### Message Role Hierarchy (Current OpenAI)

| Role | Purpose | Persistence |
|------|---------|-------------|
| `developer` | System instructions (highest priority) | Persists via PRI |
| `user` | User input | Persists via PRI |
| `assistant` | Model responses | Persists via PRI |
| `instructions` param | Per-request behavioral overrides | Does NOT persist |

---

## Architecture Changes Required

| Aspect | Current (OpenAI Responses) | Target (OpenRouter Chat Completions) |
|--------|---------------------------|-------------------------------------|
| Threading | `previous_response_id` | Full message array per request |
| System prompt | `developer` role | `system` role |
| Tool response | `functionToolCallOutput` | `tool` role message |
| Streaming format | `ResponseStreamEvent` | SSE chunks with `delta.content` |
| State management | Server-managed | Client-managed |
| Request size | Small (just new content) | Large (full history) |

---

## Implementation Phases (Direct Anthropic API)

### Phase 1: Add Anthropic Service to SwiftOpenAI Fork

**Goal:** Add Anthropic Messages API support to the existing SwiftOpenAI library.

**New Files in `SwiftOpenAI-ttsfork/Sources/OpenAI/`:**

```
Anthropic/
├── AnthropicAPI.swift           # Endpoint definitions
├── AnthropicService.swift       # Service implementation
├── AnthropicStreamEvent.swift   # SSE event types
└── AnthropicParameters.swift    # Request/response models
```

**Key Types:**
```swift
struct AnthropicMessageParameter: Encodable {
    let model: String
    let messages: [AnthropicMessage]
    let system: String?           // System prompt (replaces "developer" role)
    let tools: [AnthropicTool]?
    let maxTokens: Int
    let stream: Bool
}

struct AnthropicMessage: Codable {
    let role: String              // "user" | "assistant"
    let content: AnthropicContent
}

// Server-side tools
struct AnthropicServerTool: Encodable {
    let type: String              // "web_search_20250305" | "web_fetch_20250910"
    let name: String
    let maxUses: Int?
}
```

---

### Phase 2: Register Anthropic Backend in LLMFacade

**Goal:** Add Anthropic as a backend option alongside OpenRouter and OpenAI.

**Modify: `Sprung/Shared/AI/Models/Services/LLMFacade.swift`**

```swift
enum Backend: CaseIterable {
    case openRouter
    case openAI
    case gemini
    case anthropic  // NEW
}

func registerAnthropicService(_ service: AnthropicService) {
    self.anthropicService = service
}

func anthropicMessagesStream(
    parameters: AnthropicMessageParameter
) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
    guard let service = anthropicService else {
        throw LLMError.clientError("Anthropic service not configured")
    }
    return try await service.messagesStream(parameters: parameters)
}
```

---

### Phase 3: Anthropic Request Builder for Onboarding

**Goal:** Build Anthropic Messages API requests from onboarding context.

**New File: `Sprung/Onboarding/Core/AnthropicRequestBuilder.swift`**

```swift
struct AnthropicRequestBuilder {
    let baseDeveloperMessage: String
    let toolRegistry: ToolRegistry

    func buildRequest(
        history: [OnboardingMessage],
        bundledDeveloperMessages: [JSON],
        userMessage: String,
        modelId: String
    ) -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Conversation history (user/assistant only)
        for msg in history {
            switch msg.role {
            case .user:
                messages.append(.init(role: "user", content: .text(msg.text)))
            case .assistant:
                messages.append(.init(role: "assistant", content: .text(msg.text)))
            case .system:
                continue // System goes in separate field
            }
        }

        // New user message
        messages.append(.init(role: "user", content: .text(userMessage)))

        // Combine system prompts
        var systemPrompt = baseDeveloperMessage
        for devMsg in bundledDeveloperMessages {
            systemPrompt += "\n\n" + devMsg["text"].stringValue
        }

        // Build tools array (function tools + server-side tools)
        var tools: [AnthropicTool] = convertFunctionTools(toolRegistry.getTools())
        tools.append(.serverTool(AnthropicServerTool(
            type: "web_search_20250305",
            name: "web_search",
            maxUses: 5
        )))

        return AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt,
            tools: tools,
            maxTokens: 4096,
            stream: true
        )
    }
}
```

---

### Phase 4: Stream Event Adapter

**Goal:** Map Anthropic stream events to existing onboarding domain events.

**New File: `Sprung/Onboarding/Core/AnthropicStreamAdapter.swift`**

```swift
struct AnthropicStreamAdapter {
    mutating func process(_ event: AnthropicStreamEvent) -> [OnboardingDomainEvent] {
        switch event {
        case .contentBlockStart(let block):
            if block.type == "text" {
                return [.streamingMessageBegan(id: UUID())]
            }
        case .contentBlockDelta(let delta):
            if let text = delta.text {
                return [.streamingMessageUpdated(delta: text)]
            }
        case .contentBlockStop:
            return []
        case .messageStop:
            return [.streamingMessageFinalized(...)]
        case .toolUse(let toolUse):
            return [.toolCallRequested(
                callId: toolUse.id,
                name: toolUse.name,
                arguments: toolUse.input
            )]
        }
    }
}
```

---

### Phase 5: LLMMessenger Anthropic Path

**Goal:** Add Anthropic execution path to LLMMessenger.

**Modify: `Sprung/Onboarding/Core/LLMMessenger.swift`**

```swift
private func executeUserMessageViaAnthropic(
    _ payload: JSON,
    bundledDeveloperMessages: [JSON]
) async {
    let text = payload["text"].stringValue
    let history = await chatTranscriptStore.getAllMessages()

    let request = anthropicRequestBuilder.buildRequest(
        history: history,
        bundledDeveloperMessages: bundledDeveloperMessages,
        userMessage: text,
        modelId: "claude-sonnet-4-20250514"
    )

    let stream = try await llmFacade.anthropicMessagesStream(parameters: request)

    var adapter = AnthropicStreamAdapter()
    for try await event in stream {
        let domainEvents = adapter.process(event)
        for evt in domainEvents {
            await networkRouter.handleDomainEvent(evt)
        }
    }
}
```

---

### Phase 6: Provider Selection & Settings UI

**Goal:** Add Anthropic API key and backend toggle to Settings and Setup Wizard.

#### 6.1 Add Anthropic to APIKeyManager

**Modify: `Sprung/Shared/Utilities/APIKeyManager.swift`**

```swift
enum APIKeyType: String {
    case openRouter = "openRouterApiKey"
    case openAI = "openAiApiKey"
    case gemini = "geminiApiKey"
    case anthropic = "anthropicApiKey"  // NEW
}
```

#### 6.2 Add Anthropic Key to APIKeysSettingsView

**Modify: `Sprung/App/Views/Settings/APIKeysSettingsView.swift`**

```swift
@State private var anthropicApiKey: String = APIKeyManager.get(.anthropic) ?? ""

// Add new APIKeyEditor after Gemini:
APIKeyEditor(
    title: "Anthropic (Claude Interview)",
    systemImage: "brain.head.profile",
    value: $anthropicApiKey,
    placeholder: "sk-ant-…",
    help: "Used for Claude-powered onboarding interviews with web search.",
    testEndpoint: .anthropic,
    onSave: handleAnthropicSave
)

// Add test endpoint:
enum APITestEndpoint {
    case anthropic  // NEW

    var testURL: URL {
        case .anthropic:
            return URL(string: "https://api.anthropic.com/v1/messages")!
    }

    func buildRequest(apiKey: String) -> URLRequest {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    }
}
```

#### 6.3 Add Anthropic to Setup Wizard

**Modify: `Sprung/App/Views/SetupWizardView.swift`**

In `apiKeysStep`, add Anthropic field alongside OpenAI:

```swift
@State private var anthropicApiKey: String = APIKeyManager.get(.anthropic) ?? ""

// In apiKeysStep view:
VStack(alignment: .leading, spacing: 8) {
    Text("Anthropic API Key (Claude)")
        .font(.headline)
    Text("Required for Claude-powered interviews with built-in web search.")
        .font(.caption)
        .foregroundStyle(.secondary)
    SecureField("sk-ant-...", text: $anthropicApiKey)
        .textFieldStyle(.roundedBorder)
}
```

Update welcome step text:
```swift
Label("Add API keys for OpenRouter, OpenAI, Anthropic, and Gemini.", systemImage: "key.fill")
```

#### 6.4 Add Onboarding Backend Toggle to Settings

**New File or Section: `Sprung/App/Views/Settings/OnboardingSettingsView.swift`**

```swift
struct OnboardingSettingsView: View {
    @AppStorage("onboarding_llm_backend") private var backend: String = "openai"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Interview AI Provider")
                .font(.headline)

            Picker("Provider", selection: $backend) {
                Text("OpenAI (GPT-5)").tag("openai")
                Text("Anthropic (Claude)").tag("anthropic")
            }
            .pickerStyle(.radioGroup)

            switch backend {
            case "anthropic":
                Label("Uses Claude with built-in web search", systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                Label("Uses GPT-5 via OpenAI Responses API", systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Show warning if selected provider's key is missing
            if backend == "anthropic" && APIKeyManager.get(.anthropic) == nil {
                Label("Anthropic API key required", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }
}
```

#### 6.5 LLMMessenger Backend Switch

**Modify: `Sprung/Onboarding/Core/LLMMessenger.swift`**

```swift
private func executeUserMessage(...) async {
    let backend = UserDefaults.standard.string(forKey: "onboarding_llm_backend") ?? "openai"

    if backend == "anthropic" {
        await executeUserMessageViaAnthropic(payload, bundledDeveloperMessages)
    } else {
        await executeUserMessageViaResponsesAPI(payload, ...)  // Existing OpenAI path
    }
}
```

#### 6.6 Dynamic Model Selection Based on Backend

**Goal:** When backend changes between OpenAI and Anthropic, the model picker should show appropriate models fetched from each provider's API.

**Anthropic Models List API:**
```
GET https://api.anthropic.com/v1/models
Headers:
  x-api-key: $ANTHROPIC_API_KEY
  anthropic-version: 2023-06-01
```

Response format:
```json
{
  "data": [
    {
      "id": "claude-sonnet-4-20250514",
      "created_at": "2025-02-19T00:00:00Z",
      "display_name": "Claude Sonnet 4",
      "type": "model"
    }
  ],
  "first_id": "...",
  "has_more": true,
  "last_id": "..."
}
```

**Add to SwiftOpenAI Fork: `Anthropic/AnthropicService.swift`**

```swift
struct AnthropicModel: Codable, Identifiable {
    let id: String
    let createdAt: String?
    let displayName: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case displayName = "display_name"
        case type
    }
}

struct AnthropicModelsResponse: Codable {
    let data: [AnthropicModel]
    let firstId: String?
    let hasMore: Bool
    let lastId: String?

    enum CodingKeys: String, CodingKey {
        case data
        case firstId = "first_id"
        case hasMore = "has_more"
        case lastId = "last_id"
    }
}

extension AnthropicService {
    func listModels() async throws -> AnthropicModelsResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
    }
}
```

**Modify: `Sprung/App/Views/SettingsView.swift`**

Add new state variables:
```swift
@AppStorage("onboarding_llm_backend") private var onboardingBackend: String = "openai"
@AppStorage("onboardingAnthropicModelId") private var anthropicModelId: String = "claude-sonnet-4-20250514"

@State private var anthropicModels: [AnthropicModel] = []
@State private var isLoadingAnthropicModels = false
@State private var anthropicModelError: String?

/// Filtered Anthropic models: claude-sonnet-4*, claude-opus-4* (production models)
private var filteredAnthropicModels: [AnthropicModel] {
    anthropicModels.filter { model in
        let id = model.id.lowercased()
        return id.hasPrefix("claude-sonnet-4") ||
               id.hasPrefix("claude-opus-4") ||
               id.hasPrefix("claude-haiku-4")
    }
}
```

Update model picker section:
```swift
var onboardingInterviewModelPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
        // Backend selector
        Picker("Interview Provider", selection: $onboardingBackend) {
            Text("OpenAI (GPT-5)").tag("openai")
            Text("Anthropic (Claude)").tag("anthropic")
        }
        .pickerStyle(.segmented)
        .onChange(of: onboardingBackend) { _, newValue in
            Task {
                if newValue == "anthropic" {
                    await loadAnthropicModels()
                } else {
                    await loadInterviewModels()
                }
            }
        }

        // Model picker - conditional based on backend
        if onboardingBackend == "anthropic" {
            anthropicModelPicker
        } else {
            openAIModelPicker  // Existing picker logic
        }
    }
}

var anthropicModelPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
        if !hasAnthropicKey {
            Label("Add Anthropic API key above to enable model selection.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if isLoadingAnthropicModels {
            ProgressView()
                .controlSize(.small)
            Text("Loading Claude models...")
                .font(.caption)
        } else if let error = anthropicModelError {
            VStack(alignment: .leading) {
                Label("Failed to load models", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if filteredAnthropicModels.isEmpty {
            Text("No Claude 4 models available")
                .foregroundStyle(.secondary)
        } else {
            Picker("Interview Model", selection: $anthropicModelId) {
                ForEach(filteredAnthropicModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        }

        Text("Select Claude model for onboarding interviews.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private var hasAnthropicKey: Bool {
    APIKeyManager.get(.anthropic) != nil
}

@MainActor
private func loadAnthropicModels() async {
    guard let apiKey = APIKeyManager.get(.anthropic), !apiKey.isEmpty else {
        anthropicModelError = "Anthropic API key not configured"
        return
    }
    isLoadingAnthropicModels = true
    anthropicModelError = nil
    do {
        let service = AnthropicService(apiKey: apiKey)
        let response = try await service.listModels()
        anthropicModels = response.data
        // Validate current selection
        if !filteredAnthropicModels.contains(where: { $0.id == anthropicModelId }) {
            if let first = filteredAnthropicModels.first {
                anthropicModelId = first.id
            }
        }
    } catch {
        anthropicModelError = error.localizedDescription
    }
    isLoadingAnthropicModels = false
}
```

#### 6.7 Backend-Specific Settings (Reasoning, etc.)

**Goal:** Show different options based on selected backend.

| Setting | OpenAI | Anthropic |
|---------|--------|-----------|
| Reasoning Effort | `none/minimal/low/medium/high` | Extended Thinking (`budget_tokens`) |
| Flex Processing | Yes (50% cost savings) | N/A |
| Prompt Cache | `24h` retention | `cache_control` breakpoints |
| Web Search | Built-in tool | `web_search_20250305` server tool |

**Modify reasoning picker in `SettingsView.swift`:**

```swift
var onboardingReasoningPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
        if onboardingBackend == "anthropic" {
            // Claude: Extended Thinking with budget_tokens
            Toggle("Extended Thinking", isOn: $anthropicExtendedThinking)
            if anthropicExtendedThinking {
                Stepper("Token Budget: \(anthropicThinkingBudget)",
                        value: $anthropicThinkingBudget,
                        in: 1024...16384,
                        step: 1024)
                Text("Higher budgets allow deeper reasoning but increase latency.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            // OpenAI: Reasoning effort levels
            Picker("Default Reasoning", selection: $onboardingReasoningEffort) {
                ForEach(reasoningOptions, id: \.self) { Text($0).tag($0) }
            }
            Text("Controls reasoning depth for standard interview tasks.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

**New AppStorage keys for Anthropic settings:**
```swift
@AppStorage("onboardingAnthropicExtendedThinking") private var anthropicExtendedThinking: Bool = false
@AppStorage("onboardingAnthropicThinkingBudget") private var anthropicThinkingBudget: Int = 4096
```

---

## Files Summary (Direct Anthropic API)

### New Files in SwiftOpenAI Fork

| File | Purpose |
|------|---------|
| `Anthropic/AnthropicAPI.swift` | Endpoint definitions for `api.anthropic.com` |
| `Anthropic/AnthropicService.swift` | Service with `messagesStream()` and `listModels()` methods |
| `Anthropic/AnthropicStreamEvent.swift` | SSE event type definitions |
| `Anthropic/AnthropicParameters.swift` | Request/response Codable types |
| `Anthropic/AnthropicModels.swift` | `AnthropicModel`, `AnthropicModelsResponse` types for `/v1/models` |

### New Files in Onboarding

| File | Purpose |
|------|---------|
| `Onboarding/Core/AnthropicRequestBuilder.swift` | Builds Anthropic Messages API requests |
| `Onboarding/Core/AnthropicStreamAdapter.swift` | Maps Anthropic events → domain events |

### New/Modified Settings UI Files

| File | Changes |
|------|---------|
| `Shared/Utilities/APIKeyManager.swift` | Add `.anthropic` case to `APIKeyType` |
| `App/Views/Settings/APIKeysSettingsView.swift` | Add Anthropic API key editor + test endpoint |
| `App/Views/SetupWizardView.swift` | Add Anthropic key to wizard |
| `App/Views/SettingsView.swift` | Dynamic model picker (OpenAI vs Anthropic), backend-specific reasoning settings, `loadAnthropicModels()` |

### Files to Modify (Core)

| File | Changes |
|------|---------|
| `Shared/AI/Models/Services/LLMFacade.swift` | Add `.anthropic` backend, register service |
| `Onboarding/Core/LLMMessenger.swift` | Add Anthropic execution path, backend switch |
| `Onboarding/Core/NetworkRouter.swift` | Handle adapter domain events |

### Existing Infrastructure Reused

| File | What's Reused |
|------|---------------|
| `ChatTranscriptStore.swift` | Message history (client-managed) |
| `ToolRegistry.swift` | Tool schemas (convert to Anthropic format) |
| `OnboardingEvents.swift` | Domain events (adapter targets these) |

---

## Known Limitations & Considerations

### 1. Web Search / Web Fetch

**Anthropic API (Direct):** Claude has built-in server-side tools:
- `web_search_20250305` - $10 per 1,000 searches (uses Brave Search)
- `web_fetch_20250910` - No additional cost (beta, requires header)

**OpenRouter:** Has its **own** web search plugin system:
- Enable via `:online` suffix: `"model": "anthropic/claude-sonnet-4:online"`
- Or via plugin: `"plugins": [{"id": "web"}]`
- Uses "native search for Anthropic" but this is OpenRouter's wrapper
- **Does NOT appear to pass through** Anthropic's `web_search_20250305` tool type

**Recommendation:** Use **direct Anthropic API** for full feature parity:
- Native `web_search_20250305` and `web_fetch_20250910` support
- No intermediary translation layer
- Prompt caching with `cache_control` breakpoints
- Full API compatibility with future Anthropic features

### 2. Reasoning Display
- **Current**: OpenAI provides `reasoningSummaryDelta` events
- **Claude**: Has "extended thinking" feature
- **Solution**: Map Claude's thinking output to existing reasoning UI (OpenRouter already supports this via `reasoningDetails` in chunks)

### 3. Prompt Caching
- **Current**: OpenAI supports `promptCacheRetention: "24h"`
- **Claude/Anthropic**: Supports prompt caching with `cache_control` breakpoints
- **OpenRouter**: Check if caching headers are passed through
- **Solution**: Test and document caching behavior via OpenRouter

---

## Migration Path

### Feature Flag Approach
```swift
// In LLMMessenger.executeUserMessage()
let backend = UserDefaults.standard.string(forKey: "onboarding_llm_backend") ?? "openai"
if backend == "claude" {
    await executeUserMessageViaChatCompletions(...)
} else {
    await executeUserMessageViaResponsesAPI(...)  // Existing code
}
```

### Rollout Strategy
1. **Phase A**: Ship with OpenAI as default, Claude as opt-in setting
2. **Phase B**: After validation, switch default to Claude
3. **Phase C**: (Optional) Remove OpenAI Responses API code if full migration desired

### Session Continuity
Both paths restore from the same persisted messages (`OnboardingMessageRecord`). The `previousResponseId` field becomes unused for Claude path but remains for OpenAI compatibility.

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Tool compatibility | Test all 30+ onboarding tools with Claude before release |
| Prompt behavior differences | May need Claude-specific prompt tuning in `baseDeveloperMessage` |
| Session restoration edge cases | Both providers use same persistence format |
| Network payload size increase | Monitor but likely negligible impact |
| Streaming format differences | Comprehensive adapter testing |

---

## Open Questions

1. **Fallback behavior**: Keep both providers available, or full migration to Anthropic?
2. **Model selection**: Which Claude model as default?
   - `claude-sonnet-4-20250514` - Best balance of speed/capability
   - `claude-opus-4-20250514` - Most capable, higher cost
3. **Web search**: Enable `web_search_20250305` by default, or make opt-in?
4. **Prompt tuning**: Will existing prompts work well with Claude, or need adaptation?
5. **API key management**: How to handle Anthropic API key alongside existing OpenAI/OpenRouter keys?

---

## Reference: Anthropic Messages API

### Endpoint
```
POST https://api.anthropic.com/v1/messages
```

### Headers
```
x-api-key: $ANTHROPIC_API_KEY
anthropic-version: 2023-06-01
anthropic-beta: web-fetch-2025-09-10  (for web_fetch tool)
content-type: application/json
```

### Key Documentation
- [Messages API](https://docs.anthropic.com/en/api/messages)
- [Web Search Tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)
- [Web Fetch Tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool)
- [Streaming](https://docs.anthropic.com/en/api/messages-streaming)

### Existing Reference Code
The Discovery module uses OpenRouter (different approach), but tool execution patterns can be referenced:
- `Sprung/Discovery/Services/DiscoveryAgentService.swift` - Tool loop pattern
- `Sprung/Discovery/Tools/DiscoveryToolExecutor.swift` - Tool execution
