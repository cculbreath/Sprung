# PhysCloudResume: Codebase References Requiring Review or Clarification

Use this list to target review and clarify edge cases before or during the refactor. Paths are workspace‑relative.

## App Lifecycle and Command Bridge
- App/PhysicsCloudResumeApp.swift: App entry, menu/toolbar commands, NotificationCenter posts, and environment setup.
- App/Views/MenuNotificationHandler.swift: Command bridge observers and side effects; ensure scope remains limited to UI coordination.
- App/Views/MenuCommands.swift: Notification namespace; confirm only command/toolbar parity events live here.

## Global Singletons / Hidden Dependencies
- App/AppState.swift: Singleton holding both UI state and service references; plan to move services into `AppDependencies` and UI state into `SessionState`.
- AI/Models/Services/LLMService.swift: Singleton, tightly coupled to `SwiftOpenAI`; many call sites reference `.shared`.
- AI/Models/Services/OpenRouterService.swift: Singleton + UserDefaults caching; API key configuration flows.
- Shared/Utilities/Logger.swift: Static logger mixed with UserDefaults and file IO; target `os.Logger` wrapper.
- Shared/Utilities/KeychainHelper.swift: Static helpers; wrap behind `SecureStorage` protocol.

## JSON and Tree Utilities
- Shared/Utilities/JSONParser.swift: Custom byte‑level parser; replace with `JSONSerialization`.
- ResumeTree/Utilities/JsonToTree.swift: Depends on custom parser; refactor to stdlib.
- ResumeTree/Utilities/TreeToJson.swift: Manual JSON via strings; replace with `ResumeTemplateDataBuilder`.
- ResumeTree/Models/TreeNodeModel.swift: `orderedChildren`, `myIndex`, and JSON export helpers; ensure builder preserves order and expected keys.

## Export/PDF Pipeline and UI Entanglement
- Shared/Utilities/ResumeExportService.swift: Contains `NSAlert`/panel logic; extract into `ExportTemplateSelection` UI helper.
- Shared/Utilities/NativePDFGenerator.swift: Rendering + preprocessing + debug file writes; keep to rendering concerns; switch to builder context.

## Stores, Views, and Force Unwraps
- DataManagers/JobAppStore.swift: Mixed UI/store responsibilities; `fatalError` and NotificationCenter “RefreshJobApps” listener (likely dead code).
- Resumes/ViewModels/ResumeDetailVM.swift: ViewModel created from UI with `.shared` services; move to DI via environment.
- App/Views/ContentView.swift: Constructs `ResumeReviseViewModel` with `LLMService.shared`; swap to dependencies.
- Sidebar/Views/SidebarView.swift; ResumeTree/Views/*; CoverLetters/Views/*: Audit for force unwraps, direct singleton access, or persistence in views.

## LLM Reasoning UI and State
- App/AppState.swift: `globalReasoningStreamManager` stored on singleton; consider lifting to `SessionState` (purely UI).
- AI/Views/ReasoningStreamView.swift: Modal overlay; verify it responds correctly when DI replaces `.shared` usages in upstream services.

## SwiftData and ModelContainer
- DataManagers/*Store.swift: All `SwiftDataStore` adopters; confirm `modelContext` lifetimes under environment DI.
- Resumes/Models/Resume.swift: Debounce export and background work; ensure UI is main‑threaded and IO off main.

## Concurrency and `@MainActor`
- Classes annotated `@MainActor` broadly (e.g., services): narrow to UI entry points; move blocking work off main.

## NotificationCenter Cleanups
- DataManagers/JobAppStore.swift: Remove `RefreshJobApps` observer if truly unused.
- App/Views/*Toolbar* and command wiring: confirm notifications remain focused on UI bridging only (no state propagation).

## Open Questions (clarify before changes)
- Template override locations and expectations: `NativePDFGenerator` searches multiple locations and embedded templates; confirm the intended precedence.
- Mustache helper parity: `preprocessTemplateForGRMustache` trims helpers; confirm no required helpers are lost.
- Conversation persistence scope: References to `ConversationContext`/`ConversationMessage` schemas exist; confirm intended usage and UI entry points.

