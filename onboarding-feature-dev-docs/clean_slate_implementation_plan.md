# **Onboarding Interview \- Clean Slate Implementation Plan**

## **Overview**

This is a personal project with complete freedom to delete and rebuild. No migration, no backward compatibility, no stakeholder management. Just clean, focused implementation.

## **Week 0: Scorched Earth & Setup**

### **Day 1: Complete Cleanup**

**Morning: Delete Everything**  
```
\# Delete all obsolete files  
rm \-rf Onboarding/Models/\*  
rm \-rf Onboarding/Services/\*  
rm \-f DataManagers/ResRefStore.swift  
rm \-f DataManagers/CoverRefStore.swift
```
**Afternoon: Create New Structure**  
````
/Onboarding/  
  /Core/  
    InterviewOrchestrator.swift  
    InterviewSession.swift        // Replaces InterviewStateMachine.swift  
    CheckpointActor.swift       // New checkpointing  
  /Tools/  
    ToolProtocol.swift          // Points to Tool Spec  
    ToolExecutor.swift  
    ToolRegistry.swift  
    /Implementations/  
      GetUserOptionTool.swift  
      SubmitForValidationTool.swift  
      GetUserUploadTool.swift  
      SetObjectiveStatusTool.swift  
      PersistDataTool.swift  
  /Agents/  
    AgentManager.swift  
    OrchestratorAgent.swift  
  /Models/  
    KnowledgeCard.swift  
    ArtifactRecord.swift  
    SkeletonTimeline.swift  
    InterviewProgress.swift  
    CandidateDossier.swift  
  /Stores/  
    KnowledgeCardStore.swift  
    ArtifactRecordStore.swift  
    InterviewProgressStore.swift
````
### **Day 2-3: Core Infrastructure**

**Essential Setup:**  
````
// 1\. Configure OpenAI client 
 
let configuration \= OpenAI.Configuration(  
    apiKey: ProcessInfo.processInfo.environment\["OPENAI\_API\_KEY"\]\!,  
    organizationId: nil,  
    timeoutInterval: 30.0 // Note: Will be managed by StreamWatchdog  
)

// 2\. Model configuration (Centralized)  
// We use ModelProvider as the single source of truth.  

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

// 3\. Basic debug-only logging  

@inline(\_\_always) func debugLog(\_ msg: @autoclosure () \-\> String) {  
    \#if DEBUG  
    print("🔎", msg())  
    \#endif  
}
```

## **M0 – Skeleton running**

### **Day 1-2: Data Models & State Machine**

**Priority Implementation Order:**

1. InterviewSession.swift \- Minimal state definitions  
2. CheckpointActor.swift \- Persistence  
3. KnowledgeCard.swift \- Core data model  
4. ArtifactRecord.swift \- Artifact storage  
5. InterviewProgress.swift \- Progress tracking

**Minimal State Machine Implementation:**  
// See state\_machine\_specification.md for the full, minimal implementation  
```
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
```
**Checkpointing Implementation:**  
```
struct Checkpoint: Codable {  
    let t: Date  
    let phase: Phase  
    let objectivesDone: \[String\]  
}

actor Checkpoints {  
    private var last: \[Checkpoint\] \= \[\] // keep last N only  
    private let url: URL \= {  
        let appSup \= FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)\[0\]  
        try? FileManager.default.createDirectory(at: appSup, withIntermediateDirectories: true)  
        return appSup.appendingPathComponent("Interview.checkpoints.json")  
    }()  
    private let maxN \= 8

    func save(from s: Session) async {  
        last.append(.init(t: Date(), phase: s.phase, objectivesDone: Array(s.objectivesDone)))  
        if last.count \> maxN { last.removeFirst(last.count \- maxN) }  
        do {  
            let data \= try JSONEncoder().encode(last)  
            try data.write(to: url, options: .atomic)  
        } catch { debugLog("Checkpoint save failed: \\(error)") }  
    }

    func restoreLatest() async \-\> Session? {  
        guard let data \= try? Data(contentsOf: url),  
              let arr \= try? JSONDecoder().decode(\[Checkpoint\].self, from: data),  
              let cp \= arr.max(by: { $0.t \< $1.t }) else { return nil }  
        var s \= Session()  
        s.phase \= cp.phase  
        s.objectivesDone \= Set(cp.objectivesDone)  
        return s  
    }  
}
```
### **Day 3-4: Tool Framework**

Core Tool Protocol:  
The canonical tool protocol is defined in the LLM Tools Specification. We will not use generics or associatedtype.  
// See tool\_specification.md for definitions  
```
protocol InterviewTool {  
    var name: String { get }  
    var description: String { get }  
    var parameters: JSONSchema { get }  
    func execute(\_ params: JSON) async throws \-\> ToolResult  
}

enum ToolResult {  
    case immediate(JSON)  
    case waiting(String, ContinuationToken)  
    case error(ToolError)  
}
```
**Tool Implementation Example:**  
// This tool conforms to the canonical protocol from the Tool Spec.  
```
struct GetUserOptionTool: InterviewTool {  
    let name \= "get\_user\_option"  
    let description \= "Present multiple choice to user"  
    let parameters: JSONSchema \= /\* ... schema definition ... \*/

    func execute(\_ params: JSON) async throws \-\> ToolResult {  
        // 1\. Decode params from raw JSON  
        let request \= try JSONDecoder().decode(OptionRequest.self, from: params.data)  
          
        // 2\. Update UI  
        await MainActor.run {  
            InterviewUI.shared.presentOptions(request)  
        }  
          
        // 3\. Return waiting status with continuation ID  
        let continuationId \= UUID()  
        let token \= ContinuationToken(id: continuationId, /\*...\*/)  
        PendingTools.shared.register(token)  
          
        return .waiting(  
            message: "Waiting for user selection",  
            continuation: token  
        )  
    }  
}
```
### **Day 5: Basic Orchestrator**

**Minimal Working Orchestrator (using Responses API):**  
actor InterviewOrchestrator {  
    private let client: OpenAI.Client // Assuming OpenAI client  
    private let state: InterviewState  
    private let toolExecutor: ToolExecutor  
    private var messages: \[ChatMessage\] \= \[\]  
      
    func startInterview() async throws {  
        // ... system prompt setup ...  
        await processNextStep()  
    }  
      
    func processNextStep() async {  
        let cfg \= ModelProvider.forTask(.orchestrator)  
          
        do {  
            // Use the Responses API  
            let resp \= try await client.responses.create(  
                model: cfg.id,  
                input: messages,  
                tools: toolExecutor.availableTools,  
                text: cfg.defaultVerbosity.map { \["verbosity": $0\] },  
                reasoning: cfg.defaultReasoningEffort.map { \["effort": $0\] }  
            )

            // ... handle response, tool calls, or content ...  
              
        } catch {  
            debugLog("Orchestrator error: \\(error.localizedDescription)")  
            await handleError(error)  
        }  
    }  
}

## **M1 – Phase 1 usable**

### **Day 1-2: ApplicantProfile Collection**

**Implementation Focus:**

* Contact card fetching (using withCheckedThrowingContinuation wrapper).  
* Manual entry UI integration.  
* Upload handling for resume/LinkedIn.  
* Validation and user confirmation loop (submit\_for\_validation tool).

### **Day 3-4: SkeletonTimeline Building**

**Key Components:**

* Resume parsing (can be naive gpt-5-mini extraction).  
* LinkedIn extraction (if URL provided).  
* Timeline validation loop.  
* User confirmation UI.

### **Day 5: Progress Tracking & Phase Transition**

**Progress Implementation:**  
// This logic is now inside the InterviewState actor  
```
actor InterviewState {  
    // ...  
    func completeObjective(\_ id: String) async {  
        session.objectivesDone.insert(id)  
        if shouldAdvancePhase() {  
            advancePhase()  
            debugLog("Advanced to phase: \\(session.phase)")  
        }  
    }  
      
    private func shouldAdvancePhase() \-\> Bool {  
        switch session.phase {  
        case .phase1CoreFacts:  
            return \["applicant\_profile", "skeleton\_timeline", "enabled\_sections"\]  
                .allSatisfy(session.objectivesDone.contains)  
        // ... other phases  
        default: return false  
        }  
    }  
    // ...  
}
```
## **M2 – Deep dive basics**

### **Day 1-2: Knowledge Card Generator**

**Agent Implementation:**  
```
class KnowledgeCardAgent {  
    private let client: OpenAI.Client  
      
    func generateCard(  
        for experience: Experience,  
        artifacts: \[ArtifactRecord\],  
        transcript: String  
    ) async throws \-\> KnowledgeCard {  
          
        let cfg \= ModelProvider.forTask(.knowledgeCard)  
        let prompt \= KnowledgeCardPrompts.build(...)  
          
        let resp \= try await client.responses.create(  
            model: cfg.id,  
            input: \[ChatMessage(role: .user, content: prompt)\],  
            responseFormat: .jsonObject,  
            text: cfg.defaultVerbosity.map { \["verbosity": $0\] },  
            reasoning: cfg.defaultReasoningEffort.map { \["effort": $0\] }  
        )  
          
        return try JSONDecoder().decode(KnowledgeCard.self, from: resp.data)  
    }  
}
```

### **Day 3-4: Artifact Ingestion**

**Artifact Processing Pipeline:**

* Use gpt-5-mini with reasoning.effort: "minimal" for text extraction.  
* Generate metadata.  
* Create citations.  
* Build and persist ArtifactRecord.

### **Day 5: Experience Interview Flow**

* Loop through timeline experiences.  
* Ask targeted questions.  
* Generate Knowledge Card for one experience.  
* Validate with user.

## **M3 – Personal-use polish**

### **Day 1-2: Writing Sample Collection**

* Simple implementation using get\_user\_upload.  
* Store as ArtifactRecord.

### **Day 3: CandidateDossier Completion**

* Weave dossier questions throughout.  
* Build comprehensive profile.

### **Day 4-5: UI Polish & Error Recovery**

* Integrate StreamWatchdog for 30s inactivity timeout.  
* Ensure "Resume from checkpoint" works on launch.  
* Add loading states and clear error messages (no alerts).

## **Implementation Guidelines**

### **Code Quality Standards**

**Keep It Simple:**  
// ✅ Simple and clear, per Tool Spec  
```
func executeTool(\_ name: String, params: JSON) async throws \-\> JSON {  
    // Direct implementation  
}
```
**Async Everywhere:**

* All API calls use async/await.  
* No completion handlers.

**Fail Fast (in Debug):**  
```
// Use preconditions for impossible states  
precondition(state \== .complete, "Cannot advance from complete state")

// Use graceful handling in Release  
guard state \!= .complete else {  
    debugLog("Attempted to advance from complete state")  
    return  
}
```
### **Data Persistence**

**Simple Storage Strategy:**

* Use Checkpoints actor for session state.  
* Use SwiftData or file system for KnowledgeCard and ArtifactRecord.

## **Risk Management**

### **Technical Risks**

| Risk | Mitigation |
| :---- | :---- |
| OpenAI API changes | ModelProvider abstracts this. Responses API is current. |
| Rate limiting | Implement simple exponential backoff. |
| Large context windows | Chunk and summarize progressively (M3+). |
| State corruption | Atomic writes in Checkpoints actor. |

### **Scope Risks**

| Risk | Mitigation |
| :---- | :---- |
| Feature creep | Stick to M0-M3 milestones. |
| Over-optimization | Ship first, optimize later. |
| Perfect UI | Function before form. |

## **Principles**

1. **Delete First** \- Remove all old code before starting  
2. **Real Implementation** \- No mocks, no stubs  
3. **Function Over Form** \- Working code before pretty UI  
4. **Async Native** \- Use Swift concurrency throughout  
5. **Simple Logging** \- Use debugLog for dev.  
6. **Fail Fast** \- preconditionFailure in dev, log in prod  
7. **No Premature Optimization** \- Make it work, then make it fast  
8. **Personal Project Freedom** \- No committees, no consensus, just build

## **Final Notes**

This is a personal project. The only measure of success is whether it works for you.  
Remember: Perfect is the enemy of done. Ship something that works, iterate from there.