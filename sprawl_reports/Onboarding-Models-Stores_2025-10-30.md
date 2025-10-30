# Code Sprawl Analysis Report
**Directory**: ./Sprung/Onboarding/Models/ and ./Sprung/Onboarding/Stores/
**Analysis Date**: 2025-10-30
**Files Examined**: 7

## ✅ COMPLETED REFACTORING (2025-10-30)
**OnboardingPlaceholders.swift Cleanup:**
1. Removed 5 explicit initializers from simple structs (-35 LOC)
2. Simplified OnboardingWizardStep.title to use raw values (-13 LOC)

**Status**: Models directory reduced from 670 → 622 LOC

## Executive Summary
- Total LOC in directories: 622 (was 670, reduced by 48)
- Estimated reducible LOC: 167 (27%, was 215)
- High-priority issues: 8
- Medium-priority issues: 5 (was 6, completed 1)
- Low-priority issues: 3 (was 4, completed 1)

## File-by-File Analysis

### KnowledgeCardDraft.swift
**Current LOC**: 196
**Estimated reducible LOC**: 90

#### Issues Found

1. **Manual JSON Serialization Boilerplate** (Priority: High)
   - **Lines**: 20-32, 61-83, 111-129, 159-183
   - **Problem**: Four separate manual JSON conversion implementations (`init(json:)` and `toJSON()`) totaling ~80 lines. This pattern is repeated across `KnowledgeCardDraft.Achievement`, `EvidenceItem`, and `ArtifactRecord`. SwiftyJSON is being used for parsing but manual property-by-property mapping creates verbose, error-prone code.
   - **Recommendation**: Replace with `Codable` conformance. SwiftyJSON can be eliminated entirely in favor of Swift's native `JSONEncoder`/`JSONDecoder`. The structs already have clean property definitions that map 1:1 to their JSON representations.
   - **Effort**: Medium
   - **Impact**: ~80 LOC reduction + improved type safety + eliminates SwiftyJSON dependency
   - **Example**:
     ```swift
     // BEFORE (20+ lines)
     init(json: JSON) {
         id = UUID(uuidString: json["id"].stringValue) ?? UUID()
         claim = json["claim"].stringValue
         evidence = EvidenceItem(json: json["evidence"])
     }

     func toJSON() -> JSON {
         var json = JSON()
         json["id"].string = id.uuidString
         json["claim"].string = claim
         json["evidence"] = evidence.toJSON()
         return json
     }

     // AFTER (1 line + compiler-generated)
     struct Achievement: Identifiable, Equatable, Codable {
         // Properties remain the same, all conversion is automatic
     }
     ```

2. **Redundant Default Parameters** (Priority: Low)
   - **Lines**: 10-18, 43-59, 99-109, 141-157
   - **Problem**: All initializers have default values for every property including `id: UUID = UUID()`. This is verbose when creating new instances but adds little value since most properties need to be explicitly set anyway.
   - **Recommendation**: Remove default parameters except for genuinely optional fields. Keep `id` generation but remove defaults for required content fields.
   - **Effort**: Low
   - **Impact**: ~15 LOC reduction, clearer API indicating what's required
   - **Example**:
     ```swift
     // BEFORE
     init(
         id: UUID = UUID(),
         title: String = "",
         summary: String = "",
         source: String? = nil,
         achievements: [Achievement] = [],
         metrics: [String] = [],
         skills: [String] = []
     )

     // AFTER
     init(
         title: String,
         summary: String,
         source: String? = nil,
         achievements: [Achievement],
         metrics: [String],
         skills: [String]
     )
     ```

3. **Duplicated Type Definitions** (Priority: Medium)
   - **Lines**: 132-184
   - **Problem**: `ArtifactRecord` is defined in KnowledgeCardDraft.swift but should be in its own file or possibly in OnboardingArtifactRecord.swift. Same type responsibilities scattered across files creates confusion about source of truth.
   - **Recommendation**: Extract `ArtifactRecord` to a shared file or consolidate with `OnboardingArtifactRecord` if they serve the same purpose. Currently unclear if these are meant to be different types.
   - **Effort**: Medium
   - **Impact**: Better organization, reduced file size by ~52 LOC

4. **Unnecessary Wrapper Struct** (Priority: Medium)
   - **Lines**: 186-196
   - **Problem**: `ExperienceContext` is a simple 3-property struct with no methods or logic. It exists solely as a parameter bag for `KnowledgeCardAgent.generateCard()`.
   - **Recommendation**: This can be eliminated by passing the three fields directly as parameters to `generateCard()`, or converted to a tuple if grouping is desired for clarity.
   - **Effort**: Low
   - **Impact**: ~10 LOC reduction, one less type to maintain

---

### OnboardingPlaceholders.swift
**Current LOC**: 279
**Estimated reducible LOC**: 55

#### Issues Found

1. **Verbose Enum String Mapping** (Priority: Medium)
   - **Lines**: 88-103
   - **Problem**: The `title` computed property on `OnboardingWizardStep` manually maps each enum case to a display string. This is 15 lines for what could be handled more elegantly.
   - **Recommendation**: Use a custom `rawValue` with proper casing, or store the display names in a static dictionary. Given the cases are simple enough, using proper raw values would eliminate this extension entirely.
   - **Effort**: Low
   - **Impact**: ~15 LOC reduction
   - **Example**:
     ```swift
     // BEFORE (17 lines total)
     enum OnboardingWizardStep: String, CaseIterable, Hashable, Codable {
         case introduction
         case resumeIntake
         // ...
     }
     extension OnboardingWizardStep {
         var title: String {
             switch self { /* 15 lines of mapping */ }
         }
     }

     // AFTER (5 lines)
     enum OnboardingWizardStep: String, CaseIterable, Hashable, Codable {
         case introduction = "Introduction"
         case resumeIntake = "Résumé Intake"
         case artifactDiscovery = "Artifact Discovery"
         case writingCorpus = "Writing Corpus"
         case wrapUp = "Wrap Up"
     }
     ```

2. **Over-Initialization of Simple Structs** (Priority: Low)
   - **Lines**: 25-37, 59-71, 109-112, 141-145, 199-213, 222-227, 246-256, 266-278
   - **Problem**: Many simple data-holding structs have explicit initializers that just assign properties. Swift's memberwise initializers would handle this automatically with less code.
   - **Recommendation**: Remove explicit initializers for pure data structs unless custom logic is needed. Only keep initializers when defaults are strategic or when initialization order matters.
   - **Effort**: Low
   - **Impact**: ~40 LOC reduction
   - **Example**:
     ```swift
     // BEFORE (8 lines)
     struct OnboardingQuestion: Identifiable, Codable {
         let id: UUID
         let text: String

         init(id: UUID = UUID(), text: String) {
             self.id = id
             self.text = text
         }
     }

     // AFTER (3 lines, compiler generates initializer)
     struct OnboardingQuestion: Identifiable, Codable {
         var id = UUID()
         let text: String
     }
     ```

3. **Redundant Identifiable Conformance** (Priority: Low)
   - **Lines**: Throughout file
   - **Problem**: Several structs conform to `Identifiable` but are never used in SwiftUI ForEach loops or collections requiring identification. Examples: `OnboardingMessage`, `OnboardingQuestion`, `OnboardingPendingExtraction`.
   - **Recommendation**: Audit usage via Grep. If these types aren't used with SwiftUI views requiring `Identifiable`, remove the conformance and the `id` property to simplify the models.
   - **Effort**: Low
   - **Impact**: Potential for cleaner models, investigation needed

4. **Nested Enum in Struct** (Priority: Low)
   - **Lines**: 163-189
   - **Problem**: `OnboardingApplicantProfileIntakeState` has two nested enums (`Mode` and `Source`) and a static factory method. This is acceptable but adds cognitive load.
   - **Recommendation**: Consider if this complexity is needed. The nested enums could be top-level if they're used elsewhere, or the state could be flattened.
   - **Effort**: Medium
   - **Impact**: Improved clarity, potential for reuse

---

### OnboardingArtifactRecord.swift
**Current LOC**: 17
**Estimated reducible LOC**: 0

#### Issues Found
No significant issues found. This is a clean, minimal `@Model` class for SwiftData persistence. The explicit initializer is appropriate here since SwiftData models benefit from explicit initialization patterns.

---

### OnboardingPreferences.swift
**Current LOC**: 8
**Estimated reducible LOC**: 0

#### Issues Found
No significant issues found. This is a clean, minimal struct with sensible defaults. Well-designed and appropriate for its purpose.

---

### InterviewDataStore.swift
**Current LOC**: 83
**Estimated reducible LOC**: 25

#### Issues Found

1. **Verbose Error Construction** (Priority: Low)
   - **Lines**: 33-37, 42-44
   - **Problem**: Manual `NSError` construction with explicit dictionaries is verbose (10 lines total for 2 errors).
   - **Recommendation**: Define a custom error enum conforming to `LocalizedError`. This provides type safety and reduces boilerplate.
   - **Effort**: Low
   - **Impact**: ~8 LOC reduction + better error handling
   - **Example**:
     ```swift
     // BEFORE
     throw NSError(domain: "InterviewDataStore", code: 1, userInfo: [
         NSLocalizedDescriptionKey: "Unable to encode payload for \(dataType)."
     ])

     // AFTER
     enum InterviewDataStoreError: LocalizedError {
         case encodingFailed(String)
         case persistFailed(Error)

         var errorDescription: String? {
             switch self {
             case .encodingFailed(let type): return "Unable to encode payload for \(type)."
             case .persistFailed(let error): return "Failed to persist data: \(error.localizedDescription)"
             }
         }
     }
     throw InterviewDataStoreError.encodingFailed(dataType)
     ```

2. **Redundant Guard Statements** (Priority: Medium)
   - **Lines**: 52-54, 60-66, 71-72
   - **Problem**: Multiple places use guard statements with early returns, but the logic could be simplified using optional chaining and functional patterns.
   - **Recommendation**: Use `compactMap` more idiomatically and simplify the error handling flow.
   - **Effort**: Medium
   - **Impact**: ~10 LOC reduction, more idiomatic Swift

3. **Questionable Filename Generation** (Priority: Medium)
   - **Lines**: 29-31
   - **Problem**: Using UUID as part of filename is fine, but the `list()` method assumes filenames sort correctly. This fragile coupling between persist/list logic could break if filename format changes.
   - **Recommendation**: Consider storing metadata separately (e.g., JSON index file) or using file creation timestamps for ordering. Current approach works but is brittle.
   - **Effort**: High
   - **Impact**: More robust implementation, but significant refactoring

---

### OnboardingArtifactStore.swift
**Current LOC**: 26
**Estimated reducible LOC**: 15

#### Issues Found

1. **Pointless Store Wrapper** (Priority: High)
   - **Lines**: 1-26 (entire file)
   - **Problem**: This "store" does nothing but hold a cached `OnboardingArtifacts` struct in memory. It provides no actual storage, no persistence logic, no validation. The `ModelContext` is injected but never used. This is a pure pass-through wrapper adding zero value.
   - **Recommendation**: **Delete this file entirely.** The `OnboardingArtifacts` struct can be held directly in `OnboardingInterviewCoordinator` (which already has `private(set) var artifacts = OnboardingArtifacts()` at line 28). The store adds complexity without benefit.
   - **Effort**: Low
   - **Impact**: ~26 LOC reduction + eliminates unnecessary dependency injection + simplifies architecture
   - **Example**:
     ```swift
     // CURRENT (pointless indirection)
     // OnboardingInterviewCoordinator has:
     private(set) var artifacts = OnboardingArtifacts()
     // But also injects/uses OnboardingArtifactStore which just wraps the same thing

     // AFTER (direct usage)
     // Just use the artifacts property directly in coordinator
     // Remove OnboardingArtifactStore entirely
     ```

2. **Unused ModelContext** (Priority: High)
   - **Lines**: 8, 11-13
   - **Problem**: The store accepts a `ModelContext` parameter but never uses it. This suggests either incomplete implementation or mistaken dependency injection.
   - **Recommendation**: Remove the unused parameter, or if persistence was intended, implement it properly using `InterviewDataStore` instead.
   - **Effort**: Low
   - **Impact**: Cleaner API, fewer false dependencies

---

### ChatTranscriptStore.swift
**Current LOC**: 61
**Estimated reducible LOC**: 15

#### Issues Found

1. **Verbose Streaming Boilerplate** (Priority: Medium)
   - **Lines**: 9, 23-28, 30-33, 35-45
   - **Problem**: The streaming message pattern requires manual tracking of start times in a separate dictionary, explicit `removeValue` calls, and repetitive index lookups. This is ~25 lines of boilerplate for what's essentially "update message text and track duration".
   - **Recommendation**: Create a custom `StreamingMessage` type that encapsulates the timing logic, or use a state machine enum. The current approach is error-prone (easy to forget cleanup).
   - **Effort**: Medium
   - **Impact**: ~10 LOC reduction + more robust streaming API
   - **Example**:
     ```swift
     // CURRENT (manual tracking, easy to leak memory)
     private var streamingMessageStart: [UUID: Date] = [:]
     func beginAssistantStream(...) { streamingMessageStart[id] = Date() }
     func finalizeAssistantStream(...) { streamingMessageStart.removeValue(forKey: id) }

     // BETTER (encapsulated state)
     enum MessageState {
         case complete(text: String)
         case streaming(text: String, startedAt: Date)
     }
     ```

2. **Unnecessary @discardableResult** (Priority: Low)
   - **Lines**: 15, 22
   - **Problem**: `appendAssistantMessage` and `beginAssistantStream` return UUIDs, but in many calling contexts these aren't used. The `@discardableResult` attribute is correct but indicates potential API design issue.
   - **Recommendation**: Check usage. If callers rarely need the UUID, consider splitting into two methods: one that returns it, one that doesn't. Alternatively, this is fine as-is if the UUID is frequently needed.
   - **Effort**: Low
   - **Impact**: Minimal, mostly API clarity

3. **Mutating Published Array** (Priority: Low)
   - **Lines**: 12, 18, 25, 32, 37, 49, 54, 58
   - **Problem**: The `messages` array is directly mutated via `append` and subscript assignment. This works with `@Observable` but is less explicit than methods that clearly signal mutations.
   - **Recommendation**: This is actually fine for an `@Observable` class in Swift 5.9+. No change needed unless you want more explicit mutation signals.
   - **Effort**: N/A
   - **Impact**: N/A (not actually a problem)

---

## Cross-Cutting Patterns

### Pattern 1: Manual JSON Serialization Everywhere
**Files**: KnowledgeCardDraft.swift
**Problem**: SwiftyJSON dependency creates manual boilerplate for JSON encoding/decoding when Swift's `Codable` would handle it automatically.
**Impact**: ~80 LOC across KnowledgeCardDraft.swift alone
**Recommendation**: Migrate to `Codable`, eliminate SwiftyJSON dependency from models

### Pattern 2: Redundant Store Layers
**Files**: OnboardingArtifactStore.swift
**Problem**: Stores that provide no storage logic, just pass-through wrappers around in-memory structs.
**Impact**: ~26 LOC + unnecessary dependencies
**Recommendation**: Remove store abstractions that don't abstract anything

### Pattern 3: Explicit Initializers for Simple Structs
**Files**: OnboardingPlaceholders.swift, KnowledgeCardDraft.swift
**Problem**: Many structs define explicit initializers that just assign properties, duplicating what Swift's compiler generates for free.
**Impact**: ~55 LOC across both files
**Recommendation**: Trust Swift's memberwise initializers, only write custom ones when needed

### Pattern 4: Error Handling Inconsistency
**Files**: InterviewDataStore.swift uses NSError, KnowledgeCardAgent.swift uses custom error enum
**Problem**: No consistent error handling strategy across stores and services.
**Impact**: Harder to handle errors uniformly
**Recommendation**: Standardize on custom error enums conforming to LocalizedError

---

## Prioritized Recommendations

### Quick Wins (High Impact, Low Effort)

1. **Delete OnboardingArtifactStore.swift entirely** (Priority: CRITICAL)
   - Files: OnboardingArtifactStore.swift + update OnboardingInterviewCoordinator.swift
   - Estimated LOC reduction: ~26 in store + ~5 in coordinator = 31 LOC
   - Reason: This file provides zero value and creates false abstraction complexity
   - Effort: 30 minutes to remove and update references

2. **Remove unused ModelContext parameter from OnboardingArtifactStore** (if not deleting)
   - Files: OnboardingArtifactStore.swift
   - Estimated LOC reduction: 3 LOC
   - Reason: Unused dependencies create confusion
   - Effort: 5 minutes

3. **Replace manual initializers with memberwise defaults in OnboardingPlaceholders.swift**
   - Files: OnboardingPlaceholders.swift
   - Estimated LOC reduction: ~40 LOC
   - Reason: Swift generates these for free, no need to write them manually
   - Effort: 20 minutes to identify and remove unnecessary ones

4. **Simplify OnboardingWizardStep.title to use raw values**
   - Files: OnboardingPlaceholders.swift
   - Estimated LOC reduction: ~15 LOC
   - Reason: Eliminates entire extension for trivial string mapping
   - Effort: 10 minutes

---

### Medium-term Improvements (High Impact, Medium Effort)

1. **Migrate KnowledgeCardDraft to Codable and eliminate SwiftyJSON** (Priority: HIGH)
   - Files: KnowledgeCardDraft.swift + update KnowledgeCardAgent.swift, GenerateKnowledgeCardTool.swift
   - Estimated LOC reduction: ~80 LOC in models + ~10 in services = 90 LOC
   - Reason: Modern Swift best practice, removes dependency, improves type safety
   - Effort: 2-3 hours (need to test JSON compatibility carefully)
   - Trade-off: Requires thorough testing of JSON serialization compatibility

2. **Replace NSError with custom error enum in InterviewDataStore**
   - Files: InterviewDataStore.swift
   - Estimated LOC reduction: ~8 LOC
   - Reason: Better type safety, cleaner error handling
   - Effort: 30 minutes

3. **Extract or consolidate ArtifactRecord type definition**
   - Files: KnowledgeCardDraft.swift, potentially OnboardingArtifactRecord.swift
   - Estimated LOC reduction: ~0 (moves LOC, doesn't reduce)
   - Reason: Single source of truth for domain concept
   - Effort: 1 hour (need to understand if OnboardingArtifactRecord is related)

---

### Strategic Refactoring (High Impact, High Effort)

1. **Redesign ChatTranscriptStore streaming message API**
   - Files: ChatTranscriptStore.swift + all callers
   - Estimated LOC reduction: ~10 LOC + improved robustness
   - Reason: Current manual tracking is error-prone
   - Effort: 3-4 hours (impacts calling code, needs careful migration)

2. **Audit and remove unnecessary Identifiable conformances**
   - Files: OnboardingPlaceholders.swift
   - Estimated LOC reduction: Potentially 10-20 LOC
   - Reason: Simpler models, fewer ID properties to maintain
   - Effort: 2 hours (requires grep analysis of all usage sites)

---

### Not Recommended (Low Impact or High Risk)

1. **Change InterviewDataStore filename sorting approach**
   - Reason: Works fine as-is, refactoring would be high effort for little gain
   - Current implementation is fragile but not causing issues

2. **Flatten OnboardingApplicantProfileIntakeState nested enums**
   - Reason: Current structure is reasonable for UI state modeling
   - Complexity is justified by domain requirements

3. **Split @discardableResult methods in ChatTranscriptStore**
   - Reason: Current API is flexible and caller-friendly
   - Would create API bloat without clear benefit

---

## Total Impact Summary

- **Quick Wins**: ~91 LOC reduction (31 + 40 + 15 + 5)
- **Medium-term**: ~98 LOC reduction (90 + 8)
- **Strategic**: ~30 LOC reduction (10 + 20)
- **Total Potential**: ~219 LOC reduction (32.7% of 670 total LOC)

### Key Architectural Improvements Beyond LOC:
1. Elimination of pointless abstraction layer (OnboardingArtifactStore)
2. Migration to modern Swift best practices (Codable vs SwiftyJSON)
3. Better error handling patterns
4. Reduced maintenance burden from simpler models

### Risk Assessment:
- **Low Risk**: Quick wins (store deletion, initializer removal, enum simplification)
- **Medium Risk**: Codable migration (requires careful JSON compatibility testing)
- **High Risk**: Streaming API redesign (touches multiple interaction points)

### Recommended Action Plan:
1. Start with OnboardingArtifactStore deletion (immediate value, low risk)
2. Clean up OnboardingPlaceholders.swift verbose patterns
3. Plan Codable migration as next sprint item with comprehensive test coverage
4. Defer streaming API redesign until pain points emerge in production use
