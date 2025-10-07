# Phase 2 — Safety Pass: Remove Force‑Unwraps and FatalErrors

Status: ✅ Complete
Branch: `refactor/phase-1-di-skeleton`
Date: 2025-10-07

Objective
- Eliminate user‑reachable force‑unwraps (`!`, `as!`, `try!`) and `fatalError` calls.
- Replace with guarded logic, optional binding, and user‑visible or logged errors.

Summary of Changes
- NativePDFGenerator
  - Removed force‑unwrap when returning generated PDF; guarded `self` and PDF data.
  - File: `PhysCloudResume/Shared/Utilities/NativePDFGenerator.swift`

- NewAppSheetView
  - Replaced `URL(string:)!` with guarded parsing; show error on invalid URL.
  - File: `PhysCloudResume/JobApplications/Views/NewAppSheetView.swift`

- IndeedJobScrape
  - Replaced `locArray.first!` with safe binding; handle empty arrays.
  - File: `PhysCloudResume/JobApplications/Models/IndeedJobScrape.swift`

- CoverLetterModelNameFormatter
  - Replaced `.last!` with safe optional handling.
  - File: `PhysCloudResume/CoverLetters/AI/Utilities/CoverLetterModelNameFormatter.swift`

- JobAppStore
  - Replaced multiple `fatalError` calls in user flows (delete/edit/cancel/save) with logged errors and safe early returns.
  - File: `PhysCloudResume/DataManagers/JobAppStore.swift`

- ImageButton
  - Replaced initializer `fatalError` with a logged fallback to a safe system image when misconfigured.
  - File: `PhysCloudResume/Shared/UIComponents/ImageButton.swift`

Additional Safety Fixes
- FontNodeView
  - Replaced chained unwraps `selectedApp!.selectedRes!` with safe optional binding.
  - File: `PhysCloudResume/ResumeTree/Views/FontNodeView.swift`

- TextRowViews
  - Removed `trailingText!.isEmpty` in frame calculation; use optional checks.
  - File: `PhysCloudResume/Shared/UIComponents/TextRowViews.swift`

- Template and Documents paths
  - Replaced `.first!` for `FileManager.default.urls(...).first` with guarded access or fallbacks in:
    - `NativePDFGenerator.swift` (user template lookup)
    - `ResumeTemplateProcessor.swift` (template lookup)
    - `TextResumeGenerator.swift` (text template lookup)
    - `TemplateEditorView.swift` (load/save/delete template paths)
    - `FileHandler.swift` (Application Support directory)
    - `CloudflareCookieManager.swift` (cookie directory)

- OpenRouterService
  - Replaced `pricingData.first!/last!` with safe guards in pricing logs.
  - File: `PhysCloudResume/AI/Models/Services/OpenRouterService.swift`

- ClarifyingQuestionsSheet / TemplateTextEditor
  - Replaced `as! NSTextView` casts with safe casts and guards in NSViewRepresentable implementations.
  - Files:
    - `PhysCloudResume/JobApplications/AI/Views/ClarifyingQuestionsSheet.swift`
    - `PhysCloudResume/App/Views/TemplateTextEditor.swift`

- CoverLetterPDFGenerator
  - Replaced `mutableCopy() as! NSMutableParagraphStyle` with safe copy/fallback.
  - File: `PhysCloudResume/CoverLetters/Utilities/CoverLetterPDFGenerator.swift`

- ImageConversionService
  - Replaced `NSGraphicsContext.current!.cgContext` with guarded context handling.
  - File: `PhysCloudResume/AI/Models/Services/ImageConversionService.swift`

- TreeNodeModel depth
  - Replaced `parent!.depth` with optional mapping.
  - File: `PhysCloudResume/ResumeTree/Models/TreeNodeModel.swift`

- TreeToJson
  - Removed `items!` usage in JSON assembly; guarded optionals.
  - File: `PhysCloudResume/ResumeTree/Utilities/TreeToJson.swift`

- ResumeReviewViewModel
  - Removed `reviewService!` unwraps during service wiring; guard presence.
  - File: `PhysCloudResume/Resumes/AI/Views/ResumeReviewViewModel.swift`

- ResumeInspectorListView
  - Replaced `resume.model!.name` with a safe fallback label.
  - File: `PhysCloudResume/Resumes/Views/ResumeInpectorListView.swift`

Remaining Considerations
- `Shared/Utilities/JSONParser.swift` contains force‑unwraps within internal parsing/error paths (ported from Swift’s parser). Low risk to users and slated for removal in Phase 4 when we consolidate template/JSON handling. Left unchanged to avoid destabilizing the parser.

Validation
- Build compiles; UI flows tested for:
  - Creating/editing/deleting Job Applications
  - Resume/Cover Letter export paths
  - Template editing and preview generation
  - Model pickers when no models meet capability (safe messaging)
  - No user‑path crashes from unwraps or casts

Next
- Phase 3 — Secrets and Configuration (Keychain‑backed APIKeyManager, AppConfig constants).

