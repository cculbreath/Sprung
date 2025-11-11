# Technical Debt: Duplicate Sync Cache Pattern

**Created:** 2024-11-10
**Status:** Active Technical Debt
**Priority:** Medium
**Effort:** ~4 hours

## Problem Summary

The codebase currently has duplicate `nonisolated(unsafe)` sync caches in both `ArtifactRepository` and `StateCoordinator`, violating the single source of truth principle defined in `.arch-spec.md`.

## Current State

### ArtifactRepository (actor)
```swift
actor ArtifactRepository {
    // Actor-isolated state (correct)
    private var artifacts = OnboardingArtifacts()

    // PROBLEM: Sync caches (should not be here)
    nonisolated(unsafe) private(set) var skeletonTimelineSync: JSON?
    nonisolated(unsafe) private(set) var artifactRecordsSync: [JSON] = []
    nonisolated(unsafe) private(set) var applicantProfileSync: JSON?
    nonisolated(unsafe) private(set) var enabledSectionsSync: Set<String> = []
    nonisolated(unsafe) private(set) var knowledgeCardsSync: [JSON] = []
}
```

### StateCoordinator (actor)
```swift
actor StateCoordinator {
    // DUPLICATE: Copies of ArtifactRepository's sync caches
    nonisolated(unsafe) private(set) var skeletonTimelineSync: JSON?
    nonisolated(unsafe) private(set) var artifactRecordsSync: [JSON] = []

    // Updates by copying from ArtifactRepository
    func handleTimelineEvent(_ event: OnboardingEvent) async {
        await artifactRepository.createTimelineCard(card)
        skeletonTimelineSync = artifactRepository.skeletonTimelineSync // Copying!
    }
}
```

## Architecture Violations

1. **Violates Single Source of Truth** - `.arch-spec.md` line 4 states "StateCoordinator (actor) is the ONLY source of truth"
2. **Data Duplication** - Same data exists in two places
3. **Synchronization Risk** - Caches could become out of sync
4. **Unclear Ownership** - Which component owns the sync cache?

## Correct Architecture

Per the hybrid architecture specification:
- **StateCoordinator**: Single source of truth, owns all sync caches for UI
- **ArtifactRepository**: Domain service with actor-isolated state only
- **@Observable chain**: UI observes StateCoordinator's sync properties

## Detailed Refactoring Plan

### Phase 1: Inventory Sync Properties (30 min)
1. List all `nonisolated(unsafe)` properties in ArtifactRepository
2. Identify which StateCoordinator properties duplicate them
3. Find all access points from UI components

### Phase 2: Refactor ArtifactRepository (1.5 hours)

#### Step 2.1: Remove sync caches from ArtifactRepository
```swift
actor ArtifactRepository {
    // KEEP: Actor-isolated state
    private var artifacts = OnboardingArtifacts()

    // REMOVE: All nonisolated(unsafe) properties
    // - skeletonTimelineSync
    // - artifactRecordsSync
    // - applicantProfileSync
    // - enabledSectionsSync
    // - knowledgeCardsSync

    // ADD: Async getters for actor-isolated data
    func getSkeletonTimeline() -> JSON? {
        artifacts.skeletonTimeline
    }

    func getArtifactRecords() -> [JSON] {
        artifacts.artifactRecords
    }

    func getApplicantProfile() -> JSON? {
        artifacts.applicantProfile
    }

    func getEnabledSections() -> Set<String> {
        artifacts.enabledSections
    }

    func getKnowledgeCards() -> [JSON] {
        artifacts.knowledgeCards
    }
}
```

### Phase 3: Update StateCoordinator (1.5 hours)

#### Step 3.1: StateCoordinator owns all sync caches
```swift
actor StateCoordinator {
    // KEEP: These sync caches (single source of truth)
    nonisolated(unsafe) private(set) var skeletonTimelineSync: JSON?
    nonisolated(unsafe) private(set) var artifactRecordsSync: [JSON] = []
    nonisolated(unsafe) private(set) var applicantProfileSync: JSON?
    nonisolated(unsafe) private(set) var enabledSectionsSync: Set<String> = []
    nonisolated(unsafe) private(set) var knowledgeCardsSync: [JSON] = []
}
```

#### Step 3.2: Update event handlers to sync from async getters
```swift
private func handleTimelineEvent(_ event: OnboardingEvent) async {
    switch event {
    case .timelineCardCreated(let card):
        await artifactRepository.createTimelineCard(card)
        // Update OUR cache from actor data (not copying their cache)
        skeletonTimelineSync = await artifactRepository.getSkeletonTimeline()

    case .artifactRecordProduced(let record):
        await artifactRepository.upsertArtifactRecord(record)
        artifactRecordsSync = await artifactRepository.getArtifactRecords()

    // ... similar for all events
    }
}
```

#### Step 3.3: Initialize sync caches on startup
```swift
func initialize() async {
    // Load initial state into sync caches
    skeletonTimelineSync = await artifactRepository.getSkeletonTimeline()
    artifactRecordsSync = await artifactRepository.getArtifactRecords()
    applicantProfileSync = await artifactRepository.getApplicantProfile()
    enabledSectionsSync = await artifactRepository.getEnabledSections()
    knowledgeCardsSync = await artifactRepository.getKnowledgeCards()
}
```

### Phase 4: Update Coordinator Access (30 min)

The OnboardingInterviewCoordinator already correctly accesses StateCoordinator's sync caches:
```swift
var skeletonTimelineSync: JSON? { state.skeletonTimelineSync }
var artifactRecordsSync: [JSON] { state.artifactRecordsSync }
```

No changes needed here - this is already correct!

### Phase 5: Test & Verify (30 min)

1. **Compile check** - Ensure no references to removed properties
2. **Runtime test** - Verify timeline cards still update in real-time
3. **Event flow test** - Confirm all artifact operations work
4. **UI reactivity test** - Check @Observable chain still triggers updates

## Migration Checklist

- [ ] Create feature branch `refactor/sync-cache-consolidation`
- [ ] Remove all `nonisolated(unsafe)` from ArtifactRepository
- [ ] Add async getter methods to ArtifactRepository
- [ ] Update StateCoordinator event handlers to use async getters
- [ ] Add StateCoordinator initialization of sync caches
- [ ] Search codebase for any direct ArtifactRepository sync access
- [ ] Run full test suite
- [ ] Test timeline card real-time updates
- [ ] Test artifact uploads and persistence
- [ ] Update architecture documentation

## Benefits After Refactoring

1. **Single Source of Truth** - StateCoordinator owns all UI state
2. **Clear Ownership** - No ambiguity about where sync caches live
3. **Reduced Complexity** - One less synchronization point
4. **Better Testability** - Can mock ArtifactRepository's async methods
5. **Compliance** - Follows `.arch-spec.md` principles

## Risk Assessment

**Risk Level:** Low-Medium

**Potential Issues:**
- Startup performance if loading large artifact sets
- Need to ensure all event handlers properly update caches
- Must verify no UI components directly access ArtifactRepository

**Mitigation:**
- Can lazy-load some caches if performance is an issue
- Comprehensive testing of event flows
- Compiler will catch direct access attempts

## Notes

This debt was introduced when implementing real-time timeline updates. The quick solution was to expose the sync caches through the @Observable chain, but this revealed the underlying duplication issue. The refactor will make the architecture cleaner while preserving the real-time update functionality.