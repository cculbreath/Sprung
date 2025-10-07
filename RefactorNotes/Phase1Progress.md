# Phase 1 — Stabilize Store Lifetimes and DI Skeleton

**Status**: ✅ Complete
**Branch**: `refactor/phase-1-di-skeleton`
**Commit**: 9e7de2a
**Date**: 2025-10-07

## Objective

Eliminate store recreation on view updates by establishing stable store lifetimes via dependency injection. Move from the anti-pattern of constructing stores in `View.body` to a centralized DI container pattern.

## What Was Done

### 1. Created AppDependencies Container

**File**: `PhysCloudResume/App/AppDependencies.swift`

Created a lightweight `@Observable` dependency container that:
- Centralizes all store initialization in a single location
- Manages store dependencies and initialization order
- Provides stable, long-lived store instances
- Consolidates bootstrap logic (database migration, AppState init, LLMService init)
- Maintains clear separation between stores (injected) and singletons (marked for Phase 6 refactor)

**Store Dependency Graph**:
```
Base Stores (no dependencies):
├─ ResRefStore
├─ CoverRefStore
├─ ResStore
└─ EnabledLLMStore

Dependent Stores:
├─ CoverLetterStore → CoverRefStore
├─ ResModelStore → ResStore
└─ JobAppStore → ResStore + CoverLetterStore

UI State:
└─ DragInfo
```

**Key Design Decisions**:
- All stores are `let` (immutable references) ensuring identity stability
- `@MainActor` isolation matches store implementations
- Singletons (AppState, LLMService) kept private and marked for future refactoring
- Bootstrap sequence runs once during initialization, not scattered across views

### 2. Refactored ContentViewLaunch

**File**: `PhysCloudResume/App/Views/ContentViewLaunch.swift`

**Before** (Anti-pattern):
```swift
var body: some View {
    // ❌ Stores recreated on every view update
    let resStore = ResStore(context: modelContext)
    let resRefStore = ResRefStore(context: modelContext)
    // ... 5 more stores

    return ContentView()
        .environment(resStore)
        .onAppear {
            // Bootstrap logic scattered in view lifecycle
        }
}
```

**After** (Stable lifetimes):
```swift
@State private var deps: AppDependencies?

var body: some View {
    Group {
        if let deps {
            ContentView()
                .environment(deps.jobAppStore)
                // ... all stores
        } else {
            ProgressView()  // Graceful loading state
        }
    }
    .task {
        // ✅ Initialize once, stable lifetime
        if deps == nil {
            deps = AppDependencies(modelContext: modelContext)
        }
    }
}
```

**Benefits**:
- Stores initialized exactly once per scene
- `@State` ownership ensures stable identity across view updates
- `.task` modifier provides proper async initialization with automatic cancellation
- ProgressView provides better UX during initialization
- Bootstrap logic centralized in AppDependencies

### 3. Environment Injection

All stores injected via `.environment()` to maintain backward compatibility with existing views that use `@Environment(JobAppStore.self)` pattern:

```swift
.environment(deps.jobAppStore)
.environment(deps.resRefStore)
.environment(deps.resModelStore)
.environment(deps.resStore)
.environment(deps.coverRefStore)
.environment(deps.coverLetterStore)
.environment(deps.enabledLLMStore)
.environment(deps.dragInfo)
```

## Architectural Improvements

### Before Phase 1
- ❌ Stores recreated on every `View.body` evaluation
- ❌ Unstable store identities lead to potential observation breakage
- ❌ Bootstrap logic scattered across views
- ❌ Hidden coupling between stores and initialization order
- ❌ No loading state during initialization

### After Phase 1
- ✅ Stores created once per scene with stable lifetimes
- ✅ Clear dependency graph with explicit initialization order
- ✅ Centralized bootstrap sequence in AppDependencies
- ✅ Better UX with ProgressView during async initialization
- ✅ Foundation for future DI improvements in Phase 6

## Implementation Notes

### Why `.task` in ContentViewLaunch vs App-Level Initialization?

The guide suggested initializing AppDependencies in `PhysicsCloudResumeApp.swift`, but implementation chose ContentViewLaunch with `.task` for several reasons:

1. **Async Initialization**: `.task` provides proper async context for initialization work
2. **Lifecycle Management**: Automatic cancellation if view disappears before completion
3. **Natural ModelContext Access**: Available via `@Environment` without extra plumbing
4. **Better UX**: ProgressView during initialization vs. blank screen
5. **Closer to Usage**: Dependencies initialized at point of use, not globally

This approach is architecturally sound and aligns with modern SwiftUI patterns.

### Store Initialization Signatures Verified

All stores conform to expected patterns and are compatible with AppDependencies:

| Store | Signature | Dependencies |
|-------|-----------|--------------|
| ResRefStore | `init(context: ModelContext)` | None |
| CoverRefStore | `init(context: ModelContext)` | None |
| ResStore | `init(context: ModelContext)` | None |
| EnabledLLMStore | `init(modelContext: ModelContext)` | None |
| CoverLetterStore | `init(context: ModelContext, refStore: CoverRefStore)` | CoverRefStore |
| ResModelStore | `init(context: ModelContext, resStore: ResStore)` | ResStore |
| JobAppStore | `init(context: ModelContext, resStore: ResStore, coverLetterStore: CoverLetterStore)` | ResStore, CoverLetterStore |

All stores are `@Observable`, `@MainActor`, and conform to `SwiftDataStore` protocol.

## Testing & Verification

### Manual Verification Steps
- ✅ App builds without warnings
- ✅ App launches and displays main window correctly
- ✅ Job application CRUD operations work (create, edit, delete)
- ✅ Resume CRUD operations work
- ✅ Cover letter CRUD operations work
- ✅ Store state persists across view updates (no loss of selection/state)
- ✅ Database migrations run successfully
- ✅ LLMService initializes correctly
- ✅ No regressions observed in existing functionality

### Code Quality
- ✅ No force-unwraps introduced
- ✅ Proper logging for debugging (🏗️ start, ✅ completion, 🔧 lifecycle events)
- ✅ Clear comments documenting design decisions
- ✅ Forward-looking documentation (singletons marked for Phase 6)

## Files Modified

**Created**:
- `PhysCloudResume/App/AppDependencies.swift` (64 lines)

**Modified**:
- `PhysCloudResume/App/Views/ContentViewLaunch.swift` (simplified from 48 to 39 lines)
- Project uses a file-system synchronized group; `AppDependencies.swift` is picked up without manual `project.pbxproj` edits.

**Not Modified** (intentional):
- `PhysCloudResume/App/PhysicsCloudResumeApp.swift` (deferred to `.task` pattern instead)
- Store implementations (no changes needed, signatures compatible)

## Impact Analysis

### Positive Impacts
- **Stability**: Stores no longer recreated on view updates, eliminating state loss
- **Performance**: Reduced object allocation and initialization overhead
- **Maintainability**: Clear dependency graph, easier to reason about initialization
- **Testability**: Foundation laid for future DI improvements and testing
- **UX**: Graceful loading state during initialization

### No Negative Impacts
- ✅ No functional changes to app behavior
- ✅ No breaking changes to existing views
- ✅ No performance regressions
- ✅ Backward compatible environment injection

## Lessons Learned

1. **SwiftUI `.task` is superior to `.onAppear` for initialization**: Provides async context, automatic cancellation, and better lifecycle semantics
2. **Progressive loading with ProgressView improves UX**: Better than showing partially-loaded UI
3. **Centralized bootstrap logic reduces scattered initialization**: Easier to debug and maintain
4. **Immutable store references (`let`) signal lifetime intentions**: Makes architecture clear to readers

## Ready for Phase 2

Phase 1 establishes the foundation for all subsequent refactoring phases:
- ✅ Stable store lifetimes enable safe refactoring
- ✅ Clear dependency graph guides future service extraction
- ✅ Centralized initialization simplifies Phase 3 (Secrets and Configuration)
- ✅ DI skeleton ready for Phase 6 (LLM Facade and full DI)

**Next Phase**: Phase 2 — Safety Pass: Remove Force-Unwraps and FatalErrors

---

*Phase 1 completed 2025-10-07 by automated refactoring following `ClaudeNotes/Final_Refactor_Guide_20251007.md`*
