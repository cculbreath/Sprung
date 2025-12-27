# SearchOpsOnboardingView Refactoring Assessment

**File**: `/Users/cculbreath/devlocal/codebase/Sprung/Sprung/SearchOps/Views/Onboarding/SearchOpsOnboardingView.swift`
**Lines**: 830
**Date**: 2025-12-27

---

## File Overview and Primary Purpose

`SearchOpsOnboardingView` is a SwiftUI view that implements a multi-step onboarding wizard for the SearchOps module. It collects job search preferences from the user through a 5-step flow:

1. **Welcome** - Introduction to Discovery features
2. **Sectors** - Role/sector selection with LLM-suggested roles
3. **Location** - Work location and arrangement preferences
4. **Goals** - Weekly application and networking targets
5. **Setup** - Final configuration and AI-powered source discovery

The view manages form state, LLM interactions for role suggestions and location extraction, and orchestrates the onboarding completion workflow.

---

## Responsibility Analysis

### Primary Responsibility
Multi-step onboarding wizard UI for collecting job search preferences.

### Distinct Concerns Identified

| # | Concern | Lines | Description |
|---|---------|-------|-------------|
| 1 | **View State Management** | 17-34 | 18 `@State` properties for form data, loading states, errors |
| 2 | **Step Navigation** | 57-89, 616-657 | Progress bar, step switching, navigation buttons |
| 3 | **Welcome Step UI** | 114-161 | Static feature introduction |
| 4 | **Sectors Step UI** | 165-233 | Role selection with grid, custom input |
| 5 | **LLM Role Suggestions** | 272-390 | Fetching and displaying AI-suggested roles |
| 6 | **Location Preferences Extraction** | 392-436 | LLM-based preference extraction |
| 7 | **Location Step UI** | 462-513 | Location and work arrangement inputs |
| 8 | **Goals Step UI** | 518-560 | Weekly goal steppers |
| 9 | **Setup/Completion Step** | 564-612, 661-696 | Final summary, discovery execution |
| 10 | **Supporting Views** | 701-830 | 5 private helper views (130 lines) |

**Total Concerns: 10** (though some overlap naturally in a wizard pattern)

---

## Code Quality Observations

### Positive Patterns

1. **Clear Step Organization**: Each step is extracted into its own computed property (`welcomeStep`, `sectorsStep`, etc.)
2. **Supporting Views Extracted**: Small reusable components (`FeatureRow`, `SectorButton`, `GoalStepper`, `OnboardingSummaryRow`, `FlowLayout`) are properly extracted as private structs
3. **Logical Flow**: The wizard progression is easy to follow
4. **Async/Await Usage**: Modern concurrency patterns for LLM interactions
5. **Clear MARK Comments**: Code is well-organized with section markers

### Code Smells

1. **Large State Block**: 18 `@State` properties (lines 17-34) - approaching state management complexity
2. **Mixed Responsibilities**: LLM interaction logic is embedded in the view rather than delegated to a view model or service
3. **Business Logic in View**:
   - `buildDossierSummary()` (lines 370-390) - data transformation logic
   - `fetchRoleSuggestions()` (lines 348-368) - orchestration logic
   - `fetchLocationPreferences()` (lines 392-436) - complex async logic with fallback handling
   - `startSetup()` (lines 661-692) - complex save and discovery logic

### Anti-Patterns

1. **View Contains Business Logic**: The `startSetup()` function saves preferences to multiple stores and orchestrates discovery - this should be in a coordinator or view model
2. **Direct Store Manipulation**: Lines 666-679 directly manipulate `preferencesStore` and `weeklyGoalStore`

---

## Coupling Analysis

### Dependencies
- `SearchOpsCoordinator` - for LLM operations and discovery
- `CoverRefStore` - for dossier data
- `ApplicantProfileStore` - for profile data
- `Logger` - for logging

### Testability Issues
- **Moderate**: The view has many dependencies injected via initializer, which is good
- **However**: LLM interaction logic in the view makes it harder to test the suggestion/extraction flows in isolation
- **State Complexity**: 18 state variables make UI testing complex

---

## Recommendation: **DO NOT REFACTOR**

### Rationale

1. **Working Code**: This is a functional, well-organized onboarding wizard that appears to work correctly

2. **Natural Wizard Pattern**: The ~830 lines largely reflect the inherent complexity of a 5-step wizard with:
   - 5 distinct step UIs
   - 5 reusable supporting views
   - Form state management
   - Navigation logic

3. **Already Follows Extraction Patterns**:
   - Each step is a separate computed property
   - Supporting views are already extracted as private structs
   - The coordinator pattern is already in use for LLM operations

4. **Premature Abstraction Risk**: Extracting a separate view model would add indirection without significant benefit. The state is inherently tied to this specific wizard flow.

5. **130 Lines Are Supporting Views**: Lines 701-830 are private helper views that are appropriately scoped. They're single-use and tightly coupled to this wizard by design.

6. **LLM Logic is Thin**: The actual LLM calls are already delegated to `coordinator.suggestTargetRoles()` and `coordinator.extractLocationPreferences()`. The view just calls these and handles the results.

### Counter-Arguments Considered

| Concern | Why NOT to Refactor |
|---------|---------------------|
| 18 state variables | They represent form fields - natural for a wizard |
| Business logic in view | The "logic" is primarily orchestration of already-abstracted coordinator calls |
| `buildDossierSummary()` | Simple data formatting, 20 lines - not worth extracting |
| `startSetup()` complexity | Could be moved, but it's a single function with clear purpose |

### Minor Improvement Opportunities (Optional)

If touching this file for other reasons, consider:

1. **Extract `FlowLayout`**: The custom layout (lines 792-830) is general-purpose and could be moved to a shared UI components folder for reuse elsewhere

2. **Move Supporting Views**: `FeatureRow`, `SectorButton`, `GoalStepper`, `OnboardingSummaryRow` could be moved to a separate file if they're reused. However, they're currently private and single-use, which is appropriate.

---

## Summary

| Metric | Assessment |
|--------|------------|
| **Line Count** | 830 (large but not excessive for a wizard) |
| **Responsibilities** | Multiple but cohesive (all serve the wizard) |
| **Code Smells** | Minor - some business logic in view |
| **Coupling** | Moderate - uses coordinator appropriately |
| **Testability** | Acceptable - main logic delegated to coordinator |
| **Recommendation** | **DO NOT REFACTOR** |

The file is large but well-organized. The complexity is inherent to the feature (multi-step wizard with LLM enhancements). The code follows established patterns (coordinator for LLM, extracted helper views) and further abstraction would add complexity without proportional benefit.
