# **Onboarding Interview – State Machine Specification (v1.1)**

## **Overview**

This version adds `"dossier_complete"` to Phase 3’s completion check for consistency with the narrative UX.

---

## **Core State Components**

```swift
enum Phase: String, Codable {
    case phase1CoreFacts
    case phase2DeepDive
    case phase3WritingCorpus
    case complete
}

struct Session {
    var phase: Phase = .phase1CoreFacts
    var objectivesDone: Set<String> = []
    var waiting: Waiting? = nil

    enum Waiting: String, Codable {
        case selection
        case upload
        case validation
    }
}
```

---

## **Phase Transition Logic**

```swift
actor InterviewState {
    private(set) var session = Session()

    func completeObjective(_ id: String) async {
        session.objectivesDone.insert(id)
        if shouldAdvancePhase() { advancePhase() }
    }

    private func shouldAdvancePhase() -> Bool {
        switch session.phase {
        case .phase1CoreFacts:
            return ["applicant_profile", "skeleton_timeline", "enabled_sections"]
                .allSatisfy(session.objectivesDone.contains)

        case .phase2DeepDive:
            return ["interviewed_one_experience", "one_card_generated"]
                .allSatisfy(session.objectivesDone.contains)

        case .phase3WritingCorpus:
            // UPDATED: now requires both writing sample and dossier
            return ["one_writing_sample", "dossier_complete"]
                .allSatisfy(session.objectivesDone.contains)

        case .complete:
            return false
        }
    }

    private func advancePhase() {
        switch session.phase {
        case .phase1CoreFacts:
            session.phase = .phase2DeepDive
        case .phase2DeepDive:
            session.phase = .phase3WritingCorpus
        case .phase3WritingCorpus:
            session.phase = .complete
        case .complete:
            break
        }
    }
}
```

---

**Document Version:** 1.1  
**Updated:** 2025-10-24  
**Change:** Added `"dossier_complete"` objective to Phase 3 advancement condition.
