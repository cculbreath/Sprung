# Code Sprawl Analysis Report
**Directory**: /Users/cculbreath/devlocal/codebase/Sprung/Sprung/Onboarding/Views
**Analysis Date**: 2025-10-30
**Files Examined**: 28

## Executive Summary
- Total LOC in directory: 4,105
- Estimated reducible LOC: 820 (20%)
- High-priority issues: 12
- Medium-priority issues: 18
- Low-priority issues: 8

## File-by-File Analysis

### OnboardingInterviewView.swift
**Current LOC**: 455
**Estimated reducible LOC**: 120

#### Issues Found

1. **Excessive onChange Handlers** (Priority: High)
   - **Lines**: 130-157
   - **Problem**: 6 separate onChange handlers managing state synchronization between AppStorage, service, and viewModel. Each handler performs nearly identical conditional checks.
   - **Recommendation**: Consolidate into a single state management layer or use Combine to coordinate multi-source state changes.
   - **Effort**: Medium
   - **Impact**: ~40 LOC reduction + improved maintainability
   - **Example**:
     ```swift
     // Before: 6 separate onChange handlers
     .onChange(of: defaultModelId) { _, newValue in
         uiState.handleDefaultModelChange(...)
         updateServiceDefaults()
     }
     .onChange(of: defaultWebSearchAllowed) { _, newValue in
         if !service.isActive {
             uiState.webSearchAllowed = newValue
             updateServiceDefaults()
         }
     }
     // ... 4 more similar handlers

     // After: Consolidated state observer
     .onReceive(stateCoordinator.publisher) {
         updateServiceDefaults()
     }
     ```

2. **Hardcoded Visual Constants Scattered Throughout** (Priority: Medium)
   - **Lines**: 32-35, 84-87
   - **Problem**: Shadow radii, corner radii, and padding values are defined inline in body. Same constants repeated in other view files.
   - **Recommendation**: Extract to a shared DesignSystem or ViewConstants file.
   - **Effort**: Low
   - **Impact**: ~15 LOC reduction when consolidated across files

3. **Wizard Step Logic Duplication** (Priority: High)
   - **Lines**: 293-326, 328-349, 351-368
   - **Problem**: Three separate switch statements over wizardStep for button titles, disabled state, and navigation. Logic is tightly coupled to step enum.
   - **Recommendation**: Create a WizardStepConfig struct that encapsulates button titles, validation logic, and transitions for each step.
   - **Effort**: Medium
   - **Impact**: ~50 LOC reduction + easier to add new wizard steps

4. **Tool Status Logging Pattern** (Priority: Low)
   - **Lines**: 17, 184-193
   - **Problem**: Local state (`loggedToolStatuses`) exists solely to dedupe logging calls. This is UI-level deduplication of a cross-cutting concern.
   - **Recommendation**: Move deduplication into Logger itself or the tool router.
   - **Effort**: Low
   - **Impact**: ~10 LOC reduction + removes state tracking from view

5. **Resume Choice Dialog Logic** (Priority: Medium)
   - **Lines**: 401-433
   - **Problem**: Complex state management for showing/hiding resume dialog with pendingStartModelId coupling. Modal presentation logic mixed with business logic.
   - **Recommendation**: Move resume decision logic to coordinator/service, expose simple boolean for UI.
   - **Effort**: Medium
   - **Impact**: ~15 LOC reduction

---

### OnboardingInterviewToolPane.swift
**Current LOC**: 529
**Estimated reducible LOC**: 140

#### Issues Found

1. **God View - Too Many Responsibilities** (Priority: High)
   - **Lines**: 1-529 (entire file)
   - **Problem**: Single file manages: upload requests, profile intake, choice prompts, validation, phase advance dialogs, section toggles, extraction status, AND summary cards. 529 lines handling 8+ distinct interaction patterns.
   - **Recommendation**: Split into specialized components: UploadCoordinator, ValidationCoordinator, SummaryRenderer. ToolPane should just route to sub-coordinators.
   - **Effort**: High
   - **Impact**: ~200 LOC reduction via elimination of routing logic duplication

2. **Repetitive Task Wrapping Pattern** (Priority: High)
   - **Lines**: 36-46, 59-68, 100-104, 111-122, etc.
   - **Problem**: Every interactive card callback wraps result handling in identical `Task { await service.resumeToolContinuation(from: result) }` pattern. Repeated 10+ times.
   - **Recommendation**: Create helper method `handleToolResult(_ action: @escaping () async -> ToolResult)` to eliminate boilerplate.
   - **Effort**: Low
   - **Impact**: ~60 LOC reduction
   - **Example**:
     ```swift
     // Before
     onSubmit: { selection in
         Task {
             let result = coordinator.resolveChoice(selectionIds: selection)
             await service.resumeToolContinuation(from: result)
         }
     }

     // After
     onSubmit: handleToolResult { coordinator.resolveChoice(selectionIds: $0) }
     ```

3. **Upload Request Filtering Logic** (Priority: Medium)
   - **Lines**: 211-226
   - **Problem**: Switch over wizard steps with hardcoded upload kind filters. Same pattern appears in multiple views.
   - **Recommendation**: Make this a computed property on WizardStep enum or move to coordinator.
   - **Effort**: Low
   - **Impact**: ~15 LOC reduction

4. **File Type Mapping Duplication** (Priority: Medium)
   - **Lines**: 251-272
   - **Problem**: Hardcoded mapping of upload kinds to file extensions. Fragile, no single source of truth.
   - **Recommendation**: Move to UploadRequest metadata or a centralized FileTypeRegistry.
   - **Effort**: Low
   - **Impact**: ~20 LOC reduction + centralized file type knowledge

5. **isPaneOccupied State Logic** (Priority: Medium)
   - **Lines**: 274-313
   - **Problem**: Manual tracking of whether pane shows interactive card. Two helper methods with 8+ boolean checks.
   - **Recommendation**: Coordinator should expose single `currentInteraction` enum case. View just checks `!= .none`.
   - **Effort**: Medium
   - **Impact**: ~35 LOC reduction

6. **Private Summary Card Views** (Priority: Low)
   - **Lines**: 376-528
   - **Problem**: Three mini-views (ApplicantProfileSummaryCard, SkeletonTimelineSummaryCard, EnabledSectionsSummaryCard) defined at bottom of this file. They're reusable components masquerading as helpers.
   - **Recommendation**: Extract to separate SummaryCards.swift file.
   - **Effort**: Low
   - **Impact**: ~150 LOC moved (not reduced, but improves organization)

---

### OnboardingValidationReviewCard.swift
**Current LOC**: 353
**Estimated reducible LOC**: 90

#### Issues Found

1. **Dual State Management Pattern** (Priority: High)
   - **Lines**: 30-83, 135-158
   - **Problem**: Separate state for applicant profile draft AND skeleton timeline draft, with parallel change tracking, baseline tracking, and JSON normalization. Same logic duplicated for both types.
   - **Recommendation**: Create generic `EditableDataState<T>` type that handles baseline tracking and dirty state.
   - **Effort**: Medium
   - **Impact**: ~50 LOC reduction
   - **Example**:
     ```swift
     // Before
     @State private var applicantDraft: ApplicantProfileDraft
     @State private var baselineApplicantDraft: ApplicantProfileDraft
     @State private var applicantHasChanges: Bool
     // ... + timeline equivalents

     // After
     @State private var applicantEditor: EditableDataState<ApplicantProfileDraft>
     @State private var timelineEditor: EditableDataState<ExperienceDefaultsDraft>
     ```

2. **Type Checking Pattern** (Priority: Medium)
   - **Lines**: 237-247
   - **Problem**: Three computed properties checking `prompt.dataType` string equality. Used in 10+ locations throughout the view.
   - **Recommendation**: Create enum from dataType in init, switch on enum instead of string comparisons.
   - **Effort**: Low
   - **Impact**: ~10 LOC reduction + type safety

3. **Decision Enum Duplication** (Priority: Medium)
   - **Lines**: 5-19
   - **Problem**: Local Decision enum identical to one in OnboardingPhaseAdvanceDialog. Both represent approve/modify/reject pattern.
   - **Recommendation**: Extract to shared ValidationDecision enum.
   - **Effort**: Low
   - **Impact**: ~15 LOC reduction across files

4. **Repetitive Reset Logic** (Priority: Medium)
   - **Lines**: 297-307
   - **Problem**: resetStructuredEditors manually resets 3 pieces of state for each type. Same logic as initialization.
   - **Recommendation**: EditableDataState (from issue #1) would have reset() method.
   - **Effort**: Low (if combined with #1)
   - **Impact**: ~10 LOC reduction

5. **Submit Method Complexity** (Priority: Medium)
   - **Lines**: 309-342
   - **Problem**: 34-line submit method with nested conditionals for each data type. Error state management interspersed.
   - **Recommendation**: Extract per-type submission into helpers or protocol-based approach.
   - **Effort**: Low
   - **Impact**: ~15 LOC reduction

---

### OnboardingPhaseAdvanceDialog.swift
**Current LOC**: 331
**Estimated reducible LOC**: 45

#### Issues Found

1. **Phase Display Name Duplication** (Priority: Medium)
   - **Lines**: 43-54, 273-284
   - **Problem**: Two identical switch statements mapping phase enum to display strings.
   - **Recommendation**: Add displayName property to OnboardingPhase enum or create single helper function.
   - **Effort**: Low
   - **Impact**: ~15 LOC reduction

2. **Verbose Layout Pattern** (Priority: Low)
   - **Lines**: 106-174
   - **Problem**: Nested VStacks with repetitive formatting for "incomplete objectives" and "proposed overrides" sections. Nearly identical structure.
   - **Recommendation**: Extract reusable ObjectiveListCard component accepting icon, color, title, items.
   - **Effort**: Low
   - **Impact**: ~20 LOC reduction

3. **Decision Submission Logic** (Priority: Low)
   - **Lines**: 292-295
   - **Problem**: Simple method that just conditionally passes feedback. Could be inline.
   - **Recommendation**: Inline into button action.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

4. **Formatting Helper** (Priority: Low)
   - **Lines**: 286-290
   - **Problem**: Single-use helper for capitalizing underscored strings. General utility function in specific view.
   - **Recommendation**: Move to String extension if used elsewhere, otherwise inline.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

---

### OnboardingInterviewChatPanel.swift
**Current LOC**: 147
**Estimated reducible LOC**: 20

#### Issues Found

1. **Hardcoded Padding Constants** (Priority: Low)
   - **Lines**: 26-29
   - **Problem**: Local constants for padding that should be in design system.
   - **Recommendation**: Use shared spacing tokens.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

2. **ConditionalIntelligenceGlow ViewModifier** (Priority: Medium)
   - **Lines**: 5-16
   - **Problem**: Private view modifier that switches between intelligence glow and shadow. Single-use abstraction that obscures what's happening.
   - **Recommendation**: Inline the conditional logic at call site (only used once).
   - **Effort**: Low
   - **Impact**: ~10 LOC reduction
   - **Example**:
     ```swift
     // Before
     .modifier(ConditionalIntelligenceGlow(...))

     // After
     Group {
         if service.isProcessing {
             scrollView.intelligenceOverlay(in: shape)
         } else {
             scrollView.shadow(...)
         }
     }
     ```

3. **Auto-Scroll onChange Duplication** (Priority: Low)
   - **Lines**: 49-61
   - **Problem**: Three separate onChange/onAppear handlers for auto-scrolling with identical guard conditions and scrollTo logic.
   - **Recommendation**: Extract to autoScrollIfNeeded(proxy:) helper.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

---

### OnboardingInterviewInteractiveCard.swift
**Current LOC**: 155
**Estimated reducible LOC**: 40

#### Issues Found

1. **ToolStatusBar Excessive Mapping Logic** (Priority: Medium)
   - **Lines**: 92-153
   - **Problem**: Manual display order array, displayName switch, statusText switch, indicatorColor switch. 60+ lines just to render tool status pills.
   - **Recommendation**: Add displayMetadata property to OnboardingToolIdentifier enum returning (name, order).
   - **Effort**: Low
   - **Impact**: ~30 LOC reduction

2. **Status Map Construction** (Priority: Low)
   - **Lines**: 16-20
   - **Problem**: Inline closure that builds status map with special extraction handling. Awkward syntax.
   - **Recommendation**: Make router.statusSnapshot include extraction status, or create helper.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

3. **isOccupied Binding** (Priority: Low)
   - **Lines**: 12, 21
   - **Problem**: Local state isToolPaneOccupied that's unused in this view, only passed to child. Unnecessary state relay.
   - **Recommendation**: Let ToolPane manage its own occupancy state if needed.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

---

### OnboardingInterviewStepProgressView.swift
**Current LOC**: 150
**Estimated reducible LOC**: 30

#### Issues Found

1. **Complex Animation State Management** (Priority: Medium)
   - **Lines**: 21-96
   - **Problem**: StepProgressItem manages 3 pieces of state (measuredLabelWidth, animatedProgress, and derives 7 computed values) just for layout animation. Over-engineered for the visual effect.
   - **Recommendation**: Simplify to 2-state system (pending/active) with spring animation. Remove manual progress interpolation.
   - **Effort**: Medium
   - **Impact**: ~25 LOC reduction

2. **StepLabelWidthReader Preference Key** (Priority: Low)
   - **Lines**: 120-149
   - **Problem**: 30 lines of preference key infrastructure for measuring text width. Standard pattern but verbose.
   - **Recommendation**: Use GeometryReader directly with @State, or accept fixed width approach.
   - **Effort**: Low
   - **Impact**: ~10 LOC reduction if simplified

---

### KnowledgeCardReviewCard.swift
**Current LOC**: 174
**Estimated reducible LOC**: 25

#### Issues Found

1. **Set Toggle Extension** (Priority: Low)
   - **Lines**: 165-173
   - **Problem**: Private extension defining toggleMembership for Set. General-purpose utility in specific view file.
   - **Recommendation**: Move to shared Set+Extensions.swift if used elsewhere.
   - **Effort**: Low
   - **Impact**: ~8 LOC moved to shared location

2. **ByteCountFormatter Recreation** (Priority: Low)
   - **Lines**: 157-162
   - **Problem**: Creates new formatter in computed property, called for every artifact. Should be static.
   - **Recommendation**: Make static let or @State created once.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction + performance improvement

3. **SectionCard Wrapping** (Priority: Low)
   - **Lines**: 55-78, 82-106, 109-134, 136-155
   - **Problem**: Each section wrapped in SectionCard with identical patterns.
   - **Recommendation**: Create array of sections with builders, ForEach over them.
   - **Effort**: Low
   - **Impact**: ~12 LOC reduction

---

### OnboardingInterviewWrapUpSummaryView.swift
**Current LOC**: 249
**Estimated reducible LOC**: 60

#### Issues Found

1. **Unused Private View Structs** (Priority: High)
   - **Lines**: 155-248
   - **Problem**: FactLedgerListView, StyleProfileView, WritingSamplesListView are defined but never used in this file or externally. Dead code from earlier iteration.
   - **Recommendation**: Delete unused views or move to actual usage location.
   - **Effort**: Low
   - **Impact**: ~94 LOC deletion if truly unused

2. **JSON Formatting Duplication** (Priority: Low)
   - **Lines**: 58-60, 197-199
   - **Problem**: Same formattedJSON helper defined twice in same file.
   - **Recommendation**: Move to single location or JSON extension.
   - **Effort**: Low
   - **Impact**: ~3 LOC reduction

3. **Artifact Summary String Building** (Priority: Medium)
   - **Lines**: 62-89
   - **Problem**: 28 lines of imperative string building with conditional appends. Hard to read.
   - **Recommendation**: Use string interpolation with computed properties for each metadata field.
   - **Effort**: Low
   - **Impact**: ~10 LOC reduction

---

### ValidationCardContainer.swift
**Current LOC**: 170
**Estimated reducible LOC**: 20

#### Issues Found

1. **SaveState Enum with Associated Error String** (Priority: Low)
   - **Lines**: 6-11
   - **Problem**: Error case has associated string value, but only generic "Unable to save changes" is ever used.
   - **Recommendation**: If error messages won't vary, use simple boolean success flag.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

2. **Manual Dirty State Tracking** (Priority: Medium)
   - **Lines**: 123-138
   - **Problem**: markDirty, updateDirtyState methods manually coordinate hasChanges with draft comparison. Fragile.
   - **Recommendation**: Use Combine or observation to auto-derive hasChanges from draft != baseline.
   - **Effort**: Medium
   - **Impact**: ~15 LOC reduction

---

### ApplicantProfileIntakeCard.swift
**Current LOC**: 207
**Estimated reducible LOC**: 35

#### Issues Found

1. **Option Button Repetition** (Priority: Medium)
   - **Lines**: 71-102
   - **Problem**: Four nearly identical optionButton calls with slight variations. Could be data-driven.
   - **Recommendation**: Define array of IntakeOption structs, ForEach over them.
   - **Effort**: Low
   - **Impact**: ~20 LOC reduction
   - **Example**:
     ```swift
     struct IntakeOption {
         let title: String
         let subtitle: String
         let icon: String
         let action: () -> Void
     }

     let options: [IntakeOption] = [...]
     ForEach(options) { option in
         optionButton(option)
     }
     ```

2. **State Sync Pattern** (Priority: Low)
   - **Lines**: 39-42
   - **Problem**: onChange to sync local state with passed state. Standard but feels like fighting the framework.
   - **Recommendation**: Consider using @Binding directly instead of @State copy.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

3. **Mode-based View Switching** (Priority: Low)
   - **Lines**: 46-56
   - **Problem**: Switch on mode to render different views. Common pattern, but each case is defined inline below.
   - **Recommendation**: Keep as-is, this is standard SwiftUI pattern.
   - **Effort**: N/A
   - **Impact**: 0 (not an issue)

---

### InterviewChoicePromptCard.swift
**Current LOC**: 126
**Estimated reducible LOC**: 15

#### Issues Found

1. **Selection State Duplication** (Priority: Medium)
   - **Lines**: 8-9, 95-102, 104-115
   - **Problem**: Separate state variables for single vs multi-selection, with switch logic duplicated in 3 methods.
   - **Recommendation**: Use single SelectionState enum that abstracts single/multi.
   - **Effort**: Low
   - **Impact**: ~10 LOC reduction

2. **Icon Name Switching** (Priority: Low)
   - **Lines**: 117-124
   - **Problem**: Simple switch just to pick icon names. Could be computed on SelectionStyle enum.
   - **Recommendation**: Add iconNames property to SelectionStyle.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

---

### ApplicantProfileReviewCard.swift
**Current LOC**: 74
**Estimated reducible LOC**: 10

#### Issues Found

1. **Draft Merging in Init** (Priority: Low)
   - **Lines**: 17-25
   - **Problem**: Init performs business logic (merging drafts). Views should receive ready-to-display state.
   - **Recommendation**: Coordinator should provide merged draft, view just displays it.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

2. **Plural Handling** (Priority: Low)
   - **Lines**: 34
   - **Problem**: Inline conditional for source pluralization. Minor but common pattern that could be utility.
   - **Recommendation**: String extension for pluralization helper.
   - **Effort**: Low
   - **Impact**: ~2 LOC reduction

---

### OnboardingInterviewUploadRequestCard.swift
**Current LOC**: 124
**Estimated reducible LOC**: 15

#### Issues Found

1. **Async URL Loading Logic** (Priority: Low)
   - **Lines**: 108-122
   - **Problem**: Complex continuation-based async loading with multiple fallback attempts. Standard pattern.
   - **Recommendation**: Keep as-is, this handles NSItemProvider quirks.
   - **Effort**: N/A
   - **Impact**: 0 (necessary complexity)

2. **Drop Handler Task Wrapping** (Priority: Low)
   - **Lines**: 84-106
   - **Problem**: Drop handler creates Task that loops through providers with conditionals. Could be cleaner.
   - **Recommendation**: Extract provider processing to async helper method.
   - **Effort**: Low
   - **Impact**: ~10 LOC reduction

---

### OnboardingInterviewChatComponents.swift
**Current LOC**: 155
**Estimated reducible LOC**: 25

#### Issues Found

1. **LLMActivityView Gradient Layers** (Priority: Low)
   - **Lines**: 116-148
   - **Problem**: Four nearly identical Circle views with increasing blur. Pattern for glow effect.
   - **Recommendation**: ForEach over array of blur values to generate layers.
   - **Effort**: Low
   - **Impact**: ~15 LOC reduction

2. **Assistant Reply Parsing** (Priority: Medium)
   - **Lines**: 70-86
   - **Problem**: Two-pass JSON parsing with manual string searching fallback. Fragile.
   - **Recommendation**: Use proper Codable or SwiftyJSON throughout, eliminate string parsing.
   - **Effort**: Low
   - **Impact**: ~10 LOC reduction

---

### ResumeSectionsToggleCard.swift
**Current LOC**: 64
**Estimated reducible LOC**: 0

#### Issues Found

1. **Well-Structured Component** (Priority: N/A)
   - **Lines**: All
   - **Problem**: None identified
   - **Recommendation**: This file is concise and well-organized. No changes recommended.
   - **Effort**: N/A
   - **Impact**: 0

---

### SkeletonTimelineReviewView.swift
**Current LOC**: 73
**Estimated reducible LOC**: 10

#### Issues Found

1. **Manual Binding Wrapper** (Priority: Low)
   - **Lines**: 46-55
   - **Problem**: Creates new Binding to inject onChange callback. Standard pattern but verbose.
   - **Recommendation**: Consider onChange modifier on Toggle directly.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

2. **Callbacks Struct Recreation** (Priority: Low)
   - **Lines**: 57-71
   - **Problem**: Creates new callbacks struct on every render. Should be memoized.
   - **Recommendation**: Make callbacks a computed property with @State cache.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction (performance gain)

---

### ExtractionReviewSheet.swift
**Current LOC**: 83
**Estimated reducible LOC**: 5

#### Issues Found

1. **JSON Validation in onConfirm** (Priority: Low)
   - **Lines**: 68-75
   - **Problem**: Inline JSON parsing in button handler. Mixing validation with presentation.
   - **Recommendation**: Extract to separate validation method.
   - **Effort**: Low
   - **Impact**: ~3 LOC reduction

---

### ExtractionStatusCard.swift
**Current LOC**: 40
**Estimated reducible LOC**: 0

#### Issues Found

1. **Simple and Focused** (Priority: N/A)
   - **Lines**: All
   - **Problem**: None
   - **Recommendation**: No issues found. Appropriately sized component.
   - **Effort**: N/A
   - **Impact**: 0

---

### OnboardingInterviewBottomBar.swift
**Current LOC**: 48
**Estimated reducible LOC**: 0

#### Issues Found

1. **Clean UI Component** (Priority: N/A)
   - **Lines**: All
   - **Problem**: None
   - **Recommendation**: Well-structured bottom bar with clear props. No changes needed.
   - **Effort**: N/A
   - **Impact**: 0

---

### IntelligenceGlowEffect.swift
**Current LOC**: 129
**Estimated reducible LOC**: 20

#### Issues Found

1. **Rainbow Gradient Hardcoded Colors** (Priority: Low)
   - **Lines**: 90-106
   - **Problem**: 9 hardcoded Color values with opacity tweaks. Should be design system colors.
   - **Recommendation**: Move to centralized color palette.
   - **Effort**: Low
   - **Impact**: ~15 LOC reduction

2. **Gradient Stops Randomization** (Priority: Low)
   - **Lines**: 103-104
   - **Problem**: Random location for gradient stops regenerated repeatedly. Interesting effect but computationally wasteful.
   - **Recommendation**: Consider pre-computed gradient variations or simpler animation.
   - **Effort**: Low
   - **Impact**: ~5 LOC reduction

---

### AnimatedThinkingText.swift
**Current LOC**: 32
**Estimated reducible LOC**: 0

#### Issues Found

1. **Concise Animation Component** (Priority: N/A)
   - **Lines**: All
   - **Problem**: None
   - **Recommendation**: Clean, focused component. No issues.
   - **Effort**: N/A
   - **Impact**: 0

---

### SectionCard.swift
**Current LOC**: 28
**Estimated reducible LOC**: 0

#### Issues Found

1. **Appropriate Wrapper** (Priority: N/A)
   - **Lines**: All
   - **Problem**: None
   - **Recommendation**: Simple, reusable wrapper. Well done.
   - **Effort**: N/A
   - **Impact**: 0

---

### CollapsibleSidePanel.swift
**Current LOC**: 30
**Estimated reducible LOC**: 0

#### Issues Found

1. **Minimal Component** (Priority: N/A)
   - **Lines**: All
   - **Problem**: None
   - **Recommendation**: Appropriately scoped component. No issues.
   - **Effort**: N/A
   - **Impact**: 0

---

### ValidationProtocols.swift
**Current LOC**: 37
**Estimated reducible LOC**: 0

#### Issues Found

1. **Protocol Definition File** (Priority: N/A)
   - **Lines**: All
   - **Problem**: None
   - **Recommendation**: Clean protocol and callback structure. No issues.
   - **Effort**: N/A
   - **Impact**: 0

---

### CitationRow.swift
**Current LOC**: 82
**Estimated reducible LOC**: 5

#### Issues Found

1. **Binding Construction for Toggle** (Priority: Low)
   - **Lines**: 30-33
   - **Problem**: Creates inverted Binding for checkbox. Standard but verbose.
   - **Recommendation**: Consider separate isAccepted state instead of isRejected.
   - **Effort**: Low
   - **Impact**: ~3 LOC reduction

---

### OnboardingInterviewIntroductionCard.swift
**Current LOC**: 69
**Estimated reducible LOC**: 0

#### Issues Found

1. **Clear Onboarding Card** (Priority: N/A)
   - **Lines**: All
   - **Problem**: None
   - **Recommendation**: Well-structured introduction view. No issues.
   - **Effort**: N/A
   - **Impact**: 0

---

### OnboardingInterviewBackgroundView.swift
**Current LOC**: 19
**Estimated reducible LOC**: 0

#### Issues Found

1. **Minimal Background View** (Priority: N/A)
   - **Lines**: All
   - **Problem**: None
   - **Recommendation**: Simple gradient background. Appropriately minimal.
   - **Effort**: N/A
   - **Impact**: 0

---

## Cross-Cutting Patterns

### 1. Hardcoded Visual Constants
**Files**: OnboardingInterviewView, OnboardingInterviewChatPanel, OnboardingInterviewInteractiveCard, IntelligenceGlowEffect
**Problem**: Corner radii (18, 20, 24, 28, 44), shadow parameters (radius: 16-30, y: 10-22), and padding values scattered across files.
**Recommendation**: Create shared DesignSystem.swift with:
```swift
enum DesignSystem {
    enum CornerRadius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 18
        static let large: CGFloat = 28
        static let xlarge: CGFloat = 44
    }

    enum Shadow {
        static let card = (color: Color.black.opacity(0.16), radius: 24.0, y: 18.0)
        static let floating = (color: Color.black.opacity(0.12), radius: 16.0, y: 10.0)
    }
}
```

### 2. Task Wrapping for Tool Continuation
**Files**: OnboardingInterviewToolPane (10+ instances), several card components
**Problem**: Every interactive component wraps result handling in `Task { let result = ...; await service.resumeToolContinuation(from: result) }`
**Recommendation**: Service layer helper:
```swift
func handleToolAction<T>(
    _ action: @escaping () async -> T,
    waitingState: WaitingState = .unchanged,
    persistCheckpoint: Bool = false
) where T: ToolResult {
    Task {
        let result = await action()
        await resumeToolContinuation(from: result, waitingState: waitingState, persistCheckpoint: persistCheckpoint)
    }
}
```

### 3. Enum Display Name Mapping
**Files**: OnboardingPhaseAdvanceDialog, OnboardingInterviewInteractiveCard, OnboardingInterviewView
**Problem**: Repeated switch statements mapping enum cases to user-facing strings.
**Recommendation**: Add displayName computed property to enums themselves (OnboardingPhase, OnboardingWizardStep, OnboardingToolIdentifier).

### 4. JSON Formatting Helpers
**Files**: OnboardingInterviewWrapUpSummaryView, ExtractionReviewSheet, multiple validation cards
**Problem**: `json.rawString(options: .prettyPrinted)` fallback pattern repeated throughout.
**Recommendation**: JSON extension:
```swift
extension JSON {
    var prettyString: String {
        rawString(options: .prettyPrinted) ?? rawString() ?? description
    }
}
```

### 5. State Synchronization Between Sources
**Files**: OnboardingInterviewView, ApplicantProfileIntakeCard, OnboardingValidationReviewCard
**Problem**: Multiple onChange handlers coordinating AppStorage, Environment objects, and local State.
**Recommendation**: Consider Combine publishers or single StateCoordinator class to manage multi-source state synchronization.

---

## Prioritized Recommendations

### Quick Wins (High Impact, Low Effort)

1. **Extract Task Wrapping Helper** (~60 LOC reduction)
   - Files: OnboardingInterviewToolPane, multiple cards
   - Create `handleToolResult` helper to eliminate boilerplate
   - Estimated time: 30 minutes

2. **Create DesignSystem Constants** (~50 LOC reduction across files)
   - Files: All views with hardcoded constants
   - Centralize corner radii, shadows, padding
   - Estimated time: 45 minutes

3. **Delete Unused View Structs** (~94 LOC deletion)
   - File: OnboardingInterviewWrapUpSummaryView
   - Remove FactLedgerListView, StyleProfileView, WritingSamplesListView
   - Estimated time: 15 minutes (verify they're truly unused first)

4. **Add Enum Display Properties** (~40 LOC reduction)
   - Files: OnboardingPhaseAdvanceDialog, OnboardingInterviewInteractiveCard, OnboardingInterviewView
   - Add displayName to phase/step/tool enums
   - Estimated time: 30 minutes

5. **Consolidate Wizard Step Logic** (~50 LOC reduction)
   - File: OnboardingInterviewView
   - Create WizardStepConfig struct
   - Estimated time: 1 hour

**Quick Wins Total**: ~294 LOC reduction, ~3 hours effort

### Medium-term Improvements (High Impact, Medium Effort)

1. **Split OnboardingInterviewToolPane** (~200 LOC better organized)
   - File: OnboardingInterviewToolPane
   - Extract UploadCoordinator, ValidationCoordinator, SummaryRenderer
   - Estimated time: 4 hours

2. **Create Generic EditableDataState** (~70 LOC reduction)
   - Files: OnboardingValidationReviewCard, ValidationCardContainer
   - Eliminates dual state management patterns
   - Estimated time: 3 hours

3. **Consolidate onChange Handlers** (~40 LOC reduction)
   - File: OnboardingInterviewView
   - Use Combine or StateCoordinator for multi-source sync
   - Estimated time: 2 hours

4. **Refactor ToolStatusBar** (~30 LOC reduction)
   - File: OnboardingInterviewInteractiveCard
   - Add metadata to OnboardingToolIdentifier enum
   - Estimated time: 1.5 hours

**Medium-term Total**: ~340 LOC reduction, ~10.5 hours effort

### Strategic Refactoring (High Impact, High Effort)

1. **Wizard Flow State Machine** (~100 LOC reduction + easier extensions)
   - Files: OnboardingInterviewView, coordinator
   - Create declarative wizard configuration with transitions, validations, and UI config per step
   - Eliminates scattered switch statements across multiple methods
   - Estimated time: 8 hours

2. **Tool Interaction Protocol** (~80 LOC reduction)
   - Files: All interactive cards
   - Create protocol-based tool interaction system to eliminate type-specific branches
   - Estimated time: 6 hours

**Strategic Total**: ~180 LOC reduction, ~14 hours effort

### Not Recommended (Low Impact or High Risk)

1. **Simplify OnboardingInterviewStepProgressView Animation**
   - While it could save ~25 LOC, the current implementation provides smooth UX
   - The complexity is intentional for quality animation
   - Risk: Degraded user experience

2. **Flatten View Hierarchy**
   - Some files have nested private views that could be inlined
   - However, current structure aids readability and testing
   - Trade-off isn't worth it

3. **Eliminate ConditionalIntelligenceGlow ViewModifier**
   - While it's single-use, it documents intent clearly
   - Inlining would save 10 LOC but reduce clarity
   - Keep for documentation value

---

## Total Impact Summary

- **Quick Wins**: ~294 LOC reduction (~3 hours)
- **Medium-term**: ~340 LOC reduction (~10.5 hours)
- **Strategic**: ~180 LOC reduction (~14 hours)
- **Total Potential**: ~814 LOC reduction (20% of codebase)

## Observations

### Strengths
1. **Consistent component patterns**: Most files follow clear SwiftUI patterns
2. **Good separation of concerns**: Interactive cards are well-isolated
3. **Type safety**: Strong use of Swift enums and protocols
4. **Reusable components**: SectionCard, CollapsibleSidePanel, CitationRow are clean abstractions

### Weaknesses
1. **God components**: OnboardingInterviewToolPane (529 LOC) and OnboardingInterviewView (455 LOC) have too many responsibilities
2. **Duplicated patterns**: Task wrapping, enum display mapping, state synchronization all repeated
3. **Missing design system**: Visual constants scattered throughout
4. **Manual state tracking**: hasChanges, dirty state, and sync logic written repeatedly
5. **Dead code**: Unused view structs suggest incomplete cleanup from refactoring

### Maintainability Concerns
- Adding new wizard steps requires touching 4+ switch statements in OnboardingInterviewView
- Adding new tool types requires updating multiple conditional branches in ToolPane
- Changing visual styling requires hunting through 10+ files for hardcoded values
- State synchronization bugs likely due to manual onChange coordination

### Testing Challenges
- Large view files make unit testing difficult
- State management spread across onChange handlers is hard to test
- Tool interaction logic mixed into view layer
