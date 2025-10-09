# Phase SP3 – Progress Log (2025-10-23)

## Completed
- Replaced the legacy `TreeToJson` pipeline with `ResumeTemplateDataBuilder` and removed the manual JSON string builder.
- Introduced `ResumeExportCoordinator` + `ResumeExportService` to centralize export throttling and async rendering outside the `Resume` model; updated all call sites.
- Added SwiftData-backed template storage (`Template`, `TemplateAsset`, `TemplateStore`) with automatic bootstrap via `TemplateImporter`.
- Updated PDF/text generators, export flows, and Template Editor to read/write templates through SwiftData while keeping file-system overrides as fallback.
- Wired new dependencies through `AppDependencies`/`AppEnvironment`, ensuring resumes track their template selections.

## In Progress / Next
- Expand Template Editor UI to expose CSS/assets and surface selected template per resume.
- Document the new template architecture and coordinator workflow in developer notes / README.
- Sanity check exports after import of legacy templates (HTML + text parity).
