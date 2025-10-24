# **Onboarding Interview Feature \- Revised SPEC Completion & Analysis**

## **Executive Summary**

This is a greenfield implementation with no migration concerns and complete freedom to build the optimal solution. The existing onboarding interview code can be deleted entirely, preserving only the UI components. This document addresses all SPEC TO-DO items and incorporates detailed tool specifications, state management design, and current model recommendations.

## **1\. SPEC TO-DO Completions (Revised)**

### **1.3 ResRef to ArtifactRecord (Updated)**

**Location:** Data Types section \- KnowledgeCard/ArtifactRecord  
**Assessment:** Clean slate implementation \- no migration required.  
**Action Plan:**

1. Delete all ResRef-related files  
2. Implement ArtifactRecord as the primary artifact storage model  
3. Update all calling sites to use new ArtifactRecord API  
4. No backward compatibility code needed

**Files to Update:**

* Replace ResRefStore.swift with ArtifactRecordStore.swift  
* Update all import statements and references

### **1.4 CoverRef to WritingSample (Updated)**

**Location:** Data Types section \- WritingSample  
**Assessment:** Direct replacement with no migration path needed.  
**Action Plan:**

1. Delete CoverRefStore.swift and related files  
2. Implement WritingSample with full schema  
3. Update all calling sites directly  
4. No adapter code required

### **1.5 WritingStyleProfile Elimination**

**Confirmed:** Eliminate WritingStyleProfile completely. Direct sample matching provides better fidelity.

### **1.9 Agent Model Selection (Updated with GPT-5)**

**Location:** Agent Definitions section  
Updated Model Policy (GPT-5 Series):  
All model selection is centralized in a ModelProvider to ensure consistency. We prioritize intelligence over speed over cost. We will use the Responses API with new parameters like text.verbosity and reasoning.effort.  
**How we’ll choose models (priority: intelligence \> speed \> cost)**

* Use **GPT-5 (large)** when orchestration or generation requires judgment, multi-step planning, or synthesis.  
* Use **GPT-5-mini** for most structured tasks (extraction, validation, small transformations) with reasoning.effort: "minimal" unless the step fails.  
* Use **GPT-5-nano** only for tiny, deterministic chores (e.g., label/classify/route) where you care most about speed.  
* Keep **o-series (o1)** available for hard reasoning spikes if needed.

**Drop-in ModelProvider (single source of truth)**  
enum TaskType {  
    case orchestrator       // planning, multi-step conversation  
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
            // Highest intelligence first  
            return .init(id: "gpt-5", defaultVerbosity: "medium", defaultReasoningEffort: nil)  
        case .validate, .extract:  
            // Fast, cheap, deterministic  
            return .init(id: "gpt-5-mini", defaultVerbosity: "low", defaultReasoningEffort: "minimal")  
        case .summarize:  
            // Fastest, cheapest  
            return .init(id: "gpt-5-nano", defaultVerbosity: "low", defaultReasoningEffort: "minimal")  
        }  
    }

    // Optional “escape hatch” for extra-hard reasoning  
    static func escalate(\_ prior: Config) \-\> Config {  
        // Move to an o-series model only if the task truly needs deep reasoning  
        return .init(id: "o1", defaultVerbosity: prior.defaultVerbosity, defaultReasoningEffort: nil)  
    }  
}

**Note:** Costs are variable and tool calls may be billed separately. We will default to mini tiers and escalate only when needed. See official pricing for details.

## **2\. Tool Complexity Deep Dive**

### **2.1 Complete Tool Specification**

All tools will follow the canonical, schema-first, dynamic JSON interface as defined in the LLM Tools Specification document.

#### **Core Local Execution Tools**

1. **GetUserOption**  
2. **SubmitForValidation**  
3. **GetUserUpload**  
4. **GetMacOSContactCard**  
5. **SetObjectiveStatus**

#### **Data Persistence Tools**

6. **PersistKnowledgeCard**  
7. **PersistArtifact**

#### **Agent Deployment Tools**

8. **DeployAgent**

*(See tool\_specification.md for full JSON schemas and implementation details.)*

### **2.2 Tool Implementation Requirements**

**Infrastructure Needed:**

1. Tool registry with automatic discovery  
2. Tool execution queue  
3. **Continuation ID persistence** (e.g., a simple dictionary keyed by UUID) to ensure waiting tools can survive an app quit.  
4. Error recovery and retry logic  
5. Tool response caching (postponed for v1)

**Tool Response Types:**  
// From canonical Tool Specification  
enum ToolResult {  
    case immediate(JSON)  
    case waiting(String, ContinuationToken)  
    case error(ToolError)  
}

## **3\. State Machine Design**

### **3.1 State Machine (v1)**

Per edit guidance, the expansive state machine is replaced with a minimal session struct and a single waiting flag. This avoids over-abstraction.  
// See state\_machine\_specification.md for the full implementation  
enum Phase: String, Codable {  
    case phase1CoreFacts  
    case phase2DeepDive  
    case phase3WritingCorpus  
    case complete  
}

struct Session {  
    var phase: Phase \= .phase1CoreFacts  
    var objectivesDone: Set\<String\> \= \[\]  
    var waiting: Waiting? \= nil  // .selection / .upload / .validation

    enum Waiting: String, Codable {  
        case selection  
        case upload  
        case validation  
    }  
}

actor InterviewState {  
    private(set) var session \= Session()  
      
    // ... (See State Machine Specification for transition logic) ...  
}

## **4\. Error Recovery Contingencies**

### **4.1 Network Failures**

**Recovery Strategy:**

* Automatic retry with exponential backoff  
* Checkpoint before each API call  
* Graceful degradation to limited functionality

### **4.2 Agent Timeouts**

**Recovery Strategy:**

* **30-second inactivity timeout** for all agent calls, managed by a StreamWatchdog.  
* Automatic retry with a different model (e.g., escalate to o1) if gpt-5 fails.  
* Fall back to simpler prompts  
* Manual intervention option

### **4.3 Invalid Data**

**Recovery Strategy:**

* Schema validation at every step  
* User correction interface  
* Partial save capability  
* Skip and continue option

### **4.4 User Abandonment**

**Recovery Strategy:**

* Auto-save checkpoints frequently.  
* On next launch, check for a checkpoint and offer to resume from that exact point.  
* Progressive data collection (useful even if incomplete).

## **5\. Service Architecture**

### **5.1 Service Decomposition**

Based on the recommendation to split OnboardingInterviewService:  
// Core orchestration  
class InterviewOrchestrator {  
    private let toolExecutor: ToolExecutor  
    private let artifactStore: ArtifactStore  
    private let progressTracker: ProgressTracker // This is now the InterviewState actor  
    private let agentManager: AgentManager  
      
    func startInterview() async  
    func processUserInput(\_ input: String) async  
    func handleToolResponse(\_ response: ToolResponse) async  
    func transitionPhase() async  
}

// Tool execution  
class ToolExecutor {  
    private let toolRegistry: ToolRegistry  
    private let executionQueue: DispatchQueue  
      
    func execute(\_ toolCall: ToolCall) async \-\> ToolResponse  
    func registerTool(\_ tool: Tool)  
    func cancelExecution(\_ id: String)  
}

// Data persistence  
class ArtifactStore {  
    func save(\_ artifact: ArtifactRecord) async  
    func save(\_ knowledgeCard: KnowledgeCard) async  
    func save(\_ writingSample: WritingSample) async  
    func fetchAll\<T\>(type: T.Type) async \-\> \[T\]  
}

// Progress management  
class ProgressTracker {  
    private let stateMachine: InterviewState // The minimal actor  
      
    func updateObjective(\_ id: String, status: ObjectiveStatus)  
    func currentPhase() \-\> Phase  
    func completionPercentage() \-\> Double  
    func checkpoint() async  
}

// Agent management  
class AgentManager {  
    // Manages deploying sub-agents  
    func createAgent(\_ type: AgentType) \-\> Agent  
}

### **5.2 Async Architecture**

**Why Async Matters:**

* All OpenAI API calls are network operations  
* Tool execution may involve file I/O  
* UI must remain responsive during processing  
* Multiple agents may run concurrently

**Implementation Approach (using Responses API):**  
// Use Swift's async/await throughout  
actor InterviewSession {  
    private var state: Session  
    private var activeTools: Set\<String\> \= \[\]  
      
    func processMessage(\_ message: String) async throws {  
        // Async OpenAI API call  
        let cfg \= ModelProvider.forTask(.orchestrator)  
        let resp \= try await client.responses.create(  
            model: cfg.id,  
            input: messages,  
            text: cfg.defaultVerbosity.map { \["verbosity": $0\] },  
            reasoning: cfg.defaultReasoningEffort.map { \["effort": $0\] }  
        )  
          
        // Process tool calls concurrently  
        if let toolCalls \= resp.toolCalls {  
            try await withThrowingTaskGroup(of: ToolResponse.self) { group in  
                for toolCall in toolCalls {  
                    group.addTask {  
                        return try await self.executeTool(toolCall)  
                    }  
                }  
                  
                // Collect results  
                for try await result in group {  
                    await handleToolResponse(result)  
                }  
            }  
        }  
    }  
}

## **6\. Implementation Recommendations**

### **6.1 Build from Scratch**

* Delete all existing onboarding interview code  
* Keep only UI components  
* No migration code, no feature flags, no backward compatibility

### **6.2 Prototype First**

**M0 Milestone Goals:**

* Single orchestrator agent working  
* Basic tool execution (GetUserOption, SubmitForValidation)  
* Minimal state management  
* Prove the architecture

### **6.3 No Mocks**

Avoid mock implementations \- build real tools from the start. Mocks become technical debt.

### **6.4 Focus on Function Over Form**

* Get core functionality working first  
* UI polish comes after functionality proven  
* Avoid over-engineering early  
* Ship working code, iterate on design

## **7\. Files to Delete**

**Complete removal list:**  
/Onboarding/Models/  
\- OnboardingArtifactRecord.swift ❌ DELETE  
\- OnboardingArtifacts.swift ❌ DELETE  
\- OnboardingValidationRequests.swift ❌ DELETE  
\- OnboardingWizardState.swift ❌ DELETE

/Onboarding/Services/  
\- ArtifactSummarizer.swift ❌ DELETE  
\- LinkedInProfileExtractor.swift ❌ DELETE  
\- OnboardingArtifactStore.swift ❌ DELETE  
\- OnboardingArtifactValidator.swift ❌ DELETE  
\- OnboardingInterviewMessageManager.swift ❌ DELETE  
\- OnboardingInterviewRequestHandler.swift ❌ DELETE  
\- OnboardingInterviewRequestManager.swift ❌ DELETE  
\- OnboardingInterviewResponseProcessor.swift ❌ DELETE  
\- OnboardingInterviewService.swift ❌ DELETE  
\- OnboardingInterviewStreamHandler.swift ❌ DELETE  
\- OnboardingInterviewWizardManager.swift ❌ DELETE  
\- OnboardingLLMResponseParser.swift ❌ DELETE  
\- OnboardingPendingExtraction.swift ❌ DELETE  
\- OnboardingPromptBuilder.swift ❌ DELETE  
\- OnboardingToolCatalog.swift ❌ DELETE  
\- OnboardingToolExecutor.swift ❌ DELETE  
\- OnboardingUploadRegistry.swift ❌ DELETE  
\- ResumeRawExtractor.swift ❌ DELETE  
\- SchemaValidator.swift ❌ DELETE  
\- SystemContactsFetcher.swift ❌ DELETE  
\- WebLookupService.swift ❌ DELETE  
\- WritingSampleAnalyzer.swift ❌ DELETE

/DataManagers/  
\- ResRefStore.swift ❌ DELETE  
\- CoverRefStore.swift ❌ DELETE

**Keep only:**

* UI components in /Onboarding/Views/  
* Basic data stores that work well

## **8\. Critical Success Factors**

### **8.1 Technical Excellence**

* Clean architecture from day one  
* Proper error handling throughout  
* Comprehensive debug logging  
* State recovery capability

### **8.2 User Experience**

* Sub-2 second response times  
* Clear progress indicators  
* Graceful error messages  
* Ability to pause and resume

### **8.3 Data Quality**

* Rigorous validation at every step  
* No hallucinated information  
* User confirmation for all data  
* Citation tracking for claims

## **9\. Next Steps (M-Milestone Scope)**

### **M0 – Skeleton running**

* OpenAI client \+ ModelProvider wired (GPT-5 params)  
* Orchestrator loop calling Responses API  
* Tool registry with three tools: get\_user\_option, submit\_for\_validation, persist\_data  
* Minimal state machine (Phase \+ objectives \+ waiting) and checkpoints

### **M1 – Phase 1 usable**

* Applicant profile (manual \+ optional macOS "Me" card)
* Skeleton timeline from resume upload (parsing can be naive - improved in M2 with OpenRouter PDF extraction, see `pdf_extraction_specification.md`)
* User validation loop (approve/modify)

### **M2 – Deep dive basics**

* One experience interview end-to-end
* Generate a single Knowledge Card and validate it
* Save artifacts (text only at first)
* **OpenRouter PDF extraction** - Replace naive text extraction with Gemini 2.0 Flash for OCR, layout preservation, and multimodal processing

### **M3 – Personal-use polish**

* Writing samples (optional)  
* Light UX polish, resume from checkpoint, robust inactivity timeouts

## **Conclusion**

With a clean slate approach and modern OpenAI models (GPT-5 series, and o-series for reasoning), this implementation can be streamlined and powerful. The key is to:

1. Start fresh \- delete all old code  
2. Build real tools, not mocks  
3. Focus on core functionality  
4. Use proper async patterns throughout  
5. Use debugLog for logging

No migration concerns, no backward compatibility, no feature flags \- just clean, modern code built for the task at hand.