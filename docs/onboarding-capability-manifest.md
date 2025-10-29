# Onboarding Capability Manifest

The onboarding interview exposes a capability manifest (version `2`) so the interview orchestrator can discover which tools are available and whether user action is required. This document summarizes the status fields emitted by `OnboardingInterviewService.capabilityManifest()`.

---

## Status Vocabulary

| Status | Meaning | Source |
| ------ | ------- | ------ |
| `ready` | Tool can be invoked immediately. No user input is pending. | Default state when no handler has outstanding work. |
| `waiting_for_user` | UI needs input before the tool can resume. | A handler has an active choice/intake/validation request. |
| `processing` | Operation in progress; orchestrator should wait. | Long-running background work (e.g., contacts import, uploads). |
| `locked` | Tool is unavailable because the required backend is absent. | Example: `generate_knowledge_card` when no OpenAI client exists. |

---

## Tool Status Details

### `capabilities_describe`
- Always `ready`.
- Call at the start of each phase to refresh tool availability.

### `get_user_option`
- `waiting_for_user` when `OnboardingToolRouter` has an active `pendingChoicePrompt`.
- Otherwise `ready`.

### `get_user_upload`
- `waiting_for_user` when there are outstanding upload requests.
- Includes metadata:
  - `accepts`: Allowed file extensions.
  - `max_bytes`: Current upload size cap (10 MB).

### `get_macos_contact_card`
- `processing` while `ProfileInteractionHandler` is in `.loading` mode (contacts import in progress).
- Otherwise `ready`.

### `get_applicant_profile`
- `waiting_for_user` when either an intake flow (`pendingApplicantProfileIntake`) or validation request (`pendingApplicantProfileRequest`) is active.
- `paths` enumerates supported intake modes (`upload`, `url`, `contacts`, `manual`).

### `extract_document`
- `processing` whenever an extraction review is pending (`pendingExtraction` set).
- Includes capabilities metadata (`supports`, `ocr`, `layout_preservation`, `return_types`).

### `submit_for_validation`
- `waiting_for_user` while a validation prompt is displayed.
- `data_types` enumerates supported payload categories.

### `persist_data`
- Always `ready` and lists allowed `data_types`.

### `set_objective_status`
- Always `ready`; updates objective completion flags.

### `next_phase`
- Always `ready`; transitions interview phases after validation.

### `generate_knowledge_card`
- `ready` when an OpenAI client is available (`KnowledgeCardAgent` exists).
- `locked` when the optional dependency is missing.

---

## Implementation Notes

- The manifest is read under `@MainActor` to ensure consistency with SwiftUI-observed state.
- When adding new tools, extend the manifest with the same status vocabulary. Keep metadata arrays (`accepts`, `paths`, `data_types`) alphabetical to simplify diffs.
- The orchestrator expects the manifest to be side-effect free—do not perform expensive computations or disk reads.

