# CoachingService.swift Refactor Assessment

**File**: `/Users/cculbreath/devlocal/codebase/Sprung/Sprung/SearchOps/Services/CoachingService.swift`
**Lines**: 915
**Assessment Date**: 2025-12-27

---

## File Overview and Primary Purpose

`CoachingService` is the main orchestration service for the "Job Search Coach" feature. It manages an AI-driven coaching flow that:

1. Generates activity reports from user data
2. Asks the user 2-3 check-in questions via LLM tool calls
3. Collects answers and maintains conversation state
4. Delivers personalized coaching recommendations
5. Offers contextual follow-up actions

The service uses dependency injection properly (8 injected dependencies) and follows the `@Observable` pattern for SwiftUI integration.

---

## Responsibility Analysis

### Primary Responsibilities Identified

| # | Responsibility | Lines | Percentage |
|---|----------------|-------|------------|
| 1 | **Conversation Orchestration** | ~150 | 16% |
| 2 | **Tool Call Handling** (3 research tools) | ~120 | 13% |
| 3 | **Question/Answer Flow Management** | ~100 | 11% |
| 4 | **Follow-Up Action System** | ~90 | 10% |
| 5 | **Context Building** (dossier, knowledge cards, job apps) | ~70 | 8% |
| 6 | **Prompt Building** | ~140 | 15% |
| 7 | **Session Lifecycle Management** | ~80 | 9% |
| 8 | **State Management** | ~50 | 5% |

### Responsibility Assessment

The file has **multiple related responsibilities** that form a cohesive coaching workflow. However, these responsibilities are:

1. **Tightly coupled by design** - The coaching flow is inherently sequential and interdependent
2. **Not independently useful** - Tool handlers and context builders only make sense within the coaching context
3. **Logically grouped** - All code serves the single feature: "AI Coaching Session"

---

## Code Quality Observations

### Strengths

1. **Excellent Dependency Injection**: All 8 dependencies are injected through the initializer, making testing straightforward
2. **Clear State Machine**: The `CoachingState` enum provides clean state transitions
3. **Well-Organized MARK Sections**: Code is logically grouped with clear section markers
4. **Defensive Programming**: Guards and nil checks are used consistently
5. **Proper Logging**: Uses the project's Logger utility with appropriate levels
6. **Good Separation from Stores**: Session persistence delegated to `CoachingSessionStore`
7. **Tool Schemas Externalized**: `CoachingToolSchemas` is already a separate file

### Potential Concerns

1. **Long System Prompt** (lines 765-913): 140 lines of prompt text embedded in code
2. **Tool Handlers in Service**: Three tool handlers (`handleGetKnowledgeCard`, `handleGetJobDescription`, `handleGetResume`) are implemented inline
3. **Follow-Up Action Mapping**: Hard-coded label matching logic (lines 632-651)

### Not Anti-Patterns

The following are **intentional design choices**, not problems:

- **Large file size**: The 915 lines include ~140 lines of prompt text, making the actual logic ~775 lines
- **Multiple methods**: Methods are appropriately scoped and focused
- **Private methods**: Encapsulation is proper; these shouldn't be public APIs

---

## Coupling and Testability Assessment

### Testability: GOOD

The service is **highly testable** due to:

1. **Protocol-backed dependencies**: `SearchOpsLLMService`, `CoachingSessionStore`, etc. can be mocked
2. **Pure input/output methods**: Context builders and tool handlers are deterministic
3. **Clear public API**: Only 7 public methods/properties to test

### Coupling: ACCEPTABLE

- Dependencies are injected, not created internally
- No singleton usage (`.shared`)
- State is encapsulated within the service

---

## Refactoring Candidates (If Required)

### 1. Extract System Prompt to Resource File

**Effort**: Low
**Benefit**: Low-Medium
**Current State**: 140-line string literal in `buildSystemPrompt()`

```swift
// Could become:
private func buildSystemPrompt(...) -> String {
    let template = CoachingPromptTemplate.load()
    return template.render(context: [
        "activitySummary": activitySummary,
        "dossierContext": dossierContext,
        ...
    ])
}
```

**Verdict**: Optional improvement. The inline prompt is readable and easy to modify. Moving to a separate file adds indirection without clear testing benefits.

### 2. Extract Tool Handlers to Separate File

**Effort**: Low
**Benefit**: Low
**Lines**: ~100

The three tool handlers (`handleGetKnowledgeCard`, `handleGetJobDescription`, `handleGetResume`) could become:

```swift
// CoachingToolHandlers.swift
struct CoachingToolHandlers {
    static func handleGetKnowledgeCard(...) -> String
    static func handleGetJobDescription(...) -> String
    static func handleGetResume(...) async -> String
}
```

**Verdict**: Marginal benefit. The handlers are simple, cohesive with the coaching flow, and already well-isolated as private methods.

### 3. Extract Follow-Up Action System

**Effort**: Medium
**Benefit**: Low
**Lines**: ~60

The follow-up mapping and execution could be extracted:

```swift
// CoachingFollowUpHandler.swift
struct CoachingFollowUpHandler {
    func mapAnswer(value: Int, label: String) -> CoachingFollowUpAction
    func execute(_ action: CoachingFollowUpAction, session: CoachingSession) -> String
}
```

**Verdict**: Premature abstraction. The follow-up system is currently simple and may evolve. Extracting now creates indirection without clear benefit.

---

## Recommendation: DO NOT REFACTOR

### Rationale

1. **Single Feature Ownership**: Despite multiple responsibilities, all code serves one cohesive feature (AI Coaching). The file has "one reason to change" - when the coaching feature changes.

2. **Good Testability**: The service is already testable through its injected dependencies. No structural changes are needed to enable testing.

3. **No Clear Pain Points**: The code is well-organized, readable, and follows project conventions. No developers have reported difficulty modifying it.

4. **Size is Justified**:
   - ~140 lines are prompt text (documentation-like)
   - ~775 lines of actual logic for a complex LLM orchestration feature is reasonable
   - Splitting would create 4-5 small files with cross-dependencies

5. **Premature Abstraction Risk**: Extracting tool handlers or follow-up logic would create abstractions that only have one consumer, violating the "don't refactor for hypothetical future needs" guideline.

6. **Working Code**: The coaching feature functions correctly and the code is maintainable.

### Minor Improvements (Not Requiring Refactoring)

If any changes are desired, consider:

1. **Move prompt to constant file** (optional): If the prompt grows beyond ~200 lines, consider `CoachingPrompts.swift` with `static let systemPrompt = """..."""`

2. **Add `extractNodeText` to TreeNode** (optional): The helper method (lines 458-473) could be an extension on `TreeNode`, but it's only used here.

---

## Summary

| Criterion | Assessment |
|-----------|------------|
| Single Responsibility | PASS - Single feature ownership |
| Clear Violations | NONE - Concerns are related |
| Large/Complex | ACCEPTABLE - Size justified by feature scope |
| Pain Points | NONE IDENTIFIED |
| Testability | GOOD - Dependencies injected |
| **Recommendation** | **DO NOT REFACTOR** |

The file is large but well-structured. Its size reflects the inherent complexity of orchestrating an LLM-driven coaching session with multiple tool calls, state management, and context building. Refactoring would fragment a cohesive feature without providing testability or maintainability benefits.
