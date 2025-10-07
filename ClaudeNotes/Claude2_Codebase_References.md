# Codebase References: Areas Requiring Review

**Date:** 2025-10-07
**Purpose:** Identify specific files and modules requiring clarification or review before refactoring

---

## Critical Files for Review

### 1. Core Architecture Files

#### AppState.swift
**Path:** `/PhysCloudResume/App/AppState.swift`
**Status:** ⚠️ Needs refactoring
**Review Points:**
- Confirm which responsibilities should stay vs. move
- Verify migration strategy for persistent settings
- Check dependencies on `resumeReviseViewModel` and `globalReasoningStreamManager`
- Validate approach for `enabledLLMStore` initialization

#### JSONParser.swift & Related
**Paths:**
- `/PhysCloudResume/Shared/Utilities/JSONParser.swift`
- `/PhysCloudResume/ResumeTree/Utilities/JsonToTree.swift`
- `/PhysCloudResume/ResumeTree/Utilities/TreeToJson.swift`

**Status:** 🔴 Replace entirely
**Review Points:**
- Confirm all usage points before removal
- Verify template compatibility after replacement
- Test with complex resume structures
- Check OrderedCollections dependency removal impact

### 2. Services Requiring DI Conversion

#### Singleton Services
**Files to review for singleton patterns:**
```
✅ Already uses DI (no change needed):
- JobAppStore.swift
- ResStore.swift
- CoverLetterStore.swift

🔴 True singletons (need conversion):
- OpenRouterService.swift (line: static let shared)
- LLMService.swift (verify singleton usage)
- ModelValidationService.swift (line: static let shared)
- Logger.swift (static methods)
```

**Review Points:**
- Identify all call sites using `.shared`
- Plan migration order to minimize breakage
- Verify no circular dependencies

### 3. UI Components with Mixed Concerns

#### Views Directly Modifying Models
**High Priority Files:**
```
/PhysCloudResume/ResumeTree/Views/NodeLeafView.swift
- Direct TreeNode manipulation
- Force unwrapping concerns
- Mixed UI/business logic

/PhysCloudResume/ResumeTree/Views/FontNodeView.swift
- Direct model updates
- Persistence triggering from view

/PhysCloudResume/Sidebar/Views/SidebarView.swift
- Complex filtering logic
- Direct store access
```

**Review Points:**
- Determine which logic belongs in services
- Identify reusable patterns
- Plan extraction strategy

### 4. Areas Needing Clarification

#### Menu/Toolbar Notification System
**Path:** `/PhysCloudResume/App/Views/MenuNotificationHandler.swift`
**Status:** ✅ Keep as-is (platform requirement)
**Clarification Needed:**
- Document why this pattern is necessary for macOS
- List all notification names and their purposes
- Verify no expansion beyond menu/toolbar coordination

#### Resume Model Structure
**Path:** `/PhysCloudResume/Resumes/Models/Resume.swift`
**Status:** ⚠️ Partially refactor
**Questions:**
- Why is conversation management referenced here? (line 11-18)
- What's the relationship with ResModel? (line 72)
- Purpose of `needToTree` and `needToFont` flags?
- Debounce export mechanism - where implemented?

#### TreeNode Status System
**Path:** `/PhysCloudResume/ResumeTree/Models/TreeNodeModel.swift`
**Status:** ✅ Keep structure
**Clarification Needed:**
- LeafStatus enum purposes (especially `aiToReplace`)
- When is `isTitleNode` used?
- Index management strategy for reordering

### 5. External Dependencies

#### SwiftOpenAI Integration
**Review Points:**
- How tightly coupled is LLMService to SwiftOpenAI types?
- Can we abstract without losing streaming functionality?
- What's in the custom fork at `~/devlocal/codebase/SwiftOpenAI-ttsfork`?

#### ChunkedAudioPlayer
**Local path:** `~/devlocal/swift-chunked-audio-player`
**Questions:**
- How is this integrated?
- Any refactoring impact?

### 6. Data Migration Concerns

#### SwiftData Models
**Critical Models:**
```
- JobApp.swift
- Resume.swift
- TreeNode.swift
- FontSizeNode.swift
- EnabledLLM.swift
```

**Review Before Changes:**
- Current relationships and delete rules
- Any custom migration code
- Impact of structure changes on existing data

### 7. Template System

#### Template Processing
**Path:** `/PhysCloudResume/Shared/Utilities/ResumeTemplateProcessor.swift`
**Status:** ✅ Works well
**Verify:**
- Template loading from Documents folder override
- Handlebars processing pipeline
- Context structure expected by templates

#### Template Files
**Path:** `/PhysCloudResume/Resources/Templates/`
**Review:**
- Document expected data structure
- List all template variables used
- Ensure backward compatibility

### 8. Performance Hotspots

#### Files to Profile Before Optimizing:
```
NativePDFGenerator.swift - @MainActor usage
ResumeExportService.swift - UI blocking?
WebViewHTMLFetcher.swift - Memory usage
CloudflareCookieManager.swift - Cookie persistence
```

### 9. Error Handling Audit

#### Files with Silent Failures:
```bash
# Files with empty catch blocks (priority for fixing):
grep -l "} catch {}" --include="*.swift" -r .

# Files with force unwrapping (crash risks):
grep -l "!\\." --include="*.swift" -r . | head -20

# Files with fatalError (2 known):
- JsonToTree.swift (being replaced)
- ImageButton.swift (needs fixing)
```

### 10. Dead Code Candidates

#### Potentially Unused:
```
- RefreshJobApps notification (confirmed unused)
- Import job apps functionality (commented out)
- Old migration code in AppState
- Deprecated resumeapi service (if still exists)
```

**Verification Needed:**
```bash
# Check for orphaned files
find . -name "*.swift" -type f | xargs grep -L "class\|struct\|enum\|protocol"

# Find TODO/FIXME comments
grep -r "TODO\|FIXME\|HACK" --include="*.swift"
```

---

## Pre-Refactoring Checklist

### Must Review Before Starting:

1. **AppState.swift** - Understand all responsibilities
2. **JSONParser usage** - Map all dependencies
3. **Singleton call sites** - Find all `.shared` references
4. **Template contracts** - Document expected structure
5. **Force unwrap locations** - Prioritize critical paths

### Questions for Stakeholders:

1. **AI Integration:**
   - Is conversation management still needed in Resume model?
   - What's special about the SwiftOpenAI fork?
   - Any planned AI feature changes?

2. **Data Persistence:**
   - Any custom migration requirements?
   - Backup strategy for SwiftData?
   - User data preservation needs?

3. **Template System:**
   - Any custom templates in production?
   - Template authoring documentation needed?
   - Backward compatibility requirements?

4. **Performance:**
   - Current performance bottlenecks?
   - PDF generation time expectations?
   - Memory usage constraints?

### Tools Needed for Analysis:

```bash
# Dependency graph
swift package show-dependencies

# Find all singletons
grep -r "static let shared" --include="*.swift"

# Find all force unwraps
grep -r "!\\." --include="*.swift" | wc -l

# Find NotificationCenter usage
grep -r "NotificationCenter" --include="*.swift"

# Memory profiling targets
grep -r "@MainActor" --include="*.swift" | grep "class"
```

---

## Risk Areas

### High Risk (Need careful attention):
- JSON parser replacement (core functionality)
- AppState decomposition (touches everything)
- SwiftData model changes (data loss potential)

### Medium Risk (Standard refactoring):
- Singleton elimination
- Force unwrap removal
- Service extraction

### Low Risk (Safe improvements):
- Dead code removal
- Error handling improvements
- Configuration centralization

---

## Recommended Review Order

1. **Week 0:** Review this document with team
2. **Week 0:** Clarify all questions above
3. **Week 1:** Deep dive on JSON/Template system
4. **Week 1:** Map all singleton usage
5. **Week 2:** Begin refactoring per roadmap

---

## Notes

- Several "problems" mentioned in both plans don't actually exist
- JobAppStore already uses DI - no changes needed
- ResumeDetailVM is reasonably sized - minimal refactoring needed
- NotificationCenter pattern for menus is correct - document but don't change
- Focus on actual problems: JSON parser, AppState, true singletons