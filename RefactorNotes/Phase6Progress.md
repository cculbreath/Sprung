# Phase 6 — LLM Facade and Concurrency Hygiene

Status: 🚧 In Progress  
Branch: `refactor/phase-1-di-skeleton`  
Date: 2025-10-08

## Objective
- Replace remaining direct `LLMService.shared` call sites with the injected `LLMFacade`.
- Keep multi-turn workflows (resume revision, clarifying questions, cover letters) functioning while migrating to DTO-based streaming.
- Surface facade hooks needed for structured streaming so downstream view models can stay decoupled from vendor types.

## Changes (current slice)
- Replaced direct `LLMService.shared` usage with dependency-injected instances; `AppDependencies` now owns the service and seeds it into the environment for views and settings.
- `LLMFacade.validate` is asynchronous and consults `ModelValidationService` on-demand; capability outcomes are persisted back into `EnabledLLMStore`, including JSON-schema failure heuristics.
- Introduced `LLMStreamingHandle` plus per-feature cancellation for clarifying questions, resume revision, and fix-fits review; affected view models capture handles and expose targeted cancel paths instead of invoking global `cancelAllRequests`.
- Added `LLMFacade.executeStructuredStreaming` to expose structured streaming through DTOs and refactored `ResumeReviewService`, `ResumeReviseViewModel`, and `ClarifyingQuestionsViewModel` to consume the new handles.
- Migrated cover letter flows (`CoverLetterService`, batch generator, multi-model committee + summary generator) and toolbar actions (`AppWindowView`) to the injected facade; removed fallbacks to `LLMService.shared`.
- Swapped `SkillReorderService` to depend on `LLMFacade`, completing the AI service migration off the singleton surface.
- Converted `LLMRequestExecutor` into an isolated actor and dispatched configuration/cancellation work off the main actor; `LLMService` now uses async initialization checks so network calls no longer execute on the main thread before suspension.
- Added facade-level gating that respects `EnabledLLMStore` selections and enforces structured-output requirements when a JSON schema is requested.

## Validation
- `xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume -destination 'platform=macOS' build`
- Smoke: basic reasoning stream parsing exercised via updated DTO pipeline during local inspection (no runtime execution available in CLI).

## Next
- Continue narrowing `@MainActor` usage inside `LLMService`/`LLMRequestExecutor`, keeping network work off the UI thread.
- Follow-up gating audit for ancillary AI features (e.g., application review) to ensure new validation pipeline covers edge cases.
- Additional manual smoke once the remaining concurrency clean-up lands (resume revision, clarifying questions, cover letter generation).
