# Phase SP1 – Core Lifecycle & DI Hardening

**Completion Date:** 2025-10-08

## Objectives Met
- Removed remaining singleton accessors (`AppState.shared`, `CoverLetterService.shared`) and shifted construction into `AppDependencies`.
- Introduced `AppEnvironment` as the canonical bundle of long-lived services and injected it through `ContentViewLaunch`.
- Updated all views and utilities to consume injected instances (CoverLetter workflows, batch generator, toolbar buttons, sheets).
- Replaced `fatalError` during model container creation with a recoverable launch flow that surfaces read-only mode guidance and backup restore actions.
- Applied read-only gating by disabling the main UI when storage fails and exposing ``AppEnvironment.launchState`` for downstream consumers.

## Validation
- `xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume build`
  - Completed successfully (warnings unchanged: Info.plist listed in Copy Bundle Resources).

## Follow-ups / Risks
- Read-only launch mode currently disables the main window; follow-on work should audit menu handlers to show an alert instead of silently ignoring write commands.
- Consider centralizing `ModelContainer` schema list to avoid duplication when new entities are added.
- Monitor CoverLetter batch workflows for concurrency regressions now that conversations are tracked per injected service instance.
