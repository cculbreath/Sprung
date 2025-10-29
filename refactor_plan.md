# Onboarding Interview Slim-Down Plan

## Objectives
- Finish decomposing `OnboardingInterviewService` into a thin façade that defers lifecycle, persistence, and tool orchestration to the coordinator layer.
- Ensure router/handler components expose all UI-facing state so SwiftUI views and action handlers no longer touch legacy fields.
- Leverage `PhaseScriptRegistry` and `WizardProgressTracker` to drive system prompt construction and wizard visuals.
- Align documentation with the finalized architecture so future contributors understand the ownership model.

## Team Setup
- **Developer A** – Coordinator lifecycle & façade reduction
- **Developer B** – Tool router capability/state reporting
- **Developer C** – UI/action handler integration
- **Developer D** – Documentation & cleanup

## Coordination Notes
- All developers share the same `OnboardingInterviewCoordinator`; check in before changing initializer signatures.
- Expose new coordinator APIs as async-safe (`@MainActor`) so SwiftUI usage stays consistent.
- Update `OnboardingInterviewService` only after the corresponding coordinator functionality is ready to avoid broken build windows.
- When adjusting capability manifest logic, update `Sprung/Onboarding/ARCHITECTURE.md` and log format expectations.
- Run `xcodebuild -project Sprung.xcodeproj -scheme Sprung -destination 'platform=macOS' build` after each major milestone.

## Workstreams & TODO Lists

### Developer A — Coordinator Lifecycle & Service Facade
- [ ] Migrate `startInterview/sendMessage/resetInterview` orchestration into `OnboardingInterviewCoordinator` (including system prompt assembly using `PhaseScriptRegistry`).
- [ ] Move checkpoint persistence/restore logic into the coordinator and remove direct `Checkpoints` usage from the façade.
- [ ] Eliminate remaining wizard-state mutations from `OnboardingInterviewService`; rely solely on `WizardProgressTracker`.
- [ ] Collapse duplicated payload helpers in the service (choice/validation/upload/profile) into coordinator calls and prune unused legacy state.
- [ ] Verify the service initializer only wires dependencies and environment bindings (no business logic).

### Developer B — Tool Router & Capability Reporting
- [ ] Extend `OnboardingToolRouter` to publish a consolidated status model (ready/waiting/processing) for each tool.
- [ ] Replace `OnboardingInterviewService.capabilityManifest()` with coordinator-driven logic that consumes the router status model.
- [ ] Remove `pendingContactsRequest` and any other orphan state—route contacts permission through `ProfileInteractionHandler` and the router.
- [ ] Ensure router handlers emit analytics/logging hooks (success/failure) for uploads, prompts, and profile intake.
- [ ] Update `OnboardingInterviewActionHandler` to call coordinator APIs directly (no lingering references to removed façade methods).

### Developer C — UI & Action Integration
- [ ] Refactor SwiftUI views (`OnboardingInterviewView`, tool pane components) to bind directly to coordinator-published state (prompts, uploads, wizard progress).
- [ ] Replace any view logic that inspects legacy façade properties (e.g., `pendingApplicantProfileRequest`) with coordinator/router equivalents.
- [ ] Simplify `OnboardingInterviewActionHandler` to mirror the coordinator surface; remove unused placeholder methods and ensure cancellation flows propagate back to handlers.
- [ ] Exercise the intake flows manually (upload, URL, contacts, manual) to confirm UI reacts correctly to router state (waiting vs processing).
- [ ] Adjust logging/UI toast messages to align with new router-driven statuses (especially for contact fetch and upload retries).

### Developer D — Documentation & Cleanup
- [ ] Update `Sprung/Onboarding/ARCHITECTURE.md` with the final coordinator/router/handler diagram and lifecycle description.
- [ ] Author migration notes explaining new public APIs (`OnboardingInterviewCoordinator`, `WizardProgressTracker`, `PhaseScriptRegistry`).
- [ ] Remove obsolete utilities (old contact fetch helpers, upload temp methods, unused models) and ensure no dead code lingers.
- [ ] Review capability manifest output against product requirements and document the status fields in `docs/`.
- [ ] Add inline documentation/comments where necessary to clarify ownership boundaries (service vs. coordinator vs. router).

## Definition of Done
- `OnboardingInterviewService` exposes only façade-level methods and computed properties; all stateful logic lives in coordinator/router/managers.
- Capability manifest derives from router status and accurately reflects UI state transitions.
- SwiftUI views and action handlers consume coordinator-managed state without referencing deprecated service properties.
- Phase scripts and wizard tracker drive prompts, wizard visuals, and phase advancement checks.
- Architecture docs and inline comments reflect the finalized structure; no orphan files remain.
