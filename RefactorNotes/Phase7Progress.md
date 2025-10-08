# Phase 7 — Logging and Diagnostics

Status: ✅ Complete  
Branch: `refactor/phase-1-di-skeleton`  
Date: 2025-10-09

## Objective
- Introduce a `Logging` protocol with an `os.Logger` backend while maintaining the existing `Logger` facade.
- Centralize debug settings so verbosity and file logging are runtime configurable instead of relying on ad-hoc `UserDefaults` reads.
- Reduce noisy main-actor logs in high-frequency UI flows and attach category metadata for easier filtering.

## Changes
- Rebuilt `Shared/Utilities/Logger.swift` around a configurable `Logger.Configuration`, a pluggable backend (`OSLoggerBackend`), and category-aware log routing. Added newline sanitization, optional metadata, and file persistence guarded to debug builds.
- Added `App/Models/DebugSettingsStore`, exposing observable log level and `saveDebugPrompts` toggles; `AppDependencies` instantiates the store, hooks it into `AppState`, and injects it through the SwiftUI environment (including the Settings window).
- Updated `DebugSettingsView` to bind directly to the new store, keeping UI in sync without `@AppStorage`.
- Retooled key call sites (`AppDependencies`, `ContentView`, `AppSheets`, `AppState`, `PhysicsCloudResumeApp`, `ReasoningStreamManager`, `LLMRequestExecutor`) to supply log categories, gate verbose diagnostics, and shift side-effect logging into `.onAppear` or async handlers to avoid `@ViewBuilder` pollution.
- Clarified reasoning overlay logging by moving modal traces to appear hooks and letting `ReasoningStreamManager` handle state-change messages only when verbose logging is enabled.
- Ensured `AppDelegate` injects the debug settings store for settings windows, keeping toggles consistent across scenes.

## Validation
- `xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume build`

## Next
- Audit remaining services that call `UserDefaults.standard.bool(forKey: "saveDebugPrompts")` and migrate them to consume `DebugSettingsStore` once those flows move to the new export pipeline.
- Evaluate whether additional log metadata (request IDs, model IDs) should be lifted into `Logger` `metadata` arguments for structured filtering once structured logging is adopted elsewhere.
