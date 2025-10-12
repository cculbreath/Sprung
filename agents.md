# @agents.md

This file provides comprehensive guidance for AI agents and developers working with the Sprung codebase, combining build instructions, architectural principles, and coding standards.

## Project Overview
- **Project Type**: macOS application (not iOS)
- **Project File**: `Sprung.xcodeproj`
- **Target**: Sprung
- **Scheme**: Sprung
- **Build Configurations**: Debug, Release
- **Environment**: macOS command-line environment with coreutils installed

## Project Structure

### Repository Organization
- This is a **macOS** app, not an iOS app
- Local clones of dependency repositories are available for code and documentation reference:
  - `~/devlocal/swift-chunked-audio-player` contains `ChunkedAudioPlayer`
  - `~/devlocal/codebase/SwiftOpenAI-ttsfork` contains customized fork of `SwiftOpenAI`
- **CRITICAL**: `./Notes/` contains essential architectural documentation
  - `Notes/LLM Design Intent Docs/LLM_OPERATIONS_ARCHITECTURE.md` - Complete LLM refactoring plan
  - `Notes/LLM Design Intent Docs/LLM_MULTI_TURN_WORKFLOWS.md` - Complex workflow patterns
  - `Notes/ClaudeNotes/` - Various refactoring plans and architectural reviews
  - `Notes/RefactorNotes/` - Phase progress tracking and implementation guides
  - **Always read relevant documentation before starting LLM-related work**

### Package Dependencies
The project uses Swift Package Manager with the following dependencies:
- ViewInspector (testing)
- SwiftSoup (HTML parsing)
- Mustache (templating)
- SwiftOpenAI (custom fork for LLM integration)
- swift-chunked-audio-player (custom audio streaming)
- swift-collections (Apple collections)
- SwiftyJSON (JSON handling)

## Architectural Principles

### Single Responsibility Principle
- **Each class/struct should have one reason to change**
- Split large, multi-purpose classes into focused components
- Business logic, UI logic, and data persistence are separate concerns
- Models should be pure data containers without presentation logic

### Dependency Injection Over Singletons
- **AVOID singletons (`.shared`) whenever possible** - they create hidden dependencies and make testing difficult
- Use dependency injection through initializers or SwiftUI's `@Environment`
- Protocol-oriented design enables testability and flexibility
- Only use singletons for truly global, stateless utilities

### Clear Separation of Concerns
- **Models**: Pure data structures, no business logic or UI concerns
- **Services**: Business logic, data processing, external API interactions
- **ViewModels**: UI state management, formatting data for presentation
- **Views**: Declarative UI only, minimal logic

### SwiftUI-Native Architecture
- Leverage `@Observable` classes for business logic services
- Use SwiftUI's `@Environment` for dependency injection
- Prefer SwiftUI's reactive patterns over traditional MVVM when appropriate
- Break complex views into focused, single-purpose components

## Coding Standards

### Data Handling
- **ALWAYS use SwiftyJSON for dynamic JSON operations** - replaced rigid Codable with flexible approach
- Never implement custom JSON parsers - use SwiftyJSON and DynamicResumeService
- Define clear DTOs (Data Transfer Objects) for external API interactions
- Use fully array-based JSON structure for all resume data

### Resume JSON Structure (Array-Based Schema)
The resume system uses a fully array-based JSON structure to ensure order preservation and eliminate keys-as-values patterns:

**Top-Level Structure:**
```json
[
    {
        "title": "section-name",
        "value": [data-or-array]
    },
    ...
]
```

**Special Keywords:**
- `title`: Used for section names, item names, and property keys
- `value`: Contains the actual data (arrays, strings, objects)
- **NO keys-as-values allowed** - all meaningful data goes in `value` fields

**Key Principles:**
- Arrays preserve order naturally at all levels
- `title`/`value` coupling enables AI replacement workflows
- No section-specific code needed - universal processing
- Templates receive flattened dictionaries for compatibility

### Error Handling
- **Use Swift's native error handling with `try/catch`**
- Never use empty `catch {}` blocks - always log or propagate errors
- Replace `fatalError` used for control flow with proper error throwing
- Define custom error types for specific failure scenarios
- Provide meaningful error messages for user-facing failures

### Memory Safety
- **Avoid force unwrapping (`!`) - use guard statements or optional binding**
- Use `guard let` or `if let` for safe optional unwrapping
- Handle nil cases explicitly with appropriate fallbacks or errors
- Be cautious with implicitly unwrapped optionals

### No Stubs or Placeholder Code
- Do not add stub implementations, placeholder switches, or dummy return values during development.
- If a feature is in progress, either complete the implementation or leave the call site untouched.
- Temporary scaffolding must be accompanied by working behavior and clear removal plans—avoid `TODO`, `fatalError`, or silent fallbacks as shortcuts.

### Swift Concurrency and Actor Isolation
- **MainActor Usage**: Mark functions with `@MainActor` when they need to access main actor-isolated properties
- **Actor Isolation**: Remove `@MainActor` from services that don't need UI thread access to avoid compilation conflicts
- **Swift 6 Compliance**: Use `Task { @MainActor in }` for callback assignments when needed
- **Async/Await Patterns**: Prefer structured concurrency over completion handlers
- **Service Communication**: Design services to minimize actor boundary crossings

### SwiftUI Best Practices
- Use correct property wrappers: `@State` for value types, `@StateObject`/`@ObservedObject` for reference types
- When working with sheets: prefer keeping parent views visible and using completion handlers
- For progress/loading states: ensure UI updates happen on MainActor
- Maintain separate state for: processing status, results, errors, and UI visibility
- Always provide cancellation support for long-running operations
- Break large views into smaller, focused components
- Test sheet presentation flows before assuming implementation is correct
- Add debug logging for view lifecycle events when debugging UI issues

## Build Instructions

### List Available Schemes
```bash
xcodebuild -project Sprung.xcodeproj -list
```

### Basic Build Commands

**Standard Debug Build:**
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung build
```

**Release Build:**
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung -configuration Release build
```

**Build for macOS (explicit platform):**
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung -destination 'platform=macOS' build
```

**Build with specific macOS version:**
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung -destination 'platform=macOS,arch=arm64' build
```

### Quick Error Check Build
When you need to quickly verify there are no compilation errors without waiting for a full build:
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung build 2>&1 | grep -E "(error:|warning:|failed)" | head -20
```

### Clean Build
When you need to start fresh:
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung clean build
```

### Package Resolution
If packages fail to resolve:
```bash
xcodebuild -resolvePackageDependencies -project Sprung.xcodeproj
```

## Build Strategy Guidelines

**IMPORTANT: Avoid excessive building - it wastes time and computational resources**

### When to Build
- ✅ After creating new service files (to catch import/dependency issues early)
- ✅ After major structural changes or multi-file refactoring
- ✅ When changing method signatures, protocols, or public interfaces
- ✅ After changing dependencies or project configuration
- ✅ Final verification before committing
- ✅ When debugging complex linking, actor isolation, or compilation issues

### When NOT to Build
- ❌ After every small change
- ❌ After single file edits (unless changing interfaces)
- ❌ After UI-only changes (use Xcode's live preview instead)
- ❌ For localized changes that are well-understood

### Incremental Build Strategy
1. For single file changes: Skip build verification unless changing interfaces
2. For multi-file refactoring: Use quick error check build first
3. For service extraction: Build incrementally to isolate actor isolation issues
4. For final verification: Run full xcodebuild with error filtering
5. Use targeted compilation: `swift build --target Sprung`
6. When checking for errors: Use `| grep -E "(error:|warning:|failed)" | head -20`

## Service Design Patterns

### Protocol-Oriented Programming
- Define protocols for all services to enable testing and flexibility
- Use dependency injection through initializers or SwiftUI environment
- Create mock implementations for testing
- Keep protocol interfaces focused and minimal

### Service Layer Architecture
```swift
// Example service structure
protocol JobAppRepository {
    func fetchJobApps() async throws -> [JobApp]
    func save(_ jobApp: JobApp) async throws
    func delete(_ jobApp: JobApp) async throws
}

@Observable
class JobApplicationService {
    private let repository: JobAppRepository

    var jobApps: [JobApp] = []
    var isLoading = false
    var errorMessage: String?

    init(repository: JobAppRepository) {
        self.repository = repository
    }

    func loadJobApps() async {
        isLoading = true
        defer { isLoading = false }

        do {
            jobApps = try await repository.fetchJobApps()
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("Failed to load job apps: \(error)")
        }
    }
}
```

### SwiftUI Environment Injection
```swift
// Service registration at app startup
@main
struct SprungApp: App {
    let jobAppService = JobApplicationService(
        repository: SwiftDataJobAppRepository()
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(jobAppService)
                .modelContainer(for: [JobApp.self])
        }
    }
}

// Usage in views
struct JobApplicationView: View {
    @Environment(JobApplicationService.self) private var service

    var body: some View {
        List(service.jobApps) { jobApp in
            JobAppRowView(jobApp: jobApp)
        }
        .task { await service.loadJobApps() }
    }
}
```

### Menu/Toolbar Coordination

For macOS menu bar and toolbar coordination where SwiftUI's environment doesn't reach:

#### Option 1: FocusedBinding (Preferred)
```swift
struct MenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Job Applications") {
            Button("Add Job Application") {
                // Automatically finds focused window's binding
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}
```

#### Option 2: Type-Safe NotificationCenter (When Needed)
```swift
extension Notification.Name {
    static let addJobApplication = Notification.Name("addJobApplication")
}

struct AppNotifications {
    static func postAddJobApplication() {
        NotificationCenter.default.post(name: .addJobApplication, object: nil)
    }
}
```

## Testing Strategy

### Design for Testability
- Use dependency injection to enable mock services
- Keep business logic separate from UI components
- Create protocol abstractions for external dependencies
- Write tests for business logic in services, not UI components

### Mock Implementation Example
```swift
class MockJobAppRepository: JobAppRepository {
    var jobApps: [JobApp] = []

    func fetchJobApps() async throws -> [JobApp] {
        return jobApps
    }

    func save(_ jobApp: JobApp) async throws {
        jobApps.append(jobApp)
    }

    func delete(_ jobApp: JobApp) async throws {
        jobApps.removeAll { $0.id == jobApp.id }
    }
}
```

### Running Tests
```bash
xcodebuild -project Sprung.xcodeproj -scheme Sprung test
```

## API Schema Management
- When modifying Codable structs used for API responses, ALWAYS update corresponding JSON schemas
- Check for both required and optional fields in schemas
- When debugging JSON parsing failures, first verify schema matches struct definition
- Use optional fields in structs when the API might not always return a value

## Systematic Debugging
- Use the project's Logger utility at `/Sprung/Shared/Utilities/Logger.swift` for all logging
- Understand the debug level system:
  - **User Settings**: Users can set "None", "Basic", or "Verbose" in app settings
  - **None**: Only shows error-level logs (`Logger.error()`)
  - **Basic**: Shows info, warning, and error logs (`Logger.info()`, `Logger.warning()`, `Logger.error()`)
  - **Verbose**: Shows all logs including debug and verbose (`Logger.verbose()`, `Logger.debug()`, plus all above)
- Choose appropriate log levels for your code:
  - `Logger.verbose()` - Detailed trace information (🔍, only shown in Verbose mode)
  - `Logger.debug()` - Development debugging information (🔍, only shown in Verbose mode)
  - `Logger.info()` - Important state changes and milestones (ℹ️, shown in Basic+ mode)
  - `Logger.warning()` - Potential issues that don't prevent operation (⚠️, shown in Basic+ mode)
  - `Logger.error()` - Actual errors and failures (🚨, always shown)
- Use descriptive emoji prefixes for context: 🚀 start, 📊 progress, ✅ success, ❌ error, 🎯 key events
- For multi-step processes, log transitions at info level for major steps, debug level for substeps
- The Logger automatically saves error and warning logs to Downloads folder when debug file saving is enabled

## Code Quality Guidelines

### Avoid Anti-Patterns
- **God Objects**: Classes that know too much or have too many responsibilities
- **Custom JSON Parsing**: Always use Swift's native `Codable` framework or SwiftyJSON
- **Silent Error Handling**: Always log or propagate errors appropriately
- **Hardcoded Values**: Externalize configuration, use enums for constants
- **Mixed Concerns**: Keep data, business logic, and UI separate

### Enforce Consistency
- Organize imports alphabetically
- Follow protocol-oriented programming patterns
- Document public methods with triple-slash (`///`) comments
- Use `@available` annotations for version-specific features
- Prefer async/await over completion handlers where possible

## Development Workflow

### Coding Practices
- **🚫 NEVER include AI attribution in commit messages** - Work anonymously
- Commit code changes regularly with detailed commit messages
- For major features: create branches and use multiple commits
- **Before editing code**: generate implementation plans for feedback
- Build at regular intervals and address compiler errors immediately
- Do not add TODO statements - implement what's needed
- Use `gcat -A` to visualize whitespace in code files
- Use `grep -n` for searching (allowed)

### File Management
- **Default to Editing**: Prefer editing existing files over creating new ones
- **Proper File Deletion**: Use appropriate deletion tools for obsolete files
- **File Consolidation**: When merging files, delete source files after successfully moving content
- **Avoid File Blanking**: Never replace file content with empty strings
- **Validation**: Verify compilation after file operations

### LLM Refactoring Specific
- Start with Phase 1 implementation (LLMService + ResumeReviseService)
- Test each operation manually through UI before proceeding
- Preserve existing functionality during migration
- Follow two-stage model filtering patterns
- Do not implement "fallback" code or backwards compatibility unless specifically asked

### Implementation Planning
- **Before editing any code**: Generate a detailed implementation plan for feedback
- For long, multi-part sessions: Convert plan into checklist file and update regularly
- If unsure about feature functionality: Ask for screenshot, test run, or UI feedback

## Refactoring Guidelines

### When to Refactor
- **Clear Violations**: Files mixing multiple distinct concerns
- **Large Complex Files**: 500+ lines with multiple responsibilities
- **Actual Pain Points**: Code that's difficult to modify, test, or understand
- **Testability Issues**: Code that can't be tested due to tight coupling

### When NOT to Refactor
- **Working Code**: If code functions well and is maintainable, leave it alone
- **Premature Abstraction**: Don't create services for simple, single-use logic
- **Speculative Improvements**: Don't refactor for hypothetical future needs
- **Pattern Matching**: Don't refactor just to match common patterns

### Refactoring Process
- **Refactoring Restraint Principle**: Default assumption is existing code structure is adequate
- **Articulation Test**: Clearly explain why refactoring is needed
- **Minimal Viable Changes**: Make smallest change that solves the problem
- **Preserve Functionality**: Maintain all original behavior
- **Incremental Approach**: Small, testable changes over big-bang rewrites

## Common Build Issues

### Actor Isolation Errors
- Services may need `@MainActor` annotation for UI-related properties
- Use `Task { @MainActor in }` for callback assignments
- Remove `@MainActor` from services that don't need UI thread access

### Swift Concurrency
- Project follows Swift 6 concurrency patterns
- Use async/await over completion handlers
- Mark functions with `@MainActor` when accessing main actor-isolated properties

## Important Reminders
- Do not implement #Preview in any views
- Use SwiftData for persistence
- Log network calls with descriptive emojis for debugging
- Always test critical workflows manually after implementation
- This is a **macOS** app, not an iOS app

## Related Documentation
- See `Notes/LLM Design Intent Docs/LLM_OPERATIONS_ARCHITECTURE.md` for LLM refactoring guidance
- See `Notes/LLM Design Intent Docs/LLM_MULTI_TURN_WORKFLOWS.md` for complex workflow patterns
- See `Notes/ClaudeNotes/` for refactoring plans and architectural reviews
- See `Notes/RefactorNotes/` for phase progress tracking and implementation guides
- See `Notes/CodeReviewFindings/` for detailed code review findings by module
- See global `~/.claude/CLAUDE.md` for build verification strategy details
