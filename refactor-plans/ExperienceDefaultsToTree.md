# Refactor Plan: ExperienceDefaultsToTree.swift

**File:** `Sprung/ResumeTree/Utilities/ExperienceDefaultsToTree.swift`
**Lines:** 1,119
**Date assessed:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`ExperienceDefaultsToTree` translates an `ExperienceDefaults` model (typed Swift structs representing a user's canonical resume data) plus a `TemplateManifest` into a `TreeNode` hierarchy that the editor UI works against. It is the sole entry point for tree construction — no other class performs this conversion.

The class is owned by `ResumeDetailVM` (or equivalent) and called once per resume-open / refresh cycle. The output (`TreeNode` root) becomes the mutable document the user edits.

---

## 2. Distinct Logical Sections

The file contains **five distinct logical concerns**, each clearly marked by MARK comments:

| # | Lines | MARK / purpose | What it does |
|---|-------|----------------|--------------|
| 1 | 26–130 | **Orchestration & section routing** | `buildTree()` as public entry point; `shouldIncludeSection()`, `isSectionEnabled()`, and the `buildSection()` dispatch switch. Decides *which* sections appear and in what order. |
| 2 | 132–657 | **Per-section builders** (11 sections + custom) | One private method per resume section (`buildWorkSection`, `buildVolunteerSection`, … `buildCustomSection`). Each follows the same three-step pattern: create container node, iterate items, add child field nodes. |
| 3 | 659–759 | **Editable template fields** | `buildEditableTemplateFields`, `buildStylingNode`, `buildTemplateNode`. Populates the `styling` subtree (fontSizes) and `template` subtree (sectionLabels) from manifest defaults. These are not resume data — they are template configuration values. |
| 4 | 761–942 | **Field-level helpers** | `applyEditorLabel`, `addFieldIfNotHidden`, `addHighlightsIfNotHidden`, `addKeywordsIfNotHidden`, `addCoursesIfNotHidden`, `addRolesIfNotHidden`, `buildHiddenFieldPaths`, `isFieldHidden`. Low-level tree-construction primitives shared across section builders. |
| 5 | 944–1118 | **Default AI fields / pattern application** | `applyDefaultAIFields`, `applyPattern`, `applyBundlePattern`, `applyEnumeratePattern`, `applyContainerEnumeratePattern`, `applyScalarPattern`, `findNode`. Reads manifest `defaultAIFields` patterns and stamps `bundledAttributes`, `enumeratedAttributes`, or `.aiToReplace` status onto matching tree nodes. |

---

## 3. SRP Assessment

The class violates the Single Responsibility Principle. It has **three independently-varying reasons to change**:

**Reason 1 — A new resume section is added (or an existing one changes fields)**
Only the per-section builder methods (concern #2) would change. Today that's 430 lines of highly repetitive boilerplate. Adding a `publications` field or renaming a field on `WorkExperienceDefault` touches only these methods.

**Reason 2 — Template field structure changes (fontSizes, sectionLabels, future fields)**
Only concern #3 (`buildStylingNode`, `buildTemplateNode`) changes. This logic is qualitatively different from resume-data building — it reads manifest defaults, not `ExperienceDefaults`, and populates configuration nodes, not content nodes.

**Reason 3 — The AI pattern language evolves**
Only concern #5 (pattern parsing and tree annotation) changes. This is a self-contained mini-interpreter (~175 lines) for a pattern DSL (`section.*.attr`, `section[].attr`, `section.field`). It already uses its own `findNode` traversal distinct from the builders.

Concerns #1 and #4 (orchestration and field helpers) are genuinely shared infrastructure that does not warrant separation.

---

## 4. Length Justification

**The length is not justified by SRP compliance.** The file is 1,119 lines primarily because:

1. The 11 per-section builder methods (concern #2) are structurally identical — each is ~20–35 lines of the same pattern. This is data that reads like code. A data-driven approach would collapse them significantly, but even as-is they belong in a separate file because they vary independently.
2. The AI pattern interpreter (concern #5, ~175 lines) is a conceptually distinct subsystem with its own traversal logic and its own test surface.
3. The template field builder (concern #3, ~100 lines) reads from a different data source (`manifest` defaults, not `experienceDefaults`) and is likely to expand as more template-configurable fields are added.

The orchestration core (concern #1 + #4, ~200 lines) is appropriately sized and is the only part that belongs in the primary file.

---

## 5. Recommendation: Split Into Three Files

Split into the following files. All files live under `Sprung/ResumeTree/Utilities/`. No new directories needed. No visibility changes are required — all extracted methods are `private` within `ExperienceDefaultsToTree`, and Swift extensions on the same type in the same module share access to `private` members declared in the primary file **only if using `fileprivate`**. See visibility note below.

---

### File 1 (keep, heavily trimmed): `ExperienceDefaultsToTree.swift`

**Purpose:** Orchestration — public API, section routing, section-enable logic, field helpers, and hidden-field logic.

**Retains these line ranges from the original:**
- Lines 1–130 (file header, class declaration, init, `buildTree`, `shouldIncludeSection`, `isSectionEnabled`, `buildSection` dispatch)
- Lines 761–942 (field helpers: `applyEditorLabel`, `addFieldIfNotHidden`, `addHighlightsIfNotHidden`, `addKeywordsIfNotHidden`, `addCoursesIfNotHidden`, `addRolesIfNotHidden`, `buildHiddenFieldPaths`, `isFieldHidden`)

**After extraction this file will be approximately 310 lines.**

**Visibility note:** The `hiddenFieldPaths` stored property is declared on the primary class and will remain there. The section-builder extension and AI-fields extension will call helpers like `addFieldIfNotHidden` and `isFieldHidden` — these must be changed from `private` to `fileprivate` so extensions in separate files can access them. Properties `resume`, `experienceDefaults`, `manifest`, and `hiddenFieldPaths` must also be `fileprivate` (or `internal`) rather than `private`.

---

### File 2 (new): `ExperienceDefaultsToTree+Sections.swift`

**Purpose:** Per-section tree building — one method per JSON Resume section type.

**Path:** `Sprung/ResumeTree/Utilities/ExperienceDefaultsToTree+Sections.swift`

**Moves these line ranges from the original:**
- Lines 132–657 (all section builders: `buildWorkSection`, `buildVolunteerSection`, `buildEducationSection`, `buildProjectsSection`, `buildSkillsSection`, `buildAwardsSection`, `buildCertificatesSection`, `buildPublicationsSection`, `buildLanguagesSection`, `buildInterestsSection`, `buildReferencesSection`, `buildCustomSection`)

**Structure:**

```swift
//
//  ExperienceDefaultsToTree+Sections.swift
//  Sprung
//
//  Per-section TreeNode builders. Each method creates the section container,
//  iterates items, and adds child field nodes via helpers defined in
//  ExperienceDefaultsToTree.swift.
//

import Foundation

@MainActor
extension ExperienceDefaultsToTree {

    // MARK: - Work Section
    func buildWorkSection(parent: TreeNode) { ... }         // was private

    // MARK: - Volunteer Section
    func buildVolunteerSection(parent: TreeNode) { ... }    // was private

    // MARK: - Education Section
    func buildEducationSection(parent: TreeNode) { ... }    // was private

    // MARK: - Projects Section
    func buildProjectsSection(parent: TreeNode) { ... }     // was private

    // MARK: - Skills Section
    func buildSkillsSection(parent: TreeNode) { ... }       // was private

    // MARK: - Awards Section
    func buildAwardsSection(parent: TreeNode) { ... }       // was private

    // MARK: - Certificates Section
    func buildCertificatesSection(parent: TreeNode) { ... } // was private

    // MARK: - Publications Section
    func buildPublicationsSection(parent: TreeNode) { ... } // was private

    // MARK: - Languages Section
    func buildLanguagesSection(parent: TreeNode) { ... }    // was private

    // MARK: - Interests Section
    func buildInterestsSection(parent: TreeNode) { ... }    // was private

    // MARK: - References Section
    func buildReferencesSection(parent: TreeNode) { ... }   // was private

    // MARK: - Custom Section
    func buildCustomSection(parent: TreeNode) { ... }       // was private
}
```

**Approximate size after move:** ~530 lines (lines 132–657 verbatim plus boilerplate).

**Visibility changes required:**
- All methods change from `private` to `fileprivate` (so the dispatch in `buildSection` in the primary file can call them via the extension).
- No other visibility changes within this file — the helpers they call (`addFieldIfNotHidden`, `applyEditorLabel`, etc.) will be `fileprivate` in the primary file and accessible from this extension since they share the same module and same type.

---

### File 3 (new): `ExperienceDefaultsToTree+TemplateFields.swift`

**Purpose:** Build the `styling` and `template` tree nodes from manifest defaults. These are template-configuration values (font sizes, section labels), not resume content.

**Path:** `Sprung/ResumeTree/Utilities/ExperienceDefaultsToTree+TemplateFields.swift`

**Moves these line ranges from the original:**
- Lines 659–759 (`buildEditableTemplateFields`, `buildStylingNode`, `buildTemplateNode`)

**Structure:**

```swift
//
//  ExperienceDefaultsToTree+TemplateFields.swift
//  Sprung
//
//  Builds the styling and template subtrees from manifest defaults.
//  Font sizes (styling.fontSizes) and section labels (template.sectionLabels)
//  are template-configuration nodes, not resume content.
//

import Foundation

@MainActor
extension ExperienceDefaultsToTree {

    // MARK: - Editable Template Fields

    func buildEditableTemplateFields(parent: TreeNode) { ... }  // was private
    func buildStylingNode(parent: TreeNode) { ... }             // was private
    func buildTemplateNode(parent: TreeNode) { ... }            // was private
}
```

**Approximate size after move:** ~110 lines.

**Visibility changes required:**
- `buildEditableTemplateFields` is called from `buildTree()` in the primary file, so it must be `fileprivate` (or `internal`).
- `buildStylingNode` and `buildTemplateNode` are only called from `buildEditableTemplateFields` within this extension — they can remain `private` if desired, since they are in the same file as their caller after the split. However, for consistency with the pattern, `fileprivate` is fine.

---

### File 4 (new): `ExperienceDefaultsToTree+AIFields.swift`

**Purpose:** Parse and apply `defaultAIFields` patterns from the manifest to stamp `bundledAttributes`, `enumeratedAttributes`, and `.aiToReplace` status onto tree nodes. Self-contained DSL interpreter.

**Path:** `Sprung/ResumeTree/Utilities/ExperienceDefaultsToTree+AIFields.swift`

**Moves these line ranges from the original:**
- Lines 944–1118 (`applyDefaultAIFields`, `applyPattern`, `applyBundlePattern`, `applyEnumeratePattern`, `applyContainerEnumeratePattern`, `applyScalarPattern`, `findNode`)

**Structure:**

```swift
//
//  ExperienceDefaultsToTree+AIFields.swift
//  Sprung
//
//  Parses and applies defaultAIFields patterns from the template manifest.
//
//  Pattern types:
//    section.*.attr         → bundledAttributes on collection node
//    section[].attr         → enumeratedAttributes on collection node
//    section.container[]    → enumeratedAttributes["*"] on container node
//    section.field          → .aiToReplace status on scalar node
//

import Foundation

@MainActor
extension ExperienceDefaultsToTree {

    // MARK: - Default AI Fields

    func applyDefaultAIFields(to root: TreeNode, patterns: [String]) { ... }  // was private
    func applyPattern(_ pattern: String, to root: TreeNode) { ... }           // was private
    func applyBundlePattern(...) { ... }                                       // was private
    func applyEnumeratePattern(...) { ... }                                    // was private
    func applyContainerEnumeratePattern(...) { ... }                           // was private
    func applyScalarPattern(...) { ... }                                       // was private
    func findNode(path: [String], from root: TreeNode) -> TreeNode? { ... }   // was private
}
```

**Approximate size after move:** ~185 lines.

**Visibility changes required:**
- `applyDefaultAIFields` is called from `buildTree()` in the primary file, so it must be `fileprivate` (or `internal`).
- All other methods here are only called from within this extension file — they can be `private` if grouped in the same file, or `fileprivate` if spread across multiple extensions. Keeping them `private` within this file is cleaner and preferred.

---

## 6. Complete Visibility Change Summary

| Symbol | Current | After Split | Reason |
|--------|---------|-------------|--------|
| `resume` | `private` | `fileprivate` | Accessed from extension files |
| `experienceDefaults` | `private` | `fileprivate` | Accessed from extension files |
| `manifest` | `private` | `fileprivate` | Accessed from extension files |
| `hiddenFieldPaths` | `private` | `fileprivate` | Accessed from `+Sections` |
| `buildHiddenFieldPaths()` | `private` | `fileprivate` | Called from init in primary file — stays `private` (same file) |
| `isFieldHidden(path:)` | `private` | `fileprivate` | Called from `+Sections` |
| `addFieldIfNotHidden(...)` | `private` | `fileprivate` | Called from `+Sections` |
| `addHighlightsIfNotHidden(...)` | `private` | `fileprivate` | Called from `+Sections` |
| `addKeywordsIfNotHidden(...)` | `private` | `fileprivate` | Called from `+Sections` |
| `addCoursesIfNotHidden(...)` | `private` | `fileprivate` | Called from `+Sections` |
| `addRolesIfNotHidden(...)` | `private` | `fileprivate` | Called from `+Sections` |
| `applyEditorLabel(to:for:)` | `private` | `fileprivate` | Called from `+Sections` and `+TemplateFields` |
| `buildSection(key:parent:)` | `private` | stays `private` | Only called from `buildTree()`, same file |
| `shouldIncludeSection(_:)` | `private` | stays `private` | Only called from `buildTree()`, same file |
| `isSectionEnabled(_:)` | `private` | stays `private` | Only called from `shouldIncludeSection`, same file |
| `buildWorkSection(parent:)` … `buildCustomSection(parent:)` | `private` | `fileprivate` | Called from `buildSection()` in primary file; defined in `+Sections` |
| `buildEditableTemplateFields(parent:)` | `private` | `fileprivate` | Called from `buildTree()`, defined in `+TemplateFields` |
| `buildStylingNode(parent:)` | `private` | `private` | Called only within `+TemplateFields` |
| `buildTemplateNode(parent:)` | `private` | `private` | Called only within `+TemplateFields` |
| `applyDefaultAIFields(to:patterns:)` | `private` | `fileprivate` | Called from `buildTree()`, defined in `+AIFields` |
| All other AI pattern methods | `private` | `private` | Internal to `+AIFields` |

---

## 7. How the Files Interact

```
ExperienceDefaultsToTree.swift          (primary: orchestration + field helpers)
        │
        ├── calls buildSection()  ──────────► ExperienceDefaultsToTree+Sections.swift
        │       which dispatches to                (12 section builder methods)
        │       buildWorkSection, etc.             uses fileprivate helpers from primary
        │
        ├── calls buildEditableTemplateFields() ──► ExperienceDefaultsToTree+TemplateFields.swift
        │                                           (styling + template node builders)
        │                                           reads from manifest, not experienceDefaults
        │
        └── calls applyDefaultAIFields() ─────► ExperienceDefaultsToTree+AIFields.swift
                                                 (pattern DSL interpreter)
                                                 self-contained, only reads tree nodes
```

No imports are needed between extension files — they are all part of the same module and same type. Only `import Foundation` is needed in each file.

---

## 8. Expected File Sizes After Refactoring

| File | Approx. Lines | Primary concern |
|------|---------------|-----------------|
| `ExperienceDefaultsToTree.swift` | ~310 | Orchestration, section enable logic, field-level helpers |
| `ExperienceDefaultsToTree+Sections.swift` | ~530 | 12 per-section tree builders |
| `ExperienceDefaultsToTree+TemplateFields.swift` | ~110 | Styling and template configuration nodes |
| `ExperienceDefaultsToTree+AIFields.swift` | ~185 | defaultAIFields pattern interpreter |
| **Total** | **~1,135** | (slight increase from added boilerplate headers) |

---

## 9. What Does NOT Need to Change

- The public API (`buildTree() -> TreeNode?`) is unchanged.
- The calling site (wherever `ExperienceDefaultsToTree` is instantiated and `buildTree()` is called) requires zero changes.
- No data model types (`ExperienceDefaults`, `TemplateManifest`, `TreeNode`) are affected.
- No Xcode project file changes are needed — the project uses filesystem-synced groups, so new files added to `Sprung/ResumeTree/Utilities/` are picked up automatically.
- No test changes (assuming no existing unit tests target these private methods directly).

---

## 10. Implementation Order

Execute in this order to catch compilation errors incrementally:

1. Change `private` to `fileprivate` on all stored properties and shared helpers in the primary file (see table in section 6). Build — should be clean.
2. Create `ExperienceDefaultsToTree+AIFields.swift`, move lines 944–1118, remove from primary. Build.
3. Create `ExperienceDefaultsToTree+TemplateFields.swift`, move lines 659–759, remove from primary. Build.
4. Create `ExperienceDefaultsToTree+Sections.swift`, move lines 132–657, remove from primary. Build.
5. Final full build to confirm clean compilation.
