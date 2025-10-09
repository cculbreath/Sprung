# File-Level Refactoring Assessment Criteria

**Purpose**: Per-file checklist for parallel code review agents to systematically assess whether individual files contain pre-refactor architecture, anti-patterns, or violations of the new architectural principles.

**Usage**: Apply these criteria to each file in the codebase. Report findings with specific line numbers and code excerpts.

**Last Updated**: 2025-10-08

---

## Assessment Categories

Each file should be evaluated across these categories. Report violations with:
- **File path**
- **Line number(s)**
- **Code excerpt**
- **Violation type**
- **Severity**: Critical / High / Medium / Low
- **Recommendation**

---

## 1. Singleton Usage (Anti-Pattern)

### What to Look For

**Critical Violations**:
```swift
// OLD: Singleton pattern
static let shared = SomeService()
SomeService.shared

// OLD: Global shared instance usage
AppState.shared
OpenRouterService.shared
CoverLetterService.shared
```

**Expected New Pattern**:
```swift
// NEW: Dependency injection via initializer
init(service: SomeService, otherDep: OtherDep) {
    self.service = service
}

// NEW: SwiftUI environment injection
@Environment(SomeService.self) private var service
```

### Assessment Questions
- [ ] Does this file define a singleton via `static let shared`?
- [ ] Does this file reference `.shared` on any service?
- [ ] Are all dependencies injected via initializer or `@Environment`?
- [ ] Is `AppState.shared` referenced anywhere?

### Exceptions
- Truly global, stateless utilities (e.g., `Logger`, `KeychainHelper`)
- System-level coordinators documented as intentional singletons

---

## 2. Force Unwrapping and Fatal Errors (Safety)

### What to Look For

**Critical Violations**:
```swift
// OLD: Force unwraps
let url = URL(string: urlString)!
let data = try! encoder.encode(object)
let first = array.first!
let last = array.last!
pdfData!

// OLD: fatalError in user-reachable paths
fatalError("Container initialization failed")
```

**Expected New Pattern**:
```swift
// NEW: Safe unwrapping
guard let url = URL(string: urlString) else {
    Logger.error("Invalid URL: \(urlString)")
    return .failure(.invalidURL)
}

// NEW: Proper error handling
do {
    let data = try encoder.encode(object)
} catch {
    Logger.error("Encoding failed: \(error)")
    throw CustomError.encodingFailed(error)
}

// NEW: Safe optional access
guard let first = array.first else { return defaultValue }
```

### Assessment Questions
- [ ] Does this file contain force unwraps (`!`) outside of test code?
- [ ] Does this file use `try!` anywhere?
- [ ] Does this file call `fatalError()` in user-reachable code paths?
- [ ] Are all optionals handled with guard/if-let or optional chaining?
- [ ] Are `URL(string:)` calls always guarded?

### Exceptions
- `fatalError()` for programmer errors in init (rare, must be justified)
- Force unwraps in unit tests only
- IBOutlet force unwraps (not applicable to this SwiftUI project)

---

## 3. Secrets and Configuration (Security)

### What to Look For

**Critical Violations**:
```swift
// OLD: API keys in UserDefaults
UserDefaults.standard.string(forKey: "apiKey")
UserDefaults.standard.set(apiKey, forKey: "openRouterAPIKey")

// OLD: Hardcoded secrets
let apiKey = "sk-or-v1-..."
```

**Expected New Pattern**:
```swift
// NEW: Keychain-backed APIKeyManager
let apiKey = APIKeyManager.shared.getAPIKey(for: .openRouter)
try APIKeyManager.shared.setAPIKey(apiKey, for: .openRouter)

// NEW: Configuration constants
let timeout = AppConfig.networkTimeout
let maxRetries = AppConfig.maxRetryAttempts
```

### Assessment Questions
- [ ] Does this file read API keys from `UserDefaults`?
- [ ] Does this file store secrets in `UserDefaults`?
- [ ] Does this file contain hardcoded API keys or tokens?
- [ ] Are all secrets accessed via `APIKeyManager` and `KeychainHelper`?
- [ ] Are configuration constants in `AppConfig` rather than hardcoded?

---

## 4. Custom JSON Handling (Deprecated)

### What to Look For

**Critical Violations**:
```swift
// OLD: Custom JSON parser
JSONParser.parse(string)

// OLD: Manual JSON string building
var json = "{"
json += "\"key\": \"\(value)\""
json += "}"

// OLD: TreeToJson usage
TreeToJson.convert(node)
Resume.jsonTxt // if it uses TreeToJson internally
```

**Expected New Pattern**:
```swift
// NEW: ResumeTemplateDataBuilder
let builder = ResumeTemplateDataBuilder()
let context = builder.buildContext(from: treeNode, metadata: metadata)

// NEW: Standard JSONSerialization
let jsonData = try JSONSerialization.data(withJSONObject: dictionary)
let object = try JSONSerialization.jsonObject(with: data)
```

### Assessment Questions
- [ ] Does this file import or reference `JSONParser`?
- [ ] Does this file build JSON strings manually with concatenation?
- [ ] Does this file reference `TreeToJson`?
- [ ] Does this file use `ResumeTemplateDataBuilder` for context generation?
- [ ] Are all JSON operations using standard library or SwiftyJSON?

### Exceptions
- Reading/parsing JSON from external APIs can use Codable
- SwiftyJSON usage is acceptable for dynamic JSON

---

## 5. Concurrency and Main Actor (Performance)

### What to Look For

**High Violations**:
```swift
// OLD: Blanket @MainActor on service classes
@MainActor
class LLMService { ... }

@MainActor
class OpenRouterService { ... }

@MainActor
class ConversationManager { ... }

// OLD: Synchronous heavy work on main thread
func processLargeData() { // Called from UI
    // Heavy processing without Task or background queue
}
```

**Expected New Pattern**:
```swift
// NEW: Selective @MainActor on UI-touching methods only
class LLMService {
    func fetchData() async throws -> Data { // Background
        // Network call
    }

    @MainActor
    func updateUI(with data: Data) { // Only UI updates
        // Update observable properties
    }
}

// NEW: Actor for mutable shared state
actor ConversationManager {
    private var conversations: [Conversation] = []

    func addConversation(_ conv: Conversation) {
        conversations.append(conv)
    }
}

// NEW: Background processing
func processLargeData() async {
    await Task.detached { // or just async context
        // Heavy processing off main thread
    }.value
}
```

### Assessment Questions
- [ ] Does this file mark entire service classes with `@MainActor`?
- [ ] Are network calls wrapped in main-actor contexts unnecessarily?
- [ ] Is heavy processing (parsing, encoding, computation) on background threads?
- [ ] Are actors used for mutable shared state?
- [ ] Are `@MainActor` annotations justified and minimal?

### Exceptions
- ViewModels and Views should be `@MainActor`
- UI update methods can be `@MainActor`-isolated

---

## 6. Vendor Type Leakage (LLM/AI Services)

### What to Look For

**High Violations**:
```swift
// OLD: SwiftOpenAI types in public APIs
import SwiftOpenAI

func sendMessage(_ message: MessageChatGPT) async -> ChatCompletionObject

typealias LLMMessage = MessageChatGPT // Public alias
typealias LLMResponse = ChatCompletionObject

// OLD: Direct SwiftOpenAI usage in view models
let openAI = SwiftOpenAI(apiToken: token)
openAI.createChatCompletions(...)
```

**Expected New Pattern**:
```swift
// NEW: Domain types only in public APIs
func sendMessage(_ message: LLMMessageDTO) async -> LLMResponseDTO

// NEW: Adapter pattern with internal conversion
class SwiftOpenAIAdapter: LLMClient {
    private let client: SwiftOpenAI

    func sendMessage(_ message: LLMMessageDTO) async -> LLMResponseDTO {
        let vendorMessage = convertToVendor(message) // Internal only
        let vendorResponse = await client.send(vendorMessage)
        return convertFromVendor(vendorResponse)
    }
}
```

### Assessment Questions
- [ ] Does this file expose SwiftOpenAI types in public APIs?
- [ ] Are there typealiases to vendor types outside adapter modules?
- [ ] Do view models import SwiftOpenAI directly?
- [ ] Are domain DTOs (`LLMMessageDTO`, `LLMResponseDTO`) used at boundaries?
- [ ] Is vendor conversion isolated to adapter/mapper files?

### Key Files to Check
- Anything importing `SwiftOpenAI` outside of `LLMVendorMapper.swift`, `SwiftOpenAIClient.swift`
- `ConversationTypes.swift` - should not have public typealiases
- View models in `Resumes/AI/`, `JobApplications/AI/`, `CoverLetters/AI/`

---

## 7. Export and Template Context (Architecture)

### What to Look For

**High Violations**:
```swift
// OLD: Model contains export orchestration
class Resume {
    func debounceExport() { ... }
    func throttleExport() { ... }
    func exportToPDF() { ... }
}

// OLD: Template context mixed with rendering
class NativePDFGenerator {
    func generate() {
        // Shows alerts/pickers
        let panel = NSOpenPanel()
        panel.runModal()

        // Builds context inline
        let context = buildContextHere()

        // Renders
        render(context)
    }
}

// OLD: UI logic in service
class ResumeExportService {
    func export() {
        let alert = NSAlert()
        alert.runModal()
    }
}
```

**Expected New Pattern**:
```swift
// NEW: Models are pure data
struct Resume {
    let title: String
    let sections: [Section]
    // No behavior, no export logic
}

// NEW: Export coordination in dedicated service
class ResumeExportCoordinator {
    func scheduleExport(for resume: Resume) { ... }
    func cancelPendingExport() { ... }
}

// NEW: Context building separated
class ResumeTemplateDataBuilder {
    func buildContext(from tree: TreeNode) -> [String: Any] { ... }
}

// NEW: Rendering isolated
class NativePDFGenerator {
    func render(context: [String: Any], template: String) -> Data { ... }
    // No UI, no context building
}

// NEW: UI interactions in view/helper
class ExportTemplateSelection {
    func pickTemplate() async -> Template? { ... }
}
```

### Assessment Questions
- [ ] Do model types (`Resume`, `TreeNode`) contain export orchestration?
- [ ] Does `NativePDFGenerator` show UI (alerts, panels)?
- [ ] Does `NativePDFGenerator` build template context?
- [ ] Does `ResumeExportService` contain NSAlert/NSPanel code?
- [ ] Is context building delegated to `ResumeTemplateDataBuilder`?
- [ ] Is export throttling/debouncing in a service, not a model?

---

## 8. NotificationCenter Usage (macOS Bridge)

### What to Look For

**Medium Violations**:
```swift
// OLD: Undocumented NotificationCenter usage
NotificationCenter.default.post(name: .someRandomName, object: nil)

// OLD: View-local state via NotificationCenter
NotificationCenter.default.addObserver(forName: .showSheet, ...)

// OLD: Removed listeners still registered
NotificationCenter.default.addObserver(forName: .refreshJobApps, ...)
```

**Expected New Pattern**:
```swift
// NEW: Documented, menu/toolbar-specific notifications
// (In MenuNotificationHandler.swift or similar)
extension Notification.Name {
    /// Posted by menu command to add new job application
    static let addJobApplication = Notification.Name("addJobApplication")
}

// NEW: SwiftUI bindings for view-local state
@State private var showSheet = false
Button("Show") { showSheet = true }
.sheet(isPresented: $showSheet) { ... }

// NEW: Environment-based state sharing
@Environment(AppSheets.self) private var sheets
Button("Show") { sheets.showJobAppSheet = true }
```

### Assessment Questions
- [ ] Does this file post undocumented NotificationCenter notifications?
- [ ] Are notifications used for view-local state (sheets, alerts)?
- [ ] Is `.refreshJobApps` notification still present?
- [ ] Are all notifications documented in `MenuNotificationHandler` or similar?
- [ ] Could this NotificationCenter usage be replaced with SwiftUI bindings?

### Exceptions
- Menu commands bridging to SwiftUI (documented explicitly)
- Toolbar coordination where environment doesn't reach (documented)

---

## 9. Logging and Observability (Diagnostics)

### What to Look For

**Medium Violations**:
```swift
// OLD: Empty catch blocks
do {
    try riskyOperation()
} catch {
    // Silent failure
}

// OLD: print() debugging
print("Debug info: \(value)")

// OLD: No logging in error paths
func saveData() {
    guard let data = processData() else {
        return // Silent failure
    }
}
```

**Expected New Pattern**:
```swift
// NEW: Proper error logging
do {
    try riskyOperation()
} catch {
    Logger.error("Failed to complete operation: \(error)")
    throw ServiceError.operationFailed(error)
}

// NEW: Logger utility usage
Logger.debug("🔍 Processing data: \(data)")
Logger.info("✅ Operation completed successfully")
Logger.warning("⚠️ Potential issue detected")
Logger.error("🚨 Critical failure: \(error)")

// NEW: Error path logging
func saveData() throws {
    guard let data = processData() else {
        Logger.error("Failed to process data")
        throw DataError.processingFailed
    }
    Logger.info("✅ Data saved successfully")
}
```

### Assessment Questions
- [ ] Does this file have empty `catch {}` blocks?
- [ ] Does this file use `print()` for debugging?
- [ ] Are error paths logged with `Logger.error()`?
- [ ] Are important state transitions logged with `Logger.info()`?
- [ ] Is verbose debugging using `Logger.debug()` or `Logger.verbose()`?

---

## 10. Dependency Injection and Initialization (Lifecycle)

### What to Look For

**High Violations**:
```swift
// OLD: Store creation in view body
struct ContentView: View {
    var body: some View {
        SomeSubView()
            .environment(JobAppStore()) // NEW INSTANCE EVERY RENDER!
    }
}

// OLD: Initializing stores directly in views
struct SomeView: View {
    @State private var store = JobAppStore()
}

// OLD: Implicit dependencies
class SomeService {
    func doWork() {
        let otherService = OtherService.shared // Hidden dependency
    }
}
```

**Expected New Pattern**:
```swift
// NEW: Stable store via @State at parent
struct ContentView: View {
    @State private var jobAppStore = JobAppStore()

    var body: some View {
        SomeSubView()
            .environment(jobAppStore) // Same instance across renders
    }
}

// NEW: AppDependencies container
class AppDependencies {
    let jobAppStore: JobAppStore
    let llmService: LLMService

    init() {
        self.jobAppStore = JobAppStore()
        self.llmService = LLMService(/*...*/)
    }
}

// NEW: Explicit dependencies
class SomeService {
    private let otherService: OtherService

    init(otherService: OtherService) {
        self.otherService = otherService
    }
}
```

### Assessment Questions
- [ ] Are stores created inside `var body: some View`?
- [ ] Are dependencies injected via initializer or environment?
- [ ] Does this file hide dependencies behind `.shared` calls?
- [ ] Is `AppDependencies` used for app-level services?
- [ ] Are store instances stable (not recreated on each render)?

---

## 11. SwiftData and Persistence (Data Layer)

### What to Look For

**Medium Violations**:
```swift
// OLD: Silent save failures
func saveContext() {
    do {
        try modelContext.save()
    } catch {
        // No logging or error propagation
    }
}

// OLD: Direct UserDefaults for application state
UserDefaults.standard.set(selectedResumeID, forKey: "selectedResume")
```

**Expected New Pattern**:
```swift
// NEW: Logged and surfaced errors
func saveContext() throws {
    do {
        try modelContext.save()
        Logger.info("✅ Context saved successfully")
    } catch {
        Logger.error("🚨 Failed to save context: \(error)")
        throw PersistenceError.saveFailed(error)
    }
}

// NEW: SwiftData for app state
@Model
class AppSettings {
    var selectedResumeID: UUID?
    var debugLevel: DebugLevel
}
```

### Assessment Questions
- [ ] Does `saveContext()` log errors?
- [ ] Are save failures surfaced to callers?
- [ ] Is `UserDefaults` used for anything other than simple preferences?
- [ ] Is SwiftData used for application state and entities?

---

## 12. Model Responsibilities (SRP - Single Responsibility)

### What to Look For

**Medium Violations**:
```swift
// OLD: Models with presentation logic
struct JobApp {
    // ... data properties ...

    func formattedCompanyName() -> String { ... } // Presentation
    func highlightedTitle() -> AttributedString { ... } // Presentation
}

// OLD: Models with business logic
struct Resume {
    // ... data properties ...

    func validateForExport() -> ValidationResult { ... } // Business logic
    func exportToPDF() async throws -> Data { ... } // Orchestration
}

// OLD: Models with parsing logic
struct IndeedJobScrape {
    static func parseIndeedJobListing(html: String) -> JobApp? {
        // Parsing logic
        // Store mutation
        // Error handling
    }
}
```

**Expected New Pattern**:
```swift
// NEW: Pure data models
struct JobApp {
    let companyName: String
    let title: String
    let datePosted: Date
    // Just data, no behavior
}

// NEW: Presentation in ViewModels
class JobAppViewModel {
    func formattedCompanyName(for jobApp: JobApp) -> String { ... }
}

// NEW: Business logic in Services
class ResumeValidationService {
    func validate(_ resume: Resume) -> ValidationResult { ... }
}

// NEW: Parsing separated from orchestration
class IndeedParser {
    func parse(html: String) throws -> ParsedJobData { ... }
}

class JobAppService {
    func importFromHTML(_ html: String) async throws {
        let parsed = try parser.parse(html: html)
        let jobApp = try await store.save(parsed)
        Logger.info("✅ Imported job application")
    }
}
```

### Assessment Questions
- [ ] Do models contain only data (properties)?
- [ ] Is presentation logic in ViewModels/Views?
- [ ] Is business logic in dedicated Service classes?
- [ ] Is parsing separated from orchestration and persistence?

---

## 13. File Organization and Imports (Structure)

### What to Look For

**Low Violations**:
```swift
// OLD: Unused imports
import SwiftUI
import Foundation
import SomeUnusedFramework

// OLD: Missing organizational comments
// No clear sections

// OLD: Disorganized property declarations
class MyClass {
    var prop1: String
    @Published var prop2: Int
    private var prop3: Bool
    public var prop4: Data
    @State private var prop5: String
}
```

**Expected New Pattern**:
```swift
// NEW: Only necessary imports, alphabetized
import Foundation
import SwiftUI

// NEW: Clear sections
class MyClass {
    // MARK: - Properties

    // Public
    let publicProp: String

    // Private
    private let privateProp: Int

    // MARK: - Initialization

    init(publicProp: String, privateProp: Int) {
        self.publicProp = publicProp
        self.privateProp = privateProp
    }

    // MARK: - Public Methods

    // MARK: - Private Methods
}
```

### Assessment Questions
- [ ] Are imports alphabetized?
- [ ] Are there unused imports?
- [ ] Is the file organized with MARK comments?
- [ ] Are properties grouped logically (public, private, dependencies)?

---

## Severity Levels and Prioritization

### Critical
- Singleton usage (`.shared`) outside documented exceptions
- Force unwraps in user-reachable paths
- Secrets in UserDefaults
- Custom JSON parsing (JSONParser, TreeToJson usage)

### High
- Blanket `@MainActor` on service classes
- SwiftOpenAI types in public APIs
- Export orchestration in models
- Store creation in view body

### Medium
- Undocumented NotificationCenter usage
- Silent error handling (empty catch, no logging)
- Models with presentation/business logic
- UserDefaults for application state

### Low
- Missing `Logger` calls in non-critical paths
- print() debugging statements
- Disorganized imports
- Missing MARK comments

---

## Reporting Template

For each violation found:

```markdown
### [SEVERITY] Violation Type

**File**: `Path/To/File.swift`
**Lines**: 42-45

**Code Excerpt**:
```swift
let service = SomeService.shared
let url = URL(string: urlString)!
```

**Issue**: File uses deprecated singleton pattern and force unwrap.

**Recommendation**:
- Inject `SomeService` via initializer or environment
- Guard URL construction: `guard let url = URL(string: urlString) else { ... }`

**Related Phase**: Phase 1 (DI), Phase 2 (Safety)
```

---

## Special File Patterns to Flag

### Files That Should Not Exist
- `Shared/Utilities/JSONParser.swift`
- `ResumeTree/Utilities/TreeToJson.swift`
- Any file with `ConversationManager` if converted to actor or deleted

### Files That Should Exist
- `App/AppDependencies.swift`
- `App/AppEnvironment.swift`
- `Shared/Utilities/APIKeyManager.swift`
- `Shared/Utilities/ResumeTemplateDataBuilder.swift`
- `AI/Models/LLM/LLMDomain.swift`
- `AI/Models/LLM/LLMVendorMapper.swift`
- `AI/Models/Services/LLMConversationStore.swift`

---

## Quick Reference: Code Patterns to Search

### Search for Anti-Patterns
```bash
# Singletons
grep -rn "\.shared" --include="*.swift"
grep -rn "static let shared" --include="*.swift"

# Force unwraps
grep -rn "!" --include="*.swift" | grep -v "!=" | grep -v "// "

# Fatal errors
grep -rn "fatalError" --include="*.swift"

# Secrets in UserDefaults
grep -rn "UserDefaults.*apiKey" --include="*.swift"

# Custom JSON
grep -rn "JSONParser" --include="*.swift"
grep -rn "TreeToJson" --include="*.swift"

# Blanket MainActor
grep -rn "@MainActor" --include="*.swift" -B2

# Vendor leakage
grep -rn "import SwiftOpenAI" --include="*.swift"
grep -rn "MessageChatGPT\|ChatCompletionObject" --include="*.swift"

# NotificationCenter
grep -rn "NotificationCenter.default.post\|addObserver" --include="*.swift"

# Print debugging
grep -rn "print(" --include="*.swift"

# Empty catch
grep -rn "} catch {" --include="*.swift" -A1
```

---

## Final Notes

- **Context matters**: Some patterns may be acceptable in specific contexts (tests, debugging utilities, etc.)
- **Document exceptions**: If a violation is justified, it should be documented with a comment
- **Prioritize by severity**: Focus on Critical and High violations first
- **Report systematically**: Use consistent format for all findings
- **Include recommendations**: Don't just identify problems, suggest solutions

This assessment should be applied file-by-file within each subdirectory to ensure comprehensive coverage.
