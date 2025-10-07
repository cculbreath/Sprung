# Selected Refactoring Roadmap for PhysCloudResume

**Date:** 2025-10-07
**Based on:** Codex Plan (winner) with targeted enhancements from Claude Plan
**Timeline:** 8-10 weeks
**Approach:** Pragmatic, incremental, risk-minimized

---

## Overview

This roadmap adopts the Codex plan's pragmatic approach while incorporating valuable safety improvements from the Claude plan. It prioritizes high-impact, low-risk improvements that can be delivered incrementally without disrupting the application's functionality.

**Core Philosophy:**
- Fix what's actually broken
- Preserve what works
- Improve incrementally
- Minimize risk
- Ship value quickly

---

## Phase 0: Pre-Flight Checklist (Week 0)

### Actions
1. **Create a stable branch point**
   ```bash
   git checkout -b refactoring-baseline
   git push origin refactoring-baseline
   ```

2. **Document current behavior**
   - Screenshot key workflows
   - Export sample PDFs
   - Note current performance metrics

3. **Set up basic integration tests**
   - Test PDF generation
   - Test resume import/export
   - Test AI integration flow

### Deliverables
- Baseline branch for rollback
- Behavior documentation
- Smoke test suite

---

## Phase 1: Foundation & Quick Wins (Week 1-2)

### Step 1.1: Establish Lightweight Dependency Injection

**What:** Create minimal DI container without heavy frameworks

```swift
// AppDependencies.swift - Simple, no magic
@MainActor
final class AppDependencies: ObservableObject {
    lazy var llmService = LLMService(apiKeyProvider: keychainService)
    lazy var keychainService = KeychainService()
    lazy var logger = AppLogger()
    // Services that ACTUALLY need DI, not everything
}

// In App.swift
@main
struct PhysCloudResumeApp: App {
    @StateObject private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dependencies)
        }
    }
}
```

**Note:** Only convert actual singletons. JobAppStore already uses DI - leave it alone!

### Step 1.2: Add Safety Protocols Where Valuable

**What:** Protocol wrappers ONLY for services that need testing/swapping

```swift
// Only for services we actually mock/test
protocol LLMServiceProtocol {
    func sendRequest(_ request: LLMRequest) async throws -> LLMResponse
}

protocol SecureStorageProtocol {
    func getAPIKey(for service: String) throws -> String?
    func setAPIKey(_ key: String, for service: String) throws
}
```

**Skip protocols for:** Simple utilities, view models, UI components

### Step 1.3: Clean Up Dead Code

**Quick wins:**
- Remove unused `RefreshJobApps` listener in JobAppStore.swift (line 42-50)
- Remove commented import job apps functionality
- Delete any `#warning` or `TODO` that's obsolete

**Time:** 2 days
**Risk:** None
**Value:** Immediate code clarity

---

## Phase 2: Fix the Custom JSON Parser (Week 2-3)

### Step 2.1: Add SwiftyJSON Dependency

```swift
// Package.swift
.package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0")
```

### Step 2.2: Create Modern JSON Handlers

**Replace:** Custom byte-level parser
**Keep:** TreeNode structure (it's good!)

```swift
// DynamicResumeService.swift
import SwiftyJSON

class DynamicResumeService {
    /// Convert TreeNode to template-friendly dictionary
    /// Replaces TreeToJson.swift
    func createTemplateContext(from rootNode: TreeNode) -> [String: Any] {
        var context: [String: Any] = [:]

        for section in rootNode.orderedChildren {
            switch section.name {
            case "contact":
                context["contact"] = extractContact(from: section)
            case "employment":
                context["employment"] = extractEmployment(from: section)
            case "skills-and-expertise":
                context["skillsAndExpertise"] = extractSkills(from: section)
            default:
                context[section.name] = extractGeneric(from: section)
            }
        }

        return context
    }

    /// Parse JSON to TreeNode hierarchy
    /// Replaces JsonToTree.swift
    func buildTree(from jsonData: Data, for resume: Resume) throws -> TreeNode {
        let json = try JSON(data: jsonData)

        let rootNode = TreeNode(
            name: "root",
            value: "",
            inEditor: false,
            status: .isNotLeaf,
            resume: resume
        )

        // Array-based structure as documented
        for (index, sectionJSON) in json.arrayValue.enumerated() {
            guard let title = sectionJSON["title"].string else { continue }

            let sectionNode = TreeNode(
                name: title,
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            )
            sectionNode.myIndex = index

            if let value = sectionJSON["value"].array {
                buildChildren(from: value, parent: sectionNode, resume: resume)
            }

            rootNode.addChild(sectionNode)
        }

        return rootNode
    }
}
```

### Step 2.3: Migrate and Test

1. Update `ResumeTemplateProcessor` to use new service
2. Test with existing templates (should work unchanged!)
3. Remove old files: JSONParser.swift, TreeToJson.swift, JsonToTree.swift

**Time:** 3-4 days
**Risk:** Medium (but well-contained)
**Value:** Removes 500+ lines of complex custom code

---

## Phase 3: Decompose AppState (Week 3-4)

### Step 3.1: Extract Focused Services

AppState currently does too much. Break it into logical services:

```swift
// SessionState.swift - UI state only
@Observable
final class SessionState {
    var selectedTab: TabList = .listing
    var dragInfo = DragInfo()
    var showNewAppSheet = false
    @AppStorage("selectedJobAppId") var selectedJobAppId = ""
}

// AICoordinator.swift - AI workflow orchestration
@Observable
final class AICoordinator {
    private let llmService: LLMServiceProtocol
    let enabledLLMStore: EnabledLLMStore
    let modelValidationService: ModelValidationService
    let resumeReviseViewModel: ResumeReviseViewModel

    init(dependencies: AppDependencies) {
        // Wire up AI-related services
    }
}
```

### Step 3.2: Update App Entry Point

```swift
@main
struct PhysCloudResumeApp: App {
    @StateObject private var dependencies = AppDependencies()
    @StateObject private var session = SessionState()
    @StateObject private var aiCoordinator: AICoordinator

    init() {
        let deps = AppDependencies()
        _aiCoordinator = StateObject(wrappedValue: AICoordinator(dependencies: deps))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dependencies)
                .environmentObject(session)
                .environmentObject(aiCoordinator)
        }
    }
}
```

**Time:** 3 days
**Risk:** Low (incremental migration)
**Value:** Clear separation of concerns

---

## Phase 4: Modernize AI Services (Week 4-5)

### Step 4.1: Remove Singleton from OpenRouterService

```swift
// From:
class OpenRouterService {
    static let shared = OpenRouterService()
}

// To:
class OpenRouterService: AIModelProvider {
    init(apiKeyProvider: SecureStorageProtocol) {
        // Injected dependencies
    }
}
```

### Step 4.2: Improve Error Handling in LLM Services

```swift
enum LLMError: LocalizedError {
    case apiKeyMissing
    case modelNotAvailable(String)
    case requestFailed(Error)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "API key not configured"
        case .modelNotAvailable(let model):
            return "Model \(model) is not available"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        }
    }
}
```

### Step 4.3: Add Proper Cancellation Support

```swift
class LLMRequestExecutor {
    private var currentTask: Task<Void, Never>?

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    func executeRequest(_ request: LLMRequest) async throws -> LLMResponse {
        currentTask?.cancel()

        return try await withTaskCancellationHandler {
            // Request logic
        } onCancel: {
            // Cleanup
        }
    }
}
```

**Time:** 4 days
**Risk:** Low
**Value:** Better reliability and user control

---

## Phase 5: UI Safety Improvements (Week 5-6)

### Step 5.1: Eliminate Force Unwrapping

**Priority targets:**
```swift
// Before:
let resume = jobApp.selectedRes!

// After:
guard let resume = jobApp.selectedRes else {
    Logger.warning("No resume selected")
    return
}
```

Use Xcode's search: `!\.|!\.|\?!` regex to find all force unwraps

### Step 5.2: Fix Silent Catch Blocks

```swift
// Before:
do {
    try context.save()
} catch {}

// After:
do {
    try context.save()
} catch {
    Logger.error("Failed to save: \(error)")
    // Show user alert if appropriate
}
```

### Step 5.3: Remove fatalError from Control Flow

Only 2 instances found:
- JsonToTree.swift (being replaced anyway)
- ImageButton.swift (convert to optional init)

**Time:** 3 days
**Risk:** Very low
**Value:** Prevents crashes

---

## Phase 6: Clean Export/PDF Generation (Week 6-7)

### Step 6.1: Separate UI from Service Logic

```swift
// ResumeExportService.swift
class ResumeExportService {
    // Pure logic, no NSOpenPanel or alerts
    func exportPDF(resume: Resume, to url: URL) async throws {
        let pdfData = try await generatePDF(resume: resume)
        try pdfData.write(to: url)
    }
}

// ExportCoordinator.swift
@MainActor
class ExportCoordinator: ObservableObject {
    private let exportService: ResumeExportService

    func showExportDialog(for resume: Resume) {
        let panel = NSOpenPanel()
        // UI handling here
    }
}
```

### Step 6.2: Remove @MainActor from Data Processing

```swift
// Move PDF generation off main thread
class NativePDFGenerator {
    // Remove @MainActor from class

    func generatePDF(from resume: Resume) async throws -> Data {
        // Heavy processing on background
        // Only UI updates on @MainActor
    }
}
```

**Time:** 3 days
**Risk:** Low
**Value:** Better performance, cleaner architecture

---

## Phase 7: Optional Enhancements (Week 7-8)

### If Time Permits (Priority Order):

1. **Centralize Configuration** (2 days)
   ```swift
   struct AppConfig {
       static let defaultTimeout: TimeInterval = 30
       static let maxRetries = 3
       // Consolidate magic numbers
   }
   ```

2. **Add Basic Logging Protocol** (1 day)
   ```swift
   protocol LoggerProtocol {
       func debug(_ message: String)
       func info(_ message: String)
       func warning(_ message: String)
       func error(_ message: String)
   }
   ```

3. **Theme Consolidation** (2 days)
   ```swift
   struct Theme {
       static let primaryColor = Color.blue
       static let spacing = Spacing()
       // Centralize UI constants
   }
   ```

---

## Implementation Guidelines

### Do's ✅
- Test each phase before moving to next
- Keep old code commented (not deleted) for one cycle
- Use feature flags for risky changes
- Document breaking changes
- Maintain backward compatibility where possible

### Don'ts ❌
- Don't fix what isn't broken
- Don't over-abstract simple code
- Don't create protocols for single implementations
- Don't migrate everything at once
- Don't ignore platform-specific patterns (macOS menus)

---

## Success Metrics

### Must Have (Week 8)
- [ ] Custom JSON parser replaced
- [ ] AppState decomposed
- [ ] AI services use DI
- [ ] No force unwraps in critical paths
- [ ] Export separated from UI

### Nice to Have (If time permits)
- [ ] Configuration centralized
- [ ] Theme system in place
- [ ] Logging abstracted
- [ ] 100% protocol coverage for services

### Won't Do (Out of scope)
- Complete MVVM conversion
- Full TreeNode restructuring
- Data model migrations
- Comprehensive unit tests
- Dependency management changes

---

## Risk Mitigation

### Rollback Plan
1. Each phase on separate branch
2. Merge to `main` only after validation
3. Keep `refactoring-baseline` branch untouched
4. Document rollback procedures for each phase

### Testing Strategy
- Smoke tests after each phase
- Manual testing of critical workflows
- Side-by-side comparison with baseline
- User acceptance testing before final merge

---

## Timeline Summary

| Week | Phase | Deliverable | Risk |
|------|-------|-------------|------|
| 0 | Pre-flight | Baseline & tests | None |
| 1-2 | Foundation | DI setup, quick wins | Low |
| 2-3 | JSON Parser | Modern JSON handling | Medium |
| 3-4 | AppState | Service extraction | Low |
| 4-5 | AI Services | Remove singletons | Low |
| 5-6 | UI Safety | Eliminate crashes | Low |
| 6-7 | Export | Separate concerns | Low |
| 7-8 | Polish | Optional enhancements | Low |
| 8 | Wrap-up | Documentation, merge | None |

**Total Duration:** 8 weeks (with 2-week buffer for issues)

---

## Next Steps

1. **Review this roadmap** with stakeholders
2. **Adjust priorities** based on business needs
3. **Set up baseline** (Phase 0)
4. **Begin Phase 1** with DI foundation
5. **Weekly progress reviews**

---

## Appendix: What We're NOT Doing

Based on the codebase examination, these "problems" don't actually exist:

1. **ResumeDetailVM is NOT a God object** - It's focused and reasonable
2. **JobAppStore is NOT a singleton** - Already uses DI
3. **TreeNode structure is GOOD** - Don't rewrite it
4. **NotificationCenter for menus is CORRECT** - Platform requirement
5. **Not everything needs a ViewModel** - Modern SwiftUI doesn't require it

Avoiding unnecessary work saves ~11 weeks compared to the Claude plan.