# Architecture Analysis: Experience Module

**Analysis Date**: October 20, 2025
**Subdirectory**: `/Users/cculbreath/devlocal/codebase/Sprung/Sprung/Experience/`
**Total Swift Files Analyzed**: 12

## Executive Summary

The Experience module manages professional experience data (work, education, skills, projects, etc.) through a well-structured but highly repetitive architecture. The module demonstrates solid separation of concerns with clear layers (models, services, utilities, views), but suffers from significant code duplication due to the eleven similar experience sections handled through parallel object hierarchies. The architecture is fundamentally sound but operates at excessive complexity for what could be simplified through generic abstractions. Total module size: 4,434 lines of Swift code.

**Key Concerns**: Massive code repetition across section types (11 similar models, 11 identical view section patterns, repetitive encoder/decoder methods), tight coupling between model and view layers, and a lack of generic abstractions that could eliminate 60-70% of boilerplate code.

## Overall Architecture Assessment

### Architectural Style

The Experience module employs a **Layered Architecture** with explicit separation:

1. **Models Layer** (1,247 LOC across 2 files):
   - `ExperienceDefaults.swift`: SwiftData models and relationships (11 section-specific classes)
   - `ExperienceDrafts.swift`: Value type drafts for editing (11 section-specific structs)
   - `ExperienceSchema.swift`: Static schema definition (metadata about sections)

2. **Services Layer** (110 LOC):
   - `CareerKeywordStore.swift`: Singleton service managing keyword autocomplete

3. **Utilities Layer** (445 LOC):
   - `ExperienceDefaultsEncoder.swift`: Converts models to dictionary format
   - `ExperienceDefaultsDecoder.swift`: Parses JSON to models
   - (Note: Primary orchestration via `ExperienceDefaultsStore` in DataManagers)

4. **Views Layer** (2,273 LOC across 6 files):
   - `ExperienceEditorView.swift`: Main container managing 11 sections
   - `ExperienceEditorSectionViews.swift`: 11 section views with identical patterns
   - `ExperienceEditorEntryViews.swift`: Editor/summary views for each section type
   - `ExperienceEditorComponents.swift`: Shared UI components
   - `ExperienceEditorListEditors.swift`: List editing helpers
   - `ExperienceSectionBrowserView.swift`: Section enable/disable panel

**Data Flow**:
```
ExperienceEditorView (main)
  ↓ (loads draft via ExperienceDefaultsStore)
ExperienceDefaultsDraft (working copy)
  ↓ (conditional rendering by section)
[Work|Volunteer|Education|Project|Skill|Award|Certificate|Publication|Language|Interest|Reference]ExperienceSectionView
  ↓ (each item shows summary or editor)
[Type]ExperienceEditor or [Type]ExperienceSummaryView
  ↓ (on save)
ExperienceDefaultsEncoder converts to seed dictionary
```

### Strengths

- **Clear Separation of Concerns**: Models, services, utilities, and views are properly separated with minimal cross-cutting concerns
- **Consistent Patterns**: Each section type follows an identical, predictable implementation pattern, making it easy to understand and extend
- **Draft Pattern**: Use of immutable draft structs with `ExperienceDefaultsDraft` provides excellent undo/cancel capability
- **Two-Way Binding**: Smart use of SwiftUI binding callbacks (`onChange`) ensures UI state and model state stay synchronized
- **Schema-Driven**: `ExperienceSchema` provides a single source of truth for field definitions across the module
- **Drag-and-Drop Support**: Elegant reordering implementation with generic drop delegates
- **Main Actor Safety**: Appropriate use of `@MainActor` on observable stores and UI components
- **Comprehensive Field Coverage**: All JSON resume fields are properly modeled and editable

### Concerns

- **Massive Code Repetition**: 11 nearly identical copies of section view logic, editor logic, model definitions. Lines like `case .work`, `case .volunteer`, etc. repeated throughout
- **Model Explosion**: 31 separate model/struct classes for what could be 2-3 generic types:
  - ExperienceDefaults + 11 specific types (WorkExperienceDefault, VolunteerExperienceDefault, etc.)
  - ExperienceDefaultsDraft + 11 specific types (WorkExperienceDraft, VolunteerExperienceDraft, etc.)
  - Nested types for arrays (WorkHighlightDefault, EducationCourseDefault, etc.)
  - Draft versions of nested types
- **Boilerplate Encoder/Decoder**: 232 lines of nearly identical encoding logic (11 section types × 20 LOC each)
- **Tight View/Model Coupling**: Section views are tightly bound to specific draft types; no protocol abstraction
- **Manual Switch Statements**: In `ExperienceSectionBrowserView` (87-113), manual switch for binding each section's toggle state
- **Repetitive String Constants**: Section titles, field names, add button labels defined in multiple places
- **No Generic Drop Delegates**: Drag-and-drop delegates are generalized but still require separate instantiation for each section type

### Complexity Rating

**Rating**: **High**
**Justification**: The module operates at HIGH complexity primarily due to code repetition rather than algorithmic complexity. The core logic is straightforward (edit, save, reorder), but it's repeated 11 times with section-specific variations. The architecture itself is reasonable, but the implementation takes a "copy-paste and adjust names" approach instead of leveraging Swift's generics and protocols. For comparison:
- A minimally complex version would use 1-2 generic types with metadata
- The current version has ~4,400 LOC spread across 12 files
- A refactored version could achieve the same functionality in ~1,200 LOC

## File-by-File Analysis

### Models/ExperienceSchema.swift

**Purpose**: Defines the metadata structure describing all 11 experience section types and their fields.
**Lines of Code**: 201
**Dependencies**: Foundation only
**Complexity**: Low

**Observations**:
- Well-designed enum-based schema with recursive `ExperienceSchemaNode` for nested fields
- `ExperienceSectionKey` enum properly defines the 11 section types
- `displayName` and `addButtonTitle` computed properties create a clean lookup interface
- Schema is immutable and used as a single source of truth

**Recommendations**:
- Consider extracting field names as constants to ensure consistency across encoder/decoder
- Schema could be extended to include field validation rules

---

### Models/ExperienceDefaults.swift

**Purpose**: SwiftData models for persistent storage of all experience sections.
**Lines of Code**: 648
**Dependencies**: Foundation, SwiftData
**Complexity**: Medium

**Observations**:
- 31 separate `@Model` classes defined in one file (ExperienceDefaults + 11 section types + 9 nested array item types + 1 inverse relationship type)
- Each model class has identical boilerplate: unique `@Attribute(.unique)` UUID, string properties, optional relationships
- `ExperienceDefaults` initializer has 11 nested relationship rebuild operations (lines 105-116) in `establishInverseRelationships()`
- Repetitive pattern: Each section type follows structure: `init(id:, field1:, field2:, ..., relationships:, owner:)`
- SwiftData relationships properly configured with `deleteRule: .cascade` and inverse references

**Issues**:
- **Critical Repetition**: Lines 120-648 could be generated by a protocol-based approach
- **Manual Relationship Setup**: Lines 105-116 repeat the same pattern 11 times
- **Immense File Size**: Single file with 648 lines violates single responsibility principle

**Recommendations**:
- Extract into separate files: `WorkExperienceModels.swift`, `EducationModels.swift`, etc. (11 files total or 1 file per category)
- Introduce a protocol for section models to enforce consistent structure
- Consider if all 31 models must be in the persistent layer or if some could be computed

---

### Models/ExperienceDrafts.swift

**Purpose**: Value-type equivalents of SwiftData models for editing UI state.
**Lines of Code**: 598
**Dependencies**: Foundation, SwiftData (for ModelContext)
**Complexity**: High

**Observations**:
- 21 separate struct types (ExperienceDefaultsDraft + 11 section drafts + nested draft types)
- Implements conversion constructor `init(model:)` and application method `apply(to:in:)`
- Main struct contains 11 private rebuild functions (lines 83-295), each 10-20 lines and nearly identical:
  - All follow pattern: delete existing, map draft items to models, set relationships, insert into context
  - Only differences: property names and nested item types
- Smart use of Equatable conformance for dirty-checking
- Uses `ModelContext.delete()` and `context.insert()` for transactional updates

**Issues**:
- **Massive Rebuild Method**: Lines 83-295 should be a single generic rebuild method with type information
- **Parallel Type Hierarchy**: Having both Draft and Model versions of 11 types creates maintenance burden
- **Repetitive Initialization**: 21 structs with nearly identical property lists

**Recommendations**:
- Consolidate rebuild methods into a single generic approach
- Consider protocol-based approach to unify Draft and Model layers
- Extract nested type definitions to avoid cognitive overhead

---

### Services/CareerKeywordStore.swift

**Purpose**: Manages career keyword autocomplete suggestions for skill/project keywords.
**Lines of Code**: 110
**Dependencies**: Foundation, Observation
**Complexity**: Low

**Observations**:
- Well-implemented singleton service with `@MainActor @Observable`
- Clean separation of concerns: storage management, suggestion filtering, keyword registration
- Loads bundled default keywords on first run, then persists user-added keywords
- Smart normalization: case-insensitive comparisons with trimmed input
- Returns sorted results for consistent UX

**Strengths**:
- Proper error handling with Logger warnings
- Efficient suggestion algorithm (prefix matching, then contains matching)
- Atomic file writes with `.atomic` option

**Recommendations**:
- Consider batching keyword persistence (e.g., persist every 5 additions rather than on each)
- Could support fuzzy matching for typo tolerance

---

### Utilities/ExperienceDefaultsDecoder.swift

**Purpose**: Decodes JSON resume data into draft objects for editing.
**Lines of Code**: 213
**Dependencies**: Foundation, SwiftyJSON
**Complexity**: Medium

**Observations**:
- Single enum with static methods (functional style)
- Main entry point `draft(from:)` orchestrates 11 section decoders
- Determines section enablement based on non-empty arrays
- Each decode method follows identical pattern: extract fields, trim strings, construct draft
- Handles both string and object formats for keywords/roles (lines 194-212)

**Issues**:
- **11 Near-Identical Methods**: Lines 67-192 contain `decodeWork`, `decodeVolunteer`, `decodeEducation`, etc.
- **Tight Coupling**: Each method is tightly bound to a specific draft type
- **Limited Error Handling**: Silently uses default values on missing fields; no validation

**Recommendations**:
- Implement generic decoding protocol to eliminate 11 methods
- Add validation layer to warn about missing required fields
- Consider using Codable with custom decoders instead of SwiftyJSON

---

### Utilities/ExperienceDefaultsEncoder.swift

**Purpose**: Encodes model objects to dictionary format for template processing.
**Lines of Code**: 232
**Dependencies**: Foundation
**Complexity**: Medium

**Observations**:
- Main entry point `makeSeedDictionary()` orchestrates encoding all 11 sections
- Filters empty items and sections (prevents bloated output)
- Each encode method sanitizes strings and filters empty values
- Consistent pattern: build dictionary conditionally, add only non-empty fields
- Proper mapping between model field names and JSON output (e.g., `descriptionText` → `"description"`)

**Issues**:
- **11 Nearly Identical Encode Methods**: Lines 109-226 repeat the same pattern for each section
- **Duplication with Decoder**: Similar field mappings are defined in both encoder and decoder
- **Manual Attribute Mapping**: Special case for `organization` → `"entity"` in projects (line 157)

**Recommendations**:
- Extract field mappings to a configuration structure
- Generate encode/decode methods from a single metadata definition
- Use protocol with associated types for generic encoding

---

### Views/ExperienceEditorView.swift

**Purpose**: Main container view managing the entire experience editor interface.
**Lines of Code**: 297
**Dependencies**: AppKit, SwiftUI
**Complexity**: Medium

**Observations**:
- Well-structured state management: `draft`, `originalDraft`, `isLoading`, `saveState`, `editingEntries`
- Smart dirty-checking: `hasChanges = (newValue != originalDraft)`
- Proper task-based async loading (line 30-32)
- Conditional rendering based on section enablement flags
- Each section view receives 5 callback functions (isEditing, beginEditing, toggleEditing, endEditing, onChange)

**Issues**:
- **Repetitive Section Rendering**: Lines 106-225 contain 11 nearly identical conditional blocks
- **Callback Parameter Overload**: Each section receives 5 parameters; could be simplified
- **State Management Verbosity**: Three separate state variables (draft, originalDraft, saveState) could be consolidated

**Recommendations**:
- Extract section rendering into helper method parameterized by section key
- Create a ViewModel/Container struct to hold the callback functions
- Consider combining save states (idle, saving, saved, error) into a result enum

---

### Views/ExperienceEditorComponents.swift

**Purpose**: Reusable UI component primitives.
**Lines of Code**: 187 (partial read, file continues)
**Dependencies**: AppKit, SwiftUI
**Complexity**: Low

**Observations**:
- Generic component library: `ExperienceCard`, `ExperienceSectionHeader`, `ExperienceAddButton`, `ExperienceFieldRow`
- Excellent reusability: `ExperienceCard` is parameterized with ViewBuilder
- Clean button styling and accessibility labels

**Strengths**:
- Proper use of ViewBuilder for flexible content composition
- Consistent visual treatment via card styling and hover effects

---

### Views/ExperienceEditorEntryViews.swift

**Purpose**: Editor and summary views for individual experience entries.
**Lines of Code**: 476
**Dependencies**: SwiftUI
**Complexity**: High

**Observations**:
- 22 separate View structs (11 editor pairs: Editor + SummaryView)
- Each editor follows identical pattern: ExperienceFieldRow containers with ExperienceTextField/ExperienceTextEditor
- Summary views format data for display using helper views (SummaryRow, SummaryTextBlock, SummaryBulletList)
- Private helper structs at end for summary formatting

**Issues**:
- **Extreme Duplication**: 22 nearly identical View definitions
- **No Generic Approach**: Each section type has its own view, despite following identical patterns
- **Repeated Field Definitions**: Field labels like "Company", "Role", "Location" repeated across WorkExperienceEditor, etc.

**Recommendations**:
- Create generic `SectionEditor<T>` that uses reflection or metadata to render fields
- Extract field label definitions to constants
- Consider using a configuration dictionary for field definitions

---

### Views/ExperienceEditorSectionViews.swift

**Purpose**: Container views for each of the 11 experience sections.
**Lines of Code**: 977
**Dependencies**: SwiftUI, UniformTypeIdentifiers
**Complexity**: High

**Observations**:
- 11 nearly identical section view implementations (WorkExperienceSectionView, VolunteerExperienceSectionView, etc.)
- Each follows this structure:
  1. ForEach over items with drag-drop support
  2. ExperienceCard with conditional editor/summary
  3. ExperienceReorderDropDelegate for drag-and-drop
  4. Trailing drop area for final position
  5. Add button with item creation callback
- Generic drop delegate implementation (lines 894-977) properly handles reordering
- Private title/subtitle helper methods for each section type

**Issues**:
- **Massive Repetition**: Each section view is 60-100 lines with identical structure
- **Copy-Paste Errors Risk**: Future changes must be applied to 11 identical blocks
- **Private Helper Methods**: Each section has similar title/subtitle generation logic

**Recommendations**:
- Create generic `SectionContainerView<T>` parameterized by section type
- Extract title/subtitle generation to protocol with default implementations
- Move reordering logic to composable view

---

### Views/ExperienceEditorListEditors.swift

**Purpose**: Editors for nested list types (highlights, keywords, courses, etc.).
**Lines of Code**: 382 (partial)
**Dependencies**: AppKit, SwiftUI
**Complexity**: Medium

**Observations**:
- Provides specialized list editors for different item types
- Follows consistent patterns for add/delete operations
- Some duplication but more manageable than section views

**Recommendations**:
- Further consolidate using generic list editor protocol

---

### Views/ExperienceSectionBrowserView.swift

**Purpose**: Sidebar panel allowing users to enable/disable sections.
**Lines of Code**: 113
**Dependencies**: SwiftUI
**Complexity**: Medium

**Observations**:
- Shows hierarchical tree of all sections with field definitions
- Provides toggles to enable/disable each section
- Recursive `nodeView` method handles nested field/group nodes

**Issues**:
- **Manual Switch Statement**: Lines 87-113 manually create bindings for all 11 sections
- **Code Smell**: Pattern indicates need for protocol-based abstraction

**Recommendations**:
- Generate bindings automatically using section metadata
- Create enum-driven binding system

---

## Identified Issues

### Over-Abstraction Areas

**Not Present** - This module actually suffers from under-abstraction (too much code repetition) rather than over-abstraction.

### Unnecessary Complexity

#### 1. **Model Layer Duplication** (Critical)

**Location**: `ExperienceDefaults.swift` and `ExperienceDrafts.swift`

**Issue**: 31 model classes when 2 generic types with metadata could suffice.

**Example**:
```swift
// Current approach (repeated 11 times):
@Model
final class WorkExperienceDefault {
    @Attribute(.unique) var id: UUID
    var name: String
    var position: String
    var location: String
    // ... 5 more fields
}

@Model
final class VolunteerExperienceDefault {
    @Attribute(.unique) var id: UUID
    var organization: String
    var position: String
    var url: String
    // ... 4 more fields
}

// Better approach:
@Model
final class ExperienceItem {
    @Attribute(.unique) var id: UUID
    var sectionType: ExperienceSectionKey
    var fields: [String: String]
    var nestedItems: [ExperienceNestedItem]
}
```

**Impact**: Eliminates ~400 lines of boilerplate model code

#### 2. **View Layer Duplication** (Critical)

**Location**: `ExperienceEditorSectionViews.swift` (977 lines)

**Issue**: 11 nearly identical section views, each ~88 lines

**Example Pattern Repeated 11 Times**:
```swift
struct WorkExperienceSectionView: View {
    @Binding var items: [WorkExperienceDraft]
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    // ... 3 more callback parameters
    @State private var draggingID: UUID?

    var body: some View {
        sectionContainer(title: "Work Experience") {
            ForEach($items) { item in
                let entry = item.wrappedValue
                let entryID = entry.id
                let editing = isEditing(entryID)
                ExperienceCard(
                    onDelete: { ... },
                    onToggleEdit: { toggleEditing(entryID) },
                    isEditing: editing
                ) {
                    if editing {
                        WorkExperienceEditor(...)
                    } else {
                        WorkExperienceSummaryView(...)
                    }
                }
                // ... drag/drop setup (20 lines)
            }
            // ... trailing drop area, add button
        }
    }
}
// Repeated 10 more times with only type and title changes
```

**Impact**: Eliminates ~500-600 lines through genericization

#### 3. **Encoder/Decoder Repetition** (High)

**Location**: Both `ExperienceDefaultsEncoder.swift` and `ExperienceDefaultsDecoder.swift`

**Issue**: 11 section encode methods + 11 section decode methods (22 methods, ~450 LOC total)

**Example - Encoder** (lines 109-121):
```swift
private static func encodeWork(_ model: WorkExperienceDefault) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let value = sanitized(model.name) { payload["name"] = value }
    if let value = sanitized(model.position) { payload["position"] = value }
    if let value = sanitized(model.location) { payload["location"] = value }
    // ... repeated for 8 more fields
    return payload
}
// Repeated 10 more times
```

**Impact**: Could use generic reflection-based encoding

#### 4. **Editor/Summary View Pairs** (High)

**Location**: `ExperienceEditorEntryViews.swift` (476 lines)

**Issue**: 22 view definitions for 11 sections (each has Editor + Summary variant)

**Example - Work Section** (20 lines):
```swift
struct WorkExperienceEditor: View {
    @Binding var item: WorkExperienceDraft
    var onChange: () -> Void
    var body: some View {
        ExperienceFieldRow {
            ExperienceTextField("Company", text: $item.name, onChange: onChange)
            ExperienceTextField("Role", text: $item.position, onChange: onChange)
        }
        // ... similar rows for 4 more fields
    }
}

struct WorkExperienceSummaryView: View {
    let entry: WorkExperienceDraft
    var body: some View {
        VStack {
            SummaryRow(label: "Company", value: entry.name)
            SummaryRow(label: "Location", value: entry.location)
            // ... display formatted data
        }
    }
}
// Repeated 10 more times
```

**Impact**: Could be generated from field metadata

#### 5. **Main View Section Rendering** (Medium)

**Location**: `ExperienceEditorView.swift` lines 106-225

**Issue**: 11 nearly identical conditional blocks

```swift
if draft.isWorkEnabled {
    WorkExperienceSectionView(
        items: $draft.work,
        isEditing: isEditingEntry,
        beginEditing: beginEditingEntry,
        toggleEditing: toggleEditingEntry,
        endEditing: endEditingEntry,
        onChange: markDirty
    )
}
// Repeated 10 more times with different section types
```

**Impact**: Could use dynamic view creation or a section router

#### 6. **Switch Statement for Section Toggles** (Low-Medium)

**Location**: `ExperienceSectionBrowserView.swift` lines 87-113

```swift
private func sectionToggle(for key: ExperienceSectionKey) -> Binding<Bool> {
    switch key {
    case .work: return $draft.isWorkEnabled
    case .volunteer: return $draft.isVolunteerEnabled
    // ... 9 more cases
    }
}
// 28 lines for what should be a simple lookup
```

**Impact**: Could use computed property based on key

### Design Pattern Misuse

**Not Significant** - The architecture doesn't misuse patterns; it simply doesn't use enough abstraction where it should.

**Minor Issue**: The `ExperienceDefaultsDraft` struct conflates the draft pattern (for editing) with a conversion layer. Consider separating:
- `ExperienceDefaults` (persistent model)
- `ExperienceEditingState` (working copy during edit)
- `ExperienceDataLoader`/`ExperienceDataPersister` (conversion logic)

## Recommended Refactoring Approaches

### Approach 1: Metadata-Driven Architecture (Recommended)

**Effort**: High (2-3 days)
**Impact**: Eliminates 60-70% of code duplication, makes adding new sections trivial
**Complexity**: Medium

**Steps**:

1. **Create Metadata System**:
```swift
struct SectionMetadata {
    let key: ExperienceSectionKey
    let title: String
    let fields: [FieldMetadata]
    let nestedArrays: [NestedArrayMetadata]
}

struct FieldMetadata {
    let name: String
    let label: String
    let type: FieldType  // .string, .date, .url, .array
    let required: Bool
}
```

2. **Define Central Metadata Registry**:
```swift
enum ExperienceSectionMetadata {
    static let sections: [SectionMetadata] = [
        SectionMetadata(
            key: .work,
            title: "Work Experience",
            fields: [
                FieldMetadata(name: "name", label: "Company", type: .string, required: true),
                FieldMetadata(name: "position", label: "Role", type: .string, required: true),
                // ...
            ],
            nestedArrays: [
                NestedArrayMetadata(name: "highlights", itemType: .text)
            ]
        ),
        // ... other sections
    ]
}
```

3. **Generic Model Layer**:
```swift
@Model
final class ExperienceItem {
    @Attribute(.unique) var id: UUID
    var sectionType: ExperienceSectionKey
    var fieldValues: [String: String]
    @Relationship(deleteRule: .cascade) var nestedItems: [NestedItem]
}
```

4. **Generic View Generation**:
```swift
struct GenericSectionView: View {
    let metadata: SectionMetadata
    @Binding var items: [ExperienceItem]
    var body: some View {
        sectionContainer(title: metadata.title) {
            ForEach($items) { item in
                ExperienceCard { ... }
                    .onDrag { ... }
                    .onDrop { ... }
            }
        }
    }
}
```

5. **Dynamic Encoder/Decoder**:
```swift
func encodeItem(_ item: ExperienceItem, using metadata: SectionMetadata) -> [String: Any] {
    var result: [String: Any] = [:]
    for field in metadata.fields {
        if let value = item.fieldValues[field.name], !value.trimmingCharacters(in: .whitespaces).isEmpty {
            result[field.name] = value
        }
    }
    return result
}
```

**Benefits**:
- Eliminates 11 model classes → 1 generic model
- Eliminates 11 view section types → 1 generic view
- Eliminates 22 encode/decode methods → 2 generic functions
- Eliminates 22 editor/summary view pairs → generic view generator
- Adding new section type requires only adding metadata, no code changes

**Drawbacks**:
- More complex type system initially
- Metadata could become unwieldy if sections diverge significantly
- Requires rethinking how strongly-typed fields are handled

---

### Approach 2: Incremental Protocol-Based Refactoring

**Effort**: Medium (1-2 days)
**Impact**: 30-40% code reduction, maintains type safety
**Complexity**: Low-Medium

**Steps**:

1. **Create Section-Agnostic Protocols**:
```swift
protocol ExperienceSectionModel: Identifiable {
    var id: UUID { get set }
    var sectionType: ExperienceSectionKey { get }
}

protocol ExperienceSectionDraft: Equatable, Identifiable {
    var id: UUID { get set }
    func apply(to model: ExperienceDefaults, in context: ModelContext)
}
```

2. **Make Existing Types Conform**:
```swift
extension WorkExperienceDefault: ExperienceSectionModel {
    var sectionType: ExperienceSectionKey { .work }
}

extension WorkExperienceDraft: ExperienceSectionDraft {
    func apply(to model: ExperienceDefaults, in context: ModelContext) {
        // implementation
    }
}
```

3. **Generic Rebuild Method**:
```swift
func rebuild<T: ExperienceSectionModel>(
    _ items: [T],
    from drafts: [ExperienceItemDraft],
    in context: ModelContext
) -> [T] {
    // Generic implementation using reflection
}
```

4. **Type-Erased Section Container**:
```swift
struct AnyExperienceSection {
    let key: ExperienceSectionKey
    let viewType: Any.Type
    let viewBuilder: () -> AnyView
}
```

**Benefits**:
- Maintains type safety where it matters
- Incremental implementation
- Reduces duplication by ~30-40%
- Backward compatible

**Drawbacks**:
- Doesn't eliminate all boilerplate
- Still requires 11 type definitions
- More complex trait object management

---

### Approach 3: Consolidate Into Multi-Section Container

**Effort**: Medium (1.5 days)
**Impact**: 20-30% code reduction in views
**Complexity**: Low

**Steps**:

1. **Create Generic Section Container**:
```swift
struct GenericExperienceSectionView<Item: Identifiable & Equatable>: View
where Item.ID == UUID {
    let title: String
    let subtitle: String?
    @Binding var items: [Item]
    let editorBuilder: (Item.ID, Item) -> AnyView
    let summaryBuilder: (Item) -> AnyView
    // ... callbacks

    var body: some View {
        // Reusable section logic
    }
}
```

2. **Replace Section-Specific Views**:
```swift
// Before:
struct WorkExperienceSectionView { /* 88 lines */ }
struct VolunteerExperienceSectionView { /* 88 lines */ }
// ... 9 more

// After:
let workSectionView = GenericExperienceSectionView(
    title: "Work Experience",
    items: $draft.work,
    editorBuilder: { id, item in
        AnyView(WorkExperienceEditor(item: .constant(item), onChange: {}))
    },
    // ... other params
)
```

**Benefits**:
- Eliminates 11 section view definitions
- Saves ~600 lines
- Maintains type safety
- Easy to implement

**Drawbacks**:
- AnyView type erasure reduces SwiftUI optimization
- Still requires 11 editor/summary view pairs
- Less discoverable than explicit types

---

## Simpler Alternative Architectures

### Alternative 1: Data-Driven Approach (Most Recommended)

Instead of modeling each experience type as a separate class, store experiences as flexible data structures:

```swift
@Model
final class Experience {
    @Attribute(.unique) var id: UUID
    let type: ExperienceSectionKey  // Discriminator
    var data: [String: String]      // Flexible field storage
    var arrayData: [String: [String]]
}

@Model
final class ExperienceDefaults {
    @Relationship(deleteRule: .cascade) var experiences: [Experience]
}
```

**Pros**:
- Eliminates 31 model classes
- Adding new fields doesn't require code changes
- Reduced boilerplate dramatically
- Flexible for future schema evolution

**Cons**:
- Loss of compile-time type safety on field names
- Runtime validation required
- Performance may suffer with dictionary-based storage
- Debuggability reduced

---

### Alternative 2: Hybrid: Keep Models, Share View Layer

**Pros**:
- Maintains type-safe models
- Reduces view duplication significantly
- Achieves 40-50% code reduction

**Cons**:
- Still requires 11 model types
- Moderate complexity increase

---

## Conclusion

The Experience module demonstrates solid architectural fundamentals with clear separation of concerns and consistent patterns. However, it suffers from critical code duplication that increases maintenance burden and introduces risk of inconsistent updates across the 11 section types.

### Priority Recommendations (in order):

1. **Immediate (High Priority)**:
   - Extract view section rendering (977 LOC file) into generic `GenericSectionView` component
   - Estimated effort: 4-6 hours
   - Expected savings: 500+ LOC

2. **Short-term (Medium Priority)**:
   - Consolidate encoder/decoder into reflection-based generic implementations
   - Estimated effort: 6-8 hours
   - Expected savings: 300+ LOC

3. **Medium-term (Medium Priority)**:
   - Implement metadata-driven architecture for editor/summary view pairs
   - Estimated effort: 16-24 hours
   - Expected savings: 400+ LOC

4. **Long-term (Low Priority)**:
   - Consider full data-driven model layer migration
   - Estimated effort: 3-5 days
   - Expected savings: 800+ LOC total

### Immediate Quick Wins:

1. Extract section titles and field labels to constants:
```swift
enum ExperienceSectionLabels {
    static let work = "Work Experience"
    static let workCompanyLabel = "Company"
    // ...
}
```
Saves: Prevents duplication across 11 files

2. Create callback container struct:
```swift
struct SectionViewCallbacks {
    var isEditing: (UUID) -> Bool
    var beginEditing: (UUID) -> Void
    var toggleEditing: (UUID) -> Void
    var endEditing: (UUID) -> Void
    var onChange: () -> Void
}
```
Saves: 5-parameter callback lists throughout

3. Extract common drop delegate logic into helper extension:
Saves: ~30 lines

**Overall Assessment**: With targeted refactoring, this module could achieve the same functionality in approximately 1,200-1,800 LOC (from current 4,434 LOC) while improving maintainability and reducing error potential. The current architecture is sound but over-engineered for what could be simplified through better use of Swift's type system and generics.
