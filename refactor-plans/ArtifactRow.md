# ArtifactRow.swift Refactor Plan

**File:** `Sprung/Onboarding/Views/Components/ArtifactRow.swift`
**Lines:** 819
**Date assessed:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`ArtifactRow` is a collapsible list row that displays a single `ArtifactRecord` inside the Onboarding "Artifacts" tab. When collapsed it shows a header (file icon, name, metadata subtitle, status badges, action buttons). When expanded it reveals up to six distinct content sub-panels: brief description, summary, pending skills, extracted skills, narrative cards, extracted content preview, and artifact metadata (which can itself expand to show git analysis and raw JSON).

---

## 2. Distinct Logical Sections

| Lines | Section | Purpose |
|-------|---------|---------|
| 6–37 | Struct declaration + `init` | Property declarations, default-argument `init` |
| 39–41 | `hasContent` computed var | Simple helper |
| 43–272 | `body` | Top-level layout; delegates to subviews |
| 46–149 | Header row (inside `body`) | File icon, name, subtitle, status indicators, demote/delete buttons |
| 151–264 | Expanded content area (inside `body`) | Orchestrates the six sub-panels |
| 274–321 | `metadataSection` | SHA256, purpose/title fields, inline git analysis, raw JSON disclosure |
| 323–389 | `pendingSkillsSection` | Pending (unapproved) skills grouped by category with per-skill delete |
| 391–441 | `skillsSection(_:)` | Approved extracted skills, flow-layout badges, regen button |
| 443–459 | `skillBadge(_:)` | Single skill tag pill |
| 461–495 | `narrativeCardsSection(_:)` | Section header + list of `narrativeCardRow` |
| 497–565 | `narrativeCardRow(_:)` | One KnowledgeCard: title, org/date, narrative preview, domain badges |
| 567–575 | `cardTypeIcon(_:)` | Mapping `CardType` → SF Symbol name |
| 577–585 | `cardTypeColor(_:)` | Mapping `CardType` → `Color` |
| 587–593 | `proficiencyColor(_:Proficiency)` | Mapping `Proficiency` enum → `Color` |
| 595–706 | `gitAnalysisSection(analysis:)` | Repo summary, technical skills, achievements, AI collaboration, keyword cloud — all from a raw `JSON` object |
| 708–716 | `proficiencyColor(_:String)` | String-based overload of proficiency color (for git analysis JSON data) |
| 718–726 | `badgePill(_:color:)` | Generic reusable tag pill |
| 728–739 | `metadataRow(label:value:)` | Two-column label/value row for metadata |
| 741–747 | `fileIcon` | Computed view for SF Symbol based on content type |
| 749–758 | `iconForContentType(_:)` | Maps MIME type string → SF Symbol name |
| 760–765 | `formatTokenCount(_:)` | Formats `Int` → "1.4K" style string |
| 767–774 | `formatFileSize(_:)` | Formats bytes → "KB"/"MB" string |
| 778–818 | `FlowLayout` (private struct) | Custom `Layout` for wrapping tag pills |

---

## 3. SRP Assessment

`ArtifactRow` violates Single Responsibility in several compounding ways:

### 3a. Three fully self-contained domain sub-views embedded inline

- **Git analysis panel** (`gitAnalysisSection`, lines 595–706): A complete standalone view rendering repository summary, technical skills, achievements, AI collaboration profile, and keyword cloud from raw SwiftyJSON. This has nothing to do with the row's responsibility of "displaying an artifact header and toggling expansion." It is a dedicated read-only data display for a specific artifact sub-type.
- **Narrative card row** (`narrativeCardRow`, lines 497–565): Each card has its own layout (title, org/date, narrative excerpt, domain badges). This is a complete list-item view. `narrativeCardsSection` is itself a collection view wrapping these rows.
- **Pending skills section** (`pendingSkillsSection`, lines 323–389): Its own complete grouped-list view with delete affordance per item; distinct from the approved `skillsSection`.

### 3b. Duplicated utility code that belongs in a shared location

- `FlowLayout` (lines 778–818) is **identically re-implemented in at least nine other files** in the codebase (`KnowledgeTabContent.swift`, `SkillsTabContent.swift`, `KnowledgeCardView.swift`, `DocumentCollectionView.swift`, `SkillsBankBrowser.swift`, `DiscoveryOnboardingView.swift`, `SkillsGroupingView.swift`, `TitleSetEditorView.swift`, plus a near-identical `_FlowLayout` in `Shared/Views/FlowStack.swift`). `FlowStack.swift` already exists as the intended shared home.
- `badgePill(_:color:)` (lines 718–726) is a generic primitive duplicated wherever pill badges appear.
- `proficiencyColor(_:)` has two overloads: one for the `Proficiency` enum (line 587) and one for a raw `String` (line 708). The string overload exists solely because `gitAnalysisSection` receives raw JSON and has not normalized to the enum. This is a code-smell—a symptom of the git-analysis view knowing too little about the domain model.
- `iconForContentType`, `formatTokenCount`, `formatFileSize` are utilities that have no reason to live inside a view struct.

### 3c. Two conflicting skill display responsibilities

There are two entirely separate code paths for displaying skills from the same artifact:
- `pendingSkillsSection`: editable (delete button), orange-accented, for skills not yet approved.
- `skillsSection(_:)`: read-only, purple-accented, flow-layout badges, for already-extracted approved skills.

These serve different interaction models and could be independent views sharing a data contract.

### 3d. Size verdict

819 lines for a single view struct is not justified. The body orchestration logic alone (43–272) is acceptable; the rest of the file is independent sub-views and utilities that could each stand alone.

---

## 4. Refactoring Plan

The goal is to give each logical sub-panel its own file, extract shared utilities to the shared layer, and make `ArtifactRow.swift` a thin coordinator of 150–200 lines.

### New files to create

---

### File 1: `Sprung/Onboarding/Views/Components/ArtifactRowHeader.swift`

**Purpose:** The always-visible collapsed header: file icon, display name, subtitle, status badges, expand chevron, demote button, delete button.

**Lines moved from ArtifactRow.swift:** 46–149 (the `HStack` inside `body`) + 741–758 (`fileIcon` + `iconForContentType`).

**Contents:**
```
struct ArtifactRowHeader: View {
    let artifact: ArtifactRecord
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onDemote: () -> Void
    let onDelete: () -> Void
}
```

`iconForContentType` becomes a private method on this view (or a free function in the same file). `fileIcon` becomes a private computed var.

**Interactions:** `ArtifactRow.body` replaces the inline `HStack` with `ArtifactRowHeader(...)`.

---

### File 2: `Sprung/Onboarding/Views/Components/ArtifactSkillsSection.swift`

**Purpose:** Displays skills extracted from an artifact, grouped by category in flow-layout badge rows, with an optional regen button. Covers the **approved/read-only** skill display only.

**Lines moved from ArtifactRow.swift:** 391–459 (`skillsSection(_:)` + `skillBadge(_:)`).

**Contents:**
```
struct ArtifactSkillsSection: View {
    let skills: [Skill]
    let onRegenSkills: (() -> Void)?
}
```

`proficiencyColor(_:Proficiency)` (line 587–593) moves here as a private free function or method. `badgePill` is replaced by a call to the shared `ArtifactBadgePill` (see File 5).

**Interactions:** `ArtifactRow.body` replaces `skillsSection(skills)` call with `ArtifactSkillsSection(skills: skills, onRegenSkills: onRegenSkills)`.

---

### File 3: `Sprung/Onboarding/Views/Components/ArtifactPendingSkillsSection.swift`

**Purpose:** Displays skills pending approval (from `SkillStore`), grouped by category, with per-skill delete buttons. Distinct from `ArtifactSkillsSection` because it has edit affordance and different visual treatment.

**Lines moved from ArtifactRow.swift:** 323–389 (`pendingSkillsSection`).

**Contents:**
```
struct ArtifactPendingSkillsSection: View {
    let skills: [Skill]
    let onDeleteSkill: (Skill) -> Void
}
```

`proficiencyColor(_:Proficiency)` shared via import from `ArtifactSkillsSection.swift` — or extracted to the shared badge pill file (see File 5).

**Interactions:** `ArtifactRow.body` replaces `pendingSkillsSection` with `ArtifactPendingSkillsSection(skills: pendingSkills, onDeleteSkill: onDeleteSkill ?? { _ in })`.

---

### File 4: `Sprung/Onboarding/Views/Components/ArtifactNarrativeCardsSection.swift`

**Purpose:** Displays a list of `KnowledgeCard` objects extracted from an artifact, each as a self-contained card row with title, card-type badge, org/date line, narrative excerpt, and domain badges. Includes optional regen button.

**Lines moved from ArtifactRow.swift:** 461–585 (`narrativeCardsSection(_:)` + `narrativeCardRow(_:)` + `cardTypeIcon(_:)` + `cardTypeColor(_:)`).

**Contents:**
```
struct ArtifactNarrativeCardsSection: View {
    let cards: [KnowledgeCard]
    let onRegenNarrativeCards: (() -> Void)?
}

private struct NarrativeCardRow: View {
    let card: KnowledgeCard
}
```

`cardTypeIcon` and `cardTypeColor` become private free functions or static helpers in this file.

**Interactions:** `ArtifactRow.body` replaces `narrativeCardsSection(narrativeCards)` with `ArtifactNarrativeCardsSection(cards: narrativeCards, onRegenNarrativeCards: onRegenNarrativeCards)`.

---

### File 5: `Sprung/Onboarding/Views/Components/ArtifactGitAnalysisSection.swift`

**Purpose:** Renders the structured git repository analysis JSON: repository summary block, technical skills flow layout, notable achievements list, AI collaboration profile badge, keyword cloud.

**Lines moved from ArtifactRow.swift:** 595–706 (`gitAnalysisSection(analysis:)`) + 708–716 (string `proficiencyColor` overload).

**Contents:**
```
struct ArtifactGitAnalysisSection: View {
    let analysis: JSON
}
```

The string-based `proficiencyColor(_:String)` (line 708–716) stays local to this file since it maps raw JSON string values that exist only in the git analysis payload.

`badgePill` is replaced by a call to the shared badge pill (see File 6).

**Interactions:** `metadataSection` in `ArtifactRow.swift` replaces `gitAnalysisSection(analysis: artifact.metadata["analysis"])` with `ArtifactGitAnalysisSection(analysis: artifact.metadata["analysis"])`.

---

### File 6: `Sprung/Onboarding/Views/Components/ArtifactBadgePill.swift`

**Purpose:** A single shared pill/badge primitive used by `ArtifactSkillsSection`, `ArtifactPendingSkillsSection`, `ArtifactNarrativeCardsSection`, and `ArtifactGitAnalysisSection`. Also a home for `proficiencyColor(_:Proficiency)` since multiple sub-views need it.

**Lines moved from ArtifactRow.swift:** 718–726 (`badgePill`), 587–593 (`proficiencyColor(_:Proficiency)`).

**Contents:**
```
// Free function usable as a ViewBuilder helper across the artifact sub-views
func artifactBadgePill(_ text: String, color: Color) -> some View { ... }

// Shared proficiency color mapping
func artifactProficiencyColor(_ proficiency: Proficiency) -> Color { ... }
```

Note: these do NOT need to be a `View` struct—they can be free functions in the file, which keeps call sites identical.

**Interactions:** All four sub-view files import nothing extra; free functions are visible within the module.

---

### File 7: FlowLayout dedup — ALREADY COMPLETED

**COMPLETED:** The private `FlowLayout` duplicate has already been deleted from `ArtifactRow.swift` and all call sites replaced with `FlowStack(spacing: N)` as part of a cross-cutting FlowLayout dedup pass. No action needed for this step.

---

### Utility functions that stay in `ArtifactRow.swift` (or move to a formatter utility)

`formatTokenCount(_:)` and `formatFileSize(_:)` (lines 760–774) are used only inside `ArtifactRow`'s body for the "Extracted Content" and summary sub-sections. They can either:
- Stay in `ArtifactRow.swift` as private helpers since that is their only call site, or
- Move to a shared `ArtifactFormatters.swift` if other views (e.g., `ArchivedArtifactRow`) ever need them.

Recommendation: keep them in `ArtifactRow.swift` for now; they are two tiny functions.

---

## 5. What `ArtifactRow.swift` looks like after refactoring

After the split, `ArtifactRow.swift` retains:
- Struct declaration + `init` (lines 6–37)
- `hasContent` computed var (lines 39–41)
- `body` calling `ArtifactRowHeader`, the six conditional sub-panels via their new view types, and the "Extracted Content" scroll + "No content yet" fallback (the only content block with no natural standalone home)
- `metadataSection` (lines 274–321) — this can stay because it is tightly coupled to `artifact.metadata` fields and `ArtifactGitAnalysisSection` replaces only the git sub-block inside it
- `metadataRow(label:value:)` (lines 728–739) — private helper for `metadataSection`, stays
- `formatTokenCount` and `formatFileSize`

Estimated post-refactor line count: **~200 lines**.

---

## 6. File interaction summary

```
ArtifactRow.swift
  ├── ArtifactRowHeader.swift          (header HStack, file icon, status badges)
  ├── ArtifactPendingSkillsSection.swift  (pending skills with delete)
  ├── ArtifactSkillsSection.swift      (approved skills read-only, flow badges)
  │     └── uses ArtifactBadgePill.swift
  ├── ArtifactNarrativeCardsSection.swift (KnowledgeCard list)
  │     └── uses ArtifactBadgePill.swift
  ├── ArtifactGitAnalysisSection.swift (git repo JSON display)
  │     └── uses ArtifactBadgePill.swift
  └── ArtifactBadgePill.swift          (shared pill + proficiencyColor)

Shared/Views/FlowStack.swift           (expose _FlowLayout as internal FlowLayout)
```

No type visibility changes are needed beyond removing the `private` qualifier from `_FlowLayout` in `FlowStack.swift` (it is already in the same module).

---

## 7. Types that need visibility changes

| Type | Current | Change | Reason |
|------|---------|--------|--------|
| `_FlowLayout` in `FlowStack.swift` | `private` | `internal` (default) | Allow use across the module without re-declaring everywhere |
| All helper free functions in `ArtifactBadgePill.swift` | n/a (new) | `internal` (default) | Visible to all files in the Sprung module |
| `NarrativeCardRow` inside `ArtifactNarrativeCardsSection.swift` | n/a (new) | `private` | Implementation detail of the section; not used outside |

No `public` declarations are needed; this is a single-module app target.

---

## 8. Implementation order

Perform in this sequence to keep the build green at each step:

1. Create `ArtifactBadgePill.swift` with `artifactBadgePill` and `artifactProficiencyColor`. Build.
2. Create `ArtifactGitAnalysisSection.swift`. Remove `gitAnalysisSection` from `ArtifactRow.swift`; update call site in `metadataSection`. Build.
3. Create `ArtifactNarrativeCardsSection.swift`. Remove `narrativeCardsSection`, `narrativeCardRow`, `cardTypeIcon`, `cardTypeColor` from `ArtifactRow.swift`. Build.
4. Create `ArtifactSkillsSection.swift`. Remove `skillsSection(_:)`, `skillBadge(_:)` from `ArtifactRow.swift`. Build.
5. Create `ArtifactPendingSkillsSection.swift`. Remove `pendingSkillsSection` from `ArtifactRow.swift`. Build.
6. Create `ArtifactRowHeader.swift`. Remove header HStack from `body` in `ArtifactRow.swift`; remove `fileIcon`, `iconForContentType`. Build.
7. Remove `private struct FlowLayout` from `ArtifactRow.swift` and all duplicates in the Onboarding Components directory (`KnowledgeTabContent.swift`, `SkillsTabContent.swift`, `KnowledgeCardView.swift`, `DocumentCollectionView.swift`). Make `_FlowLayout` in `FlowStack.swift` internal. Update call sites to use `FlowStack` or `FlowLayout` (rename the exposed type). Build.
8. Remove `proficiencyColor(_:Proficiency)` (line 587) and `badgePill` (line 718) from `ArtifactRow.swift`; update any remaining call sites in `ArtifactRow.swift` to use `artifactProficiencyColor`/`artifactBadgePill`. Build.
9. Final review: grep for `gitAnalysisSection`, `narrativeCardsSection`, `pendingSkillsSection`, `skillBadge`, `cardTypeIcon`, `cardTypeColor` — all should return zero results outside their new dedicated files.
