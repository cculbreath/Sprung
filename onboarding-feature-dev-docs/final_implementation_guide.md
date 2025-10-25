# **Onboarding Interview \- Final Implementation Guide**

## **Executive Summary**

Clean slate implementation with no migration concerns, no backward compatibility, and no legacy preservation. This is a personal project with complete freedom to delete and rebuild using the latest OpenAI models and best practices.

## **Key Architectural Decisions**

### **1\. Service Architecture Split**

Based on reviewer feedback, split OnboardingInterviewService into focused services:  
// Clean separation of concerns  
/Onboarding/  
  /Core/  
    InterviewOrchestrator.swift      // Manages interview flow and LLM interactions  
    ToolExecutor.swift               // Handles all tool execution  
    ArtifactStore.swift             // Manages all artifact storage  
    ProgressTracker.swift           // Tracks objectives and phase transitions (via InterviewState)  
      
  /Services/  
    AgentManager.swift              // Manages sub-agent deployment  
    ValidationService.swift         // Handles all data validation  
    UICoordinator.swift            // Manages UI state updates

**Benefits of this split:**

* Single responsibility per service  
* Easier testing and debugging  
* Clear dependency injection  
* Better async/await isolation

### **2\. Latest OpenAI Models (GPT-5 Series)**

We will adopt the new ModelProvider policy as the single source of truth for model selection. We prioritize intelligence \> speed \> cost. We will use the **Responses API** with new parameters like text.verbosity and reasoning.effort.

Allowed Tools per Phase (sanitized manifest + enforcement)**    
The orchestrator computes an **allowed tools list** and passes only those to the model per turn.  **Model Selection Policy:**
Use `capabilities.describe` to inform planning; hide all vendor specifics.  
Phase 1 example: `["get_user_option","get_user_upload","extract_document","submit_for_validation","persist_data"]`.* Use **GPT-5 (large)** for orchestration, planning, or synthesis.  
* Use **GPT-5-mini** for most structured tasks (extraction, validation) with reasoning.effort: "minimal".  
Responses API tuning for GPT‑5**  * Use **GPT-5-nano** for tiny, deterministic chores (e.g., routing).  
Phase prompts use `text.verbosity="medium"`; extraction micro‑steps use `text.verbosity="low", reasoning.effort="minimal"`.  * Keep **o-series (o1)** available as an "escape hatch" for hard reasoning spikes.  
Reuse reasoning with `previous_response_id` when chaining tool calls.* We will default to mini tiers and escalate only when needed. (See official pricing notes for cost details).

Universal PDF handling**  enum TaskType {  
After any upload, call `extract_document` for PDFs/DOCX; do not parse inline in tools or prompts.    case orchestrator       // planning, multi-step conversation  
    case validate           // user-approval & schema checks  
    case extract            // resume/link parsing, light transforms  
    case summarize          // short summaries/classifications  
    case knowledgeCard      // card drafting with some synthesis  
}

struct ModelProvider {  
    struct Config {  
        let id: String  
        let defaultVerbosity: String?     // "low" | "medium" | "high"  
        let defaultReasoningEffort: String? // nil | "minimal"  
    }

    static func forTask(\_ t: TaskType) \-\> Config {  
        switch t {  
        case .orchestrator, .knowledgeCard:  
            return .init(id: "gpt-5", defaultVerbosity: "medium", defaultReasoningEffort: nil)  
        case .validate, .extract:  
            return .init(id: "gpt-5-mini", defaultVerbosity: "low", defaultReasoningEffort: "minimal")  
        case .summarize:  
            return .init(id: "gpt-5-nano", defaultVerbosity: "low", defaultReasoningEffort: "minimal")  
        }  
    }  
      
    static func escalate(\_ prior: Config) \-\> Config {  
        return .init(id: "o1", defaultVerbosity: prior.defaultVerbosity, defaultReasoningEffort: nil)  
    }  
}

### **3\. Clean Slate Implementation**

**What we're deleting completely:**  
\# Remove ALL old onboarding interview code  
rm \-rf Onboarding/Models/\*  
rm \-rf Onboarding/Services/\*  
rm \-rf Onboarding/ViewModels/\*  
rm DataManagers/ResRefStore.swift  
rm DataManagers/CoverRefStore.swift

\# Keep only the UI views  
\# Keep ApplicantProfileStore.swift  
\# Keep ExperienceDefaultsStore.swift

**What we're building fresh:**

* New data models (ArtifactRecord, KnowledgeCard)  
* New service architecture  
* Direct tool implementations (schema-first JSON, per Tool Spec)  
* Minimal state machine (Session/Phase/objectives)

### **4\. Async/Await Architecture**

**Why Async Everywhere:**  
// All OpenAI API calls are async  
let cfg \= ModelProvider.forTask(.orchestrator)  
let response \= try await client.responses.create(  
    model: cfg.id,  
    input: messages,  
    text: cfg.defaultVerbosity.map { \["verbosity": $0\] },  
    reasoning: cfg.defaultReasoningEffort.map { \["effort": $0\] }  
)

// All tool executions are async  
let result \= try await tool.execute(params)

// All data operations are async  
await store.persist(data)

// Benefits:  
// \- No callback hell  
// \- Clean error propagation with try/await  
// \- Natural composition of async operations  
// \- Built-in cancellation support  
// \- Better performance with concurrent operations

**Async Implementation Pattern:**  
actor InterviewOrchestrator {  
    // Actor ensures thread safety for state  
    private var state: InterviewState  
      
    // All public methods are async  
    func startInterview() async throws {  
        // ...  
    }  
      
    // Natural error handling  
    func processStep() async throws {  
        do {  
            let response \= try await callOpenAI()  
            await updateUI(response)  
        } catch {  
            await handleError(error)  
            throw error  // Propagates naturally  
        }  
    }  
}

### **5\. State Management Without Complexity**

**Minimal State Pattern:**  
// See state\_machine\_specification.md for the full implementation  
enum Phase: String, Codable {  
    case phase1CoreFacts, phase2DeepDive, phase3WritingCorpus, complete  
}

struct Session {  
    var phase: Phase \= .phase1CoreFacts  
    var objectivesDone: Set\<String\> \= \[\]  
    var waiting: Waiting? \= nil  
    enum Waiting: String, Codable { case selection, upload, validation }  
}

actor InterviewState {  
    private(set) var session \= Session()  
    // ... transition logic ...  
}

### **6\. UI as Pure Presenter**

Following the other agent's recommendation:  
// UI only displays and collects input  
class InterviewUI: ObservableObject {  
    @Published var currentPrompt: String \= ""  
    @Published var options: \[Option\] \= \[\]  
    @Published var validationData: Any?  
    @Published var isWaiting: Bool \= false  
      
    // UI writes to stores  
    func userSelectedOption(\_ id: String) {  
        Task {  
            await dataStore.recordSelection(id)  
            await orchestrator.continueFromSelection(id)  
        }  
    }  
      
    // Stores emit changes, UI reacts  
    func observeStores() {  
        dataStore.$changes  
            .sink { \[weak self\] change in  
                self?.updateUI(for: change)  
            }  
            .store(in: \&cancellables)  
    }  
}

## **Implementation Scope (Milestones)**

### **M0 – Skeleton running**

* OpenAI client \+ ModelProvider wired (GPT-5 params)  
* Orchestrator loop calling Responses API  
* Tool registry with three tools: get\_user\_option, submit\_for\_validation, persist\_data  
* Minimal state machine (Phase \+ objectives \+ waiting) and checkpoints

### **M1 – Phase 1 usable**

* Applicant profile (manual \+ optional macOS "Me" card)
* Skeleton timeline from resume upload * 
* **OpenRouter PDF extraction** - Replace naive text extraction with Gemini 2.0 Flash for OCR, layout preservation, and multimodal processing

* User validation loop (approve/modify)

### **M2 – Deep dive basics**

* One experience interview end-to-end
* Generate a single Knowledge Card and validate it
* Save artifacts 

### **M3 – Personal-use polish**

* Writing samples (optional)  
* Light UX polish, resume from checkpoint, robust inactivity timeouts

## **Key Implementation Details**

### **1\. Auth-Dependent Features (Out of Scope)**

Auth-dependent functionality is **out of scope** for v1. Do not mock, guess, or partially wire. Before any code is written, create a short design brief covering: required scopes, token storage (Keychain), rate-limit strategy, and failure UX. Until then, tools like query\_github\_repo or fetch\_url must return a user-visible “not configured” error.  
struct QueryGitHubRepoTool: InterviewTool {  
    // ... name, description, parameters  
    func execute(\_ params: JSON) async throws \-\> ToolResult {  
        return .error(.executionFailed("GitHub analysis is not configured. Please skip for now."))  
    }  
}

### **2\. No Premature Optimization**

// ❌ Don't do this  
class CachedAPIClient {  
    var cache: \[String: Response\] \= \[:\]  
    // ... etc ...  
}

// ✅ Do this  
class APIClient {  
    func call(\_ prompt: String) async throws \-\> String {  
        let cfg \= ModelProvider.forTask(.orchestrator)  
        let resp \= try await client.responses.create(model: cfg.id, ...)  
        return resp.text  
    }  
}  
// Add caching later if actually needed

### **3\. Simple Logging**

// Just log what matters in DEBUG  
@inline(\_\_always) func debugLog(\_ msg: @autoclosure () \-\> String) {  
    \#if DEBUG  
    print("🔎", msg())  
    \#endif  
}

### **4\. Direct Tool Implementation**

All tools will conform to the canonical InterviewTool protocol from the LLM Tools Specification.  
// Real implementation from the start  
class GetUserOptionTool: InterviewTool {  
    // ... name, description, parameters  
      
    func execute(\_ params: JSON) async throws \-\> ToolResult {  
        // Update UI immediately  
        await MainActor.run {  
            UI.showOptions(params.options)  
        }  
          
        // Wait for user  
        let selection \= await UI.waitForSelection()  
          
        // Return result  
        return .immediate(selection)  
    }  
}  
// No mock needed \- this IS the implementation

### **5\. Error Handling That Works**

// Simple, effective error handling  
enum InterviewError: Error {  
    case apiFailure(Error)  
    case userCancelled  
    case invalidState(String)  
}

extension InterviewOrchestrator {  
    func handleError(\_ error: Error) async {  
        switch error {  
        case InterviewError.userCancelled:  
            // Just stop  
            await cleanup()  
        case InterviewError.apiFailure(let apiError):  
            // Log and retry once  
            debugLog("API failed: \\(apiError)")  
            await retryLastOperation()  
        default:  
            // Log and continue  
            debugLog("Error: \\(error)")  
        }  
    }  
}

### **6\. Testing**

Automated testing of the stochastic LLM loop is not a v1 goal. We will use three zero-learning-curve safeguards:

1. **Schema checks at the edges** — validate tool params and tool responses against your JSON Schemas (deterministic and cheap).  
2. **Checkpoint round-trip** — one button in a debug menu: “Save checkpoint → Clear memory → Restore” (manual smoke test).  
3. **Hard preconditions** — preconditionFailure for impossible states in DEBUG; graceful handling in RELEASE.

## **What We're NOT Building**

1. **No Migration Code** \- Starting fresh  
2. **No Feature Flags** \- Single version  
3. **No Backward Compatibility** \- New system only  
4. **No Mocks** \- Real implementations only  
5. **No Complex Abstractions** \- Direct, simple code  
6. **No Premature Optimization** \- Make it work first  
7. **No Analytics** \- Postponed  
8. **No Email Reminders** \- Removed  
9. **No Auth Features** \- (GitHub, private URLs)  
10. **No Security Posture** \- (Encryption-at-rest, etc.)

## **Success Metrics**

### **Definition of Done**

* Can complete M0-M3 milestones  
* Data persists correctly via Checkpoints actor  
* UI is responsive  
* Errors don't crash app  
* Works for your personal use case

## **Final Notes**

This is YOUR project. The implementation should:

* Be simple and direct  
* Work for your specific needs  
* Be enjoyable to build  
* Not over-engineer solutions  
* Ship when you're happy with it

Remember: The best code is code that ships and solves your problem. Everything else is optional.

## **Quick Reference**

### **Models to Use**

* **Orchestrator**: gpt-5  
* **Knowledge Cards**: gpt-5  
* **Simple Tasks**: gpt-5-mini / gpt-5-nano  
* **Reasoning Spike**: o1 (escalation only)

### **Architecture Pattern**

UI → ToolExecutor → Orchestrator → OpenAI  
         ↓              ↓  
    ArtifactStore  CheckpointActor

### **State Flow**

Phase1 → Phase2 → Phase3 → Complete  
(Managed by InterviewState actor)

### **Tool Pattern**

// Per Tool Specification  
Tool receives params → Updates UI → Waits for user → Returns result

### **Error Pattern**

Try operation → Catch error → Log → Retry once → Continue or fail gracefully  
