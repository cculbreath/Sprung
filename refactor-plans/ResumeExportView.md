# ResumeExportView.swift — Refactor Assessment

**File:** `Sprung/Export/Views/ResumeExportView.swift`
**Line count:** 815
**Date assessed:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`ResumeExportView` is the "Submit Application" panel shown when the user selects the Export/Submit tab for a job application. Its _stated_ responsibility is to present submission readiness, pipeline status, and export controls.

In practice the file contains five distinct concerns:

| Concern | Where |
|---------|-------|
| Data model for export format choices | `ExportOption` enum (lines 11–49) |
| Submit-panel layout/orchestration | `ResumeExportView` struct (lines 53–604) |
| File-writing logic for seven export formats | Private methods inside `ResumeExportView` (lines 388–594) |
| Readiness-card sub-view | `ReadinessCard` struct (lines 608–662) |
| Pipeline tracker sub-view + logic | `PipelineTrackerView` struct (lines 666–781) |
| Toast notification overlay | `MacOSToastOverlay` struct (lines 785–815) |

---

## 2. Distinct Logical Sections

### A. `ExportOption` enum (lines 11–49)
A pure data model: the seven export formats, their display names, SF Symbol icons, and stable string keys used when routing `NotificationCenter` payloads. Has no SwiftUI dependency — just `Foundation`-compatible value type.

### B. `ResumeExportView` — layout scaffolding (lines 53–123)
`body`, `onAppear`, `onChange`, `onReceive`, and `.alert` modifier. Orchestrates the five section-building helpers. This is the legitimate "view" part.

### C. `ResumeExportView` — pipeline date helpers (lines 167–194)
`pipelineDates(for:)` and `updateDateForStatus(jobApp:status:)`. These two functions translate domain status transitions into concrete `JobApp` date fields. They are _business logic_ that depends on `jobAppStore` but has no rendering concern.

### D. `ResumeExportView` — section builder functions (lines 127–297)
Five `@ViewBuilder`-style functions: `readinessSection`, `pipelineSection`, `actionsSection`, `exportSection`, `notesSection`. These are thin layout functions that compose subviews; they are appropriately in the view file.

### E. `ResumeExportView` — export dispatch and file I/O (lines 299–603)
`performExport`, `isExportDisabled`, `showToastNotification`, `sanitizeFilename`, `createUniqueFileURL`, `combinePDFs`, and seven `exportXxx` private methods. This is a complete file-export service embedded in a SwiftUI view struct. It directly calls `FileManager`, `PDFKit`, `NSWorkspace`, and `appEnvironment.resumeExportCoordinator`. None of this logic has a rendering responsibility.

### F. `ReadinessCard` (lines 608–662)
A self-contained, reusable subview: an icon + title + subtitle card with a hover state. No business logic. Private to the file. Clean single responsibility, but it is a _distinct_ component that could reasonably live elsewhere.

### G. `PipelineTrackerView` (lines 666–781)
A non-trivial subview with its own internal state helpers (`mainPipeline`, `currentIndex`, `shortDate`), three rendering sub-functions, and conditional terminal-node display. It is purely presentational (receives data in, emits `onStatusTap` callback out) but it is large enough (~115 lines) to justify its own file.

### H. `MacOSToastOverlay` (lines 785–815)
A small, generic notification overlay. Notably it is declared `struct MacOSToastOverlay: View` with `internal` (not `private`) access — it is already potentially reusable across the app.

---

## 3. SRP Verdict

**The file violates SRP in two significant ways:**

1. **File I/O / export logic lives inside a view struct.** The seven `exportXxx` methods — each calling `FileManager`, `PDFKit`, and `resumeExportCoordinator` — belong in a service or coordinator, not a SwiftUI view. The view should call a service; the service should do the writing.

2. **Three distinct reusable subview types are bundled into one file.** `ReadinessCard`, `PipelineTrackerView`, and `MacOSToastOverlay` each have a single focused responsibility; they are not helper types that are tightly coupled to `ResumeExportView`'s rendering logic. Bundling them inflates the file and makes the individual components hard to locate or reuse.

**Not a violation:** The section-builder functions (`readinessSection`, etc.) are legitimate view-decomposition helpers inside the same view struct. They belong here.

---

## 4. Length Verdict

The 815-line count is **not justified**. Removing the export service (~250 lines) and extracting three subview types (~240 lines combined) would reduce `ResumeExportView.swift` to approximately **325 lines** — well-proportioned for a panel view.

---

## 5. Refactoring Plan

### Overview

Four new files are created; `ResumeExportView.swift` is trimmed to its view-layer responsibility only.

```
Sprung/Export/
├── Views/
│   ├── ResumeExportView.swift          ← trimmed (~325 lines)
│   ├── ReadinessCard.swift             ← extracted subview (NEW)
│   ├── PipelineTrackerView.swift       ← extracted subview (NEW)
│   └── MacOSToastOverlay.swift         ← extracted subview (NEW)
└── ExportFileService.swift             ← extracted service (NEW)
```

---

### File 1: `Sprung/Export/ExportFileService.swift` (NEW)

**Purpose:** Encapsulates all file-system export operations. Knows how to write PDF, text, and JSON files to `~/Downloads`, combine PDFs, sanitize filenames, and produce unique file URLs. Has no SwiftUI dependency.

**Lines to move from `ResumeExportView.swift`:**

| Lines | Content |
|-------|---------|
| 11–49 | `ExportOption` enum (moves here as its natural home alongside the service) |
| 341–384 | `sanitizeFilename`, `createUniqueFileURL`, `combinePDFs` |
| 388–594 | All seven `exportXxx` methods + `performExport` dispatcher + `isExportDisabled` |

**Signature sketch:**

```swift
import PDFKit
import Foundation

// ExportOption enum lives here

@MainActor
final class ExportFileService {
    private let jobAppStore: JobAppStore
    private let coverLetterStore: CoverLetterStore
    private let resumeExportCoordinator: ResumeExportCoordinator

    init(jobAppStore: JobAppStore,
         coverLetterStore: CoverLetterStore,
         resumeExportCoordinator: ResumeExportCoordinator) { ... }

    func performExport(_ option: ExportOption, onToast: @escaping (String) -> Void)
    func isExportDisabled(_ option: ExportOption, for jobApp: JobApp) -> Bool

    // Private helpers:
    private func exportResumePDF(onToast: ...)
    private func exportResumeText(onToast: ...)
    private func exportResumeJSON(onToast: ...)
    private func exportCoverLetterText(onToast: ...)
    private func exportCoverLetterPDF(onToast: ...)
    private func exportApplicationPacket(onToast: ...)
    private func exportAllCoverLetters(onToast: ...)
    private func sanitizeFilename(_ name: String) -> String
    private func createUniqueFileURL(baseFileName:extension:in:) -> (URL, String)
    private func combinePDFs(pdfDataArray: [Data]) -> Data?
}
```

**How `ResumeExportView` interacts with it:** The view instantiates `ExportFileService` (injected via `@Environment` or created in `onAppear` from environment values) and calls `service.performExport(selectedExportOption, onToast: showToastNotification)`. The `onToast` callback keeps the toast state local to the view where it belongs.

**Access changes:** `ExportOption` changes from `private` (it was already `internal`) to `internal` — no change needed. The service itself is `internal`.

---

### File 2: `Sprung/Export/Views/ReadinessCard.swift` (NEW)

**Purpose:** A tappable status card displaying an icon, title, readiness indicator, and subtitle. Generic enough to be reused anywhere an icon+status+title card is needed.

**Lines to move from `ResumeExportView.swift`:**

| Lines | Content |
|-------|---------|
| 606–662 | `ReadinessCard` struct (including `// MARK: - Readiness Card` comment) |

**Access change:** Remove `private` from the struct declaration, making it `internal`. The struct is already self-contained and has no dependency on `ResumeExportView`'s state.

**Imports needed:** `SwiftUI` only.

---

### File 3: `Sprung/Export/Views/PipelineTrackerView.swift` (NEW)

**Purpose:** A horizontal pipeline progress indicator. Renders main-pipeline nodes with connectors and dates, plus optional terminal nodes for rejected/withdrawn states. Fully data-driven via `currentStatus`, `dates`, and `onStatusTap`.

**Lines to move from `ResumeExportView.swift`:**

| Lines | Content |
|-------|---------|
| 664–781 | `PipelineTrackerView` struct (including `// MARK: - Pipeline Tracker` comment) |

**Access change:** Remove `private` from the struct declaration. The pipeline-date helpers that _remain_ in `ResumeExportView` (`pipelineDates(for:)` and `updateDateForStatus(jobApp:status:)`) stay in `ResumeExportView.swift` since they depend on `jobAppStore` — they feed data into `PipelineTrackerView` but are not part of the view itself.

**Imports needed:** `SwiftUI` only. `Statuses` must be visible (it already is `internal`).

---

### File 4: `Sprung/Export/Views/MacOSToastOverlay.swift` (NEW)

**Purpose:** A generic top-anchored toast notification overlay for macOS. Shows a checkmark + message with enter/exit animation.

**Lines to move from `ResumeExportView.swift`:**

| Lines | Content |
|-------|---------|
| 783–815 | `MacOSToastOverlay` struct (including `// MARK: - Toast Overlay` comment) |

**Access change:** Already `internal` — no change needed. Consider moving to `Sprung/Shared/Views/` if it is (or will be) used outside the Export module. For now, keeping it in `Sprung/Export/Views/` is fine since it is only referenced there.

**Imports needed:** `SwiftUI` only.

---

### What Remains in `ResumeExportView.swift` After Refactoring

- `import SwiftUI` (drop `import PDFKit`)
- `ResumeExportView` struct with:
  - `@Environment` properties
  - `@State` properties (retain `showToast`, `toastMessage`, `toastTimer`, `selectedExportOption`, etc.)
  - `body` and `onAppear`/`onChange`/`onReceive` modifiers
  - Five `sectionXxx(for:)` layout helpers
  - `sectionHeader(_:)` helper
  - `showToastNotification(_:)` (stays here; it manages `@State` toast properties)
  - `pipelineDates(for:)` and `updateDateForStatus(jobApp:status:)` (stay here; they use `jobAppStore`)
  - `getPrimaryApplyURL(for:)` (stays here; feeds `actionsSection`)

---

## 6. Implementation Order

1. Create `ExportFileService.swift` — move `ExportOption` enum and all file I/O methods. Build to catch import/dependency issues early (per project build strategy).
2. Update `ResumeExportView.swift` — replace inline export calls with `service.performExport(...)`. Remove moved code.
3. Create `MacOSToastOverlay.swift` — move the struct, remove from `ResumeExportView.swift`.
4. Create `ReadinessCard.swift` — move the struct, update access modifier.
5. Create `PipelineTrackerView.swift` — move the struct, update access modifier.
6. Remove `import PDFKit` from `ResumeExportView.swift` (it will no longer be needed there).
7. Final build verification.

---

## 7. Notes and Risks

- **`onToast` threading:** The existing `exportResumePDF` callback already dispatches to `DispatchQueue.main.async`. The service should be annotated `@MainActor` to avoid adding more dispatch call sites.
- **`ExportOption` consumers:** `Notification.Name.triggerExport` routing in `MenuNotificationHandler.swift` uses `ExportOption.fromKey(_:)`. Moving `ExportOption` to `ExportFileService.swift` does not change its visibility (still `internal`) so no import changes are needed in `MenuNotificationHandler.swift` or `MenuCommands.swift`.
- **`MacOSToastOverlay` reuse:** It is referenced only in `ResumeExportView.swift` today. If it is moved to `Sprung/Shared/Views/` in the future, no source changes are needed (just an Xcode group move) because its access is already `internal`.
- **No new protocols needed:** The service is a concrete `@MainActor` class. Adding a protocol abstraction would be speculative; skip it.
