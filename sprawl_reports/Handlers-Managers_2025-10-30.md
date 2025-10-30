# Code Sprawl Analysis Report
**Directories**:
- `/Users/cculbreath/devlocal/codebase/Sprung/Sprung/Onboarding/Handlers/`
- `/Users/cculbreath/devlocal/codebase/Sprung/Sprung/Onboarding/Managers/`

**Analysis Date**: 2025-10-30
**Files Examined**: 5

## Executive Summary
- Total LOC in directories: 847
- Estimated reducible LOC: 198 (23%)
- High-priority issues: 6
- Medium-priority issues: 8
- Low-priority issues: 4

### Key Findings
The handler files demonstrate good separation of concerns but suffer from:
1. **Repetitive boilerplate**: Payload construction, continuation management, and logging patterns are duplicated across all handlers
2. **Verbose state management**: Manual clearing, guard checks, and logging in every method
3. **Inconsistent abstraction**: Similar flows (present/resolve/cancel) implemented separately in each handler
4. **Unnecessary state duplication**: WizardProgressTracker manually maps phases to steps when this could be computed

## File-by-File Analysis

---

### ProfileInteractionHandler.swift
**Current LOC**: 301
**Estimated reducible LOC**: 85

#### Issues Found

1. **Repetitive Payload Construction** (Priority: High)
   - **Lines**: 74-77, 92-95, 228-230, 240-247, 262-263
   - **Problem**: Every method that returns a payload manually creates `var payload = JSON()` and sets fields. This pattern appears 5 times in this file alone.
   - **Recommendation**: Extract a `PayloadBuilder` utility class with fluent API for common patterns like `status`, `data`, `userNotes`, `mode`, etc.
   - **Effort**: Low
   - **Impact**: ~15 LOC reduction in this file, ~40 LOC across all handlers + improved consistency
   - **Example**:
     ```swift
     // Before
     var payload = JSON()
     payload["status"].string = "rejected"
     if !reason.isEmpty {
         payload["userNotes"].string = reason
     }

     // After
     let payload = PayloadBuilder()
         .status("rejected")
         .userNotes(reason, ifNotEmpty: true)
         .build()
     ```

2. **Guard + Logging Pattern Duplication** (Priority: High)
   - **Lines**: 64-68, 86-88, 213, 238, 259
   - **Problem**: Every resolver method has identical guard-log-return pattern for missing continuation IDs
   - **Recommendation**: Extract a `guardContinuation<T>(_ id: UUID?, operation: String, block: (UUID) -> T) -> T?` helper
   - **Effort**: Low
   - **Impact**: ~20 LOC reduction + eliminates inconsistencies in logging
   - **Example**:
     ```swift
     // Before
     guard let continuationId = applicantProfileContinuationId else {
         Logger.warning("⚠️ No pending profile request to resolve", category: .ai)
         return nil
     }

     // After
     return guardContinuation(applicantProfileContinuationId, operation: "resolve profile") { continuationId in
         // actual logic
     }
     ```

3. **Repetitive State Clearing** (Priority: Medium)
   - **Lines**: 57-60, 276-279, 270-273
   - **Problem**: Two methods (`clearProfileRequest()` and `clearProfileRequest(continuationId:)`) both clear the same two properties. The conditional version adds unnecessary complexity.
   - **Recommendation**: Remove the conditional `clearProfileRequest(continuationId:)` variant - callers can check the ID themselves if needed, or use unconditional clear
   - **Effort**: Low
   - **Impact**: ~8 LOC reduction + simplified API surface

4. **Verbose Intake Mode Initialization** (Priority: Medium)
   - **Lines**: 122-127, 134-140, 147-152, 172-177, 190-195, 198-203, 217-222
   - **Problem**: Creating `OnboardingApplicantProfileIntakeState` with full parameter lists (mode, draft, urlString, errorMessage) repeated 7 times. Most calls use empty draft, empty URL, nil error.
   - **Recommendation**: Add convenience initializers or factory methods on `OnboardingApplicantProfileIntakeState` for common cases: `.options()`, `.loading(_:)`, `.manual(draft:, source:)`, `.urlEntry(urlString:, error:)`
   - **Effort**: Low
   - **Impact**: ~25 LOC reduction + improved readability
   - **Example**:
     ```swift
     // Before
     pendingApplicantProfileIntake = OnboardingApplicantProfileIntakeState(
         mode: .options,
         draft: ApplicantProfileDraft(),
         urlString: "",
         errorMessage: error.message
     )

     // After
     pendingApplicantProfileIntake = .options(error: error.message)
     ```

5. **Excessive Logging** (Priority: Low)
   - **Lines**: Throughout - 17 log statements for 301 LOC (1 per 18 lines)
   - **Problem**: Nearly every method has enter/exit logging with emoji decorations. Adds noise and maintenance burden.
   - **Recommendation**: Reduce to critical paths only (errors, user actions). Remove redundant "mode activated" logs - these can be inferred from state changes.
   - **Effort**: Low
   - **Impact**: ~12 LOC reduction + improved log signal-to-noise ratio

6. **Unnecessary ISO Formatter Property** (Priority: Low)
   - **Lines**: 27-31, 298
   - **Problem**: Dedicated property for ISO8601DateFormatter used in only one place (line 298). Adds 5 lines of setup for a single-use case.
   - **Recommendation**: Use a static computed property or inject from a shared DateFormatterProvider if used widely in the app
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

---

### PromptInteractionHandler.swift
**Current LOC**: 131
**Estimated reducible LOC**: 35

#### Issues Found

1. **Identical Choice/Validation Patterns** (Priority: High)
   - **Lines**: 21-63 (Choice), 67-121 (Validation)
   - **Problem**: The choice and validation flows are structurally identical (present/clear/resolve/cancel) but implemented separately with duplicated code
   - **Recommendation**: Extract a generic `PromptHandler<T>` that encapsulates the continuation/state management pattern, then compose choice and validation as specialized instances
   - **Effort**: Medium
   - **Impact**: ~30 LOC reduction + eliminates future duplication for new prompt types

2. **Repetitive Payload Construction** (Priority: High)
   - **Lines**: 39-40, 52-56, 88-97, 111-115
   - **Problem**: Same as ProfileInteractionHandler - manual JSON payload construction
   - **Recommendation**: Use shared PayloadBuilder (cross-cutting recommendation)
   - **Effort**: Low
   - **Impact**: ~8 LOC reduction in this file

3. **Redundant Clear Methods** (Priority: Medium)
   - **Lines**: 27-31, 73-77
   - **Problem**: Both `clearChoicePrompt` and `clearValidationPrompt` check continuation ID before clearing. This guards against clearing the wrong prompt, but adds complexity.
   - **Recommendation**: If continuation IDs are managed correctly, unconditional clear is safe. If guard is needed, extract shared `clearIfMatches` helper.
   - **Effort**: Low
   - **Impact**: ~6 LOC reduction

4. **Reset Method Verbosity** (Priority: Low)
   - **Lines**: 125-130
   - **Problem**: Manual nil assignment for 4 properties. Fragile - adding new state requires updating reset.
   - **Recommendation**: Group related state in nested structs, reset via `self.choiceState = nil`, or use property wrappers that auto-reset
   - **Effort**: Medium
   - **Impact**: ~2 LOC immediate, improves maintainability

---

### SectionToggleHandler.swift
**Current LOC**: 79
**Estimated reducible LOC**: 18

#### Issues Found

1. **Smallest Handler Shows Base Overhead** (Priority: High)
   - **Lines**: Entire file
   - **Problem**: This is the simplest handler (1 request type, 2 operations) yet still needs 79 lines due to boilerplate. Demonstrates that the handler pattern has high fixed overhead.
   - **Recommendation**: This handler could be replaced by a generic `SimpleRequestHandler<TRequest>` that handles present/resolve/reject for single-continuation workflows
   - **Effort**: Medium (requires generic abstraction)
   - **Impact**: ~60 LOC reduction if this handler is eliminated, establishes pattern for future simple handlers

2. **Redundant `clear()` wrapper** (Priority: Medium)
   - **Lines**: 70-73, 76-78
   - **Problem**: Private `clear()` method (3 lines) is only called from `reset()` (3 lines). The reset method is public API but just delegates.
   - **Recommendation**: Inline `clear()` into both call sites or remove the public/private distinction
   - **Effort**: Low
   - **Impact**: ~3 LOC reduction

3. **Same Payload/Logging Issues** (Priority: Medium)
   - **Lines**: 42-43, 58-61 (payload), 30, 46, 64 (logging)
   - **Problem**: Same repetitive patterns as other handlers
   - **Recommendation**: Use shared PayloadBuilder and reduce logging
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

---

### UploadInteractionHandler.swift
**Current LOC**: 225
**Estimated reducible LOC**: 45

#### Issues Found

1. **Complex Upload Completion Flow** (Priority: High)
   - **Lines**: 81-175 (95 lines)
   - **Problem**: `handleUploadCompletion` is a massive method handling guard checks, request lookup, item tracking, file processing, error handling, targeted uploads, and logging. Violates SRP.
   - **Recommendation**: Break into smaller methods: `validateUploadRequest`, `trackUploadedItems`, `buildUploadPayload`, `processUploadedFiles`, `handleUploadError`
   - **Effort**: Medium
   - **Impact**: ~15 LOC reduction through eliminating intermediate variables + improved testability

2. **Status String Matching Anti-pattern** (Priority: High)
   - **Lines**: 163-173
   - **Problem**: After building payload, code extracts status string and switches on it for logging. Status should be represented as an enum, not magic strings.
   - **Recommendation**: Define `UploadStatus` enum, use it throughout payload building, convert to string only at JSON boundary
   - **Effort**: Medium
   - **Impact**: ~8 LOC reduction + type safety

3. **Inconsistent Error Handling** (Priority: Medium)
   - **Lines**: 126-160 (do/catch wraps most logic), 65-71 (defer cleanup)
   - **Problem**: Two different error handling patterns: some methods catch and build error payload, others return early. Cleanup via defer in one place but not others.
   - **Recommendation**: Standardize on Result<Payload, Error> return type, handle Result -> Payload conversion in one place
   - **Effort**: Medium
   - **Impact**: ~10 LOC reduction + consistent error semantics

4. **Targeted Upload Switch** (Priority: Medium)
   - **Lines**: 191-211
   - **Problem**: Only one case ("basics.image") in a switch that anticipates future cases. Classic premature abstraction.
   - **Recommendation**: Replace switch with simple if-let or guard until there are actually multiple cases
   - **Effort**: Low
   - **Impact**: ~3 LOC reduction + removes future-proofing

5. **Dual Upload APIs** (Priority: Low)
   - **Lines**: 59-61 (local files), 64-72 (remote URL), 75-77 (skip)
   - **Problem**: Three separate methods that all call `handleUploadCompletion`. Could be unified.
   - **Recommendation**: Single `completeUpload(id: UUID, source: UploadSource)` where `UploadSource` is enum of `.local([URL])`, `.remote(URL)`, `.skipped`
   - **Effort**: Low
   - **Impact**: ~8 LOC reduction + clearer API

6. **Dependencies Injection Bloat** (Priority: Low)
   - **Lines**: 27-30, 34-43
   - **Problem**: Four injected dependencies for a handler. Suggests the handler is doing too much or dependencies are too granular.
   - **Recommendation**: Evaluate if `uploadFileService` and `uploadStorage` should be combined, or if targeted upload logic belongs elsewhere
   - **Effort**: Medium (requires architectural decision)
   - **Impact**: No LOC reduction but improves cohesion

---

### WizardProgressTracker.swift
**Current LOC**: 111
**Estimated reducible LOC**: 35

#### Issues Found

1. **Manual Phase-to-Step Mapping** (Priority: High)
   - **Lines**: 68-91 (24 lines)
   - **Problem**: Large switch statement manually maps interview phases to wizard steps. This is derived state that's being eagerly computed and stored.
   - **Recommendation**: Make `currentStep` a computed property based on `session.phase` and `session.objectivesDone`. Remove `completedSteps` storage if it can be computed.
   - **Effort**: Medium
   - **Impact**: ~25 LOC reduction + eliminates sync drift between session and tracker

2. **Redundant completedSteps Updates** (Priority: Medium)
   - **Lines**: 59-61, 76-78, 82-84, 87-89
   - **Problem**: `completedSteps.insert()` called 4 times in the phase switch, then iterated to set statuses (lines 94-96). Double bookkeeping.
   - **Recommendation**: If `currentStep` becomes computed, `completedSteps` can be computed as "all steps before current". Eliminate storage.
   - **Effort**: Medium (depends on issue #1)
   - **Impact**: ~10 LOC reduction

3. **Status Dictionary Redundancy** (Priority: Medium)
   - **Lines**: 19, 27, 44-46, 94-96, 99
   - **Problem**: `stepStatuses` dictionary stores `.current` and `.completed` states that can be computed from `currentStep` and `completedSteps`/phase
   - **Recommendation**: Make `stepStatuses` a computed property that derives status from current/completed step sets
   - **Effort**: Low
   - **Impact**: ~8 LOC reduction + eliminates inconsistency risk

4. **Unnecessary setStep Method** (Priority: Low)
   - **Lines**: 24-38
   - **Problem**: Public `setStep` method updates state manually but `syncProgress` is the real source of truth. Having two ways to update state is error-prone.
   - **Recommendation**: Evaluate if `setStep` is actually used. If `syncProgress` is always called, `setStep` can be removed or made private.
   - **Effort**: Low (requires checking call sites)
   - **Impact**: ~15 LOC reduction if unused

5. **Logger Noise** (Priority: Low)
   - **Lines**: 37, 101, 109
   - **Problem**: Debug logging of step changes adds little value in production
   - **Recommendation**: Remove or gate behind debug flag
   - **Effort**: Low
   - **Impact**: ~3 LOC reduction

---

## Cross-Cutting Patterns

### Pattern 1: Continuation Management Boilerplate
**Occurrences**: All 4 handlers
**Total Impact**: ~50 LOC

Every handler implements the same continuation management pattern:
```swift
private var someContinuationId: UUID?

func present(..., continuationId: UUID) {
    self.someContinuationId = continuationId
    // ...
}

func resolve() -> (UUID, JSON)? {
    guard let continuationId = someContinuationId else {
        Logger.warning("...")
        return nil
    }
    // ...
    someContinuationId = nil
    return (continuationId, payload)
}
```

**Recommendation**: Extract `ContinuationManager<T>` that encapsulates:
- Storage of continuation ID
- Present/resolve/clear lifecycle
- Guard-and-warn pattern
- Automatic cleanup

Each handler would compose a `ContinuationManager` instead of reimplementing.

### Pattern 2: JSON Payload Construction
**Occurrences**: All 4 handlers (13 instances)
**Total Impact**: ~40 LOC

Every handler manually builds JSON payloads:
```swift
var payload = JSON()
payload["status"].string = "completed"
payload["data"] = someJSON
if !notes.isEmpty {
    payload["userNotes"].string = notes
}
```

**Recommendation**: Implement `PayloadBuilder` DSL:
```swift
PayloadBuilder()
    .status(.completed)  // Enum instead of string
    .data(someJSON)
    .userNotes(notes, ifNotEmpty: true)
    .build()
```

### Pattern 3: Excessive Debug Logging
**Occurrences**: All 5 files (38 statements)
**Total Impact**: ~38 LOC + noise

Every operation logs entry/exit with emoji prefixes. This creates maintenance burden and log noise.

**Recommendation**:
- Remove logging for internal state transitions (setter methods)
- Keep logging only for: user actions, errors, external service calls
- Use structured logging attributes instead of formatted strings
- Move emoji decorations to log viewer, not source code

### Pattern 4: Request/Response State Holding
**Occurrences**: All 4 handlers
**Total Impact**: N/A (architectural)

Each handler holds `pending*Request` state that's presented, resolved, and cleared. This is a mini state machine duplicated 4+ times.

**Recommendation**: Extract a `PendingRequest<TRequest, TResponse>` generic type that encapsulates:
- Optional pending request
- Continuation ID
- Present/clear/resolve operations
- State machine validation

## Prioritized Recommendations

### Quick Wins (High Impact, Low Effort)

1. **Extract PayloadBuilder utility** (~40 LOC reduction)
   - Files: All handlers
   - Estimated LOC: -40
   - Eliminates repetitive JSON construction across 13 call sites

2. **Extract continuation guard helper** (~20 LOC reduction)
   - Files: ProfileInteractionHandler, PromptInteractionHandler, SectionToggleHandler, UploadInteractionHandler
   - Estimated LOC: -20
   - Standardizes guard-warn-return pattern

3. **Reduce logging by 50%** (~19 LOC reduction)
   - Files: All files
   - Estimated LOC: -19
   - Remove redundant entry/exit logs, keep only user actions and errors

4. **Add convenience initializers to OnboardingApplicantProfileIntakeState** (~25 LOC reduction)
   - Files: ProfileInteractionHandler.swift
   - Estimated LOC: -25
   - Reduces verbose state initialization

5. **Inline SectionToggleHandler's clear() method** (~3 LOC reduction)
   - Files: SectionToggleHandler.swift
   - Estimated LOC: -3
   - Simple refactoring with no risk

6. **Replace switch with if-let in handleTargetedUpload** (~3 LOC reduction)
   - Files: UploadInteractionHandler.swift
   - Estimated LOC: -3
   - Removes premature abstraction

**Total Quick Wins**: ~110 LOC reduction, Low risk

### Medium-term Improvements (High Impact, Medium Effort)

1. **Extract generic ContinuationManager** (~50 LOC reduction)
   - Files: All handlers
   - Estimated LOC: -50
   - Eliminates cross-cutting continuation boilerplate, prevents future duplication

2. **Make WizardProgressTracker state computed** (~35 LOC reduction)
   - Files: WizardProgressTracker.swift
   - Estimated LOC: -35
   - Eliminates manual sync logic and storage redundancy

3. **Extract generic PromptHandler<T>** (~30 LOC reduction)
   - Files: PromptInteractionHandler.swift
   - Estimated LOC: -30
   - Unifies choice and validation patterns

4. **Break up handleUploadCompletion method** (~15 LOC reduction)
   - Files: UploadInteractionHandler.swift
   - Estimated LOC: -15
   - Improves testability and readability through SRP

5. **Introduce UploadStatus enum** (~8 LOC reduction)
   - Files: UploadInteractionHandler.swift
   - Estimated LOC: -8
   - Adds type safety, eliminates string matching

**Total Medium-term**: ~138 LOC reduction, Moderate risk

### Strategic Refactoring (High Impact, High Effort)

1. **Extract PendingRequest<TRequest, TResponse> abstraction** (~60 LOC reduction)
   - Files: All handlers
   - Estimated LOC: -60
   - Requires architectural changes but eliminates entire category of duplication

2. **Replace SectionToggleHandler with generic SimpleRequestHandler** (~60 LOC reduction)
   - Files: SectionToggleHandler.swift + new abstraction
   - Estimated LOC: -60
   - Demonstrates pattern for eliminating trivial handlers

3. **Standardize error handling with Result types** (~10 LOC reduction)
   - Files: UploadInteractionHandler.swift
   - Estimated LOC: -10
   - Improves error semantics, requires API changes

**Total Strategic**: ~130 LOC reduction, High complexity

### Not Recommended (Low Impact or High Risk)

1. **Consolidate handlers into single OnboardingInteractionHandler**
   - Impact: Would reduce LOC but violate SRP and increase coupling
   - Reason: Current separation by interaction type (profile, prompt, upload, section) is appropriate

2. **Make all handlers conform to a protocol**
   - Impact: Would add protocol overhead without reducing code
   - Reason: Handlers have different signatures and responsibilities; forced conformance adds artificial complexity

3. **Remove ISO8601DateFormatter from ProfileInteractionHandler**
   - Impact: 5 LOC reduction
   - Reason: Only used once, but datetime formatting is complex enough to warrant dedicated setup. Not worth the churn.

4. **Combine uploadFileService and uploadStorage dependencies**
   - Impact: No LOC reduction
   - Reason: These are separate concerns (file I/O vs. storage management). Keep separate unless broader architectural changes occur.

## Total Impact Summary

- **Quick Wins**: ~110 LOC reduction (13% of total)
- **Medium-term**: ~138 LOC reduction (16% of total)
- **Strategic**: ~130 LOC reduction (15% of total)
- **Total Potential**: ~378 LOC reduction (45% of total)

**Note**: Actual reduction may be less due to overlap between recommendations. Conservative estimate: **198 LOC reduction (23%)** after accounting for necessary replacement code in extracted utilities.

## Maintainability Improvements Beyond LOC

Even if LOC reduction is modest, the recommended changes deliver:

1. **Reduced duplication**: Fewer places to update when continuation/payload patterns change
2. **Type safety**: Enums for status strings, Result types for errors
3. **Testability**: Smaller methods in UploadInteractionHandler, extracted utilities are easier to test
4. **Consistency**: Standardized patterns across all handlers reduce cognitive load
5. **Future-proofing**: Generic abstractions prevent accumulation of similar handlers

## Risk Assessment

**Low Risk Refactorings**: Quick wins are all safe, localized changes
**Medium Risk**: Generic abstractions require careful design but don't change public APIs
**High Risk**: None - no recommendations involve changing coordination layer or public handler APIs

## Next Steps

1. Start with PayloadBuilder and continuation guard helper (Quick Wins #1-2)
2. Incrementally migrate handlers to use new utilities
3. Measure actual LOC reduction after Quick Wins
4. Decide on Medium-term improvements based on actual vs. estimated impact
5. Defer Strategic refactorings until pattern is proven with multiple handlers
