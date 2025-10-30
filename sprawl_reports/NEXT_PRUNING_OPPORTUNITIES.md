# Next High-Impact Pruning Opportunities
**Generated**: 2025-10-30
**After Completing**: 449 LOC reduction (Phase 1)

## Overview
This document identifies the next 10 high-impact code reduction opportunities across the Onboarding module, prioritized by ROI (effort vs. impact).

---

## 🎯 Quick Wins (Low Effort, High Impact)

### 1. **Remove Duplicate Storage Methods in Coordinator** ⭐️ TOP PRIORITY
- **File**: `Core/OnboardingInterviewCoordinator.swift`
- **Lines**: 482-583 (public sync) vs 1096-1153 (private async)
- **LOC Reduction**: ~90 lines
- **Effort**: Low (1-2 hours)
- **Priority**: High

**Problem**: Near-identical implementations exist for `storeApplicantProfile()`, `storeSkeletonTimeline()`, `storeArtifactRecord()`, and `storeKnowledgeCard()`. The pattern repeats twice - public synchronous wrappers and private async implementations.

**Solution**:
- Keep only async variants
- Make them public
- Remove all sync wrappers
- Update callers to use async/await

**Example**:
```swift
// DELETE lines 482-583 (public sync methods)
// KEEP lines 1096-1153 (private async methods)
// CHANGE visibility: private → public
```

---

### 2. **Eliminate Repetitive Task Wrapping in ToolPane** ⭐️
- **File**: `Views/OnboardingInterviewToolPane.swift`
- **Lines**: 36-46, 59-68, 100-104, 111-122, etc. (10+ instances)
- **LOC Reduction**: ~60 lines
- **Effort**: Low (30 minutes)
- **Priority**: High

**Problem**: Every interactive card callback wraps result handling in identical `Task { await service.resumeToolContinuation(from: result) }` pattern.

**Solution**: Create helper method in ToolPane:
```swift
private func handleToolResult(_ action: @escaping () async -> ToolResult) {
    Task {
        let result = await action()
        await service.resumeToolContinuation(from: result)
    }
}

// Then replace all instances:
onSubmit: { selection in
    handleToolResult { coordinator.resolveChoice(selectionIds: selection) }
}
```

---

### 3. **Remove Passthrough Properties in Coordinator**
- **File**: `Core/OnboardingInterviewCoordinator.swift`
- **Lines**: 278-314
- **LOC Reduction**: ~30 lines
- **Effort**: Low (20 minutes)
- **Priority**: Medium

**Problem**: 37 lines of computed properties that just forward to `toolRouter` or `wizardTracker`.

**Solution**:
- Expose `toolRouter` and `wizardTracker` as public properties
- Let callers access them directly
- Remove all passthrough computed properties

```swift
// DELETE all of lines 278-314
// CHANGE:
private let toolRouter → public let toolRouter
private let wizardTracker → public let wizardTracker
```

---

### 4. **Consolidate Sanitization Logic in Orchestrator**
- **File**: `Core/InterviewOrchestrator.swift`
- **Lines**: 781-819
- **LOC Reduction**: ~25 lines
- **Effort**: Low (30 minutes)
- **Priority**: Medium

**Problem**: Three nearly identical case blocks in `sanitizeToolOutput()` that all call `removeHiddenEmailOptions()` and `attachValidationMetaIfNeeded()`.

**Solution**: Extract common pattern:
```swift
private func sanitizeValidationPayload(_ payload: JSON, dataType: String) -> JSON {
    var sanitized = removeHiddenEmailOptions(from: payload, dataType: dataType)
    return attachValidationMetaIfNeeded(payload: sanitized, dataType: dataType)
}

// Then use in each case:
case "submit_for_validation":
    return sanitizeValidationPayload(payload, dataType: dataType)
```

---

### 5. **Simplify allowedToolsMap with Composition**
- **File**: `Core/InterviewOrchestrator.swift`
- **Lines**: 47-82
- **LOC Reduction**: ~20 lines
- **Effort**: Low (20 minutes)
- **Priority**: Medium

**Problem**: 36 lines of hardcoded tool lists per phase. Tools repeated across phases (e.g., "get_user_option" appears 4 times).

**Solution**: Use set composition:
```swift
private static let baseTools: Set<String> = [
    "get_user_option", "persist_data", "set_objective_status", "next_phase"
]
private static let phase1Additions: Set<String> = [
    "get_macos_contact_card", "get_applicant_profile", "extract_document",
    "submit_for_validation"
]

private static func allowedTools(for phase: InterviewPhase) -> Set<String> {
    switch phase {
    case .phase1CoreFacts: return baseTools.union(phase1Additions)
    case .phase2DeepDive: return baseTools.union(phase2Additions)
    // ...
    }
}
```

---

### 6. **Extract Guard+Log Pattern in Handlers**
- **File**: `Handlers/ProfileInteractionHandler.swift` (and others)
- **Lines**: 64-68, 86-88, 213, 238, 259 (repeated across 5 handlers)
- **LOC Reduction**: ~20 lines per handler (~100 total across 5 handlers)
- **Effort**: Low (1 hour)
- **Priority**: High

**Problem**: Every resolver method has identical guard-log-return pattern for missing continuation IDs.

**Solution**: Create shared extension in Handlers directory:
```swift
// New file: Handlers/HandlerUtilities.swift
extension Optional where Wrapped == UUID {
    func guardContinuation(
        operation: String,
        category: Logger.Category = .ai
    ) -> UUID? {
        guard let id = self else {
            Logger.warning("⚠️ No pending \(operation) to resolve", category: category)
            return nil
        }
        return id
    }
}

// Usage:
guard let continuationId = applicantProfileContinuationId.guardContinuation(
    operation: "profile request"
) else { return nil }
```

---

### 7. **Consolidate Checkpoint Save Logic**
- **File**: `Core/OnboardingInterviewCoordinator.swift`
- **Lines**: 459-472 vs 1155-1162
- **LOC Reduction**: ~10 lines
- **Effort**: Low (15 minutes)
- **Priority**: Medium

**Problem**: `saveCheckpoint()` and `persistCheckpoint()` do essentially the same thing.

**Solution**: Keep one method, update all callers:
```swift
// Keep persistCheckpoint() (used by InterviewOrchestrator)
// Delete saveCheckpoint()
// Update 3 call sites that use saveCheckpoint() → persistCheckpoint()
```

---

## 💎 Medium Effort, High Value

### 8. **Convert Manual JSON to Codable in KnowledgeCardDraft**
- **File**: `Models/KnowledgeCardDraft.swift`
- **Lines**: 20-32, 61-83, 111-129, 159-183
- **LOC Reduction**: ~80 lines
- **Effort**: Medium (2-3 hours)
- **Priority**: High

**Problem**: Four separate manual JSON conversion implementations. Verbose, error-prone property-by-property mapping.

**Solution**: Replace with `Codable` conformance:
```swift
struct KnowledgeCardDraft: Codable {
    var title: String
    var achievements: [Achievement]
    var metadata: [String: String]

    // Delete all init(json:) and toJSON() methods
    // Use JSONEncoder/JSONDecoder instead of SwiftyJSON
}

// Replace usage:
let draft = try JSONDecoder().decode(KnowledgeCardDraft.self, from: data)
let json = try JSONEncoder().encode(draft)
```

**Benefit**: Also eliminates SwiftyJSON dependency for these models.

---

### 9. **Simplify Wizard Step Logic with Config Pattern**
- **File**: `Views/OnboardingInterviewView.swift`
- **Lines**: 293-326, 328-349, 351-368
- **LOC Reduction**: ~50 lines
- **Effort**: Medium (1-2 hours)
- **Priority**: High

**Problem**: Three separate switch statements over `wizardStep` for button titles, disabled state, and navigation.

**Solution**: Create WizardStepConfig:
```swift
struct WizardStepConfig {
    let continueTitle: String
    let backTitle: String?
    let canContinue: (OnboardingInterviewViewModel, OnboardingInterviewService) -> Bool
    let onContinue: () -> Void
}

extension OnboardingWizardStep {
    func config(viewModel: OnboardingInterviewViewModel, service: OnboardingInterviewService) -> WizardStepConfig {
        switch self {
        case .introduction:
            return WizardStepConfig(
                continueTitle: "Begin Interview",
                backTitle: nil,
                canContinue: { _, _ in true },
                onContinue: { /* logic */ }
            )
        // ...
        }
    }
}
```

---

### 10. **Consolidate onChange Handlers with Combine**
- **File**: `Views/OnboardingInterviewView.swift`
- **Lines**: 130-157
- **LOC Reduction**: ~40 lines
- **Effort**: Medium (1-2 hours)
- **Priority**: High

**Problem**: 6 separate onChange handlers managing state synchronization between AppStorage, service, and viewModel.

**Solution**: Create unified state coordinator:
```swift
class InterviewStateCoordinator: ObservableObject {
    @AppStorage("defaultModelId") var modelId: String = ""
    @AppStorage("defaultWebSearchAllowed") var webSearchAllowed: Bool = false
    // ... other @AppStorage properties

    private var cancellables = Set<AnyCancellable>()

    func sync(with service: OnboardingInterviewService, viewModel: OnboardingInterviewViewModel) {
        // Single publisher combining all changes
        Publishers.CombineLatest4($modelId, $webSearchAllowed, ...)
            .sink { [weak self] ... in
                self?.updateServiceDefaults(service, viewModel)
            }
            .store(in: &cancellables)
    }
}

// Replace 6 onChange handlers with:
.onAppear { stateCoordinator.sync(with: service, viewModel: viewModel) }
```

---

## 📊 Summary

| # | Change | File | LOC | Effort | Priority |
|---|--------|------|-----|--------|----------|
| 1 | Remove duplicate storage | Coordinator | -90 | Low | High |
| 2 | Task wrapping helper | ToolPane | -60 | Low | High |
| 3 | Remove passthroughs | Coordinator | -30 | Low | Med |
| 4 | Consolidate sanitization | Orchestrator | -25 | Low | Med |
| 5 | Tool map composition | Orchestrator | -20 | Low | Med |
| 6 | Guard+log pattern | Handlers (5 files) | -100 | Low | High |
| 7 | Merge checkpoint saves | Coordinator | -10 | Low | Med |
| 8 | Convert to Codable | KnowledgeCardDraft | -80 | Med | High |
| 9 | WizardStepConfig | InterviewView | -50 | Med | High |
| 10 | Combine state sync | InterviewView | -40 | Med | High |

**Total Potential Reduction**: ~505 LOC
**Quick Wins (1-7)**: ~355 LOC in 5-7 hours
**Medium Effort (8-10)**: ~170 LOC in 5-7 hours

**Cumulative Impact**: Phase 1 (449 LOC) + Phase 2 (505 LOC) = **954 LOC reduction (12% of module)**

---

## 🎯 Recommended Implementation Order

**Week 1 - Quick Wins (Items 1-7)**
1. Day 1: #1 (duplicate storage), #3 (passthroughs)
2. Day 2: #2 (task wrapping), #6 (guard+log)
3. Day 3: #4 (sanitization), #5 (tool map), #7 (checkpoint)

**Week 2 - Medium Effort (Items 8-10)**
1. Day 1-2: #8 (Codable conversion)
2. Day 3: #9 (WizardStepConfig)
3. Day 4: #10 (Combine state sync)

---

## ✅ Validation Checklist

After implementing each change:
- [ ] Code compiles without warnings
- [ ] Existing tests pass (if any)
- [ ] Manual testing of affected workflows
- [ ] Git commit with clear description
- [ ] Update this document with completion notes
