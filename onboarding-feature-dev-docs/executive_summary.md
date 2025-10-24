# **Onboarding Interview Implementation \- Executive Summary**

## **Your Feedback Addressed**

### **✅ Clean Slate Approach**

* **No migration needed** \- Working from empty data store  
* **No backward compatibility** \- Delete old code completely  
* **No feature flags** \- Single version only  
* **Keep UI only** \- Everything else can be deleted and rebuilt

### **✅ Latest OpenAI Models (GPT-5 Series)**

We will adopt the new ModelProvider policy to centralize model selection, prioritizing intelligence \> speed \> cost. We will use the **Responses API** with new parameters like text.verbosity and reasoning.effort to control output without prompt engineering.  
**Model Selection Policy:**

* Use **GPT-5 (large)** for orchestration, planning, or synthesis.  
* Use **GPT-5-mini** for most structured tasks (extraction, validation) with reasoning.effort: "minimal".  
* Use **GPT-5-nano** for tiny, deterministic chores (e.g., routing).  
* Keep **o-series (o1)** available as an "escape hatch" for hard reasoning spikes.  
* We will default to mini tiers and escalate only when needed. (See official pricing notes for cost details).

enum TaskType {  
    case orchestrator, validate, extract, summarize, knowledgeCard  
}

struct ModelProvider {  
    struct Config {  
        let id: String  
        let defaultVerbosity: String?  
        let defaultReasoningEffort: String?  
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

### **✅ Service Architecture Split**

Following the recommendation to split OnboardingInterviewService:

* **InterviewOrchestrator**: Manages flow and LLM interactions  
* **ToolExecutor**: Handles all tool execution  
* **ArtifactStore**: Manages artifact storage  
* **ProgressTracker**: Tracks objectives and phases

### **✅ Direct Implementation (No Mocks)**

* Build real tools from day one  
* No mock implementations that become legacy code  
* Direct UI integration  
* Real data persistence immediately

### **✅ Async/Await Architecture**

All operations use Swift's modern concurrency:

* Clean error propagation with try await  
* Natural composition of async operations  
* Built-in cancellation support  
* Better performance with concurrent operations  
* No callback hell or Combine complexity

### **✅ Simple State Management**

* Track only what matters  
* Minimal state machine (Phase \+ objectives \+ waiting)  
* Simple objective completion tracking  
* UI as pure presenter (following other agent's recommendation)

### **✅ Personal Project Freedom**

* No stakeholders to manage  
* No migration code needed  
* No extensive testing framework  
* Ship when you're happy  
* Build for your specific needs

## **Deliverables Created**

### **📄 Revised Spec Completion**

Complete answers to all SPEC TO-DO items with your feedback incorporated

### **📄 Tool Specification**

Comprehensive specification for all 10 LLM tools with implementation details

### **📄 State Machine Specification**

Complete enumeration of states, transitions, and tracking requirements

### **📄 Error Recovery & Contingency**

Specific failure scenarios and recovery strategies without over-engineering

### **📄 Final Implementation Guide**

Clean slate implementation plan with all feedback incorporated

### **📄 Clean Slate Implementation Plan**

Implementation plan focusing on shipping working code

## **Key Decisions Made**

### **1\. Model Selection**

* **Orchestrator**: gpt-5 (best reasoning)  
* **Knowledge Cards**: gpt-5 (synthesis)  
* **Simple Tasks**: gpt-5-mini / gpt-5-nano (fast/cheap)  
* **No WritingStyleProfile**: Direct sample matching works better

### **2\. Architecture**

* Split services for single responsibility  
* Actor pattern for thread-safe state  
* Direct tool implementation (schema-first JSON)  
* UI as presenter only

### **3\. Implementation Strategy**

* Delete all old onboarding code  
* Keep UI views only  
* Build incrementally  
* Ship when working for personal use

## **Implementation Scope (Milestones)**

### **M0 – Skeleton running**

* OpenAI client \+ ModelProvider wired (GPT-5 params)  
* Orchestrator loop calling Responses API  
* Tool registry with three tools: get\_user\_option, submit\_for\_validation, persist\_data  
* Minimal state machine (Phase \+ objectives \+ waiting) and checkpoints

### **M1 – Phase 1 usable**

* Applicant profile (manual \+ optional macOS “Me” card)  
* Skeleton timeline from resume upload (parsing can be naive)  
* User validation loop (approve/modify)

### **M2 – Deep dive basics**

* One experience interview end-to-end  
* Generate a single Knowledge Card and validate it  
* Save artifacts (text only at first)

### **M3 – Personal-use polish**

* Writing samples (optional)  
* Light UX polish, resume from checkpoint, robust inactivity timeouts

## **What We're NOT Building**

* ❌ Migration code  
* ❌ Backward compatibility  
* ❌ Feature flags  
* ❌ Mock implementations  
* ❌ Premature optimization  
* ❌ Complex abstractions  
* ❌ Analytics or email reminders  
* ❌ Auth-dependent features (GitHub, etc.)

## **Success Criteria**

* ✅ Old code completely deleted  
* ✅ New architecture implemented  
* ✅ Full interview completable  
* ✅ Data persists correctly  
* ✅ Works for personal use  
* ✅ Enjoyable to build

## **Next Steps**

### **Immediate Actions**

1. **Delete all old onboarding code** (except UI views)  
2. **Create new folder structure**  
3. **Implement InterviewOrchestrator**  
4. **Build first tool (GetUserOption)**  
5. **Test with simple interview flow**

### **Architecture Pattern to Follow**

UI → ToolExecutor → Orchestrator → OpenAI  
         ↓              ↓  
    ArtifactStore  ProgressTracker

### **Core Principle**

**Make it work, make it right, make it fast** \- in that order.

## **Final Notes**

This is your personal project with complete freedom to:

* Change direction as needed  
* Skip uninteresting features  
* Spend extra time on parts you enjoy  
* Ship when satisfied  
* Never ship if you prefer

The implementation prioritizes:

1. **Simplicity** over complexity  
2. **Working code** over perfect architecture  
3. **Personal utility** over general solution  
4. **Shipping** over endless refinement

Remember: Perfect is the enemy of done. Build something that works for you, then iterate if needed.