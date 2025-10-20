# Architecture Analysis: DataManagers Module

**Analysis Date**: October 20, 2025
**Subdirectory**: `/Users/cculbreath/devlocal/codebase/Sprung/Sprung/DataManagers`
**Total Swift Files Analyzed**: 10

## Executive Summary

The DataManagers module implements a well-structured, consistency-focused persistence layer built on SwiftData. The architecture demonstrates a **pragmatic, sensible approach** with minimal over-abstraction. Each store manages a specific domain entity (JobApp, Resume, CoverLetter, etc.) and implements CRUD operations following a consistent pattern. The module exhibits **low-to-medium complexity** with clear separation of concerns and appropriate use of protocols. A unifying `SwiftDataStore` protocol eliminates boilerplate, and stores are centrally composed via dependency injection in `AppDependencies`. The primary concern is **moderate inter-store coupling** and opportunities for further simplification in some stores.

**Key Findings**:
- **Strengths**: Consistency across stores, clear protocols, effective DRY application, MainActor safety
- **Concerns**: Some stores have multiple responsibilities; limited test isolation due to tight context coupling
- **Complexity Rating**: **Medium** - appropriate for the domain, not excessive

## Overall Architecture Assessment

### Architectural Style

This module implements a **Store Pattern** (also called Repository Pattern) on top of SwiftData. Key characteristics:

1. **Protocol-Based Design**: Each domain entity has optional protocol specifications (`ApplicantProfileProviding`, `ExperienceDefaultsProviding`)
2. **Shared Base Functionality**: `SwiftDataStore` protocol provides common persistence operations
3. **MainActor Threading Model**: All stores enforce thread safety with `@MainActor` annotation
4. **Observable State Pattern**: Stores adopt `@Observable` for SwiftUI reactivity
5. **Dependency Injection**: Stores receive dependencies (ModelContext, related stores) through initializers
6. **Computed Properties**: Some stores use computed properties that fetch directly from SwiftData (e.g., `JobAppStore.jobApps`)

### Strengths

- **High Consistency**: Every store follows the same initialization and method naming patterns
- **DRY Principle Applied**: The `SwiftDataStore` extension eliminates repeated `saveContext()` implementations
- **Thread Safety**: Explicit `@MainActor` annotation ensures all operations are safe
- **Observable Integration**: Seamless SwiftUI integration via `@Observable` macro
- **Clear Separation**: Domain stores are not mixed with UI concerns
- **Minimal Abstraction**: Protocols exist only where multiple implementations exist or where abstraction adds real value
- **Schema Centralization**: `SchemaVersioning.swift` maintains a single source of truth for the data model
- **Low Boilerplate**: Init methods are straightforward; no unnecessary builder patterns or factories

### Concerns

1. **Store Interdependencies**: Some stores depend on multiple other stores (e.g., `ResStore` depends on 4 different stores), creating coupling
2. **Mutable State Management**: Stores like `CoverLetterStore` have mutable properties (`cL`, `isGeneratingCoverLetter`) that could introduce stale state
3. **Context Fetching Pattern**: Multiple stores use try-catch blocks with identical error handling; could be extracted
4. **Incomplete Testing Boundaries**: Stores assume `ModelContext` is always available and don't gracefully degrade
5. **Ad-hoc Caching**: `ApplicantProfileStore` and `ExperienceDefaultsStore` use manual caching (`cachedProfile`, `cachedDefaults`) which could diverge from database state
6. **Asymmetric Error Handling**: Some methods catch errors silently (e.g., `EnabledLLMStore.try? modelContext.save()`), others don't handle errors
7. **Large Methods**: `ResStore.create()` and `ResStore.duplicate()` are >55 lines each, handling multiple concerns
8. **Weak Store Relationships**: Some stores use `unowned` references which could crash if the context is deallocated unexpectedly

## File-by-File Analysis

### SwiftDataStore.swift

**Purpose**: Protocol and extension providing common persistence operations for all stores

**Lines of Code**: 48

**Dependencies**: Foundation, SwiftData, Logger

**Complexity**: Low

**Observations**:
- Excellent application of the protocol extension pattern to eliminate boilerplate
- The `saveContext()` method includes helpful debug-only logging with file/line information
- Uses `@discardableResult` to allow callers to ignore return values when not needed
- Logging is conditionally compiled (only in DEBUG builds) to avoid production overhead
- Perfect use case for shared functionality

**Recommendations**:
- ✅ No changes needed - this is exemplary DRY code

---

### ApplicantProfileStore.swift

**Purpose**: Manages the singleton ApplicantProfile entity representing the current user

**Lines of Code**: 56

**Dependencies**: Foundation, Observation, SwiftData

**Complexity**: Low

**Observations**:
- Uses manual caching pattern (`cachedProfile`) to avoid repeated fetches
- Implements both `SwiftDataStore` and a custom protocol `ApplicantProfileProviding` for testability
- `currentProfile()` has three code paths: return cached, fetch existing, create new
- The caching pattern assumes the profile doesn't change outside this store
- `save(_:)` accepts either cached or external profiles, providing flexibility

**Recommendations**:
- Consider adding a method to refresh the cache from disk (for multi-window scenarios)
- Document the assumption that profiles aren't modified externally
- Consider using `try?` instead of bare `try` since the fetch descriptor has a default fallback

---

### CoverLetterStore.swift

**Purpose**: Manages cover letters, including creation, duplication, deletion, and export

**Lines of Code**: 145

**Dependencies**: Foundation, SwiftData, SwiftUI, CoverRefStore, ApplicantProfileStore, LocalCoverLetterExportService

**Complexity**: Medium-High

**Observations**:
- Has multiple responsibilities: CRUD operations, reference management, generation tracking, PDF export
- Contains mutable state properties: `cL` (currently selected letter), `isGeneratingCoverLetter` (boolean flag)
- `createDuplicate()` method (lines 59-87) is a complex operation with side effects
- Letter naming logic (`getNextOptionLetter()`) is delegated to the model
- `deleteUngeneratedDrafts()` is a cleanup utility that seems like infrastructure concern
- Holds a hard reference to an export service protocol instance
- The dependency on `coverRefStore` and `applicantProfileStore` increases coupling

**Recommendations**:
- Consider extracting letter duplication logic into a separate `CoverLetterDuplicationService` to reduce complexity
- Separate generation state tracking from the store (use a dedicated `GenerationStateManager` or similar)
- Move `deleteUngeneratedDrafts()` to a dedicated maintenance service
- Consider lazy-loading the export service or making it a dependency injection parameter
- Document why `modelContext` is `unowned` vs `ResStore` using it without annotation

---

### CoverRefStore.swift

**Purpose**: Manages cover letter references/templates as a simple lookup store

**Lines of Code**: 45

**Dependencies**: Foundation, SwiftData

**Complexity**: Low

**Observations**:
- Minimal, straightforward store with only three methods
- Uses computed property `storedCoverRefs` which always fetches fresh data
- Provides filtered computed property `defaultSources` for quick access
- No external dependencies beyond SwiftData
- The note about "no JSON File backing – SwiftData only" suggests this evolved from a file-based system
- Perfect example of a simple, focused store

**Recommendations**:
- ✅ Keep as-is - this store demonstrates excellent simplicity

---

### EnabledLLMStore.swift

**Purpose**: Manages LLM model availability, capabilities, and validation state with database persistence

**Lines of Code**: 174

**Dependencies**: Foundation, SwiftData, Combine, Logger, OpenRouterModel, EnabledLLM

**Complexity**: Medium

**Observations**:
- Maintains an in-memory cache (`enabledModels`) that must be kept in sync with database
- Multiple update methods with overlapping concerns: `updateModelCapabilities()` (two overloads), `recordJSONSchemaFailure()`, `recordJSONSchemaSuccess()`
- Calls `try? modelContext.save()` directly (inconsistent with using `saveContext()` from protocol)
- Has explicit `refreshEnabledModels()` method to sync in-memory state from database
- Logging includes emoji indicators (👍, ❌, 🔄, 📊) which is non-standard for production code
- The constructor calls `loadEnabledModels()` which can fail silently
- Uses computed property for `enabledModelIds` which is a simple projection

**Recommendations**:
- Standardize on using `saveContext()` from `SwiftDataStore` protocol instead of `try? modelContext.save()`
- Consolidate the two `updateModelCapabilities()` methods into one parameterized version
- Extract JSON schema validation tracking into a separate `JSONSchemaValidationTracker`
- Remove emoji logging in favor of structured logging (unless this is a deliberate debug convention)
- Consider documenting when manual `refreshEnabledModels()` calls are necessary
- Add initialization error handling (currently silently sets empty array on fetch failure)

---

### ExperienceDefaultsStore.swift

**Purpose**: Manages singleton experience template defaults that users can apply across entries

**Lines of Code**: 57

**Dependencies**: Foundation, Observation, SwiftData

**Complexity**: Low

**Observations**:
- Mirrors `ApplicantProfileStore` pattern with manual caching (`cachedDefaults`)
- Implements both the store protocol and a custom `ExperienceDefaultsProviding` protocol
- Supports working with a `ExperienceDefaultsDraft` for transaction-like operations
- The `loadDraft()` and `save(draft:)` pattern suggests a form-based editing workflow
- Caching is consistent with `ApplicantProfileStore`

**Recommendations**:
- Consolidate the `ApplicantProfileStore` and this store into a reusable `SingletonEntityStore<T>` generic type if the pattern repeats
- Document the relationship between `ExperienceDefaults` and `ExperienceDefaultsDraft`
- Consider whether draft application should be in the model or the store

---

### JobAppStore.swift

**Purpose**: Manages job applications (the root entity) with CRUD operations and form-based editing

**Lines of Code**: 138

**Dependencies**: Foundation, SwiftData, ResStore, CoverLetterStore, JobAppForm, Logger

**Complexity**: Medium

**Observations**:
- Holds a `JobAppForm` instance for edit state management
- Uses computed property `jobApps` that fetches fresh from SwiftData each access
- Has mutable property `selectedApp` for tracking the currently viewed application
- Deletion logic (`deleteSelected()` and `deleteJobApp()`) includes fallback selection behavior
- Delegates resume deletion to `resStore` to handle cascading deletes
- Form editing uses populate/edit/cancel/save pattern (lines 85-127)
- `updateJobApp()` method (line 129) is trivial - just calls `saveContext()`

**Recommendations**:
- Extract form handling logic into a dedicated `JobAppFormManager` to reduce store responsibilities
- Consider making `selectedApp` an `@Published` property or using a separate selection service
- Consolidate `updateJobApp()` method with a more descriptive operation or remove if unused
- Document the fallback selection behavior (why `jobApps.last` vs `jobApps.first`?)
- Consider batch operations for deletion (currently iterates through resumes)

---

### ResRefStore.swift

**Purpose**: Manages resume references/templates used as data sources for resumes

**Lines of Code**: 50

**Dependencies**: Foundation, Observation, SwiftData

**Complexity**: Low

**Observations**:
- Mirrors `CoverRefStore` with nearly identical implementation
- Minimal, focused store with three operations: add, update, delete
- Computed property fetches fresh data each access (like `CoverRefStore`)
- Provides filtered `defaultSources` computed property
- The comment "SwiftData is now the single source of truth" suggests evolution from file-based system

**Recommendations**:
- These two stores (`CoverRefStore` and `ResRefStore`) share identical structure - consider extracting a generic `ReferenceStore<T>` base class
- ✅ Otherwise appropriate simplicity

---

### ResStore.swift

**Purpose**: Manages resumes with complex creation, duplication, tree building, and export coordination

**Lines of Code**: 264

**Dependencies**: Foundation, SwiftData, SwiftUI, ResumeExportCoordinator, ApplicantProfileStore, TemplateSeedStore, ExperienceDefaultsStore, JsonToTree, ResumeTemplateContextBuilder, TemplateManifestLoader, Logger

**Complexity**: High

**Observations**:
- Most complex store in the module - handles multiple concerns
- `create()` method (39-96 lines) orchestrates: tree building, context creation, animation, async export
- `duplicate()` method (114-160 lines) with recursive tree copying logic
- `duplicateTreeNode()` method (162-212 lines) is a complex recursive tree copy with field copying
- `findCorrespondingNode()` (214-228 lines) uses O(n) tree search
- Depends on 4 other services/stores creating a web of dependencies
- Heavy use of optional unwrapping with error logging
- Mixes domain logic (tree building) with infrastructure (animations, exports)
- Uses `withAnimation()` for visual effects which is unusual for a data store

**Recommendations**:
- Extract tree building into a dedicated `ResumeTreeBuilder` service
- Extract tree duplication into a `ResumeTreeDuplicator` service
- Move animation logic into a view layer concern, not the store
- Consider async creation with structured concurrency patterns
- The `findCorrespondingNode()` method suggests data structure design issues - consider flattening or indexing
- Create a `ResumeCreationCoordinator` that orchestrates all the steps
- Document why recursion is necessary for tree operations
- Consider `Result<Resume, Error>` return types instead of optionals with implicit errors

---

### SchemaVersioning.swift

**Purpose**: Centralized schema definition for SwiftData, managing model versions and migrations

**Lines of Code**: 75

**Dependencies**: Foundation, SwiftData

**Complexity**: Low

**Observations**:
- Excellent centralization of schema definition
- Uses enum as namespace (static properties only)
- Comprehensive list of all SwiftData models (35 model types)
- Extension on `ModelContainer` provides a single factory method
- Supports lightweight migration automatically via SwiftData
- Comment indicates awareness of eventual need for custom migration plans
- No custom migration logic currently (as intended)

**Recommendations**:
- ✅ Exemplary schema management - no changes needed
- Consider adding comments documenting when models were added for historical tracking
- When custom migrations become necessary, consider extracting to a `MigrationPlan` extension

---

## Identified Issues

### 1. Over-Abstraction: Redundant Store Protocols

**Impact**: Low | **Frequency**: 3 instances

The custom protocols (`ApplicantProfileProviding`, `ExperienceDefaultsProviding`) are defined alongside their implementations with only one conformer. While good for testability, they add minimal value without multiple implementations.

**Code References**:
- `ApplicantProfileProviding` in ApplicantProfileStore.swift (lines 11-14)
- `ExperienceDefaultsProviding` in ExperienceDefaultsStore.swift (lines 6-11)

**Assessment**: These are justified for testing/mocking, but should be used consistently. Currently, other stores don't follow this pattern, creating inconsistency.

---

### 2. Unnecessary Complexity: Manual Caching Pattern

**Impact**: Medium | **Frequency**: 2 instances

`ApplicantProfileStore` and `ExperienceDefaultsStore` both implement manual caching that could diverge from database state in edge cases (multi-window scenarios, external modifications).

**Code References**:
- ApplicantProfileStore.swift lines 22, 31-37
- ExperienceDefaultsStore.swift lines 17, 23-31

**Specific Code**:
```swift
private var cachedProfile: ApplicantProfile?

func currentProfile() -> ApplicantProfile {
    if let cachedProfile {
        return cachedProfile  // Returns stale data if profile modified elsewhere
    }
    // ...
}
```

**Assessment**: Caching is premature optimization. SwiftData queries are fast for singleton patterns. If caching is needed, it should be invalidated explicitly.

---

### 3. Design Pattern Misuse: Form State in Store

**Impact**: Medium | **Frequency**: 1 instance

`JobAppStore` holds a `JobAppForm` property for edit state management. Form state is UI concern and shouldn't live in the data persistence layer.

**Code References**:
- JobAppStore.swift lines 28, 85-127

**Specific Code**:
```swift
var form = JobAppForm()  // Form is a UI concern

func editWithForm(_ jobApp: JobApp? = nil) {
    let jobAppEditing = jobApp ?? selectedApp
    guard let jobAppEditing = jobAppEditing else { return }
    populateFormFromObj(jobAppEditing)  // Coupling UI to data layer
}
```

**Assessment**: Form management should be in a view model or form coordinator, not the store.

---

### 4. Inter-Store Coupling: Complex Dependency Web

**Impact**: Medium | **Frequency**: Throughout module

Multiple stores depend on each other, creating a complex dependency graph:
- `CoverLetterStore` → `CoverRefStore`, `ApplicantProfileStore`
- `JobAppStore` → `ResStore`, `CoverLetterStore`
- `ResStore` → 4 different stores/services

**Code References**:
- CoverLetterStore.swift lines 18-22
- JobAppStore.swift lines 29-30
- ResStore.swift lines 18-21

**Assessment**: This is somewhat unavoidable for domain modeling but creates cascading initialization dependencies (documented in AppDependencies.swift lines 46-98).

---

### 5. Inconsistent Error Handling

**Impact**: Medium | **Frequency**: 4 instances

Different stores handle errors inconsistently:

**Code References**:
- `CoverLetterStore` lines 107-134: Handles errors, logs them
- `EnabledLLMStore` lines 74, 84, 92, 128: Uses `try?` silently
- `ResStore` lines 89-91: Logs error but returns nil
- `ApplicantProfileStore` line 35: Silent error with fallback

**Assessment**: No consistent error handling strategy across the module.

---

### 6. Weak Reference Risks

**Impact**: Low | **Frequency**: Multiple instances

Several stores use `unowned` for `modelContext`:

**Code References**:
- CoverLetterStore.swift line 17
- CoverRefStore.swift line 14
- ResRefStore.swift line 15

**Specific Code**:
```swift
unowned let modelContext: ModelContext  // Could crash if context deallocated
```

**Assessment**: While `ModelContext` should have stable lifetime, using `unowned` could cause crashes if the context is prematurely deallocated. Consider using `let` (owned reference) for safety.

---

### 7. Large Methods with Multiple Responsibilities

**Impact**: Medium | **Frequency**: 2 instances

**Code References**:
- ResStore.swift `create()` (lines 39-96): Creates, builds tree, manages animation, triggers async export
- ResStore.swift `duplicate()` (lines 114-160): Duplicates, copies properties, manages animation, triggers export

**Assessment**: These methods mix data transformation, animation concerns, and asynchronous operations. Testability is reduced.

---

### 8. Silent Initialization Failures

**Impact**: Low | **Frequency**: 1 instance

**Code References**:
- EnabledLLMStore.swift lines 24-35: Catches errors but silently sets empty array

**Specific Code**:
```swift
private func loadEnabledModels() {
    do {
        let descriptor = FetchDescriptor<EnabledLLM>(...)
        enabledModels = try modelContext.fetch(descriptor)
    } catch {
        Logger.error("Failed to load enabled models: \(error)")
        enabledModels = []  // Silent failure - caller doesn't know
    }
}
```

**Assessment**: Initialization errors are swallowed. Could cause confusion during debugging.

---

## Recommended Refactoring Approaches

### Approach 1: Extract Reference Store Generic

**Effort**: Low | **Impact**: Reduces duplication by ~30 lines

**Problem**: `CoverRefStore` and `ResRefStore` are nearly identical (~45 lines each)

**Solution**:
```swift
@Observable
@MainActor
final class ReferenceStore<T: PersistentModel>: SwiftDataStore {
    unowned let modelContext: ModelContext

    var storedReferences: [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }

    var defaultSources: [T] where T: Defaultable {
        storedReferences.filter { $0.enabledByDefault }
    }

    init(context: ModelContext) {
        modelContext = context
    }

    func addReference(_ ref: T) -> T {
        modelContext.insert(ref)
        saveContext()
        return ref
    }

    func deleteReference(_ ref: T) {
        modelContext.delete(ref)
        saveContext()
    }
}

typealias CoverRefStore = ReferenceStore<CoverRef>
typealias ResRefStore = ReferenceStore<ResRef>
```

**Steps**:
1. Create `ReferenceStore<T>` generic
2. Define `Defaultable` protocol with `enabledByDefault` requirement
3. Make `CoverRef` and `ResRef` conform to `Defaultable`
4. Replace `CoverRefStore.swift` and `ResRefStore.swift` with type aliases

---

### Approach 2: Extract Singleton Entity Store Pattern

**Effort**: Low | **Impact**: Reduces duplication by ~50 lines

**Problem**: `ApplicantProfileStore` and `ExperienceDefaultsStore` share identical caching pattern

**Solution**:
```swift
@Observable
@MainActor
class SingletonEntityStore<T: PersistentModel>: SwiftDataStore {
    let modelContext: ModelContext
    private var cachedEntity: T?

    init(context: ModelContext) {
        self.modelContext = context
    }

    func current() -> T {
        if let cachedEntity {
            return cachedEntity
        }

        if let existing = try? modelContext.fetch(FetchDescriptor<T>()).first {
            cachedEntity = existing
            return existing
        }

        let entity = T()
        modelContext.insert(entity)
        saveContext()
        cachedEntity = entity
        return entity
    }

    func save(_ entity: T) {
        if entity.modelContext == nil {
            modelContext.insert(entity)
        }
        cachedEntity = entity
        saveContext()
    }

    func invalidateCache() {
        cachedEntity = nil
    }
}

final class ApplicantProfileStore: SingletonEntityStore<ApplicantProfile> {
    func currentProfile() -> ApplicantProfile { current() }
}
```

**Steps**:
1. Create generic `SingletonEntityStore<T>`
2. Move caching logic to generic
3. Have `ApplicantProfileStore` and `ExperienceDefaultsStore` inherit from it
4. Add `invalidateCache()` for multi-window scenarios

---

### Approach 3: Extract Resume Creation Services

**Effort**: Medium | **Impact**: Reduces ResStore complexity by 50%; improves testability

**Problem**: `ResStore.create()` and `ResStore.duplicate()` are large, complex methods with multiple responsibilities

**Solution**:
Create specialized services:
```swift
@MainActor
struct ResumeCreationService {
    let templateSeedStore: TemplateSeedStore
    let experienceDefaultsStore: ExperienceDefaultsStore
    let applicantProfileStore: ApplicantProfileStore

    func createResume(
        for jobApp: JobApp,
        with sources: [ResRef],
        using template: Template
    ) -> Resume? {
        // Encapsulate tree building, context creation
    }
}

@MainActor
struct ResumeTreeService {
    func duplicateTree(
        _ original: TreeNode,
        for resume: Resume
    ) -> TreeNode {
        // Encapsulate recursive tree copying
    }
}
```

**Steps**:
1. Create `ResumeCreationService` for create/context-building logic
2. Create `ResumeTreeService` for tree duplication
3. Move animation logic to view models
4. Have `ResStore` delegate to these services
5. Update return types to use `Result<Resume, Error>` instead of optionals

---

### Approach 4: Extract Form Management from JobAppStore

**Effort**: Low | **Impact**: Cleaner separation of concerns

**Problem**: Form editing logic shouldn't be in data store

**Solution**:
```swift
@MainActor
final class JobAppFormManager {
    var form = JobAppForm()

    func loadFromApp(_ jobApp: JobApp) {
        form.populateFromObj(jobApp)
    }

    func applyToApp(_ jobApp: JobApp) {
        jobApp.jobPosition = form.jobPosition
        jobApp.jobLocation = form.jobLocation
        // ... etc
    }

    func reset() {
        form = JobAppForm()
    }
}

// JobAppStore becomes:
final class JobAppStore: SwiftDataStore {
    var selectedApp: JobApp?
    // ... no form property

    func editApplication(_ jobApp: JobApp) -> JobAppFormManager {
        let manager = JobAppFormManager()
        manager.loadFromApp(jobApp)
        return manager
    }
}
```

**Steps**:
1. Create `JobAppFormManager` class
2. Move form and form-related methods to it
3. Update `JobAppStore` to return managers instead of managing form
4. Update views to use the manager

---

## Simpler Alternative Architectures

### Alternative 1: Simplified Flat Store Architecture

**Current**: Multiple specialized stores with cross-dependencies
**Alternative**: Single `DataManager` with typed methods

```swift
@MainActor
final class DataManager: SwiftDataStore {
    let modelContext: ModelContext

    init(context: ModelContext) {
        self.modelContext = context
    }

    // Job Apps
    func jobApps() -> [JobApp] { ... }
    func addJobApp(_ app: JobApp) -> JobApp { ... }
    func deleteJobApp(_ app: JobApp) { ... }

    // Resumes
    func resumes(for jobApp: JobApp) -> [Resume] { ... }
    func createResume(for jobApp: JobApp, ...) -> Resume? { ... }

    // etc...
}
```

**Pros**:
- Single dependency instead of web of stores
- Easier to test (mock one object)
- No initialization order concerns
- Simpler AppDependencies initialization

**Cons**:
- Violates single responsibility principle
- File becomes very large (1000+ lines)
- No domain boundaries
- Harder to add new domain types
- `@Observable` behavior unclear with 100+ properties

**Recommendation**: ❌ Not suitable for this codebase size

---

### Alternative 2: Protocol-Based Facade Pattern

**Current**: Direct store dependency injection
**Alternative**: Capability-based protocols

```swift
protocol ApplicationPersistence {
    func applications() -> [JobApp]
    func save(_ application: JobApp)
    func delete(_ application: JobApp)
}

protocol ResumePersistence {
    func resumes(for jobApp: JobApp) -> [Resume]
    func save(_ resume: Resume)
}

@MainActor
final class PersistenceService: ApplicationPersistence, ResumePersistence {
    private let jobAppStore: JobAppStore
    private let resStore: ResStore

    init(jobAppStore: JobAppStore, resStore: ResStore) {
        self.jobAppStore = jobAppStore
        self.resStore = resStore
    }

    // Implementation delegating to stores
}

// Views inject capabilities:
struct ResumesView {
    @Environment(ResumePersistence.self) var persistence
}
```

**Pros**:
- Views depend on capabilities, not concrete stores
- Easier testing via protocol mocks
- Clear interface boundaries
- Flexible implementation swapping

**Cons**:
- Extra layer of indirection
- Protocol definitions become numerous
- Delegation boilerplate
- Harder to debug (unclear which store owns what)

**Recommendation**: ⚠️ Might be overkill for current needs; consider if view complexity increases

---

## Specific Complexity Metrics

| Metric | Value | Assessment |
|--------|-------|------------|
| **Total Files** | 10 | Reasonable for a persistence layer |
| **Total Lines** | ~950 | Low-to-medium for domain coverage |
| **Average File Size** | 95 lines | Good - focused files |
| **Max File Size** | 264 lines (ResStore) | Acceptable but large |
| **Protocols Defined** | 3 | Appropriate use of abstraction |
| **Stores** | 7 data stores | Clean domain breakdown |
| **Helper Classes** | 3 (SwiftDataStore, SchemaVersioning, etc.) | Minimal infrastructure |
| **Cross-Store Dependencies** | 6 explicit pairs | Moderate coupling |

---

## Swift-Specific Concerns

### MainActor Safety
✅ **Good**: All stores properly annotated with `@MainActor`
- Prevents data races
- Compatible with SwiftUI's threading model
- Clear intent

### Actor Isolation
⚠️ **Adequate**: No custom actors used
- Acceptable since everything is on MainActor
- Consider custom actors if background processing needed

### Concurrency
⚠️ **Minor Issue**: Some stores launch tasks without structured concurrency:
- ResStore.swift line 87-93: `Task { @MainActor in ... }`
- Should prefer `async/await` patterns if possible

### Memory Management
⚠️ **Concern**: Mix of `unowned` and owned references
- `unowned modelContext`: Assumes stable lifetime
- Consider consistent ownership model

---

## Conclusion

### Overall Assessment

The DataManagers module demonstrates **solid architectural decisions** with a pragmatic, consistency-focused approach. The module exhibits **medium complexity** that is appropriate for its domain responsibilities. The primary strengths are:

1. **High consistency** across all stores
2. **Effective use of protocols** for DRY principles
3. **Thread safety** via explicit MainActor annotation
4. **Clear separation** of concerns (mostly)
5. **Minimal over-abstraction** - pragmatic tradeoffs

### Prioritized Recommendations

**Priority 1 - High Impact, Low Effort** (Implement Soon):
1. **Extract Reference Store Generic**: Eliminate 90 lines of duplication between CoverRefStore and ResRefStore
2. **Standardize Error Handling**: Create a consistent error strategy across all saves
3. **Fix Weak Reference Risks**: Change `unowned` ModelContext to owned `let` for safety

**Priority 2 - Medium Impact, Medium Effort** (Plan for Next Sprint):
1. **Extract Form Management**: Move JobAppForm out of JobAppStore
2. **Extract Resume Services**: Split ResStore.create() and duplicate() into dedicated services
3. **Consolidate Singleton Pattern**: Generic `SingletonEntityStore<T>` for profile/defaults stores

**Priority 3 - Quality Improvements** (Nice to Have):
1. **Reduce store interdependencies** through event sourcing or notification patterns
2. **Remove emoji logging** in favor of structured logging
3. **Add cache invalidation** for multi-window support in singleton stores
4. **Extract tree building** from ResStore into dedicated TreeBuilder service

### What's Working Well

- ✅ Protocol-based abstraction at right level
- ✅ Consistent initialization patterns
- ✅ Effective use of `SwiftDataStore` to eliminate boilerplate
- ✅ Clear entity-to-store mapping
- ✅ Proper thread safety
- ✅ Centralized schema management

### Architecture Verdict

**Recommended**: Keep the current Store Pattern architecture but implement Priority 1 and Priority 2 recommendations to reduce complexity and improve maintainability. The module is on a **healthy trajectory** and doesn't require fundamental restructuring.

**Complexity Rating Justification**: **Medium** because:
- Appropriate abstractions exist without over-engineering
- Some methods are large but address legitimate complexity
- Inter-store coupling is moderate but manageable
- Code is consistent and patterns are predictable
- Testability is good (protocols exist for critical paths)
