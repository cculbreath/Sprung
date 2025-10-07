# Phase 0 — Baseline & Project Hygiene

Scope: Execute Phase 0 from `ClaudeNotes/Final_Refactor_Guide_20251007.md`, familiarize with the codebase, and capture build/target details and baseline instructions. No code changes were made in this phase.

## What I Did

- Reviewed `ClaudeNotes/Final_Refactor_Guide_20251007.md` and confirmed Phase 0 tasks and deliverables.
- Scanned repo structure and key modules to orient for later phases.
- Collected build/target metadata from the Xcode project and Info files.
- Prepared a baseline checklist for screenshots/exports/stream tests for local execution.

## Repo Orientation (high‑level)

- App shell: `PhysCloudResume/App/PhysicsCloudResumeApp.swift`, `PhysCloudResume/App/Views/*`
- Data/model: SwiftData models and stores under `PhysCloudResume/ResModels`, `PhysCloudResume/DataManagers`
- AI: LLM UI/services under `PhysCloudResume/AI/*`
- Resume/Cover Letters: `PhysCloudResume/Resumes`, `PhysCloudResume/CoverLetters`
- Shared utilities: `PhysCloudResume/Shared/Utilities/*` (template processing, PDF/text export, logging, etc.)
- Export UI: `PhysCloudResume/ExportTab`, `PhysCloudResume/App/Views/PDFPreviewView.swift`
- Project: `PhysCloudResume.xcodeproj`, entitlements, assets

Notable observations that set up later phases:
- `ContentViewLaunch` constructs multiple stores inside `body` and uses global `AppState.shared` and `LLMService.shared` → aligns with Phase 1 DI/stable lifetimes.
- Menu commands rely heavily on `NotificationCenter` → aligns with Phase 8 scoping/cleanup.
- Custom template/context utilities (`ResumeTemplateProcessor`, `NativePDFGenerator`, etc.) → aligns with Phase 4 context builder consolidation.

## Build/Target Details (from project)

- Xcode upgrade marker: `LastUpgradeCheck = 2600` (Xcode 16.0).
- Swift version: `SWIFT_VERSION = 5.0` in target settings.
- Bundle ID: `Physics-Cloud.PhysCloudResume`.
- Deployment target (project level): `MACOSX_DEPLOYMENT_TARGET = 26.0`.
- Deployment target (target level): `MACOSX_DEPLOYMENT_TARGET = 26.0`.
  - Note: Per directive, both project and target are set to 26.0 for consistency.

Paths referenced:
- Project: `PhysCloudResume.xcodeproj/project.pbxproj`
- App entry: `PhysCloudResume/App/PhysicsCloudResumeApp.swift:60` (loads `ContentViewLaunch()`)
- ContentView init pattern: `PhysCloudResume/App/Views/ContentViewLaunch.swift`

## Baseline Capture — What to Run Locally

Create a dedicated phase branch and capture artifacts (screenshots, exports, LLM stream). Suggested commands and steps:

1) Create branch
   - `git checkout -b refactor/phase-0-baseline`

2) Build and launch
   - Open `PhysCloudResume.xcodeproj` in Xcode 16 on macOS Sequoia.
   - If build fails on `MACOSX_DEPLOYMENT_TARGET = 26.0`, temporarily set target’s deployment to `15.0` to proceed. Document the change (we will formalize in Phase 1).

3) Capture screenshots (save under `Docs/Baseline/`)
   - Main window with toolbar/sidebars
   - Resume inspector and Cover Letter inspector panels
   - Template Editor, PDF preview

4) Capture exports (save under `Docs/Baseline/`)
   - Export one résumé as PDF: use “Résumé → Export Resume as PDF”
   - Export same résumé as Text: “Résumé → Export Resume as Text”

5) LLM streaming + structured output smoke
   - Provide a dummy OpenRouter API key (if feature requires) and run a minimal prompt in a screen that streams tokens (e.g., revise/clarify resume).
   - Save a short screen recording or screenshots and the resulting JSON/text output.

6) Tag checkpoint
   - `git tag -a phase-0-checkpoint -m "Phase 0: baseline artifacts captured"`

Deliverables location suggestion:
- `Docs/Baseline/screenshots/...`
- `Docs/Baseline/exports/resume-sample.pdf`
- `Docs/Baseline/exports/resume-sample.txt`
- `Docs/Baseline/llm/streaming-demo.(mov|png)` and response snapshot

## Constraints / Notes

- This environment cannot run Xcode, so the baseline build/launch and artifacts must be collected locally. Instructions and paths are provided above.
- Build hygiene: target‑level `MACOSX_DEPLOYMENT_TARGET = 26.0` is a likely blocker; adjust to `15.0` for baseline. We will make a clean, committed fix during Phase 1.

## Ready for Phase 1

Validated entry points and target files exist:
- DI/stores: `PhysCloudResume/App/PhysicsCloudResumeApp.swift`, `PhysCloudResume/App/Views/ContentViewLaunch.swift`, `PhysCloudResume/DataManagers/*Store.swift`
- Safety pass candidates exist for Phase 2, e.g., `Shared/Utilities/NativePDFGenerator.swift`

Phase 1 objective preview:
- Introduce `AppDependencies` (or `@State`‑owned `@Observable` stores) at the scene root, inject via `.environment(...)`, stop constructing stores in `View.body`, and remove global `.shared` dependencies from view creation paths.

## Quick Checklist

- [ ] Branch created: `refactor/phase-0-baseline`
- [ ] Build succeeds on Xcode 16 (macOS 15 target)
- [ ] Screenshots captured (main, inspectors, template editor, preview)
- [ ] Resume export captured (PDF + Text)
- [ ] LLM streaming/structured output smoke captured
- [ ] Tag created: `phase-0-checkpoint`

— End of Phase 0 progress —
