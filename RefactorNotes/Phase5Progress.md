# Phase 5 — Export Pipeline Boundary

Status: ✅ Complete
Branch: `refactor/phase-1-di-skeleton`
Date: 2025-10-07

Objective
- Move UI prompts (alerts/pickers) out of `ResumeExportService`.
- Keep service orchestration separated from UI concerns; renderer remains rendering-only.

Changes
- New helper: `ExportTemplateSelection`
  - Owns `NSAlert`/`NSOpenPanel` flows for missing template selection and optional CSS selection.
  - Provides CSS embedding helper.
  - File: `PhysCloudResume/Shared/Utilities/ExportTemplateSelection.swift`

- Service update
  - `ResumeExportService.handleMissingTemplate` now delegates to `ExportTemplateSelection` and no longer contains view logic.
  - File: `PhysCloudResume/Shared/Utilities/ResumeExportService.swift`

Validation
- Missing-template flow: prompts appear, custom HTML/CSS saved, and export proceeds.
- Renderer remains rendering-only (no UI dependencies).

Next
- Phase 6 — LLM facade + DTO adapters and concurrency hygiene.

