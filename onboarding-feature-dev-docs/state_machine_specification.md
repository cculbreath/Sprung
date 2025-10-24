# **Onboarding Interview \- State Machine Specification**

## **Overview**

This document provides a complete specification for the v1 interview state machine. This v1 specification is intentionally minimal, focusing on only the state required to manage the interview flow, align with the "avoid over-abstraction" goal, and facilitate simple checkpointing.  
Sub-states, analytics, observers, Mermaid diagrams, and complex transition rules have been postponed.

## **State Architecture**

### **Core State Components**

The state is managed by a lean Session struct, encapsulated within an actor for safe concurrent access.  
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
            // Check if all objectives for Phase 1 are done  
            return \["applicant\_profile", "skeleton\_timeline", "enabled\_sections"\]  
                .allSatisfy(session.objectivesDone.contains)  
        case .phase2DeepDive:  
            // Check if all objectives for Phase 2 are done  
            return \["interviewed\_one\_experience", "one\_card\_generated"\]  
                .allSatisfy(session.objectivesDone.contains)  
        case .phase3WritingCorpus:  
            // Check if all objectives for Phase 3 are done  
            return \["one\_writing\_sample"\].allSatisfy(session.objectivesDone.contains)  
        case .complete:  
            return false  
        }  
    }

    private func advancePhase() {  
        switch session.phase {  
        case .phase1CoreFacts:  
            session.phase \= .phase2DeepDive  
        case .phase2DeepDive:  
            session.phase \= .phase3WritingCorpus  
        case .phase3WritingCorpus:  
            session.phase \= .complete  
        case .complete:  
            break // No transition from complete  
        }  
    }

    func restore(from session: Session) {  
        self.session \= session  
        debugLog("State restored to phase: \\(session.phase)")  
    }  
}

## **State Debugging**

For v1, monitoring and analytics are replaced by a simple debug-only logging helper.  
@inline(\_\_always) func debugLog(\_ msg: @autoclosure () \-\> String) {  
    \#if DEBUG  
    print("🔎", msg())  
    \#endif  
}

## **State Machine Testing**

For v1, automated testing of the stochastic LLM loop is out of scope. We rely on three zero-learning-curve safeguards:

1. **Schema Checks at the Edges:** Validate tool parameters and tool responses against their JSON Schemas (deterministic and cheap).  
2. **Checkpoint Round-trip:** A manual debug menu option to "Save checkpoint → Clear memory → Restore" to smoke-test persistence.  
3. **Hard Preconditions:** Use preconditionFailure for impossible states (e.g., advancePhase() called from .complete) in DEBUG builds, and graceful error handling in RELEASE.

## **Future Expansion**

This minimal state machine is designed for v1. Future iterations can re-introduce concepts like observers for UI binding, detailed analytics hooks, or more granular sub-states (expanding on the waiting flag) if the complexity becomes necessary.