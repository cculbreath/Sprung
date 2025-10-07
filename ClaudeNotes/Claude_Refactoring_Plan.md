# PhysCloudResume: Architectural Refactoring Plan

**Generated:** 2025-10-07
**Based on:** Gemini Architectural Review

---

## Executive Summary

This refactoring plan addresses systemic architectural issues identified across 100+ files in the PhysCloudResume codebase. The review reveals pervasive anti-patterns that significantly impact maintainability, testability, and scalability. This plan provides a systematic, prioritized approach to modernize the architecture while maintaining functionality.

**Key Metrics:**
- Files analyzed: ~100+
- God Objects identified: 3 major (AppState, Resume, ResumeDetailVM)
- Singleton usages: ~15+ services
- Custom JSON implementation: 2 major components (needs replacement)
- NotificationCenter usages: ~20+ instances
- Force unwrapping instances: 50+

---

## I. Issue Summary

### 1. God Objects and Single Responsibility Violations

**Severity: CRITICAL**

Three major "God Objects" aggregate excessive responsibilities, making them unmaintainable and difficult to test:

#### A. **AppState.swift**
- **Problems:**
  - Manages UI state (`selectedTab`, `selectedJobApp`)
  - Holds application services (`openRouterService`, `llmService`)
  - Manages view-specific models (`resumeReviseViewModel`)
  - Handles data migration and persistence
- **Impact:** High coupling, hidden dependencies, difficult testing
- **Affected Files:** `AppState.swift`, all views using `@EnvironmentObject AppState`

#### B. **Resume.swift**
- **Problems:**
  - Data model (metadata, dates)
  - Generated output storage (PDF, text)
  - Hierarchical content container (`TreeNode`)
  - Template manager (custom HTML, font sizes)
  - PDF/text generator (direct `NativePDFGenerator` calls)
  - Debounce manager (content change handling)
- **Impact:** Violates SRP, tight coupling to presentation layer, business logic in model
- **Affected Files:** `Resume.swift`, all resume-related views and services

#### C. **ResumeDetailVM.swift**
- **Problems:**
  - Resume and TreeNode hierarchy management
  - Node editing state (`editingNodeID`, `tempName`, `tempValue`)
  - Expansion/collapse state (`expandedNodes`)
  - Direct interactions with multiple global singletons
  - Business logic for add/delete/update nodes
  - AI processing logic
  - PDF generation and refresh
  - External state synchronization
- **Impact:** Massive complexity, tight coupling, difficult testing
- **Affected Files:** `ResumeDetailVM.swift`, all tree-related views

### 2. Singleton Pattern Overuse

**Severity: HIGH**

Extensive use of the singleton pattern creates hidden dependencies and makes testing difficult:

**Singletons Identified:**
- `AppState.shared`
- `JobAppStore.shared`
- `CoverLetterStore.shared`
- `ResumeStore.shared`
- `OpenRouterService.shared`
- `LLMService.shared`
- `NativePDFGenerator.shared`
- `Logger` (static)
- `KeychainHelper` (static)
- Plus ~8 more utility singletons

**Problems:**
- Hidden dependencies throughout codebase
- Impossible to mock for testing
- Global mutable state
- Tight coupling between components
- Lifecycle management issues

**Impact:** Every view, service, and component that uses `.shared` is tightly coupled and difficult to test.

### 3. Mixed Concerns and Separation of Concerns Violations

**Severity: HIGH**

Business logic, UI logic, and data persistence are mixed throughout the codebase:

#### A. **Business Logic in Views**
- Views directly manipulate models
- Views contain filtering, sorting, and data transformation logic
- Views manage persistence (calling `context.save()`)
- Conditional rendering based on complex business rules

**Examples:**
- `SidebarView`: Contains filtering, selection, and persistence logic
- `NodeLeafView`: Direct `TreeNode` manipulation and SwiftData operations
- `FontNodeView`: Direct persistence triggering
- `ResumeInspectorView`: Business logic for resume management

#### B. **UI State Mixed with Data Management**
- `JobAppStore`: Mixes CRUD operations with UI state (`selectedApp`, `form`)
- `ResumeStore`: Similar pattern
- Data stores hold selection state and form objects

#### C. **Presentation Logic in Models**
- `Resume`: Contains PDF generation, text generation
- `TreeNode`: Contains JSON conversion, traversal logic, AI-specific filtering

### 4. Custom JSON Parser (Architecture is Good, Implementation Needs Update)

**Severity: MEDIUM** *(Revised from HIGH after investigation)*

**UPDATE:** After investigation, the **architecture is sound**. The custom parser is the only issue.

**What's Working Well:**
- ✅ **TreeNode abstraction** - Flexible hierarchical structure supports arbitrary resume formats
- ✅ **Template system** - Already editable without recompilation (Documents folder override)
- ✅ **Template format** - Handlebars with flat dictionary is appropriate and user-friendly
- ✅ **Data flow** - TreeNode → Dictionary → Template → PDF makes sense

**What Needs Replacement:**

#### A. **JSONParser.swift**
- **Problems:**
  - Custom byte-level JSON parser
  - Duplicates Swift standard library functionality (`JSONSerialization`)
  - Complex, error-prone, difficult to maintain
  - Uses `OrderedDictionary<String, Any>` (untyped)
  - Performance likely worse than standard tools

#### B. **JsonToTree.swift / TreeToJson.swift**
- **Problems:**
  - Manual JSON construction with string concatenation
  - Custom escaping logic (error-prone)
  - Tight coupling to custom JSONParser
  - Could use standard `JSONSerialization` or `SwiftyJSON` instead

**Recommended Solution:**
- Replace custom parser with `JSONSerialization` or `SwiftyJSON`
- Keep TreeNode structure (it's flexible and appropriate)
- Keep template system (already works great)
- Maintain same output format for templates (no template changes needed)

**Impact:**
- Custom parser creates maintenance burden
- Standard tools are more reliable
- Current architecture is otherwise good

### 5. NotificationCenter Usage (Mostly Appropriate)

**Severity: LOW** *(Revised from MEDIUM after investigation)*

**UPDATE:** After detailed investigation, NotificationCenter usage is **primarily legitimate** for macOS menu/toolbar coordination. This is the standard architectural pattern for allowing menu commands and toolbar buttons to trigger identical functionality.

**Legitimate Use Cases (Keep As-Is):**
- Menu commands triggering toolbar button actions via `MenuNotificationHandler`
- Toolbar buttons receiving menu command triggers
- Well-organized notification namespace in `MenuCommands.swift`
- Clear separation between menu commands and toolbar bridge notifications

**Minor Issues to Clean Up:**
- `RefreshJobApps` notification listener in `JobAppStore` (unused, no publishers - dead code)
- Sheet presentation via notifications (`.showResumeRevisionSheet`, `.hideResumeRevisionSheet`) could potentially use modern SwiftUI bindings instead

**Recommended Action:**
- **Keep** the menu/toolbar notification architecture - it's appropriate
- **Remove** the unused `RefreshJobApps` listener
- **Optionally modernize** sheet presentation patterns (low priority)

### 6. Unsafe Optional Handling

**Severity: MEDIUM**

Extensive use of force unwrapping (`!`) creates crash risks:

**Patterns:**
- `jobAppStore.selectedApp!`
- `resume.model!`
- `node.parent!`
- `jobApp!.modelContext!`

**Locations:** 50+ instances across views and view models

**Impact:** Runtime crashes if assumptions about non-nil values are violated

### 7. Lack of Dependency Injection

**Severity: HIGH**

Few protocol abstractions exist, and dependencies are accessed globally:

**Problems:**
- Views access stores via `@EnvironmentObject` without protocols
- Services access other services via `.shared`
- No constructor injection
- No protocol-based abstraction layer
- Impossible to swap implementations
- Testing requires real implementations

**Examples:**
- `LLMService` depends on `AppState` to access other services
- `NativePDFGenerator` accessed directly
- `JobAppStore`, `ResumeStore` accessed directly throughout

### 8. Tight Coupling to SwiftUI and External Libraries

**Severity: MEDIUM**

**A. SwiftUI-Specific Logic in Business Layer**
- `@MainActor` on entire classes (should be on specific methods)
- Business logic classes marked as `ObservableObject`
- SwiftUI property wrappers in service layer

**B. External Library Coupling**
- `LLMService` tightly coupled to `SwiftOpenAI` types
- `JSONParser` uses `OrderedCollections` unnecessarily
- No abstraction layer for external dependencies

### 9. Insufficient Error Handling

**Severity: MEDIUM**

**Patterns:**
- Empty `catch {}` blocks (silent failures)
- `fatalError` for control flow
- Errors logged but not propagated
- `try?` with no fallback handling
- Functions return empty strings on error

**Examples:**
- `fatalError` in `JsonToTree.buildTree()`
- `fatalError` in `ImageButton` initializer
- Silent `catch {}` in reorder operations
- `TreeToJson` returns `""` on error

### 10. Hardcoded Configuration and Magic Numbers

**Severity: LOW**

**Problems:**
- Styling hardcoded in views (fonts, colors, padding)
- Magic numbers for layout (`rowHeight: CGFloat = 50.0`)
- Hardcoded paths and file locations
- No centralized theming
- String literals throughout (not localized)

---

## II. Refactoring Roadmap

This roadmap is ordered by dependency and impact, with each phase building on the previous.

### Phase 1: Foundation - Protocols and Abstractions

**Goal:** Establish protocol-based architecture to enable dependency injection and testing.

**Duration:** 2-3 weeks

#### Step 1.1: Define Core Service Protocols

Create protocol abstractions for all major services:

```swift
// Data Layer Protocols
protocol JobAppRepository {
    func fetchJobApps() async throws -> [JobApp]
    func save(_ jobApp: JobApp) async throws
    func delete(_ jobApp: JobApp) async throws
}

protocol ResumeRepository {
    func fetchResumes(for jobApp: JobApp) async throws -> [Resume]
    func save(_ resume: Resume) async throws
    func delete(_ resume: Resume) async throws
}

// AI Service Protocols
protocol AIModelProvider {
    func fetchAvailableModels() async throws -> [AIModel]
    func getModel(byId id: String) -> AIModel?
}

protocol LLMServiceProtocol {
    func sendRequest(_ request: LLMRequest) async throws -> LLMResponse
    func sendStreamingRequest(_ request: LLMRequest) async throws -> AsyncStream<LLMChunk>
}

// Utility Service Protocols
protocol SecureStorageService {
    func saveAPIKey(_ key: String, for identifier: String) throws
    func getAPIKey(for identifier: String) throws -> String?
    func deleteAPIKey(for identifier: String) throws
}

protocol LoggingService {
    func verbose(_ message: String)
    func debug(_ message: String)
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}

// PDF/Export Protocols
protocol ResumeGeneratorProtocol {
    func generatePDF(from resume: Resume) async throws -> Data
    func generateText(from resume: Resume) async throws -> String
}
```

**Files to Create:**
- `Protocols/DataLayer/JobAppRepository.swift`
- `Protocols/DataLayer/ResumeRepository.swift`
- `Protocols/Services/AIModelProvider.swift`
- `Protocols/Services/LLMServiceProtocol.swift`
- `Protocols/Utilities/SecureStorageService.swift`
- `Protocols/Utilities/LoggingService.swift`
- `Protocols/Export/ResumeGeneratorProtocol.swift`

**Rationale:** Protocols enable testing, provide clear contracts, and allow for implementation swapping.

#### Step 1.2: Implement Protocol Conformance

Make existing services conform to protocols:

```swift
// Example: KeychainHelper conformance
class KeychainService: SecureStorageService {
    func saveAPIKey(_ key: String, for identifier: String) throws {
        // Implementation using Security framework
    }
    // ... other methods
}

// Example: LLMService conformance
class LLMService: LLMServiceProtocol {
    private let modelProvider: AIModelProvider
    private let executor: LLMRequestExecutor

    init(modelProvider: AIModelProvider, executor: LLMRequestExecutor) {
        self.modelProvider = modelProvider
        self.executor = executor
    }
    // ... implementation
}
```

**Benefits:**
- Existing code continues to work
- Enables gradual migration
- Establishes patterns for new code

### Phase 2: Eliminate Singletons

**Goal:** Replace singleton pattern with dependency injection.

**Duration:** 3-4 weeks

#### Step 2.1: Create Application Coordinator

Centralize service lifecycle management:

```swift
@MainActor
class AppCoordinator: ObservableObject {
    // Core Services
    let jobAppRepository: JobAppRepository
    let resumeRepository: ResumeRepository
    let llmService: LLMServiceProtocol
    let modelProvider: AIModelProvider
    let secureStorage: SecureStorageService
    let logger: LoggingService
    let pdfGenerator: ResumeGeneratorProtocol

    // Application State
    @Published var selectedJobApp: JobApp?
    @Published var selectedTab: TabList = .jobApps

    init() {
        // Instantiate all services with proper dependencies
        self.secureStorage = KeychainService()
        self.logger = AppLogger()
        self.modelProvider = OpenRouterService(
            apiKey: try? secureStorage.getAPIKey(for: "openrouter"),
            logger: logger
        )
        self.llmService = LLMService(
            modelProvider: modelProvider,
            executor: LLMRequestExecutor()
        )
        self.jobAppRepository = SwiftDataJobAppRepository()
        self.resumeRepository = SwiftDataResumeRepository()
        self.pdfGenerator = NativePDFGenerator(logger: logger)
    }

    func setup() async {
        // Any async initialization
    }
}
```

**File:** `App/AppCoordinator.swift`

#### Step 2.2: Refactor App Entry Point

```swift
@main
struct PhysCloudResumeApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .modelContainer(for: [JobApp.self, Resume.self])
        }
    }
}
```

**Files to Modify:**
- `App/PhysCloudResumeApp.swift`

#### Step 2.3: Progressive Singleton Elimination

Eliminate singletons one at a time, starting with utilities:

**Order:**
1. `KeychainHelper` → `KeychainService` (protocol-based)
2. `Logger` → `LoggingService` (protocol-based)
3. `OpenRouterService` → Inject via `AppCoordinator`
4. `LLMService` → Inject via `AppCoordinator`
5. `JobAppStore` → `JobAppService` (managed by coordinator)
6. `ResumeStore` → `ResumeService` (managed by coordinator)
7. `AppState` → Dissolve into `AppCoordinator` and specific services

**Pattern for Each:**
```swift
// Before
class MyView: View {
    @Environment(\.modelContext) var modelContext

    var body: some View {
        Button("Action") {
            JobAppStore.shared.doSomething()
        }
    }
}

// After
class MyView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        Button("Action") {
            coordinator.jobAppService.doSomething()
        }
    }
}
```

**Benefits:**
- Testable services
- Clear dependencies
- Controlled lifecycle
- No hidden global state

### Phase 3: Decompose God Objects

**Goal:** Break massive classes into focused, single-responsibility components.

**Duration:** 4-5 weeks

#### Step 3.1: Decompose AppState

**Strategy:** Distribute responsibilities to appropriate layers.

**New Structure:**
```
AppState → REMOVE
    ├─> AppCoordinator (service management, DI container)
    ├─> SessionState (UI state: selectedTab, selectedJobApp)
    ├─> Services (AI, Job, Resume - managed by coordinator)
    └─> ViewModels (view-specific state, now injectable)
```

**Implementation:**
```swift
// SessionState: UI-level state only
@Observable
class SessionState {
    var selectedTab: TabList = .jobApps
    var selectedJobAppId: UUID?
    var selectedResumeId: UUID?
}

// Inject into views
@Environment(AppCoordinator.self) private var coordinator
@Environment(SessionState.self) private var session
```

**Files:**
- Create: `App/SessionState.swift`
- Modify: `App/AppCoordinator.swift`
- Delete: `App/AppState.swift` (after migration)

#### Step 3.2: Decompose Resume Model

**Strategy:** Separate data from behavior.

**New Structure:**
```swift
// Pure data model
@Model
class ResumeMetadata {
    var id: UUID
    var name: String
    var dateCreated: Date
    var jobApp: JobApp?
    var selectedContentId: UUID?
}

// Resume content (hierarchical structure)
@Model
class ResumeContent {
    var id: UUID
    var metadata: ResumeMetadata?
    var rootNode: TreeNode?
    var fontSizes: [FontSizeNode] = []
}

// Generated outputs
@Model
class ResumeOutput {
    var id: UUID
    var metadata: ResumeMetadata?
    var pdfData: Data?
    var textData: String?
    var lastGenerated: Date?
}

// Service: Generation logic
class ResumeGeneratorService: ResumeGeneratorProtocol {
    private let pdfGenerator: PDFGeneratorProtocol
    private let textGenerator: TextGeneratorProtocol

    func generatePDF(from content: ResumeContent) async throws -> Data {
        // Business logic here
    }
}

// Service: Persistence and debouncing
class ResumePersistenceService {
    private let repository: ResumeRepository
    private var debounceTask: Task<Void, Never>?

    func saveWithDebounce(_ resume: ResumeMetadata) {
        // Debouncing logic
    }
}
```

**Files:**
- Create: `Models/Resume/ResumeMetadata.swift`
- Create: `Models/Resume/ResumeContent.swift`
- Create: `Models/Resume/ResumeOutput.swift`
- Create: `Services/Resume/ResumeGeneratorService.swift`
- Create: `Services/Resume/ResumePersistenceService.swift`
- Modify: `ResModels/Resume.swift` → Migrate then delete

**Migration Strategy:**
1. Create new models alongside old
2. Create migration utilities
3. Update data access layer
4. Update all views one-by-one
5. Remove old `Resume` model

#### Step 3.3: Decompose ResumeDetailVM

**Strategy:** Extract into specialized ViewModels and services.

**New Structure:**
```swift
// Focused ViewModel: Only view state
@Observable
class ResumeDetailViewModel {
    private let treeManager: ResumeTreeManagerProtocol
    private let editingManager: TreeNodeEditingManager
    private let pdfService: ResumeGeneratorProtocol

    var resume: ResumeContent
    var isWide: Bool = false
    var includeFonts: Bool = true

    // Delegated to services
    func expandNode(_ node: TreeNode) {
        treeManager.expand(node)
    }

    func startEditing(_ node: TreeNode) {
        editingManager.beginEdit(node)
    }
}

// Service: Tree operations
class ResumeTreeManager: ResumeTreeManagerProtocol {
    private let repository: ResumeRepository
    private(set) var expandedNodes: Set<UUID> = []

    func expand(_ node: TreeNode) {
        expandedNodes.insert(node.id)
    }

    func addChild(to parent: TreeNode, name: String, value: String) throws {
        // Complex tree manipulation logic
        try repository.save()
    }
}

// Service: Node editing
class TreeNodeEditingManager {
    var currentlyEditing: TreeNode?
    var tempName: String = ""
    var tempValue: String = ""

    func beginEdit(_ node: TreeNode) {
        currentlyEditing = node
        tempName = node.name
        tempValue = node.value
    }

    func saveEdit() throws {
        guard let node = currentlyEditing else { return }
        node.name = tempName
        node.value = tempValue
        // Save to repository
    }
}
```

**Files:**
- Create: `ViewModels/ResumeTree/ResumeDetailViewModel.swift` (new, focused)
- Create: `Services/ResumeTree/ResumeTreeManager.swift`
- Create: `Services/ResumeTree/TreeNodeEditingManager.swift`
- Create: `Services/ResumeTree/TreeAIProcessor.swift` (for AI-specific logic)
- Refactor: `ResumeTree/Views/ResumeDetailVM.swift` → Migrate then delete

### Phase 4: Modernize JSON Handling (Keep TreeNode, Replace Custom Parser)

**Goal:** Replace custom JSON parser with standard Swift tools while maintaining template compatibility and TreeNode flexibility.

**Duration:** 2-3 weeks

**IMPORTANT CONTEXT:**

After investigation, the current architecture has **good fundamentals**:
- ✅ **TreeNode** is the right abstraction (flexible, hierarchical, works for arbitrary resume structures)
- ✅ **Templates are already editable** without recompilation (Documents folder override)
- ✅ **Template format** (Handlebars + flat dictionary) is appropriate and user-friendly
- ❌ **Custom parser** (JSONParser, TreeToJson, JsonToTree) should be replaced with standard tools

**The issue:** Custom byte-level JSON parser is unnecessary complexity. We can use `JSONSerialization` or `SwiftyJSON` while keeping everything else.

---

#### Step 4.1: Understand Current Data Flow

**Current flow (keep this architecture, just replace parser):**

1. **Storage:** TreeNode (SwiftData) ← hierarchical, flexible
2. **Template Rendering:** TreeNode → Flat Dictionary → Handlebars → HTML
3. **AI Operations:** TreeNode → JSON → LLM → JSON → TreeNode

**What to preserve:**
- TreeNode structure (already flexible for any resume format)
- Template-friendly output format (flat dictionary)
- Template editability (already works via Documents folder)

**What to replace:**
- Custom `JSONParser.swift` → Use `JSONSerialization`
- Custom `TreeToJson.swift` → Use standard dictionary builder
- Custom `JsonToTree.swift` → Use standard JSON parsing

---

#### Step 4.2: Replace TreeToJson with Template Data Builder

The current `TreeToJson` converts TreeNode → dictionary for templates. Replace with standard tools:

```swift
/// Replaces TreeToJson.swift
/// Converts TreeNode to template-friendly flat dictionary
class ResumeTemplateDataBuilder {

    /// Build template context from TreeNode
    /// Output format matches what Handlebars templates expect
    static func buildTemplateContext(from rootNode: TreeNode) -> [String: Any] {
        var context: [String: Any] = [:]

        // Process each top-level section
        for sectionNode in rootNode.orderedChildren {
            let sectionName = sectionNode.name

            switch sectionName {
            case "contact":
                context["contact"] = buildContactDict(from: sectionNode)

            case "employment":
                context["employment"] = buildEmploymentArray(from: sectionNode)

            case "skills-and-expertise":
                context["skillsAndExpertise"] = buildSkillsArray(from: sectionNode)

            case "section-labels":
                context["sectionLabels"] = buildLabelsDict(from: sectionNode)

            case "font-sizes":
                context["fontSizes"] = buildFontSizesDict(from: sectionNode)

            default:
                // Generic handler for unknown sections (future templates)
                context[sectionName.camelCased] = buildGenericSection(from: sectionNode)
            }
        }

        return context
    }

    // MARK: - Section Builders

    private static func buildContactDict(from node: TreeNode) -> [String: Any] {
        var contact: [String: Any] = [:]

        for child in node.orderedChildren {
            if child.hasChildren {
                // Nested object (e.g., location: { city, state })
                contact[child.name] = buildGenericDict(from: child)
            } else {
                contact[child.name] = child.value
            }
        }

        return contact
    }

    private static func buildEmploymentArray(from node: TreeNode) -> [[String: Any]] {
        return node.orderedChildren.map { employmentNode in
            var item: [String: Any] = [
                "employer": employmentNode.name
            ]

            for field in employmentNode.orderedChildren {
                if field.name == "highlights" {
                    // Array of strings
                    item["highlights"] = field.orderedChildren.map { $0.value }
                } else {
                    item[field.name] = field.value
                }
            }

            return item
        }
    }

    private static func buildSkillsArray(from node: TreeNode) -> [[String: Any]] {
        return node.orderedChildren.map { skillNode in
            [
                "title": skillNode.name,
                "description": skillNode.value
            ]
        }
    }

    private static func buildLabelsDict(from node: TreeNode) -> [String: String] {
        var labels: [String: String] = [:]
        for child in node.orderedChildren {
            labels[child.name] = child.value
        }
        return labels
    }

    private static func buildFontSizesDict(from node: TreeNode) -> [String: String] {
        var fontSizes: [String: String] = [:]
        for child in node.orderedChildren {
            fontSizes[child.name] = child.value
        }
        return fontSizes
    }

    // MARK: - Generic Handlers (for unknown template structures)

    private static func buildGenericSection(from node: TreeNode) -> Any {
        if !node.hasChildren {
            return node.value
        }

        let children = node.orderedChildren

        // Heuristic: if children have uniform structure, treat as array
        if shouldBeArray(children) {
            return children.map { buildGenericDict(from: $0) }
        } else {
            return buildGenericDict(from: node)
        }
    }

    private static func buildGenericDict(from node: TreeNode) -> [String: Any] {
        var dict: [String: Any] = [:]

        for child in node.orderedChildren {
            dict[child.name] = child.hasChildren
                ? buildGenericSection(from: child)
                : child.value
        }

        return dict
    }

    private static func shouldBeArray(_ nodes: [TreeNode]) -> Bool {
        // If multiple nodes with same name, or all have children → array
        let uniqueNames = Set(nodes.map { $0.name })
        return uniqueNames.count < nodes.count || nodes.allSatisfy { $0.hasChildren }
    }
}
```

**Update ResumeTemplateProcessor:**

```swift
static func createTemplateContext(from resume: Resume) throws -> [String: Any] {
    guard let rootNode = resume.rootNode else {
        throw TemplateError.noRootNode
    }

    // ✅ Use standard dictionary builder instead of custom TreeToJson
    return ResumeTemplateDataBuilder.buildTemplateContext(from: rootNode)
}
```

---

#### Step 4.3: Replace JsonToTree with Standard Parser

For loading resume data from JSON files:

```swift
/// Replaces JsonToTree.swift
/// Converts JSON data to TreeNode hierarchy
class ResumeTreeBuilder {

    func buildTree(from jsonData: Data, resume: Resume) throws -> TreeNode {
        // Use standard JSONSerialization
        guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            throw JSONError.invalidFormat
        }

        // Create root node
        let rootNode = TreeNode(
            name: "root",
            value: "",
            children: [],
            parent: nil,
            inEditor: false,
            status: .isNotLeaf,
            resume: resume
        )

        // Build tree from array-based JSON structure
        for (index, sectionDict) in jsonObject.enumerated() {
            guard let title = sectionDict["title"] as? String else { continue }

            let sectionNode = TreeNode(
                name: title,
                value: "",
                children: [],
                parent: rootNode,
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            )
            sectionNode.myIndex = index

            if let value = sectionDict["value"] {
                buildChildren(from: value, parent: sectionNode, resume: resume)
            }

            rootNode.addChild(sectionNode)
        }

        return rootNode
    }

    private func buildChildren(from value: Any, parent: TreeNode, resume: Resume) {
        if let stringValue = value as? String {
            // Leaf node
            parent.value = stringValue
            parent.status = .disabled

        } else if let arrayValue = value as? [[String: Any]] {
            // Array of objects
            for (index, itemDict) in arrayValue.enumerated() {
                guard let title = itemDict["title"] as? String else { continue }

                let childNode = TreeNode(
                    name: title,
                    value: itemDict["value"] as? String ?? "",
                    children: [],
                    parent: parent,
                    inEditor: true,
                    status: .disabled,
                    resume: resume
                )
                childNode.myIndex = index

                // Recursively handle nested structures
                if let nestedValue = itemDict["value"] {
                    buildChildren(from: nestedValue, parent: childNode, resume: resume)
                }

                parent.addChild(childNode)
            }

        } else if let dictValue = value as? [String: Any] {
            // Object (key-value pairs)
            for (key, val) in dictValue.sorted(by: { $0.key < $1.key }) {
                let childNode = TreeNode(
                    name: key,
                    value: val as? String ?? "",
                    children: [],
                    parent: parent,
                    inEditor: true,
                    status: .disabled,
                    resume: resume
                )

                parent.addChild(childNode)
            }
        }
    }
}
```

---

#### Step 4.4: Replace JSONParser with Standard Tools

For any direct JSON manipulation (AI responses, etc.), use `JSONSerialization` or add SwiftyJSON:

```swift
// For dynamic JSON operations (AI responses, unknown structures)
import SwiftyJSON  // Add via SPM if not already present

class DynamicJSONHandler {

    func parseAIResponse(_ data: Data) throws -> JSON {
        return try JSON(data: data)
    }

    func extractNodeUpdates(from json: JSON) -> [(id: String, value: String)] {
        var updates: [(String, String)] = []

        // SwiftyJSON makes dynamic access safe
        if let nodesArray = json["nodes"].array {
            for nodeJSON in nodesArray {
                if let id = nodeJSON["id"].string,
                   let value = nodeJSON["value"].string {
                    updates.append((id, value))
                }
            }
        }

        return updates
    }
}
```

---

#### Step 4.5: Migration Strategy

**Phase A: Create New Implementations**
1. Create `ResumeTemplateDataBuilder.swift` (replaces TreeToJson)
2. Create `ResumeTreeBuilder.swift` (replaces JsonToTree)
3. Add SwiftyJSON dependency (if not present) for dynamic operations
4. Keep old code temporarily

**Phase B: Update Call Sites**
1. Update `ResumeTemplateProcessor.swift` to use new builder
2. Update resume import/export to use new tree builder
3. Update AI integration to use SwiftyJSON or JSONSerialization
4. Test thoroughly with existing templates

**Phase C: Remove Old Code**
1. Delete `Shared/Utilities/JSONParser.swift`
2. Delete `ResumeTree/Utilities/JsonToTree.swift`
3. Delete `ResumeTree/Utilities/TreeToJson.swift`
4. Remove `OrderedCollections` dependency if no longer used elsewhere

---

#### Step 4.6: Template Documentation

Document for template authors how data is structured:

```markdown
# Template Data Structure Guide

Templates receive a flat dictionary with the following structure:

## Contact
```json
{
  "contact": {
    "name": "string",
    "email": "string",
    "phone": "string",
    "website": "string",
    "location": {
      "city": "string",
      "state": "string"
    }
  }
}
```

## Employment (Array)
```json
{
  "employment": [
    {
      "employer": "string",
      "position": "string",
      "location": "string",
      "start": "string",
      "end": "string",
      "highlights": ["string"]
    }
  ]
}
```

## Skills (Array)
```json
{
  "skillsAndExpertise": [
    {
      "title": "string",
      "description": "string"
    }
  ]
}
```

## Section Labels (for i18n)
```json
{
  "sectionLabels": {
    "employment": "Work Experience",
    "education": "Education",
    ...
  }
}
```

Templates are stored in:
- **Bundled:** `PhysCloudResume.app/Contents/Resources/Templates/`
- **User-editable:** `~/Documents/PhysCloudResume/Templates/`

User templates override bundled templates (no recompilation needed).
```

---

**Benefits of This Approach:**
- ✅ Removes custom parser complexity
- ✅ Uses standard Swift tools (JSONSerialization, SwiftyJSON)
- ✅ Maintains TreeNode flexibility for arbitrary structures
- ✅ Preserves template editability (already working!)
- ✅ Keeps template-friendly flat dictionary format
- ✅ No changes needed to existing templates
- ✅ Clearer, more maintainable code

### Phase 5: Clean Up NotificationCenter Usage (Optional/Low Priority)

**Goal:** Remove dead code and optionally modernize sheet presentation patterns.

**Duration:** 0.5-1 week (can be done in parallel with other phases)

**IMPORTANT:** The menu/toolbar notification architecture is appropriate and should be **kept as-is**. This phase focuses only on minor cleanup.

#### Step 5.1: Remove Dead Code

**Action Items:**
1. Remove the unused `RefreshJobApps` notification listener from `JobAppStore.swift`
   - Lines 42-50: Delete the notification observer
   - Verify no code posts this notification (already confirmed: none found)

```swift
// REMOVE THIS (dead code):
NotificationCenter.default.publisher(for: NSNotification.Name("RefreshJobApps"))
    .sink { [weak self] _ in
        Task { @MainActor in
            self?.refreshJobApps()
        }
    }
    .store(in: &cancellables)
```

#### Step 5.2: Optional: Modernize Sheet Presentation (Low Priority)

The `.showResumeRevisionSheet` and `.hideResumeRevisionSheet` notifications could potentially be replaced with direct `@Published` or `@Observable` properties that the view binds to. However, this is:

**Low priority** because:
- Current pattern works reliably
- Sheet presentation from a non-parent ViewModel is legitimately challenging
- Refactoring may not provide significant benefit
- Other phases have higher ROI

**If pursuing this refactoring:**

```swift
// Current pattern (works fine):
// ViewModel posts notification → AppSheets listens → Shows sheet

// Alternative pattern (more modern, but requires ViewModel ownership changes):
@Observable
class ResumeReviseViewModel {
    // Direct binding approach
    var isShowingReviewSheet: Bool = false
}

// In view:
.sheet(isPresented: $viewModel.isShowingReviewSheet) {
    RevisionReviewView(...)
}
```

**Recommendation:** Skip this modernization unless pursuing broader ViewModel refactoring.

#### Step 5.3: Document Menu/Toolbar Pattern

Add documentation to `MenuNotificationHandler.swift` explaining why NotificationCenter is appropriate here:

```swift
/// Handles menu command notifications and delegates to appropriate UI actions.
///
/// ## Architecture Note: Why NotificationCenter?
///
/// This class uses NotificationCenter for menu/toolbar coordination, which is the
/// standard macOS pattern for this use case. Unlike general view-to-view communication,
/// menu commands cannot directly access SwiftUI view state or bindings. NotificationCenter
/// provides the necessary decoupling between AppKit menu items and SwiftUI views.
///
/// This pattern is intentional and should NOT be replaced with bindings or callbacks.
```

**Benefits of This Minimal Approach:**
- Removes actual dead code
- Preserves working architecture
- Focuses effort on higher-value refactoring
- Avoids unnecessary churn

### Phase 6: Separate Concerns in Views (Modern SwiftUI Architecture)

**Goal:** Extract business logic into services and create focused, composable views that work directly with `@Observable` models.

**Duration:** 4-5 weeks

**IMPORTANT ARCHITECTURAL NOTE:**

Traditional MVVM is **less relevant** for modern SwiftUI (iOS 17+). Apple's current guidance emphasizes:
- Views work **directly with `@Observable` models**
- Business logic lives in **services**, not ViewModels
- Only create "presentation state" objects for **complex view-specific logic**
- Prefer **small, composed views** over view/ViewModel pairs

#### Step 6.1: Modern SwiftUI Architecture Pattern

**Pattern 1: Views Working Directly with Models (Preferred)**

```swift
// Business logic in service
@Observable
class JobAppService {
    private let repository: JobAppRepository

    var jobApps: [JobApp] = []
    var isLoading: Bool = false
    var errorMessage: String?

    func loadJobApps() async {
        isLoading = true
        defer { isLoading = false }

        do {
            jobApps = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// View works directly with service
struct SidebarView: View {
    @Environment(JobAppService.self) private var jobAppService
    @State private var searchText = ""

    var filteredJobApps: [JobApp] {
        guard !searchText.isEmpty else { return jobAppService.jobApps }
        return jobAppService.jobApps.filter {
            $0.company.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack {
            SearchField(text: $searchText)

            if jobAppService.isLoading {
                ProgressView()
            } else {
                List(filteredJobApps) { jobApp in
                    JobAppRow(jobApp: jobApp)
                }
            }
        }
        .task {
            await jobAppService.loadJobApps()
        }
    }
}
```

**When to Use This:** Most cases! Views that display and interact with data.

---

**Pattern 2: Presentation State for Complex View Logic (When Needed)**

```swift
// Only when view has complex state management
@Observable
class SearchPresentationState {
    var searchText: String = ""
    var selectedFilters: Set<String> = []
    var sortOrder: SortOrder = .newest
    var isShowingFilters: Bool = false

    // View-specific computed properties
    var hasActiveFilters: Bool {
        !selectedFilters.isEmpty || sortOrder != .newest
    }

    func clearFilters() {
        selectedFilters.removeAll()
        sortOrder = .newest
    }
}

struct ComplexSearchView: View {
    @Environment(JobAppService.self) private var service
    @State private var presentationState = SearchPresentationState()

    var filteredAndSortedApps: [JobApp] {
        // Complex filtering/sorting logic using presentation state
    }

    var body: some View {
        // Complex UI with multiple filtering options
    }
}
```

**When to Use This:**
- Complex UI state that doesn't belong in the domain model
- Multi-step workflows or wizards
- Complex filtering/sorting that's view-specific
- State machines for UI flow

---

**Pattern 3: Coordinator for Multi-Service Workflows**

```swift
// When view needs to coordinate multiple services
@Observable
class ResumeGenerationCoordinator {
    private let resumeService: ResumeService
    private let llmService: LLMService
    private let pdfService: PDFService

    enum State {
        case idle, generating, reviewing, complete
    }

    var state: State = .idle
    var currentResume: Resume?

    func startGeneration(for jobApp: JobApp) async throws {
        state = .generating
        // Coordinate workflow across multiple services
        let content = try await llmService.generateContent(...)
        currentResume = try await resumeService.create(content)
        state = .reviewing
    }
}
```

**When to Use This:**
- Workflows spanning multiple services
- Complex multi-step processes
- Coordinating async operations with dependencies

---

#### Step 6.2: Decision Framework

**Use direct model binding when:**
- ✅ View displays data from a domain model
- ✅ Simple filtering/sorting
- ✅ CRUD operations on models
- ✅ Reading from a service

**Create presentation state when:**
- ⚠️ Complex view-specific state (multi-step forms, wizards)
- ⚠️ UI state that doesn't belong in domain model
- ⚠️ Complex filtering/sorting/grouping logic
- ⚠️ State machines for view flow

**Create coordinator when:**
- ⚠️ Orchestrating multiple services
- ⚠️ Complex workflows with dependencies
- ⚠️ Multi-phase operations

---

#### Step 6.3: Refactoring This Codebase

**For PhysCloudResume, apply these patterns:**

**Simple Views (Direct Model Binding):**
- `JobAppRow` → Works directly with `JobApp` model
- `ResumeRow` → Works directly with `Resume` model
- `FontSizePanel` → Works directly with `FontSizeNode` models
- Most list views → Environment service + model binding

**Moderate Complexity (Presentation State):**
- `SidebarView` → Search/filter state (but keep simple!)
- `NodeHeaderView` → Expansion state
- Form views → Form-specific validation state

**High Complexity (Coordinator):**
- `ResumeReviseViewModel` → Already coordinates LLM + Resume services (keep as coordinator)
- Multi-step AI workflows → Need coordination

**Example Refactoring for SidebarView:**

```swift
// ❌ Old way: Traditional ViewModel
class SidebarViewModel {
    var jobApps: [JobApp] = []  // Duplicates service data
    func loadJobApps() { }      // Duplicates service method
}

// ✅ New way: Direct service access
struct SidebarView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var searchText = ""

    var jobAppService: JobAppService { coordinator.jobAppService }

    var filteredApps: [JobApp] {
        guard !searchText.isEmpty else { return jobAppService.jobApps }
        return jobAppService.jobApps.filter { /* filter */ }
    }

    var body: some View {
        List(filteredApps) { app in
            JobAppRow(jobApp: app)
        }
        .searchable(text: $searchText)
        .task { await jobAppService.loadJobApps() }
    }
}
```

---

#### Step 6.4: View Decomposition Strategy

Break large views into smaller, focused components:

```swift
// Instead of one massive view
struct JobAppDetailView: View {
    // 500 lines of code
}

// Break into focused components
struct JobAppDetailView: View {
    var jobApp: JobApp

    var body: some View {
        ScrollView {
            JobAppHeader(jobApp: jobApp)
            JobAppTimeline(jobApp: jobApp)
            JobAppResumes(jobApp: jobApp)
            JobAppCoverLetters(jobApp: jobApp)
            JobAppNotes(jobApp: jobApp)
        }
    }
}

// Each component is small and focused
struct JobAppHeader: View {
    var jobApp: JobApp
    var body: some View { /* 20-30 lines */ }
}
```

**Benefits:**
- Each component has one clear purpose
- Easy to understand and maintain
- Natural testability boundaries
- Reusable across views

---

#### Step 6.5: Views to Refactor (Revised Priority)

**Tier 1 - High Impact (Direct Model Binding):**
- [ ] `SidebarView.swift` → Use `JobAppService` directly, simple search state
- [ ] `ResumeInspectorView.swift` → Use services directly
- [ ] `JobAppRow.swift` → Direct `JobApp` binding
- [ ] All simple list/row views → Direct model binding

**Tier 2 - Moderate (May Need Presentation State):**
- [ ] `ContentView.swift` → Decompose into smaller views, minimal state
- [ ] `NodeHeaderView.swift` → Simple expansion state
- [ ] Form views → Form validation state if needed

**Tier 3 - Complex (Coordinators):**
- [ ] `ResumeReviseViewModel` → Keep as coordinator (already appropriate)
- [ ] Multi-step AI workflows → Coordinator pattern
- [ ] Batch operations → Coordinator if needed

**Tier 4 - Decompose:**
- [ ] Break large views (>200 lines) into focused components
- [ ] Extract reusable components

#### Step 6.2: Extract Reusable UI Components

Create focused, configurable components:

```swift
// Generic, reusable components
struct ConfigurableCheckbox: View {
    @Binding var isOn: Bool
    var label: String
    var onSymbol: String = "checkmark.square.fill"
    var offSymbol: String = "square"
    var onColor: Color = .accentColor

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
        }
        .toggleStyle(CheckboxToggleStyle(/* config */))
    }
}

struct ThemedButton: View {
    var title: String
    var action: () -> Void
    var style: ButtonStyleConfig = .primary

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(ThemedButtonStyle(config: style))
    }
}
```

### Phase 7: Improve Error Handling

**Goal:** Robust, consistent error handling throughout the codebase.

**Duration:** 2 weeks

#### Step 7.1: Define Error Types

```swift
// Domain-specific errors
enum JobAppError: LocalizedError {
    case notFound(id: UUID)
    case saveFailed(underlying: Error)
    case deleteFailed(underlying: Error)
    case invalidData(reason: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Job application with ID \(id) not found"
        case .saveFailed(let error):
            return "Failed to save job application: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete job application: \(error.localizedDescription)"
        case .invalidData(let reason):
            return "Invalid job application data: \(reason)"
        }
    }
}

enum ResumeError: LocalizedError {
    case generationFailed(reason: String)
    case templateNotFound(name: String)
    case invalidContent(reason: String)
}

enum LLMError: LocalizedError {
    case apiKeyMissing
    case requestFailed(statusCode: Int, message: String)
    case decodingFailed(underlying: Error)
    case timeout
    case cancelled
}
```

**Files:**
- Create: `Models/Errors/JobAppError.swift`
- Create: `Models/Errors/ResumeError.swift`
- Create: `Models/Errors/LLMError.swift`

#### Step 7.2: Replace Anti-Patterns

**Pattern 1: Replace `fatalError` with `throw`**

```swift
// Before
func buildTree() {
    guard !hasBuilt else {
        fatalError("Extra run attempted")
    }
    // ...
}

// After
func buildTree() throws {
    guard !hasBuilt else {
        throw TreeBuildError.alreadyBuilt
    }
    // ...
}
```

**Pattern 2: Replace Empty Catch Blocks**

```swift
// Before
do {
    try context.save()
} catch {}

// After
do {
    try context.save()
} catch {
    logger.error("Failed to save context: \(error)")
    throw DataPersistenceError.saveFailed(underlying: error)
}
```

**Pattern 3: Replace `try?` with Proper Handling**

```swift
// Before
let value = try? someOperation()

// After
do {
    let value = try someOperation()
    // Use value
} catch {
    logger.warning("Operation failed: \(error)")
    // Provide fallback or show error to user
}
```

#### Step 7.3: Implement Centralized Error Presentation

```swift
// Service for presenting errors to users
@MainActor
class ErrorPresenter: ObservableObject {
    @Published var currentError: LocalizedError?
    @Published var showingError = false

    func present(_ error: Error) {
        if let localizedError = error as? LocalizedError {
            currentError = localizedError
        } else {
            currentError = GenericError.unexpected(error)
        }
        showingError = true
    }
}

// Usage in views
.alert("Error", isPresented: $errorPresenter.showingError) {
    Button("OK") {
        errorPresenter.currentError = nil
    }
} message: {
    if let error = errorPresenter.currentError {
        Text(error.errorDescription ?? "An unknown error occurred")
    }
}
```

### Phase 8: Eliminate Force Unwrapping

**Goal:** Safe optional handling throughout the codebase.

**Duration:** 1-2 weeks

#### Step 8.1: Automated Detection

Use SwiftLint or similar to identify all `!` usages:

```bash
grep -rn "!" --include="*.swift" . | grep -v "!=" | grep -v "import"
```

#### Step 8.2: Replacement Patterns

**Pattern 1: Use guard let**

```swift
// Before
let resume = jobApp.selectedRes!

// After
guard let resume = jobApp.selectedRes else {
    logger.error("No resume selected for job app")
    return
}
```

**Pattern 2: Use if let**

```swift
// Before
display(jobAppStore.selectedApp!.company)

// After
if let app = jobAppStore.selectedApp {
    display(app.company)
}
```

**Pattern 3: Use Optional Chaining**

```swift
// Before
let date = jobApp!.selectedRes!.dateCreated

// After
let date = jobApp?.selectedRes?.dateCreated
```

**Pattern 4: Use Nil Coalescing**

```swift
// Before
let name = resume.name ?? "Untitled"

// After (no change needed, this is correct)
let name = resume.name ?? "Untitled"
```

### Phase 9: Refine Concurrency and MainActor Usage

**Goal:** Proper use of Swift concurrency primitives.

**Duration:** 1-2 weeks

#### Step 9.1: Audit @MainActor Usage

**Principle:** Only UI updates and UI-bound properties need `@MainActor`

```swift
// Before: Entire service on MainActor
@MainActor
class ResumeGeneratorService {
    func generatePDF(from resume: Resume) async throws -> Data {
        // Heavy computation on main thread (BAD)
    }
}

// After: Only UI-interacting methods on MainActor
class ResumeGeneratorService {
    func generatePDF(from resume: Resume) async throws -> Data {
        // Runs on background thread
        let pdfData = try await heavyComputation()

        // Update UI if needed
        await MainActor.run {
            // UI updates here
        }

        return pdfData
    }

    @MainActor
    func updateProgress(_ value: Double) {
        // This needs MainActor
    }
}
```

#### Step 9.2: Replace Manual Threading with async/await

```swift
// Before
DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
    isActive = false
}

// After
Task {
    try await Task.sleep(nanoseconds: 750_000_000)
    await MainActor.run {
        isActive = false
    }
}
```

### Phase 10: Centralize Configuration and Styling

**Goal:** Externalize hardcoded values for maintainability and theming.

**Duration:** 1 week

#### Step 10.1: Create Theme System

```swift
// Theme configuration
struct AppTheme {
    struct Colors {
        static let primary = Color.blue
        static let secondary = Color.secondary
        static let accent = Color.accentColor
        static let background = Color(NSColor.controlBackgroundColor)
        static let success = Color.green
        static let danger = Color.red
    }

    struct Fonts {
        static let title = Font.title
        static let headline = Font.headline
        static let body = Font.body
        static let caption = Font.caption
    }

    struct Spacing {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 24
    }

    struct Layout {
        static let rowHeight: CGFloat = 50
        static let cornerRadius: CGFloat = 6
        static let borderWidth: CGFloat = 1
    }
}
```

**File:** `Shared/Theme/AppTheme.swift`

#### Step 10.2: Create ViewModifiers

```swift
// Reusable styling
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.Colors.background)
            .cornerRadius(AppTheme.Layout.cornerRadius)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
```

#### Step 10.3: Localization

```swift
// Localizable.strings
"job_app.add_button" = "Add Job Application";
"job_app.delete_confirm" = "Are you sure you want to delete this job application?";
"resume.untitled" = "Untitled Resume";

// Usage
Text(String(localized: "job_app.add_button"))

// Or with enum
enum L10n {
    enum JobApp {
        static let addButton = String(localized: "job_app.add_button")
        static let deleteConfirm = String(localized: "job_app.delete_confirm")
    }
}

Text(L10n.JobApp.addButton)
```

---

## III. Best Practice Alignment

### 1. SOLID Principles

#### Single Responsibility Principle (SRP)
**Applied Through:**
- Phase 3: Decompose God Objects
- Phase 6: Separate Concerns in Views
- Each class/service has one clear purpose

**Example:**
```swift
// Before: Resume does everything
class Resume {
    func generatePDF() { ... }
    func generateText() { ... }
    func debounceExport() { ... }
    var pdfData: Data?
    var textRes: String?
    var model: TreeNode?
}

// After: Focused responsibilities
class ResumeMetadata { /* Data only */ }
class ResumeGeneratorService { /* Generation only */ }
class ResumePersistenceService { /* Saving only */ }
```

#### Open/Closed Principle (OCP)
**Applied Through:**
- Phase 1: Define protocols
- Services depend on abstractions, not concretions
- New implementations without modifying existing code

**Example:**
```swift
// Protocol allows new implementations
protocol ResumeGeneratorProtocol {
    func generatePDF(from resume: Resume) async throws -> Data
}

// Can add new generators without changing consumers
class WKWebViewPDFGenerator: ResumeGeneratorProtocol { ... }
class CoreGraphicsPDFGenerator: ResumeGeneratorProtocol { ... }
```

#### Liskov Substitution Principle (LSP)
**Applied Through:**
- Protocol-based design
- Any conforming implementation can be substituted

**Example:**
```swift
// Any LLMServiceProtocol implementation works
class ViewModel {
    let llmService: LLMServiceProtocol // Can be real or mock

    func process() async {
        await llmService.sendRequest(...)
    }
}
```

#### Interface Segregation Principle (ISP)
**Applied Through:**
- Focused protocols
- Clients only depend on methods they use

**Example:**
```swift
// Instead of one massive service
protocol JobAppService {
    func fetchAll() async throws -> [JobApp]
    func save(_ jobApp: JobApp) async throws
    func delete(_ jobApp: JobApp) async throws
    func export(_ jobApp: JobApp) async throws -> Data
    func import(_ data: Data) async throws -> JobApp
}

// Split into focused protocols
protocol JobAppRepository {
    func fetchAll() async throws -> [JobApp]
    func save(_ jobApp: JobApp) async throws
    func delete(_ jobApp: JobApp) async throws
}

protocol JobAppImportExport {
    func export(_ jobApp: JobApp) async throws -> Data
    func import(_ data: Data) async throws -> JobApp
}
```

#### Dependency Inversion Principle (DIP)
**Applied Through:**
- Phase 1 & 2: Protocols and dependency injection
- High-level modules depend on abstractions

**Example:**
```swift
// High-level ViewModel depends on abstraction
class ResumeViewModel {
    private let generator: ResumeGeneratorProtocol // Abstraction

    init(generator: ResumeGeneratorProtocol) {
        self.generator = generator
    }
}
```

### 2. Modern Swift & SwiftUI Best Practices

#### Swift Concurrency
- Use `async/await` instead of completion handlers
- Use `Task` for structured concurrency
- Proper `@MainActor` usage (only for UI)
- `AsyncStream` for streaming data

```swift
// Good
func fetchData() async throws -> Data {
    try await networkService.fetch()
}

// Good: Only UI updates on MainActor
class ViewModel {
    @MainActor
    func updateUI() {
        // UI updates
    }

    func processData() async { // Background work
        // Heavy processing
    }
}
```

#### SwiftUI Patterns (Modern Architecture)

**Key Shift from Traditional MVVM:**

Traditional MVVM (view ↔ ViewModel ↔ model) is **less relevant** in modern SwiftUI. Apple's current guidance (WWDC 2023-2024, sample apps) emphasizes:

1. **Views work directly with `@Observable` models/services**
2. **Business logic in services, not ViewModels**
3. **Presentation state objects only for complex view-specific logic**
4. **Small, composed views over view/ViewModel pairs**

```swift
// ❌ Traditional MVVM (unnecessary layer)
@Observable
class ItemListViewModel {
    var items: [Item] = []  // Duplicates service
    func load() async { }    // Duplicates service
}

struct ItemListView: View {
    @State var viewModel = ItemListViewModel()
    var body: some View {
        List(viewModel.items) { ... }
    }
}

// ✅ Modern SwiftUI (direct service access)
@Observable
class ItemService {
    var items: [Item] = []
    func load() async throws { }
}

struct ItemListView: View {
    @Environment(ItemService.self) private var service

    var body: some View {
        List(service.items) { ... }
            .task { try? await service.load() }
    }
}
```

**When to create presentation objects:**
- Complex UI state machines (multi-step workflows)
- View-specific computed state that's expensive
- Coordinating multiple services in complex workflows

**Benefits of this approach:**
- Less boilerplate
- Clearer data flow
- Fewer layers to debug
- Natural alignment with SwiftUI's reactive model

**References:**
- WWDC 2023: "Discover Observation in SwiftUI"
- Apple Sample Apps (Food Truck, Backyard Birds)
- Point-Free: "Modern SwiftUI" series

#### SwiftData Integration
- Use `@Model` for entities
- Repository pattern for data access
- Proper context management
- Avoid force unwrapping `modelContext`

```swift
// Good
protocol Repository {
    associatedtype Entity
    func fetch() async throws -> [Entity]
    func save(_ entity: Entity) async throws
}

class SwiftDataJobAppRepository: Repository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetch() async throws -> [JobApp] {
        let descriptor = FetchDescriptor<JobApp>()
        return try modelContext.fetch(descriptor)
    }
}
```

### 3. Testability

#### Unit Testing
- Protocol-based design enables mocking
- ViewModels testable in isolation
- Services testable with fake dependencies

```swift
// Testable ViewModel
class SidebarViewModel {
    private let jobAppService: JobAppServiceProtocol

    init(jobAppService: JobAppServiceProtocol) {
        self.jobAppService = jobAppService
    }
}

// Test with mock
class MockJobAppService: JobAppServiceProtocol {
    var mockJobApps: [JobApp] = []

    func fetchAll() async throws -> [JobApp] {
        return mockJobApps
    }
}

// Test
func testLoadJobApps() async {
    let mock = MockJobAppService()
    mock.mockJobApps = [testJobApp1, testJobApp2]
    let vm = SidebarViewModel(jobAppService: mock)

    await vm.loadJobApps()

    XCTAssertEqual(vm.jobApps.count, 2)
}
```

### 4. Code Organization

#### Folder Structure
```
PhysCloudResume/
├── App/
│   ├── PhysCloudResumeApp.swift
│   ├── AppCoordinator.swift
│   └── SessionState.swift
├── Models/
│   ├── Domain/
│   │   ├── JobApp.swift
│   │   ├── Resume/
│   │   │   ├── ResumeMetadata.swift
│   │   │   ├── ResumeContent.swift
│   │   │   └── ResumeOutput.swift
│   │   └── TreeNode.swift
│   ├── JSON/
│   │   └── ResumeJSON.swift
│   └── Errors/
│       └── AppErrors.swift
├── Services/
│   ├── Protocols/
│   │   ├── JobAppRepository.swift
│   │   ├── LLMServiceProtocol.swift
│   │   └── ...
│   ├── Implementation/
│   │   ├── SwiftDataJobAppRepository.swift
│   │   ├── LLMService.swift
│   │   └── ...
│   └── Utilities/
│       ├── LoggingService.swift
│       └── KeychainService.swift
├── ViewModels/
│   ├── JobApp/
│   │   └── SidebarViewModel.swift
│   ├── Resume/
│   │   ├── ResumeDetailViewModel.swift
│   │   └── ResumeInspectorViewModel.swift
│   └── ...
├── Views/
│   ├── JobApp/
│   │   ├── SidebarView.swift
│   │   └── JobAppDetailView.swift
│   ├── Resume/
│   │   └── ...
│   └── Components/
│       ├── Buttons/
│       ├── TextFields/
│       └── ...
└── Shared/
    ├── Theme/
    │   └── AppTheme.swift
    └── Extensions/
        └── ...
```

### 5. Documentation

Each major component should include:

```swift
/// Manages the lifecycle and coordination of application services.
///
/// `AppCoordinator` serves as the dependency injection container for the entire
/// application. It instantiates and configures all services with their proper
/// dependencies, ensuring a clear dependency graph.
///
/// ## Usage
/// ```swift
/// @StateObject private var coordinator = AppCoordinator()
/// ```
///
/// ## Dependencies
/// - All services are created and managed here
/// - Services are injected into ViewModels as needed
///
/// ## Thread Safety
/// This class is `@MainActor` bound as it manages UI-related state.
@MainActor
class AppCoordinator: ObservableObject {
    // ...
}
```

---

## IV. Codebase References

This section maps issues to specific files that require attention during each phase.

### Phase 1: Foundation - Protocols

**Files to Create:**
- [ ] `Protocols/DataLayer/JobAppRepository.swift`
- [ ] `Protocols/DataLayer/ResumeRepository.swift`
- [ ] `Protocols/Services/AIModelProvider.swift`
- [ ] `Protocols/Services/LLMServiceProtocol.swift`
- [ ] `Protocols/Services/ConversationManagerProtocol.swift`
- [ ] `Protocols/Utilities/SecureStorageService.swift`
- [ ] `Protocols/Utilities/LoggingService.swift`
- [ ] `Protocols/Export/ResumeGeneratorProtocol.swift`
- [ ] `Protocols/Export/PDFGeneratorProtocol.swift`
- [ ] `Protocols/Export/TextGeneratorProtocol.swift`

**Files to Review:**
- [x] All service files to understand current interfaces

### Phase 2: Eliminate Singletons

**Files to Create:**
- [ ] `App/AppCoordinator.swift`
- [ ] `Services/Implementation/KeychainService.swift` (protocol-based)
- [ ] `Services/Implementation/AppLogger.swift` (protocol-based)

**Files to Modify:**
- [ ] `App/PhysCloudResumeApp.swift` - Update to use AppCoordinator
- [ ] `App/AppState.swift` - Begin migration (will be deleted in Phase 3)
- [ ] `AI/Models/Services/OpenRouterService.swift` - Remove singleton, add DI
- [ ] `AI/Models/Services/LLMService.swift` - Remove singleton, add DI
- [ ] `DataManagers/JobAppStore.swift` - Remove singleton, add DI
- [ ] `DataManagers/ResumeStore.swift` - Remove singleton (will be refactored in Phase 3)

**Files to Review for `.shared` usage:**
- [ ] All view files
- [ ] All ViewModel files
- [ ] Search codebase: `grep -r "\.shared" --include="*.swift"`

### Phase 3: Decompose God Objects

#### AppState Decomposition

**Files to Create:**
- [ ] `App/SessionState.swift`
- [ ] `Services/JobApplication/JobAppService.swift`
- [ ] `Services/Resume/ResumeService.swift`

**Files to Modify:**
- [ ] `App/AppCoordinator.swift` - Add service management
- [ ] `App/ContentView.swift` - Update to use new services

**Files to Delete:**
- [ ] `App/AppState.swift` (after complete migration)

#### Resume Decomposition

**Files to Create:**
- [ ] `Models/Resume/ResumeMetadata.swift`
- [ ] `Models/Resume/ResumeContent.swift`
- [ ] `Models/Resume/ResumeOutput.swift`
- [ ] `Services/Resume/ResumeGeneratorService.swift`
- [ ] `Services/Resume/ResumePersistenceService.swift`
- [ ] `Services/Resume/ResumeTreeManager.swift`

**Files to Modify:**
- [ ] `ResModels/Resume.swift` - Migrate then deprecate
- [ ] All views using `Resume` model
- [ ] All services interacting with `Resume`

**Files to Review:**
- [ ] `Shared/Utilities/NativePDFGenerator.swift` - Refactor to service
- [ ] `Shared/Utilities/ResumeExportService.swift` - Update to use new models
- [ ] `ResRefs/ResRefView.swift` - Update to use new services

#### ResumeDetailVM Decomposition

**Files to Create:**
- [ ] `ViewModels/ResumeTree/ResumeDetailViewModel.swift` (new, focused)
- [ ] `Services/ResumeTree/ResumeTreeManager.swift`
- [ ] `Services/ResumeTree/TreeNodeEditingManager.swift`
- [ ] `Services/ResumeTree/TreeAIProcessor.swift`
- [ ] `Services/ResumeTree/TreeNodeExpansionManager.swift`

**Files to Modify:**
- [ ] `ResumeTree/Views/ResumeDetailVM.swift` - Migrate then deprecate
- [ ] `ResumeTree/Views/ResumeDetailView.swift` - Use new ViewModel
- [ ] `ResumeTree/Views/NodeLeafView.swift` - Update dependencies
- [ ] `ResumeTree/Views/NodeHeaderView.swift` - Update dependencies
- [ ] `ResumeTree/Views/NodeWithChildrenView.swift` - Update dependencies

### Phase 4: Modernize JSON Handling

**Files to Create:**
- [ ] `Services/Resume/ResumeTemplateDataBuilder.swift` (replaces TreeToJson)
- [ ] `Services/Resume/ResumeTreeBuilder.swift` (replaces JsonToTree)
- [ ] `Services/JSON/DynamicJSONHandler.swift` (for AI operations with SwiftyJSON)
- [ ] `Documentation/TemplateDataStructure.md` (for template authors)

**Files to Modify:**
- [ ] `Shared/Utilities/ResumeTemplateProcessor.swift` - Update `createTemplateContext()` to use new builder
- [ ] Any AI integration files using JSONParser - Switch to SwiftyJSON or JSONSerialization
- [ ] Resume import/export code - Use new ResumeTreeBuilder

**Files to Delete (after migration):**
- [ ] `Shared/Utilities/JSONParser.swift` (custom byte-level parser)
- [ ] `ResumeTree/Utilities/JsonToTree.swift` (replaced by ResumeTreeBuilder)
- [ ] `ResumeTree/Utilities/TreeToJson.swift` (replaced by ResumeTemplateDataBuilder)

**Files to Keep (Already Good):**
- [x] `ResumeTree/Models/TreeNodeModel.swift` - TreeNode structure is sound
- [x] `Resources/Templates/**/*.html` - Templates don't need changes
- [x] `Shared/Utilities/ResumeTemplateProcessor.swift` - Template loading logic is good (Documents override works!)

**Dependencies:**
- [ ] Add SwiftyJSON via SPM if not already present (for dynamic JSON operations)
- [ ] Remove `OrderedCollections` if no longer used elsewhere

**Files to Review:**
- [ ] `ResumeTree/Utilities/JsonMap.swift` - May need updating
- [ ] `ResumeTree/Utilities/SectionType.swift` - May need updating
- [ ] All files using `TreeToJson` - Search: `grep -r "TreeToJson" --include="*.swift"`
- [ ] All files using `JsonToTree` - Search: `grep -r "JsonToTree" --include="*.swift"`
- [ ] All files using `JSONParser` - Search: `grep -r "JSONParser" --include="*.swift"`

### Phase 5: NotificationCenter Cleanup (Optional)

**Files to Modify:**
- [ ] `DataManagers/JobAppStore.swift` - Remove unused `RefreshJobApps` listener (lines 42-50)
- [ ] `App/Views/MenuNotificationHandler.swift` - Add architecture documentation explaining why NotificationCenter is appropriate for menu/toolbar coordination

**Files to Keep As-Is (Appropriate Architecture):**
- [x] `App/Views/MenuCommands.swift` - Well-organized notification namespace
- [x] `App/Views/MenuNotificationHandler.swift` - Proper menu/toolbar bridge
- [x] All toolbar button files - Correct pattern for receiving menu triggers
- [x] Menu command posting code - Standard macOS pattern

**Optional (Low Priority):**
- [ ] `Resumes/AI/Services/ResumeReviseViewModel.swift` - Consider modernizing sheet presentation (can defer)
- [ ] `App/Models/AppSheets.swift` - Related to sheet presentation modernization

### Phase 6: Separate Concerns in Views

**Priority Order (High to Low):**

**Tier 1 (Critical):**
- [ ] `App/ContentView.swift` → Create `ContentViewModel.swift`
- [ ] `Sidebar/Views/SidebarView.swift` → Create `SidebarViewModel.swift`
- [ ] `ResumeTree/Views/ResumeDetailView.swift` → Update to use new ViewModel

**Tier 2 (Important):**
- [ ] `ResModels/ResumeInspectorView.swift` → Create `ResumeInspectorViewModel.swift`
- [ ] `Resumes/ResumeView.swift` → Create `ResumeViewModel.swift`
- [ ] `ResumeTree/Views/NodeLeafView.swift` → Create `NodeLeafViewModel.swift`
- [ ] `ResumeTree/Views/NodeHeaderView.swift` → Extract logic to ViewModel

**Tier 3 (Standard):**
- [ ] `ResumeTree/Views/FontNodeView.swift` → Create focused ViewModel
- [ ] `ResumeTree/Views/FontSizePanelView.swift` → Create ViewModel
- [ ] `ResumeTree/Views/NodeChildrenListView.swift` → Extract logic
- [ ] `ResumeTree/Views/EditingControls.swift` → Create ViewModel

**Tier 4 (Lower Priority):**
- [ ] All remaining complex views
- [ ] Component views with business logic

**UI Components to Refactor:**
- [ ] `Shared/UIComponents/CheckboxToggleStyle.swift` - Remove redundant tap gesture
- [ ] `Shared/UIComponents/CustomTextEditor.swift` - Make height configurable
- [ ] `Shared/UIComponents/FormCellView.swift` - Decouple from stores
- [ ] `Shared/UIComponents/ImageButton.swift` - Remove fatalError, use Button
- [ ] `Shared/UIComponents/RoundedTagView.swift` - Make styling configurable
- [ ] `Shared/UIComponents/SparkleButton.swift` - Decouple from TreeNode
- [ ] `Shared/UIComponents/TextRowViews.swift` - Decouple from LeafStatus

### Phase 7: Improve Error Handling

**Files to Create:**
- [ ] `Models/Errors/JobAppError.swift`
- [ ] `Models/Errors/ResumeError.swift`
- [ ] `Models/Errors/LLMError.swift`
- [ ] `Models/Errors/TreeError.swift`
- [ ] `Services/ErrorPresenter.swift`

**Files to Audit:**
- [ ] Search: `grep -r "fatalError" --include="*.swift"` (14 files)
- [ ] Search: `grep -r "} catch {}" --include="*.swift"` (23 files)
- [ ] Search: `grep -r "try\?" --include="*.swift"` (45+ usages)

**Critical Files to Fix:**
- [ ] `ResumeTree/Utilities/JsonToTree.swift` - Replace fatalError
- [ ] `Shared/UIComponents/ImageButton.swift` - Replace fatalError
- [ ] `ResumeTree/Views/DraggableNodeWrapper.swift` - Handle errors
- [ ] `ResumeTree/Views/ReorderableLeafRow.swift` - Handle errors
- [ ] All files with empty catch blocks

### Phase 8: Eliminate Force Unwrapping

**Files to Audit:**
- [ ] Run: `grep -rn "!" --include="*.swift" . | grep -v "!=" | grep -v "import"`
- [ ] Estimated: 50+ instances

**High-Risk Files (Most Force Unwraps):**
- [ ] `ResumeTree/Views/ResumeDetailVM.swift`
- [ ] `ResumeTree/Views/NodeLeafView.swift`
- [ ] `ResModels/ResumeInspectorView.swift`
- [ ] `Resumes/ResumeView.swift`
- [ ] `ResRefs/ResRefView.swift`
- [ ] `Sidebar/Views/SidebarView.swift`

### Phase 9: Refine Concurrency

**Files to Audit:**
- [ ] Search: `grep -r "@MainActor" --include="*.swift"` (12 classes)
- [ ] Search: `grep -r "DispatchQueue.main" --include="*.swift"` (8 usages)

**Files to Review:**
- [ ] `AI/Models/Services/LLMService.swift` - Review MainActor usage
- [ ] `AI/Models/Services/LLMRequestExecutor.swift` - Improve cancellation
- [ ] `Shared/Utilities/NativePDFGenerator.swift` - Remove MainActor from processing
- [ ] `ResModels/Resume.swift` - Review MainActor on entire class
- [ ] `ResumeTree/Views/ResumeDetailVM.swift` - Review MainActor usage
- [ ] All files with `DispatchQueue.main.asyncAfter`

### Phase 10: Centralize Configuration

**Files to Create:**
- [ ] `Shared/Theme/AppTheme.swift`
- [ ] `Shared/Theme/ViewModifiers/CardStyle.swift`
- [ ] `Shared/Theme/ViewModifiers/ButtonStyles.swift`
- [ ] `Shared/Localization/Localizable.strings`
- [ ] `Shared/Localization/L10n.swift` (localization helpers)

**Files to Audit for Hardcoded Values:**
- [ ] All view files - Search for hardcoded fonts, colors, padding
- [ ] Search: `grep -r "\.padding(" --include="*.swift"`
- [ ] Search: `grep -r "\.font(" --include="*.swift"`
- [ ] Search: `grep -r "Color\." --include="*.swift"`

---

## V. Migration Strategy & Risk Management

### Migration Approach: Strangler Fig Pattern

**Strategy:** Build new architecture alongside old, gradually migrate, remove old code when safe.

**Key Principles:**
1. **No Big Bang**: Never rewrite entire system at once
2. **Feature Parity**: New code must match old functionality
3. **Dual Running**: Old and new code coexist during migration
4. **Incremental Cutover**: Switch users one component at a time
5. **Easy Rollback**: Can revert if issues arise

### Risk Mitigation

#### 1. Testing Strategy

**Before Starting Any Phase:**
- [ ] Create comprehensive integration tests for critical flows
- [ ] Document current behavior (screenshots, videos)
- [ ] Create test data sets

**During Each Phase:**
- [ ] Write unit tests for new components before migration
- [ ] Test old and new code in parallel
- [ ] Maintain feature parity

**Test Coverage Goals:**
- Services: 80%+ unit test coverage
- ViewModels: 70%+ unit test coverage
- Views: Integration tests for critical flows

#### 2. Rollback Plan

**For Each Phase:**
1. Create feature branch
2. Complete phase work
3. Test thoroughly
4. Merge to `staging` branch (not `main`)
5. Test in staging environment
6. Only merge to `main` when confident
7. Keep old code commented (not deleted) for 1 release cycle

#### 3. Code Review Checkpoints

**Required Reviews:**
- All protocol definitions
- All service implementations
- God object decompositions
- High-risk changes (force unwrap removal in critical paths)

### Breaking Changes and Compatibility

#### SwiftData Model Changes

**Resume Decomposition Creates Breaking Changes:**
- Current single `Resume` model → Three separate models
- Requires data migration

**Migration Strategy:**
```swift
// Create migration plan
class ResumeModelMigration {
    func migrateV1toV2(context: ModelContext) throws {
        // 1. Fetch all old Resume objects
        let oldResumes = try context.fetch(FetchDescriptor<Resume>())

        // 2. For each old Resume, create new models
        for oldResume in oldResumes {
            let metadata = ResumeMetadata(
                name: oldResume.name,
                dateCreated: oldResume.dateCreated
            )
            let content = ResumeContent(
                metadata: metadata,
                rootNode: oldResume.model,
                fontSizes: oldResume.fontSizes
            )
            let output = ResumeOutput(
                metadata: metadata,
                pdfData: oldResume.pdfData,
                textData: oldResume.textRes
            )

            context.insert(metadata)
            context.insert(content)
            context.insert(output)
        }

        // 3. Save new models
        try context.save()

        // 4. Mark old models as migrated (don't delete yet)
    }
}
```

**Testing Migration:**
- Test on copy of production database
- Verify all data migrates correctly
- Test rollback procedure

---

## VI. Implementation Timeline

### Overview

**Total Estimated Duration:** 19-23 weeks (4.5-6 months)

**Note:** Duration reduced by ~1 week after investigation confirmed NotificationCenter usage is appropriate for menu/toolbar coordination. Phase 5 is now minimal cleanup only.

**Team Size Assumptions:**
- 1-2 developers full-time on refactoring
- Other team members available for reviews
- No major feature additions during refactoring

### Detailed Timeline

| Phase | Duration | Dependencies | Risk |
|-------|----------|--------------|------|
| **Phase 1: Protocols** | 2-3 weeks | None | Low |
| **Phase 2: Eliminate Singletons** | 3-4 weeks | Phase 1 | Medium |
| **Phase 3: Decompose God Objects** | 4-5 weeks | Phase 2 | High |
| **Phase 4: Replace JSON** | 2-3 weeks | Phase 3 | Medium |
| **Phase 5: NotificationCenter Cleanup** | 0.5-1 week | None (parallel, optional) | Very Low |
| **Phase 6: Separate View Concerns** | 4-5 weeks | Phases 2, 3 | Medium |
| **Phase 7: Error Handling** | 2 weeks | None (parallel) | Low |
| **Phase 8: Force Unwrap Removal** | 1-2 weeks | None (parallel) | Low |
| **Phase 9: Concurrency** | 1-2 weeks | Phase 2 | Medium |
| **Phase 10: Configuration** | 1 week | None (parallel) | Low |

### Parallel Work Opportunities

**Can Be Done In Parallel:**
- Phases 5, 7, 8, 10 can run concurrently with main phases
- NotificationCenter cleanup (Phase 5) can happen anytime (very quick)
- Error handling improvements can happen alongside any phase
- Force unwrap removal can happen alongside any phase
- Configuration centralization can happen alongside any phase

**Must Be Sequential:**
- Phase 1 → Phase 2 → Phase 3
- Phase 3 (Resume decomposition) → Phase 4 (JSON)
- Phase 2 → Phase 6 (needs DI first)

### Milestone Checkpoints

**Month 1 End:**
- [ ] All protocols defined
- [ ] AppCoordinator created
- [ ] First 3-4 singletons eliminated

**Month 2 End:**
- [ ] All singletons eliminated
- [ ] AppState decomposed
- [ ] Basic DI working throughout app

**Month 3 End:**
- [ ] Resume model decomposed
- [ ] Data migration tested
- [ ] Custom JSON eliminated

**Month 4 End:**
- [ ] ResumeDetailVM decomposed
- [ ] NotificationCenter cleanup complete (dead code removed)
- [ ] Major ViewModels created

**Month 5 End:**
- [ ] All views refactored to MVVM
- [ ] Error handling improved
- [ ] Force unwraps eliminated

**Month 6:**
- [ ] Concurrency refined
- [ ] Configuration centralized
- [ ] Final testing and polish
- [ ] Documentation complete

---

## VII. Success Metrics

### Code Quality Metrics

**Before Refactoring (Baseline):**
- God Objects: 3 (AppState, Resume, ResumeDetailVM)
- Singletons: 15+
- Force unwraps: 50+
- Testable components: <20%
- Average file size: 400 lines
- Cyclomatic complexity: High
- SwiftLint warnings: 150+

**After Refactoring (Goals):**
- God Objects: 0
- Singletons: 0 (converted to DI)
- Force unwraps: 0
- Testable components: >80%
- Average file size: <200 lines
- Cyclomatic complexity: Low-Medium
- SwiftLint warnings: <20

### Testing Metrics

**Coverage Goals:**
- Unit test coverage: 70%+
- Service layer coverage: 80%+
- ViewModel coverage: 75%+
- Integration tests for all critical flows

### Performance Metrics

**Should Maintain or Improve:**
- App launch time
- PDF generation time
- UI responsiveness
- Memory usage

### Developer Experience

**Qualitative Improvements:**
- New features easier to add
- Bugs easier to find and fix
- Code easier to understand
- Onboarding new developers faster

---

## VIII. Conclusion

This refactoring plan addresses fundamental architectural issues that currently limit the PhysCloudResume codebase's maintainability, testability, and scalability. By following this systematic approach, the codebase will be transformed into a modern, well-architected Swift/SwiftUI application that adheres to industry best practices.

### Key Takeaways

1. **Protocol-First Design**: Establishes foundation for testability
2. **Dependency Injection**: Eliminates tight coupling and global state
3. **Single Responsibility**: Each component has one clear purpose
4. **Modern Swift**: Leverages latest language features and patterns
5. **Incremental Migration**: Reduces risk through gradual changes

### Next Steps

1. **Review and Validate**: Team reviews this plan, provides feedback
2. **Prioritize**: Adjust phase order based on business priorities
3. **Set Up Testing**: Create integration test suite before starting
4. **Begin Phase 1**: Start with protocol definitions
5. **Regular Reviews**: Weekly check-ins on progress and issues

### Long-Term Benefits

- **Faster Development**: New features take less time to implement
- **Fewer Bugs**: Better architecture prevents entire classes of bugs
- **Easier Maintenance**: Clear structure makes updates straightforward
- **Better Testing**: High test coverage catches regressions early
- **Team Scalability**: New developers can understand and contribute faster

---

**Document Version:** 1.0
**Last Updated:** 2025-10-07
**Status:** Ready for Review
