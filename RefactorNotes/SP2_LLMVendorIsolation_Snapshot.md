# SP2 – LLM Vendor Isolation Snapshot (2025-02-17)

## Context & Intent
- We are mid-way through **Phase SP2** of `RefactorNotes/SecondPassRefactoring.md`, focused on isolating the LLM layer from `SwiftOpenAI`, tightening concurrency, and removing `@MainActor` leakage.
- Phase SP1 DI work is partially in place (new environment scaffolding landed in the previous slice), but `LLMService` still owns singletons internally. We’re preserving the existing public API surface to avoid mass call-site rewrites.
- No automated tests exist; validation is manual via targeted smoke runs.

## Current Objectives
1. Finish the DTO boundary so `SwiftOpenAI` stays confined to adapter code.
2. Replace `ConversationManager` with the new SwiftData-backed `LLMConversationStore`.
3. Remove unnecessary `@MainActor` usage (`LLMService`, `OpenRouterService`) while keeping UI consumers safe.
4. Ensure request building and image handling are resilient (no force unwraps).
5. Update the façade (`LLMFacade`) and DI wiring (`AppDependencies`) to use the new internals without breaking callers.

## Progress So Far
- ✅ Added domain DTO layer in `PhysCloudResume/AI/Models/LLM/LLMDomain.swift` with conversion helpers.
- ✅ Hardened `LLMRequestBuilder` to use DTOs, validate image data URLs, and guard conversions.
- ✅ Introduced SwiftData-aware `LLMConversationStore.swift` plus DTO-ready `ConversationContext` / `ConversationMessage` models.
- ✅ Documented revised Phase SP2 scope in notes (tests references removed per user request).
- ✅ Completed `LLMService`/`LLMFacade` DTO migration and retired `ConversationManager` in favor of SwiftData-backed persistence with streaming support.

## Outstanding Work
- ⏳ Manual validation: run a smoke pass that creates a conversation, persists it, reloads it, and makes sure image inputs still work.

## Risks & Considerations
- Maintaining API compatibility is critical—many views call directly into `LLMService`.
- Need to re-check all force-unwrapped URLs after the service rewrite.
- Keep an eye on logging: the new async work must still surface failures to `Logger`.

## Next Steps for the Incoming Agent
1. Perform the manual end-to-end smoke test (conversation create → persist → resume with images).
2. Capture any follow-up observations or regressions uncovered during manual validation.

## Reference Files
- Domain DTOs: `PhysCloudResume/AI/Models/LLM/LLMDomain.swift`
- Conversation persistence: `PhysCloudResume/AI/Models/LLM/LLMConversationStore.swift`
- Service entry point (pending rewrite): `PhysCloudResume/AI/Models/Services/LLMService.swift`
- Facade: `PhysCloudResume/AI/Models/Services/LLMFacade.swift`
- DI wiring: `PhysCloudResume/App/AppDependencies.swift`
- Concurrency target: `PhysCloudResume/AI/Models/Services/OpenRouterService.swift`
- Plan source: `RefactorNotes/SecondPassRefactoring.md#L34`
