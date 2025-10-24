# Milestone 1 – Pending Implementations

This inventory captures the onboarding-interview code paths that are currently stubs, placeholders, or intentionally incomplete. Use it to scope follow-up work after the Phase 1 usable milestone.

## Runtime & Action Layer

- `Sprung/Onboarding/Core/OnboardingInterviewActionHandler.swift:68` – contact import hooks (`fetchApplicantProfileFromContacts`, `declineContactsFetch`) only log debug messages. The Contacts tool should call into `OnboardingInterviewService` once we support permission prompts and data merge.
- `Sprung/Onboarding/Core/OnboardingInterviewActionHandler.swift:92` – section entry review methods (`completeSectionEntryRequest`, `declineSectionEntryRequest`) are placeholders; the section-entry validation loop still needs service support and tool wiring.
- `Sprung/Onboarding/Core/OnboardingInterviewActionHandler.swift:104` – link-based uploads degrade to `skipUploadRequest`; real link ingestion (e.g., LinkedIn URL fetch) remains to be implemented under the auth-gated tooling plan.
- `Sprung/Onboarding/Core/OnboardingInterviewActionHandler.swift:113` – extraction confirmation and cancellation hooks are stubs pending extraction review UI/service logic.

## Service State Management

- `Sprung/Onboarding/Core/OnboardingInterviewService.swift:23` – `pendingContactsRequest`, `pendingSectionEntryRequests`, and `pendingExtraction` are tracked but never populated. Future milestones need presenter methods (mirroring upload/validation) so the UI cards can surface these flows.
- `Sprung/Onboarding/Core/OnboardingInterviewService.swift:263` – section toggle resolution now exists, but there is no counterpart to create toggle requests. Tool support for enabling/disabling sections must populate `pendingSectionToggleRequest` and set `sectionToggleContinuationId`.

## Tool Layer

- `Sprung/Onboarding/Tools/Implementations/GetMacOSContactCardTool.swift:37` – requesting a specific contact returns an `"not implemented yet"` error by design. When multi-contact selection arrives, extend the Contacts bridge accordingly.
- Auth-dependent tools mentioned in the design docs (e.g., `fetch_url`, GitHub queries) are intentionally absent/stubbed. Ensure they continue to return “not configured” responses until credentials and UX are ready.

## UI Components Waiting on Data

- `Sprung/Onboarding/Views/Components/ResumeSectionsToggleCard.swift` and `ResumeSectionEntriesCard.swift` assume the service will provide toggle/entry requests, but no runtime path currently feeds them.
- `Sprung/Onboarding/Views/Components/ExtractionReviewSheet.swift` expects `OnboardingPendingExtraction` to be populated with raw JSON and uncertainty annotations. The orchestrator/service workflow that captures LLM extraction review data is still pending.

Keep this list updated as features graduate from stub status during Milestones 2 and 3. Remove entries once the corresponding runtime, tool, and UI wiring ships.***
