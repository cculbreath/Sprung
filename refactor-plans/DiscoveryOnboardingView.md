# Refactor Plan: DiscoveryOnboardingView.swift

**File:** `Sprung/Discovery/Views/Onboarding/DiscoveryOnboardingView.swift`
**Lines:** 815
**Date:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`DiscoveryOnboardingView` is the multi-step onboarding wizard for the Discovery module. It collects the user's job-search preferences across four steps (welcome, target roles, location/arrangement, weekly goals) and then runs the initial AI-driven job-source discovery and task generation on the final step.

---

## 2. Distinct Logical Sections

| Lines | Section | What it does |
|-------|---------|--------------|
| 11-55 | State & data | All `@State` properties and the `commonSectors` data array |
| 57-89 | `body` | Outer shell: progress bar + step router + navigation buttons |
| 91-110 | Progress bar | `progressBar` computed view and `progressFraction` helper |
| 112-161 | Step 0 — Welcome | Marketing/feature introduction using `FeatureRow` components |
| 163-233 | Step 1 — Sectors | Role selection grid, custom role entry, `suggestedRolesSection`, `.task {}` side-effects |
| 235-264 | Selected-roles section | Chip display of already-chosen roles (sub-view of Step 1) |
| 265-344 | Suggested-roles section | LLM-powered suggestions panel, keyword refinement, loading/error states |
| 346-440 | Role suggestion logic | `fetchRoleSuggestions()`, `buildDossierSummary()`, `fetchLocationPreferences()`, `toggleSector()`, `addCustomSector()` |
| 442-496 | Step 2 — Location | Location text field, remote toggle, arrangement picker, company-size picker |
| 498-542 | Step 3 — Goals | `GoalStepper` wrappers and tip callout |
| 544-596 | Step 4 — Setup | In-progress, error, and success states for the async setup call |
| 598-641 | Navigation | `navigationButtons`, `canContinue` guard |
| 643-680 | Actions | `startSetup()` (saves preferences, calls coordinator), `completeOnboarding()` |
| 683-706 | `FeatureRow` | Private supporting view — icon + title + description row |
| 708-729 | `SectorButton` | Private supporting view — checkable sector chip |
| 731-759 | `GoalStepper` | Private supporting view — icon + stepper |
| 761-774 | `OnboardingSummaryRow` | Private supporting view — label/value pair |
| 776-814 | `FlowLayout` | Private `Layout` implementation — horizontal wrapping flow |

---

## 3. SRP Assessment

### Violations

The file mixes four distinct concerns:

**a. Async data-fetch logic inside a View struct**
`fetchRoleSuggestions()`, `buildDossierSummary()`, and `fetchLocationPreferences()` (lines 348–418) contain non-trivial async orchestration, error handling, and state mutation. This is business/service logic — it does not belong in a `View` struct. The view has to know about `candidateDossierStore`, `applicantProfileStore`, AND `coordinator` simultaneously because all three are needed only for this logic.

**b. A duplicate `FlowLayout` implementation**
Lines 776-814 implement a `private struct FlowLayout: Layout`. A superior, more capable version already exists at `Sprung/Shared/Views/FlowStack.swift` (`FlowStack` / `_FlowLayout`). The onboarding file is using an inferior private duplicate instead of the shared component.

**c. Four fully independent step views**
Each of the five steps (`welcomeStep`, `sectorsStep`, `locationStep`, `goalsStep`, `setupStep`) is a self-contained screen with its own layout, data needs, and state. Keeping all five in one file makes it impossible to work on a single step without loading the entire file.

**d. Five private supporting view types in the same file**
`FeatureRow`, `SectorButton`, `GoalStepper`, `OnboardingSummaryRow`, and `FlowLayout` are all general-purpose building blocks. Three of them (`FeatureRow`, `SectorButton`, `GoalStepper`) are reusable enough to be shared. `OnboardingSummaryRow` is trivially simple. All five inflate the file with code that is not specific to the onboarding orchestration logic.

### What is justified

The step-routing in `body` (the `switch currentStep` block), the navigation button bar, `canContinue`, the top-level state properties, and `startSetup()` / `completeOnboarding()` all legitimately belong to the orchestrating view. That portion is around 130 lines of net file content and is appropriate.

### Verdict: Refactor

At 815 lines the file violates SRP in three distinct ways: duplicated shared infrastructure, step-screen content that should be separate view files, and async data-fetch logic that should live in a dedicated type.

---

## 4. Concrete Refactoring Plan

### 4a. FlowLayout dedup — ALREADY COMPLETED

**COMPLETED:** The private `FlowLayout` duplicate has already been deleted from `DiscoveryOnboardingView.swift` and all call sites replaced with `FlowStack(spacing: 8)` as part of a cross-cutting FlowLayout dedup pass. No action needed for this step.

---

### 4b. Extract shared supporting views

**File:** `Sprung/Discovery/Views/Onboarding/DiscoveryOnboardingComponents.swift`
**Purpose:** Houses the small private view types that are used across the onboarding steps.
**Access level:** `internal` (default) — all types stay within the module; no `public` needed.

Move these type definitions (currently `private struct` in the main file) into the new file, promoting them to internal `struct`:

| Type | Current lines |
|------|---------------|
| `FeatureRow` | 685-706 |
| `SectorButton` | 708-729 |
| `GoalStepper` | 731-759 |
| `OnboardingSummaryRow` | 761-774 |

`DiscoveryOnboardingComponents.swift` needs only `import SwiftUI`. No other imports.
`DiscoveryOnboardingView.swift` needs no import change — both files are in the same module.

After the move, remove those four type definitions from `DiscoveryOnboardingView.swift`.

---

### 4c. Extract each step view

Create one file per step, each holding a single `struct` conforming to `View`. All step views are read-only from the orchestrator's perspective — they receive bindings or closures for the state they need to mutate.

#### Step 0: Welcome

**File:** `Sprung/Discovery/Views/Onboarding/DiscoveryWelcomeStepView.swift`
**Lines to move:** 114-161 (the `welcomeStep` computed property body)
**New type:**

```swift
struct DiscoveryWelcomeStepView: View {
    var body: some View { ... }
}
```

No state, no dependencies beyond `SwiftUI`. The `FeatureRow` calls remain in place (they will be found in `DiscoveryOnboardingComponents.swift`).

---

#### Step 1: Sectors

**File:** `Sprung/Discovery/Views/Onboarding/DiscoverySectorsStepView.swift`
**Lines to move:** 163-440 (the `sectorsStep` computed view body, `selectedRolesSection`, `suggestedRolesSection`, `hasDossierData`, and all four helper functions: `fetchRoleSuggestions`, `buildDossierSummary`, `fetchLocationPreferences`, `toggleSector`, `addCustomSector`)
**New type:**

```swift
struct DiscoverySectorsStepView: View {
    let coordinator: DiscoveryCoordinator
    let candidateDossierStore: CandidateDossierStore
    let applicantProfileStore: ApplicantProfileStore

    @Binding var selectedSectors: Set<String>
    @Binding var location: String
    @Binding var remoteAcceptable: Bool
    @Binding var preferredArrangement: WorkArrangement
    @Binding var companySizePreference: CompanySizePreference

    @State private var customSector: String = ""
    @State private var suggestedRoles: [String] = []
    @State private var isLoadingSuggestions: Bool = false
    @State private var suggestionError: String?
    @State private var hasFetchedInitialSuggestions: Bool = false
    @State private var suggestionKeywords: String = ""
    @State private var hasFetchedLocationPreferences: Bool = false
    @State private var isLoadingLocationPreferences: Bool = false

    // ... body, selectedRolesSection, suggestedRolesSection, and all helper funcs
}
```

Note: `location`, `remoteAcceptable`, `preferredArrangement`, and `companySizePreference` are received as `@Binding` because `fetchLocationPreferences()` writes to them (they are pre-filled for Step 2). The `.task {}` modifier that kicks off `fetchRoleSuggestions` and `fetchLocationPreferences` moves into the `.task` on this view's body.

In `DiscoveryOnboardingView`, case 1 becomes:

```swift
case 1:
    DiscoverySectorsStepView(
        coordinator: coordinator,
        candidateDossierStore: candidateDossierStore,
        applicantProfileStore: applicantProfileStore,
        selectedSectors: $selectedSectors,
        location: $location,
        remoteAcceptable: $remoteAcceptable,
        preferredArrangement: $preferredArrangement,
        companySizePreference: $companySizePreference
    )
```

Imports needed in `DiscoverySectorsStepView.swift`: `import SwiftUI` only (all referenced types are internal to the module).

---

#### Step 2: Location

**File:** `Sprung/Discovery/Views/Onboarding/DiscoveryLocationStepView.swift`
**Lines to move:** 444-496 (the `locationStep` computed view body)
**New type:**

```swift
struct DiscoveryLocationStepView: View {
    @Binding var location: String
    @Binding var remoteAcceptable: Bool
    @Binding var preferredArrangement: WorkArrangement
    @Binding var companySizePreference: CompanySizePreference

    var body: some View { ... }
}
```

In `DiscoveryOnboardingView`, case 2 becomes:

```swift
case 2:
    DiscoveryLocationStepView(
        location: $location,
        remoteAcceptable: $remoteAcceptable,
        preferredArrangement: $preferredArrangement,
        companySizePreference: $companySizePreference
    )
```

---

#### Step 3: Goals

**File:** `Sprung/Discovery/Views/Onboarding/DiscoveryGoalsStepView.swift`
**Lines to move:** 500-542 (the `goalsStep` computed view body)
**New type:**

```swift
struct DiscoveryGoalsStepView: View {
    @Binding var weeklyApplicationTarget: Int
    @Binding var weeklyNetworkingTarget: Int

    var body: some View { ... }
}
```

In `DiscoveryOnboardingView`, case 3 becomes:

```swift
case 3:
    DiscoveryGoalsStepView(
        weeklyApplicationTarget: $weeklyApplicationTarget,
        weeklyNetworkingTarget: $weeklyNetworkingTarget
    )
```

---

#### Step 4: Setup

**File:** `Sprung/Discovery/Views/Onboarding/DiscoverySetupStepView.swift`
**Lines to move:** 546-596 (the `setupStep` computed view body)
**New type:**

```swift
struct DiscoverySetupStepView: View {
    let coordinator: DiscoveryCoordinator
    let isDiscovering: Bool
    let discoveryError: String?
    let selectedSectors: Set<String>
    let location: String
    let weeklyApplicationTarget: Int
    let weeklyNetworkingTarget: Int
    let onContinueAnyway: () -> Void

    var body: some View { ... }
}
```

All values are passed as `let` (read-only from setup step's perspective). `onContinueAnyway` maps to the existing `completeOnboarding()` call. In `DiscoveryOnboardingView`, case 4 becomes:

```swift
case 4:
    DiscoverySetupStepView(
        coordinator: coordinator,
        isDiscovering: isDiscovering,
        discoveryError: discoveryError,
        selectedSectors: selectedSectors,
        location: location,
        weeklyApplicationTarget: weeklyApplicationTarget,
        weeklyNetworkingTarget: weeklyNetworkingTarget,
        onContinueAnyway: completeOnboarding
    )
```

---

### 4d. Resulting state of DiscoveryOnboardingView.swift

After the refactor, `DiscoveryOnboardingView.swift` retains only:

- The struct declaration and its stored let/injected properties (lines 11-15)
- `@State` properties that are shared across steps: `currentStep`, `selectedSectors`, `location`, `remoteAcceptable`, `preferredArrangement`, `companySizePreference`, `weeklyApplicationTarget`, `weeklyNetworkingTarget`, `isDiscovering`, `discoveryError` (lines 17-27; the suggestion/location-loading `@State` properties move to `DiscoverySectorsStepView`)
- `commonSectors` moves to `DiscoverySectorsStepView` (it is only used there)
- `body` with its progress bar, step router calling the five new step view types, and navigation buttons
- `progressBar` and `progressFraction`
- `navigationButtons` and `canContinue`
- `startSetup()` and `completeOnboarding()`

Estimated resulting size: ~180-200 lines.

---

## 5. File Summary After Refactor

| File | Purpose | Est. Lines |
|------|---------|-----------|
| `Sprung/Discovery/Views/Onboarding/DiscoveryOnboardingView.swift` | Orchestrator: step routing, nav buttons, preference persistence, coordinator calls | ~190 |
| `Sprung/Discovery/Views/Onboarding/DiscoveryOnboardingComponents.swift` | Shared small view types: `FeatureRow`, `SectorButton`, `GoalStepper`, `OnboardingSummaryRow` | ~100 |
| `Sprung/Discovery/Views/Onboarding/DiscoveryWelcomeStepView.swift` | Step 0: marketing/feature introduction | ~55 |
| `Sprung/Discovery/Views/Onboarding/DiscoverySectorsStepView.swift` | Step 1: role selection, LLM suggestions, background location prefetch | ~290 |
| `Sprung/Discovery/Views/Onboarding/DiscoveryLocationStepView.swift` | Step 2: location, remote toggle, arrangement/size pickers | ~60 |
| `Sprung/Discovery/Views/Onboarding/DiscoveryGoalsStepView.swift` | Step 3: weekly application and networking goal steppers | ~50 |
| `Sprung/Discovery/Views/Onboarding/DiscoverySetupStepView.swift` | Step 4: in-progress/error/success display for async setup | ~60 |

---

## 6. Access Level Changes

No types need to become `public`. All files live in the same module (`Sprung`). The change is:

- `private struct FeatureRow` → `struct FeatureRow` (internal, in `DiscoveryOnboardingComponents.swift`)
- `private struct SectorButton` → `struct SectorButton` (internal)
- `private struct GoalStepper` → `struct GoalStepper` (internal)
- `private struct OnboardingSummaryRow` → `struct OnboardingSummaryRow` (internal)
- `private struct FlowLayout` → **deleted entirely** (replaced by `FlowStack`)

The five new step view structs are declared `internal` (Swift default) — no access modifier needed.

---

## 7. Implementation Order

1. Delete `FlowLayout` (lines 776-814) and replace the two `FlowLayout(spacing: 8)` call sites with `FlowStack(spacing: 8)`. Build to verify no regressions.
2. Create `DiscoveryOnboardingComponents.swift` with the four supporting view types (promoted from `private`). Remove them from `DiscoveryOnboardingView.swift`. Build.
3. Create `DiscoveryWelcomeStepView.swift`. Replace the `welcomeStep` computed property in the switch with `DiscoveryWelcomeStepView()`. Remove the computed property. Build.
4. Create `DiscoveryLocationStepView.swift`. Wire up bindings. Remove `locationStep`. Build.
5. Create `DiscoveryGoalsStepView.swift`. Wire up bindings. Remove `goalsStep`. Build.
6. Create `DiscoverySetupStepView.swift`. Wire up lets and closure. Remove `setupStep`. Build.
7. Create `DiscoverySectorsStepView.swift` (largest step — do last). Move all sector state, suggestion state, location-fetch state, and all helper functions into it. Wire bindings. Remove `sectorsStep`, `selectedRolesSection`, `suggestedRolesSection`, `hasDossierData`, and all five helper functions from the orchestrator. Move `commonSectors` constant here. Build.
8. Final build verification.

---

## 8. What NOT to Change

- The `startSetup()` async function stays in `DiscoveryOnboardingView` — it saves preferences to the coordinator's stores and calls `discoverJobSources()` / `generateDailyTasks()`. It is the final action of the orchestrating view, not of any individual step.
- The `onComplete: () -> Void` callback pattern stays as-is.
- The `DiscoveryMainView` call site requires no changes; the public surface of `DiscoveryOnboardingView` is unchanged.
