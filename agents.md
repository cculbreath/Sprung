# agents.md

This file provides build instructions and project information for AI agents working with the PhysCloudResume codebase.

## Project Overview
- **Project Type**: macOS application (not iOS)
- **Project File**: `PhysCloudResume.xcodeproj`
- **Target**: PhysCloudResume
- **Scheme**: PhysCloudResume
- **Build Configurations**: Debug, Release

## Package Dependencies
The project uses Swift Package Manager with the following dependencies:
- ViewInspector (testing)
- SwiftSoup (HTML parsing)
- Mustache (templating)
- SwiftOpenAI (custom fork for LLM integration)
- swift-chunked-audio-player (custom audio streaming)
- swift-collections (Apple collections)
- SwiftyJSON (JSON handling)

## Build Instructions

### List Available Schemes
```bash
xcodebuild -project PhysCloudResume.xcodeproj -list
```

### Basic Build Commands

**Standard Debug Build:**
```bash
xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume build
```

**Release Build:**
```bash
xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume -configuration Release build
```

**Build for macOS (explicit platform):**
```bash
xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume -destination 'platform=macOS' build
```

**Build with specific macOS version:**
```bash
xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume -destination 'platform=macOS,arch=arm64' build
```

### Quick Error Check Build
When you need to quickly verify there are no compilation errors without waiting for a full build:
```bash
xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume build 2>&1 | grep -E "(error:|warning:|failed)" | head -20
```

### Clean Build
When you need to start fresh:
```bash
xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume clean build
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

## Common Build Issues

### Actor Isolation Errors
- Services may need `@MainActor` annotation for UI-related properties
- Use `Task { @MainActor in }` for callback assignments
- Remove `@MainActor` from services that don't need UI thread access

### Swift Concurrency
- Project follows Swift 6 concurrency patterns
- Use async/await over completion handlers
- Mark functions with `@MainActor` when accessing main actor-isolated properties

### Package Resolution
If packages fail to resolve:
```bash
xcodebuild -resolvePackageDependencies -project PhysCloudResume.xcodeproj
```

## Related Documentation
- See `CLAUDE.md` for coding standards and architectural principles
- See `ClaudeNotes/LLM_OPERATIONS_ARCHITECTURE.md` for LLM refactoring guidance
- See global `~/.claude/CLAUDE.md` for build verification strategy details

## Testing
The project uses ViewInspector for SwiftUI testing. Run tests with:
```bash
xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume test
```
