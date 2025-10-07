# Phase 4 — Export Pipeline & Template Context Builder

Status: ✅ Completed (core scope)
Branch: `refactor/phase-1-di-skeleton`
Date: 2025-10-07

Objective
- Remove custom JSON parser from app paths.
- Ensure a single TreeNode → Template Context builder powers HTML/PDF and text exports.
- Keep UI/service boundaries clear in export code.

What Changed
- Removed custom JSON parser from production code
  - Deleted `Shared/Utilities/JSONParser.swift`.
  - Rewrote `JsonToTree.parseUnwrapJson` to use `JSONSerialization` and construct an `OrderedDictionary` using `JsonMap.sectionKeyToTypeDict` order, followed by any extra keys (alphabetical) for determinism.
  - Files:
    - Deleted: `PhysCloudResume/Shared/Utilities/JSONParser.swift`
    - Updated: `PhysCloudResume/ResumeTree/Utilities/JsonToTree.swift`

- Unified template context builder remains the single source
  - PDF (HTML) and Text both use TreeToJson → JSONSerialization → [String: Any] context via:
    - `ResumeTemplateProcessor`, `NativePDFGenerator`, and `TextResumeGenerator`.
  - No behavioral changes required in export views/services.

Validation
- Verified no app code references `JSONParser`.
- Test exports: PDF/Text (using default or custom templates) still generate.
- Baseline flows unchanged: debounce export, ResumeExportService, and template loading.

Notes / Future
- Scripts folder still contains a copy of the old parser for reference only (not compiled).
- If needed, we can further reduce duplication between `NativePDFGenerator` and `TextResumeGenerator` context creation by extracting a tiny shared utility (out of current phase scope).

