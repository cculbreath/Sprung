# Phase 3 — Secrets and Configuration

Status: ✅ Complete
Branch: `refactor/phase-1-di-skeleton`
Date: 2025-10-07

Objective
- Store API keys in Keychain (not UserDefaults).
- Replace key reads in services/views with a Keychain-backed manager.
- Centralize non-secret configuration constants (URLs, headers).

What Changed
- Keychain Manager
  - Added `APIKeyManager` for get/set/delete of keys using Keychain, plus one-time migration from `UserDefaults`.
  - File: `PhysCloudResume/Shared/Utilities/APIKeyManager.swift`

- App Configuration
  - Added `AppConfig` (base URL, API path/version, headers) for OpenRouter service.
  - File: `PhysCloudResume/Shared/Utilities/AppConfig.swift`

- OpenRouter key usage migrated to Keychain
  - `LLMRequestExecutor.configureClient()` now uses `APIKeyManager.get(.openRouter)` and `AppConfig` values.
    - File: `PhysCloudResume/AI/Models/Services/LLMRequestExecutor.swift`
  - `ModelValidationService.validateModel(_:)` now fetches key via Keychain.
    - File: `PhysCloudResume/AI/Models/Services/ModelValidationService.swift`
  - `AppState.configureOpenRouterService()` migrates from `UserDefaults` → Keychain (idempotent) and configures service from Keychain.
    - File: `PhysCloudResume/App/AppState.swift`
  - `AppState.hasValidOpenRouterKey` uses Keychain.
    - File: `PhysCloudResume/App/AppState+APIKeys.swift`

- OpenAI TTS key usage migrated to Keychain
  - Settings writes OpenAI TTS key to Keychain; posts `.apiKeysChanged` notification.
    - File: `PhysCloudResume/App/Views/Settings/APIKeysSettingsView.swift`
  - TTS Settings and Toolbar button read from Keychain via `AppState.hasValidOpenAiKey` and `APIKeyManager.get(.openAI)`; reinitialize on `.apiKeysChanged`.
    - Files:
      - `PhysCloudResume/App/Views/Settings/TextToSpeechSettingsView.swift`
      - `PhysCloudResume/App/Views/ToolbarButtons/TTSButton.swift`
  - Added `Notification.Name.apiKeysChanged` for decoupled updates.
    - File: `PhysCloudResume/App/Views/MenuCommands.swift`

Behavior Notes
- UserDefaults → Keychain migration runs once at app startup (safe to call multiple times).
- UI disables TTS features when no valid OpenAI key is present.
- OpenRouter client uses `AppConfig` for base URL, API path, version, and headers.

Out of Scope (tracked)
- ScrapingDog and Proxycurl keys still use `UserDefaults` in Views; can be migrated later with similar pattern if desired.

Validation
- Verified OpenRouter client config uses Keychain and AppConfig.
- Verified TTS button initializes provider only when key exists; respects enable/disable setting.
- Settings “OpenAI TTS” save writes to Keychain and triggers re-init via notification.

Next
- Phase 4 — Export Pipeline and Template Context Builder.

