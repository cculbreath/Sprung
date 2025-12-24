# Core Features Refactoring Plan

## Overview

This plan addresses issues identified in all non-onboarding modules: Resume system, Job Applications, Export, SearchOps, Shared AI services, Templates, and Cover Letters.

**Guiding Principle:** If adopting a new paradigm, fully implement it. Delete old code completely. No backwards compatibility. No data migration required.

---

## Work Streams (Parallelizable)

The refactoring is organized into **6 independent work streams** that can be executed in parallel by AI subagents.

### Work Stream 1: Legacy Model Deletion (SearchOps)

**Scope:** Complete removal of deprecated `JobLead` model and all supporting code.

**Files Affected:**
- `Sprung/SearchOps/Models/JobLead.swift`
- `Sprung/SearchOps/Stores/JobLeadStore.swift`
- `Sprung/SearchOps/Services/SearchOpsPipelineCoordinator.swift`
- `Sprung/DataManagers/SchemaVersioning.swift` (or wherever `SprungSchema` is defined)

**Tasks:**

1. **Delete `JobLead.swift` entirely**
   - Remove the file from the project
   - Do NOT keep as deprecated, do NOT comment out

2. **Delete `JobLeadStore.swift` entirely**
   - Remove the file from the project

3. **Update `SearchOpsPipelineCoordinator`**
   - Remove `self.jobLeadStore = JobLeadStore(context:)` initialization
   - Replace with `JobAppStore` usage
   - Update all methods that reference `JobLeadStore`

4. **Update `SprungSchema.models`**
   - Remove `JobLead.self` from the schema models array
   - Verify no orphaned references remain

5. **Search and destroy all `JobLead` references**
   - `grep -r "JobLead" Sprung/`
   - Delete every reference found

**Commit Cadence:** Single commit after all deletions complete, titled "Remove deprecated JobLead model and store"

---

### Work Stream 2: AI Service Layer Consolidation

**Scope:** Simplify the confusing LLM service architecture into a single entry point.

**Files Affected:**
- `Sprung/Shared/AI/Models/Services/LLMFacade.swift`
- `Sprung/Shared/AI/Models/Services/_LLMService.swift`
- `Sprung/Shared/AI/Models/Services/_LLMRequestExecutor.swift`
- `Sprung/Shared/AI/Models/LLM/LLMClient.swift`
- `Sprung/App/AppDependencies.swift`

**Tasks:**

1. **Audit current architecture**
   - Map which callers use `LLMFacade` vs `_LLMService` vs `LLMClient`
   - Document the streaming setup path vs direct execution path

2. **Consolidate into `LLMFacade`**
   - Move all `_LLMService` functionality into `LLMFacade`
   - `LLMFacade` becomes the sole public interface
   - Internal implementation can use `LLMClient` and executor

3. **Delete or mark truly private**
   - If `_LLMService` logic is absorbed, delete the file
   - If kept, rename to remove underscore prefix OR make `internal`
   - Remove from `AppDependencies` public exposure

4. **Update all callers**
   - Every call site should go through `LLMFacade`
   - No direct `_LLMService` or `LLMClient` access from outside the AI module

5. **Verify `OpenAIResponsesConversationService.onboardingToolSchemas`**
   - Returns empty array - determine if dead code
   - If dead, delete the property
   - If needed for onboarding, implement properly

**Commit Cadence:** Commit after architecture audit, commit after consolidation, commit after caller updates.

---

### Work Stream 3: Resume Review Service Unification

**Scope:** Merge duplicate resume review logic into a single service.

**Files Affected:**
- `Sprung/Resumes/AI/Services/ResumeReviewService.swift`
- `Sprung/Resumes/AI/Services/ResumeReviseViewModel.swift`
- `Sprung/Resumes/AI/Types/ResumeQuery.swift`

**Tasks:**

1. **Audit both review paths**
   - `ResumeReviewService`: "Assess Quality", "Fix Overflow", "Reorder Skills"
   - `ResumeReviseViewModel`: "Customize", "Clarify", "Phase Review"
   - Document prompt builders: `ResumeReviewQuery` vs `ResumeApiQuery`

2. **Design unified architecture**
   - Single `ResumeAIService` for all review operations
   - Or: "Fix Overflow" and "Reorder" become workflows in `ResumeReviseViewModel`
   - Decide on single prompt builder or adapter pattern

3. **Implement unification**
   - Merge prompt construction logic
   - Merge response handling logic
   - Use consistent patterns throughout

4. **Extract Tools logic from ViewModel**
   - Move `showSkillExperiencePicker`, `pendingSkillQueries` to `ResumeToolsViewModel`
   - `ResumeReviseViewModel` delegates to focused sub-ViewModels
   - Reduce property/method count from 30+ to manageable size

5. **Delete redundant service**
   - Whichever service is absorbed, delete it entirely
   - Do not leave deprecated stubs

**Commit Cadence:** Commit after audit documentation, commit after each phase of unification.

---

### Work Stream 4: Web Resource & HTML Fetching

**Scope:** Consolidate duplicate HTML fetchers into unified service.

**Files Affected:**
- `Sprung/JobApplications/Utilities/WebViewHTMLFetcher.swift`
- `Sprung/JobApplications/Utilities/HTMLFetcher.swift`
- `Sprung/JobApplications/Models/JobApp.swift` (importFromIndeed)
- `Sprung/Export/NativePDFGenerator.swift`

**Tasks:**

1. **Create `WebResourceService`**
   - Internal strategy: try URLSession first, fallback to WKWebView
   - Single public API: `func fetchHTML(from url: URL) async throws -> String`
   - Encapsulate retry logic and fallback internally

2. **Delete separate fetcher files**
   - Delete `WebViewHTMLFetcher.swift`
   - Delete `HTMLFetcher.swift`

3. **Update all call sites**
   - `JobApp.importFromIndeed` uses `WebResourceService`
   - Any other HTML fetching uses same service

4. **Fix Chrome executable detection**
   - Replace hardcoded paths with `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`
   - Try "com.google.Chrome", "org.chromium.Chromium", etc.
   - If all fail, show user-facing error with option to select browser
   - Delete hardcoded path array

5. **Improve scraping error handling**
   - `AppleJobScrape.swift`: Replace silent failures with thrown errors
   - Define `ParsingError` enum: `.titleNotFound`, `.bodyNotFound`, etc.
   - Propagate to UI so user knows why import failed

**Commit Cadence:** Commit after `WebResourceService` creation, commit after deleting old fetchers, commit after Chrome fix.

---

### Work Stream 5: Template System Type Safety

**Scope:** Replace stringly-typed manifest system with compile-time safe types.

**Files Affected:**
- `Sprung/Templates/Utilities/TemplateManifestDefaults.swift`
- `Sprung/Templates/Models/TemplateManifest.swift`
- Template-related files using string keys

**Tasks:**

1. **Create `StandardSection` enum**
   ```swift
   enum StandardSection: String, CaseIterable {
       case summary, work, volunteer, education, projects
       case skills, awards, certificates, publications
       case languages, interests, references, custom, styling
   }
   ```

2. **Replace string arrays with enum arrays**
   - `defaultSectionOrder` becomes `[StandardSection]`
   - `recommendedFontSizes` keys become `StandardSection`
   - All manifest defaults use enum

3. **Update manifest readers**
   - Parse section names through enum
   - Fail fast on unknown section names (compile-time where possible)

4. **Audit and fix dead code**
   - `TemplateFilters.htmlStripFilter`: Check if any template uses it
   - If unused, delete entirely
   - `TextResumeGenerator.convertEmploymentToArray`: Check if flat dict path is dead
   - If dead (Tree always exists), delete fallback logic

5. **Create unit test for tool names**
   - Ensure `SearchOpsToolName` raw values match JSON schema filenames
   - Prevent silent failures from file renames

**Commit Cadence:** Commit after enum creation, commit after each manifest migration.

---

### Work Stream 6: Shared Utilities & Cleanup

**Scope:** Consolidate duplicate utilities, remove dead code, improve logging.

**Files Affected:**
- `Sprung/CoverLetters/AI/Services/CoverLetterService.swift`
- `Sprung/Shared/Utilities/LLMResponseParser.swift`
- `Sprung/Shared/AI/Models/LLM/LLMVendorMapper.swift`
- `Sprung/App/Views/AppSheets.swift`

**Tasks:**

1. **Consolidate JSON extraction**
   - `CoverLetterService.extractCoverLetterContent` duplicates `LLMResponseParser.extractJSONFromText`
   - Delete method from `CoverLetterService`
   - Use shared `LLMResponseParser` utility

2. **Verify `reasoningContent` mapping**
   - `LLMVendorMapper.streamChunkDTO`: Maps `reasoningContent`
   - Verify OpenRouter/SwiftOpenAI actually returns this field
   - If not returned, delete the mapping code

3. **Break down `AppSheetsModifier`**
   - Extract `ResumeSheets` modifier
   - Extract `NetworkingSheets` modifier
   - Extract `JobAppSheets` modifier
   - `AppSheetsModifier` composes the domain modifiers

4. **Improve logger subsystems**
   - Ensure unique subsystem per module for Console.app filtering
   - Example: `com.sprung.ai`, `com.sprung.data`, `com.sprung.export`

5. **Check `TemplateEditorOverlayOptionsView`**
   - `loadOverlayPDF` handles security scoped resources
   - If permissions aren't persisted across restarts, feature is broken
   - Fix persistence or remove the feature

**Commit Cadence:** Commit after each consolidation/cleanup task.

---

## Sequential Dependencies

Most streams are fully independent. Observe these minimal dependencies:

1. **Stream 1 (JobLead deletion)** is fully independent - start immediately
2. **Stream 2 (AI consolidation)** is fully independent - start immediately
3. **Stream 3 (Resume review)** may benefit from **Stream 2** completing first for cleaner LLM usage
4. **Stream 4 (Web resources)** is fully independent - start immediately
5. **Stream 5 (Templates)** is fully independent - start immediately
6. **Stream 6 (Utilities)** is fully independent - start immediately

**Recommended execution:** All streams can start in parallel.

---

## Deleted Items Checklist

The following MUST be deleted (not deprecated—deleted):

- [ ] `JobLead.swift` - entire file
- [ ] `JobLeadStore.swift` - entire file
- [ ] `JobLead.self` from `SprungSchema.models`
- [ ] `_LLMService` if fully absorbed into `LLMFacade`
- [ ] `HTMLFetcher.swift` - after consolidation
- [ ] `WebViewHTMLFetcher.swift` - after consolidation
- [ ] Hardcoded Chrome paths array
- [ ] `CoverLetterService.extractCoverLetterContent` - duplicate
- [ ] `TemplateFilters.htmlStripFilter` - if unused
- [ ] `TextResumeGenerator` flat dictionary fallback - if dead code
- [ ] `ResumeReviewService` or duplicate portions - after merge
- [ ] `OnboardingToolSchemas` empty array property - if dead code

---

## Verification Criteria

After refactoring, verify:

1. **No `JobLead` references** anywhere in codebase
2. **Single LLM entry point** - all calls go through `LLMFacade`
3. **Single resume review service** - no duplicate logic
4. **Single HTML fetcher** - `WebResourceService` only
5. **No stringly-typed section keys** - all use `StandardSection` enum
6. **No duplicate JSON extraction utilities**
7. **No hardcoded executable paths** - use bundle identifier lookup
8. **User-facing errors for scraping failures** - no silent fails
9. **Build succeeds** with no deprecation warnings for removed types
