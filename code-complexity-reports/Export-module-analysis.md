# Architecture Analysis: Export Module

**Analysis Date**: October 20, 2025
**Subdirectory**: `/Users/cculbreath/devlocal/codebase/Sprung/Sprung/Export/`
**Total Swift Files Analyzed**: 3

## Executive Summary

The Export module is a well-structured, recently refactored component that handles PDF and text resume generation. The architecture demonstrates a clear **separation of concerns** with three focused classes: a service orchestrator (`ResumeExportService`), a PDF generator (`NativePDFGenerator`), and a text generator (`TextResumeGenerator`). The module successfully abstracts the complexity of template rendering, format conversion, and output generation behind clean interfaces.

However, the module exhibits **moderate levels of unnecessary complexity**, primarily in the `NativePDFGenerator` class, which combines WebKit PDF generation, template rendering, context building, and data transformation logic. While the recent extraction of template data processing into the `TemplateData` module is commendable, some responsibilities within the Export module are still overloaded and could benefit from further decomposition.

**Key Concerns**:
1. `NativePDFGenerator` handles too many concerns (503 lines) - rendering, context building, validation, and PDF generation
2. Significant duplication between PDF and text template rendering pipelines
3. Complex context preprocessing logic mixed with generation logic
4. Error handling relies on catching specific errors and retrying with fallbacks, which could be cleaner

## Overall Architecture Assessment

### Architectural Style

The Export module employs a **layered service architecture** with specialized generators:

```
┌─────────────────────────────────────────┐
│    ResumeExportService (@MainActor)     │  Orchestrator
│  - Manages export flow                  │
│  - Selects between PDF/text paths       │
│  - Handles template resolution          │
└─────────────────────────────────────────┘
            │                    │
            ▼                    ▼
    ┌───────────────┐      ┌──────────────┐
    │NativePDFGen   │      │TextResumeGen │  Generators
    │  (WebKit)     │      │  (Mustache)  │
    └───────────────┘      └──────────────┘
            │                    │
            └────────┬───────────┘
                     ▼
    ┌─────────────────────────────────────┐
    │   TemplateData Module               │  Shared Services
    │ - ResumeTemplateDataBuilder         │
    │ - HandlebarsContextAugmentor        │
    │ - TemplateFilters                   │
    └─────────────────────────────────────┘
```

This is a **reasonable architecture** for export functionality but with notable areas of improvement.

### Strengths

1. **Clear Responsibility Separation**: Each class has a primary focus - service coordination, PDF generation, and text generation
2. **Dependency Injection**: Both generators receive `TemplateStore` and/or `ApplicantProfileStore` via constructor injection
3. **Main Thread Enforcement**: All three classes are marked with `@MainActor`, enforcing thread safety for UI-related work
4. **Shared Template Data Infrastructure**: Leverages `TemplateData` module utilities effectively
5. **Error Type Definitions**: Custom error types (`ResumeExportError`, `PDFGeneratorError`) with localized descriptions
6. **Async/Await**: Proper use of async/await for non-blocking operations
7. **Debug Support**: Thoughtful debug file saving capability for development
8. **Template Fallback Logic**: Handles missing templates gracefully by prompting for custom templates

### Concerns

1. **NativePDFGenerator is a God Class** (503 lines):
   - Combines template rendering, context building, validation, and PDF generation
   - Contains 15+ private methods handling disparate concerns
   - Mixed responsibilities make testing difficult

2. **Duplication Between Text and PDF Paths**:
   - Both `NativePDFGenerator.renderTemplate()` and `TextResumeGenerator.renderTemplate()` follow similar pipelines
   - Context building, Handlebars translation, and Mustache rendering are duplicated
   - Changes to the template pipeline require updates in multiple places

3. **Complex Context Building**:
   - `NativePDFGenerator.preprocessContextForTemplate()` has intricate nested logic (60+ lines)
   - Profile binding resolution and section visibility logic is tightly coupled
   - Mixing of concerns: merging dicts, type checking, boolean conversions

4. **WebView State Management**:
   - `NativePDFGenerator` maintains `currentCompletion` callback state
   - Continuation-based async pattern is necessary but adds complexity
   - Weak self captured in multiple closures increases memory management burden

5. **Async Continuation Pattern Complexity**:
   - `generatePDF()` and `generatePDFFromCustomTemplate()` use `withCheckedThrowingContinuation` with nested `Task`
   - The pattern requires careful coordination between WebView delegate callbacks and completion handlers
   - Hard to test due to WebView dependency

6. **Font Reference Manipulation**:
   - Regex-based font URL stripping is a workaround for macOS system font limitations
   - Fragile approach that could break with template variations

### Complexity Rating

**Rating**: **Medium-High** (6/10)

**Justification**:
- The 855 total lines across 3 files is reasonable for export functionality
- However, line distribution is unbalanced: NativePDFGenerator (59%), TextResumeGenerator (24%), ResumeExportService (17%)
- `NativePDFGenerator` handles ~8-10 distinct concerns, which is excessive for a single class
- The template rendering duplication between PDF and text paths increases cognitive complexity
- Context preprocessing logic is intricate and difficult to reason about
- WebKit integration adds necessary but inherent complexity

## File-by-File Analysis

### ResumeExportService.swift

**Purpose**: Orchestrates the export workflow, manages template resolution, and coordinates PDF and text generation

**Lines of Code**: 146

**Dependencies**:
- `NativePDFGenerator` (composed)
- `TextResumeGenerator` (composed)
- `TemplateStore` (injected)
- `ExportTemplateSelection` (external utility)

**Complexity**: Low-Medium

**Observations**:

- Clean orchestration logic with clear flow: `export()` → `exportNatively()` → PDF + text generation
- Template resolution is well-structured with fallback logic (lines 52-64)
- The `promptForCustomTemplate()` method creates a custom template with timestamp slug and defaults
- Hardcoded basic text template (lines 99-128) is readable but could be externalized
- Good error handling with custom `ResumeExportError` enum
- Minimal coupling to external concerns

**Recommendations**:
- Consider extracting the hardcoded template string to a resource or constant file
- The `ensureTemplate()` method could be simplified by removing the check on line 55 (templateStore lookup is redundant if template already exists on resume)
- Consider making `defaultTextTemplate()` more testable by extracting it to a helper or strategy
- Add documentation explaining the recovery flow for missing templates

### NativePDFGenerator.swift

**Purpose**: Generates PDF from resume data using WebKit rendering and Mustache template processing

**Lines of Code**: 503

**Dependencies**:
- `WebKit` framework (WKWebView)
- `Mustache` library for template rendering
- `OrderedCollections` (for OrderedDictionary handling)
- `TemplateStore` (injected)
- `ApplicantProfileProviding` (injected protocol)
- `ResumeTemplateDataBuilder` (external service)
- `HandlebarsContextAugmentor` (external helper)
- `TemplateFilters` (external helper)

**Complexity**: High

**Observations**:

1. **Multiple Rendering Paths** (lines 30-85):
   - `generatePDF()`: Standard rendering through `renderTemplate()`
   - `generatePDFFromCustomTemplate()`: Custom template override path
   - Both use continuation-based async but duplicate logic

2. **Template Rendering Pipeline** (lines 100-140):
   - Loads template from store
   - Creates context via `ResumeTemplateDataBuilder`
   - Preprocesses context for template
   - Translates Handlebars to Mustache
   - Registers filters on template
   - Renders to HTML string
   - Saves debug output

3. **Context Building & Preprocessing** (lines 86-209):
   - `renderingContext()` builds raw context and applies augmentation
   - `preprocessContextForTemplate()` merges applicant profile data into template context
   - Complex nested dictionary merging logic (lines 163-172)
   - Section visibility override logic (lines 273-300)

4. **Profile Data Binding** (lines 189-254):
   - Large switch statement mapping profile paths to context values
   - Handles multiple path variants (e.g., "region" or "state")
   - Returns null for empty strings, maintaining template cleanliness

5. **WebView Management**:
   - Single `WKWebView` instance (line 10)
   - Continuation-based completion handler pattern (line 11)
   - Delegate callbacks (lines 462-483) coordinate PDF generation

6. **Utility Methods**:
   - Template preprocessing to handle Handlebars incompatibilities (lines 327-338)
   - Font reference fixing via regex (lines 347-366)
   - Debug HTML saving (lines 368-388)
   - JavaScript-based document height metrics (lines 418-459)

**Code Issues**:

```swift
// Line 163-172: Complex nested dictionary merging
if var existingDict = merged[key] as? [String: Any],
   let newDict = value as? [String: Any] {
    for (subKey, subValue) in newDict {
        existingDict[subKey] = subValue
    }
    merged[key] = existingDict
} else {
    merged[key] = value
}
// This could be extracted to a helper method for reusability
```

```swift
// Line 210-243: Large switch statement
switch first {
case "name": ...
case "email": ...
case "phone": ...
// 16+ cases
default: return nil
}
// Consider replacing with a dictionary-based lookup
```

```swift
// Line 31-45: Continuation with nested Task
return try await withCheckedThrowingContinuation { continuation in
    Task { @MainActor in
        do {
            // ...
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
// The nested Task is necessary for @MainActor, but it's complex
```

**Recommendations**:

1. **Extract Context Building Logic**:
   - Create `TemplateContextProcessor` class to handle all context preprocessing
   - Move `preprocessContextForTemplate()`, `buildApplicantProfileContext()`, and related methods there
   - This would reduce `NativePDFGenerator` to 300-350 lines

2. **Extract WebView PDF Generation**:
   - Create `WebViewPDFRenderer` class encapsulating WebView lifecycle and PDF generation
   - Reduces `NativePDFGenerator` responsibility to template coordination only

3. **Unify Template Rendering Paths**:
   - Extract common template rendering logic to reduce duplication with `TextResumeGenerator`
   - Create `TemplateRenderingService` with methods for context building and Mustache rendering
   - Both PDF and text generators would compose this service

4. **Replace Switch Statement with Strategy Pattern**:
   - Create `ProfilePathResolver` using a dictionary of path components to resolution functions
   - More maintainable and testable than large switch statements

5. **Simplify Error Handling**:
   - The catch-retry pattern (lines 38-44) could be wrapped in a helper method
   - Consider a template resolution service that validates existence before calling

6. **Document WebView Async Pattern**:
   - Add comments explaining why nested `Task` is necessary
   - Document the continuation/completion handler coordination

### TextResumeGenerator.swift

**Purpose**: Generates plain-text resumes by rendering templates with context

**Lines of Code**: 206

**Dependencies**:
- `Mustache` library for template rendering
- `TemplateStore` (injected)
- `ResumeTemplateProcessor` (external service)
- `HandlebarsContextAugmentor` (external helper)
- `TemplateFilters` (external helper)

**Complexity**: Medium

**Observations**:

1. **Rendering Pipeline** (lines 27-43):
   - Load template via `loadTextTemplate()`
   - Create context via `ResumeTemplateProcessor.createTemplateContext()`
   - Preprocess context with `preprocessContextForText()`
   - Apply augmentation via `HandlebarsContextAugmentor`
   - Translate Handlebars and render with Mustache
   - Sanitize output

2. **Context Preprocessing** (lines 67-133):
   - Normalizes contact information into arrays and formatted strings (lines 71-92)
   - Converts employment data to ordered array preserving node indices (lines 94-98)
   - Transforms skills dictionary to array format (lines 100-110)
   - Converts education dictionary to array format (lines 112-123)
   - Cleans HTML from more-info section (lines 125-130)

3. **Data Structure Conversions**:
   - Employment to array (lines 142-171): Complex with tree node ordering
   - Skills normalization: Dictionary to array of title/description pairs
   - Contact items building: Filters and formats address components

4. **String Utilities**:
   - HTML entity decoding and tag removal
   - Consecutive blank line collapsing
   - Whitespace normalization

**Code Observations**:

```swift
// Line 95-98: Uses Resume.rootNode to preserve employment order
if let rootNode = resume.rootNode,
   let employmentSection = rootNode.children?.first(where: { $0.name == "employment" }),
   let employmentNodes = employmentSection.children {
    // Uses tree structure for proper ordering
}
// This tight coupling to tree structure is fragile
```

```swift
// Line 67-133: Large preprocessing method with mixed concerns
// - Contact info normalization
// - Employment array conversion
// - Skills/education transformation
// - HTML cleanup
// Should be split into separate methods
```

**Strengths**:
- Clear separation of public interface (`generateTextResume`) from implementation
- Thoughtful handling of data structure transformations
- Preserves employment order from tree structure
- Proper null handling and empty value filtering

**Recommendations**:

1. **Extract Contact Processing**:
   - Create `ContactInfoProcessor` class for contact item normalization and formatting
   - Reduces preprocessing method complexity

2. **Extract Employment Array Conversion**:
   - Create `EmploymentArrayConverter` to handle tree node ordering and array conversion
   - Makes tree dependency explicit and testable

3. **Unify Context Preprocessing**:
   - `TextResumeGenerator.preprocessContextForText()` and `NativePDFGenerator.preprocessContextForTemplate()` have similar transformations
   - Extract to shared `TemplateContextNormalizer` service

4. **Reduce Preprocessing Method Size**:
   - Current method is 67 lines doing 4+ distinct transformations
   - Break into `normalizeContact()`, `normalizeEmployment()`, `normalizeSkills()`, etc.

5. **Document Tree Node Dependency**:
   - Add comments explaining why tree node structure is needed for proper ordering
   - Consider adding validation that tree structure exists before relying on it

## Identified Issues

### Over-Abstraction Issues

1. **Continuation Pattern in PDF Generation** (NativePDFGenerator.swift, lines 31-45):
   - Using `withCheckedThrowingContinuation` with nested `Task` is abstraction overhead
   - The pattern works but adds complexity for what could be simpler async coordination
   - Necessary due to WebView delegate callback requirements, but worth documenting

### Unnecessary Complexity

1. **Duplicate Template Rendering Pipelines** (Lines duplicated between files):
   ```swift
   // NativePDFGenerator (lines 117-132)
   let rawContext = try createTemplateContext(from: resume)
   let processedContext = preprocessContextForTemplate(rawContext, from: resume)
   let translation = HandlebarsTranslator.translate(fontsFixed)
   let mustacheTemplate = try Mustache.Template(string: finalContent)
   TemplateFilters.register(on: mustacheTemplate)
   let renderedContent = try mustacheTemplate.render(processedContext)

   // TextResumeGenerator (lines 28-42) - nearly identical
   let context = try createTemplateContext(from: resume)
   var processedContext = preprocessContextForText(context, from: resume)
   processedContext = HandlebarsContextAugmentor.augment(processedContext)
   let translation = HandlebarsTranslator.translate(templateContent)
   let mustacheTemplate = try Mustache.Template(string: translation.template)
   TemplateFilters.register(on: mustacheTemplate)
   return try mustacheTemplate.render(processedContext)
   ```
   - Both follow identical Mustache rendering pattern
   - Duplication creates maintenance burden and inconsistency risk

2. **Complex Nested Dictionary Merging** (NativePDFGenerator.swift, lines 163-172):
   - 10-line operation for merging nested dictionaries
   - Could be one-liner with a helper extension
   - Same logic could appear in multiple places

3. **Large Switch Statement for Profile Paths** (NativePDFGenerator.swift, lines 211-243):
   - 33 lines for path-to-value mapping
   - Handles multiple aliases per path (e.g., "region" or "state")
   - Could be more concisely expressed with a dictionary lookup

4. **Regex-Based Font Fixing** (NativePDFGenerator.swift, lines 347-366):
   - Two separate regex patterns for font removal
   - Fragile approach dependent on template structure
   - Better handled at template authoring time or with explicit font handling

### Design Pattern Misuse

1. **Catch-Retry Anti-Pattern** (ResumeExportService.swift, lines 38-44):
   ```swift
   do {
       pdfData = try await nativeGenerator.generatePDF(for: resume, template: slug, format: "html")
   } catch PDFGeneratorError.templateNotFound {
       template = try await promptForCustomTemplate(for: resume)
       slug = template.slug
       pdfData = try await nativeGenerator.generatePDF(for: resume, template: slug, format: "html")
   }
   ```
   - Repeats the same operation after catching a specific error
   - Better expressed as template validation before generation
   - Current pattern masks the underlying issue (template not found) until runtime

2. **Service Locator Pattern** (NativePDFGenerator.swift, lines 154):
   ```swift
   let profile = profileProvider.currentProfile()
   ```
   - While dependency injection is used, the profile provider acts as a service locator
   - Direct calls to `currentProfile()` at multiple points create hidden dependencies
   - Makes testing harder due to stateful profile access

### Error Handling Concerns

1. **Generic NSError** (TextResumeGenerator.swift, line 55):
   ```swift
   throw NSError(domain: "TextResumeGenerator", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Template not found: \(template)"])
   ```
   - Should use custom error type like `TextGeneratorError`
   - `NSError` is less specific and harder to handle programmatically

2. **Silent Error Logging** (TextResumeGenerator.swift & NativePDFGenerator.swift):
   - Errors are logged via `Logger` but original errors aren't propagated with context
   - Stack traces may be lost during translation operations

3. **Exception Swallowing in Context Building** (NativePDFGenerator.swift, lines 391-405):
   ```swift
   if let metrics = try? await fetchDocumentHeightMetrics(from: webView) {
       Logger.debug(...)
   }
   ```
   - Errors are silently ignored in debug-only block
   - Should at least log failures for troubleshooting

## Recommended Refactoring Approaches

### Approach 1: Extract Shared Template Rendering Service

**Effort**: Medium
**Impact**: Eliminates 50+ lines of duplication, improves maintainability, enables consistent template processing

**Steps**:

1. Create `TemplateRenderingService` struct:
   ```swift
   struct TemplateRenderingService {
       private let templateStore: TemplateStore

       func renderTemplate<T>(
           content: String,
           context: [String: Any],
           handler: (Mustache.Template) -> throws -> T
       ) throws -> T
   }
   ```

2. Extract common pipeline:
   - Template loading validation
   - Handlebars translation
   - Filter registration
   - Rendering execution

3. Update both generators to use service:
   ```swift
   // Before
   let translation = HandlebarsTranslator.translate(fontsFixed)
   let mustacheTemplate = try Mustache.Template(string: finalContent)
   TemplateFilters.register(on: mustacheTemplate)
   let htmlContent = try mustacheTemplate.render(context)

   // After
   let htmlContent = try renderingService.renderTemplate(content: finalContent, context: context) { template in
       try template.render(context)
   }
   ```

4. Add configuration points for PDF-specific behaviors (font fixing, CSS injection)

### Approach 2: Extract Context Building into Dedicated Service

**Effort**: Medium
**Impact**: Reduces NativePDFGenerator from 503 to ~300 lines, improves testability, centralizes context logic

**Steps**:

1. Create `TemplateContextBuilder` class:
   ```swift
   @MainActor
   class TemplateContextBuilder {
       private let templateStore: TemplateStore
       private let profileProvider: ApplicantProfileProviding

       func buildRenderingContext(for resume: Resume) throws -> [String: Any]
       func preprocessContext(_ context: [String: Any], for resume: Resume) -> [String: Any]
       func buildApplicantProfileContext(profile: ApplicantProfile, manifest: TemplateManifest) -> [String: Any]
       func applySectionVisibility(context: inout [String: Any], manifest: TemplateManifest, resume: Resume)
   }
   ```

2. Move methods from NativePDFGenerator:
   - `preprocessContextForTemplate()`
   - `buildApplicantProfileContext()`
   - `applicantProfileValue()`
   - `setProfileValue()`
   - `applySectionVisibility()`
   - `dictionaryValue()`
   - `truthy()`

3. NativePDFGenerator becomes coordinator:
   ```swift
   @MainActor
   class NativePDFGenerator {
       private let contextBuilder: TemplateContextBuilder
       private let webViewRenderer: WebViewPDFRenderer

       func generatePDF(for resume: Resume, template: String) async throws -> Data
   }
   ```

4. Enables independent unit testing of context building logic

### Approach 3: Simplify Template Resolution with Strategy Pattern

**Effort**: Low
**Impact**: Eliminates catch-retry pattern, centralizes template logic

**Steps**:

1. Create `TemplateResolutionStrategy`:
   ```swift
   protocol TemplateResolutionStrategy {
       func resolveTemplate(for resume: Resume) async throws -> Template
   }
   ```

2. Implementations:
   - `DefaultTemplateStrategy`: Use resume's existing template
   - `FallbackTemplateStrategy`: Use app default
   - `CustomTemplateStrategy`: Prompt user for custom template

3. Update ResumeExportService:
   ```swift
   private let resolutionStrategies: [TemplateResolutionStrategy]

   private func resolveTemplate(for resume: Resume) async throws -> Template {
       for strategy in resolutionStrategies {
           if let template = try await strategy.resolveTemplate(for: resume) {
               return template
           }
       }
       throw ResumeExportError.noTemplatesConfigured
   }
   ```

4. Removes the catch-retry anti-pattern entirely

### Approach 4: Extract WebView PDF Generation Layer

**Effort**: Medium
**Impact**: Isolates WebView complexity, simplifies NativePDFGenerator core logic, improves testability

**Steps**:

1. Create `WebViewPDFRenderer`:
   ```swift
   @MainActor
   class WebViewPDFRenderer {
       private var webView: WKWebView
       private var currentCompletion: ((Result<Data, Error>) -> Void)?

       func renderPDF(from htmlContent: String) async throws -> Data
       private func generatePDFFromWebView() async throws -> Data
       // Delegate methods...
   }
   ```

2. Move from NativePDFGenerator:
   - WebView setup and lifecycle
   - PDF generation via WKPDFConfiguration
   - WKNavigationDelegate implementation
   - Continuation coordination

3. NativePDFGenerator uses renderer:
   ```swift
   let pdfRenderer = WebViewPDFRenderer()
   let htmlContent = try renderTemplate(for: resume, template: slug)
   let pdfData = try await pdfRenderer.renderPDF(from: htmlContent)
   ```

## Simpler Alternative Architectures

### Alternative 1: Unified Pipeline Architecture

**Concept**: Single `TemplateProcessor` handles all template rendering variations

```
Resume
   ▼
┌──────────────────────────────────┐
│   TemplateProcessor              │
│ - Builds context                 │
│ - Translates Handlebars          │
│ - Renders via Mustache           │
│ - Applies output transforms      │
└──────────────────────────────────┘
   ▼                          ▼
┌────────────────┐    ┌────────────────┐
│ PDFTransform   │    │ TextTransform   │
│ - CSS inject   │    │ - HTML decode   │
│ - WebView PDF  │    │ - Sanitize      │
└────────────────┘    └────────────────┘
   ▼                          ▼
 PDF Data                Text String
```

**Pros**:
- Eliminates rendering duplication
- Single path for context building
- Easier to maintain template changes
- Better testing - test processor once, test transforms separately

**Cons**:
- Less flexibility for format-specific optimizations
- May require more abstraction to handle PDF-specific needs (CSS, WebView)

### Alternative 2: Plugin-Based Format Architecture

**Concept**: Format handlers are pluggable, each implementing a format protocol

```
interface FormatHandler {
    func render(context: [String: Any], template: String) async throws -> OutputData
}

struct PDFFormatHandler: FormatHandler
struct TextFormatHandler: FormatHandler

class TemplateExportEngine {
    var handlers: [String: FormatHandler] = [:]
    func export(resume: Resume, format: String) async throws
}
```

**Pros**:
- Highly extensible for new formats (DOCX, LaTeX, etc.)
- Clear separation of format-specific logic
- Easier to add new formats without modifying core

**Cons**:
- More indirection and abstraction
- Shared logic (context building) still needs coordination

## Conclusion

The Export module demonstrates **solid architectural thinking** with clear responsibility boundaries and proper use of dependency injection. The recent refactoring to separate template data processing into the `TemplateData` module was a good decision that reduced Export module complexity.

However, the module has reached a point where **incremental complexity accumulation** is beginning to impact maintainability. The NativePDFGenerator class, in particular, has become a focal point of multiple concerns:

1. Template rendering coordination
2. Context building and preprocessing
3. WebKit-based PDF generation
4. Debug support and metrics

### Prioritized Recommendations

**High Priority** (Do First):
1. **Extract Shared Template Rendering** (Approach 1): Removes immediate duplication between PDF and text paths, enables consistent pipeline changes
2. **Create Custom Error Types**: Replace `NSError` with domain-specific error types for better error handling

**Medium Priority** (Do Next):
3. **Extract Context Building Service** (Approach 2): Reduces NativePDFGenerator complexity by 40%, improves testability
4. **Simplify Template Resolution** (Approach 3): Removes catch-retry pattern, cleaner error handling

**Lower Priority** (Nice to Have):
5. **Extract WebView PDF Generation** (Approach 4): Only needed if you plan to support alternative PDF backends
6. **Extract Contact/Employment Processing**: Reduces TextResumeGenerator complexity further

### Key Metrics

| Metric | Value | Assessment |
|--------|-------|-----------|
| Total LOC | 855 | Reasonable for export module |
| Max Class Size | 503 (NativePDFGenerator) | Too large, should be 250-350 |
| Duplication Ratio | ~15-20% | Moderate, addressable |
| Error Type Consistency | 2/3 files | Should standardize |
| Class Cohesion | Medium | NativePDFGenerator needs decomposition |
| Testability | Medium | Context building is hard to test |
| Documentation | Moderate | Complex patterns need more comments |

### Next Steps

1. Create the `TemplateRenderingService` to eliminate immediate duplication
2. Extract context building into dedicated service class
3. Add comprehensive comments explaining WebView continuation pattern
4. Consider adding unit tests for context building and preprocessing logic
5. Review template resolution error handling and implement strategy pattern

The module is **production-ready and functional**, but strategic refactoring following these recommendations would make it significantly more maintainable and testable for future feature additions.
