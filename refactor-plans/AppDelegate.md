# AppDelegate.swift Refactoring Plan

**File:** `Sprung/App/AppDelegate.swift`
**Total lines:** 926
**Date analyzed:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

`AppDelegate` is the `NSApplicationDelegate` for Sprung. Its stated job is to respond to application lifecycle events. In practice it has accumulated four distinct jobs:

1. Application lifecycle (launch, URL scheme handling, menu setup)
2. Toolbar wiring (attaching the `ToolbarCoordinator` to the main `NSWindow`)
3. Secondary-window presentation — creating, hosting, and managing nine separate `NSWindow` instances, each wrapping a SwiftUI view in an `NSHostingView`
4. Business-logic helper (`buildSeedGenerationContext`) that assembles a domain object from multiple stores

The class also holds 23 optional `var` properties — essentially a manual dependency-injection bag — because SwiftUI's `.onAppear` in `SprungApp` imperatively assigns them after launch.

---

## 2. Distinct Logical Sections

| Lines | Section | What it does |
|-------|---------|--------------|
| 10–38 | Property declarations | 8 window refs, 1 toolbar coordinator ref, 14 store/coordinator refs |
| 39–66 | `applicationDidFinishLaunching` | Deferred menu setup; registers 3 `NotificationCenter` observers |
| 68–97 | `setupMainWindowToolbar` | Creates `ToolbarCoordinator`, finds the main `NSWindow`, attaches `NSToolbar` |
| 99–167 | `setupAppMenu` | Imperatively inserts "Applicant Profile…", "Template Editor…", and "Experience Editor…" menu items into the live `NSMenu` |
| 168–237 | `showSettingsWindow` | Creates, configures, and presents the Settings `NSWindow` |
| 238–288 | `showApplicantProfileWindow` | Creates, configures, and presents the Applicant Profile `NSWindow` |
| 289–299 | `windowWillClose` | Nils out closed window refs (shared handler for 4 windows) |
| 300–344 | `showTemplateEditorWindow` | Creates, configures, and presents the Template Editor `NSWindow` |
| 345–413 | `showOnboardingInterviewWindow` | Creates the borderless onboarding `NSWindow`, with animated presentation |
| 415–466 | `presentOnboardingInterviewWindowAnimated` | Three-phase spring animation (fade + frame change) |
| 467–553 | `showDiscoveryWindow` | Creates, configures, and presents the Discovery `NSWindow`; dispatches follow-on notifications |
| 554–614 | `showExperienceEditorWindow` | Creates, configures, and presents the Experience Editor `NSWindow` |
| 616–676 | `showResumeRevisionWindow` | Creates, configures, and presents the Resume Revision `NSWindow` |
| 678–712 | `showDebugLogsWindow` | Creates, configures, and presents the Debug Logs `NSWindow` |
| 714–810 | `showSeedGenerationWindow` | Creates, configures, and presents the Seed Generation `NSWindow`; reads UserDefaults for model config |
| 812–848 | `buildSeedGenerationContext` | Assembles `SeedGenerationContext` from stores — pure domain logic |
| 850–880 | `showBackgroundActivityWindow` | Creates, configures, and presents the Background Activity `NSWindow` |
| 882–914 | URL scheme handling (`application(_:open:)` + `handleIncomingURL`) | Parses `sprung://` URLs, posts notifications |
| 917–925 | `Notification.Name` extension | Declares 4 app-level notification names |

---

## 3. SRP Assessment

**AppDelegate violates SRP.** The class has at minimum four reasons to change:

- The application lifecycle changes (new system notifications, launch sequence changes)
- The app menu structure changes (new menu items, reordering)
- Any secondary window is added, removed, or its dependencies change
- The business logic for assembling `SeedGenerationContext` changes

The window-creation pattern is repeated nine times with minor variations. Each repetition is roughly 40–60 lines and includes: (a) guard-checking an existing window, (b) building the SwiftUI view tree with environment injection, (c) constructing `NSWindow`, (d) assigning properties, (e) centering, and (f) ordering front. This is a textbook case of a single class doing too many things.

Additionally, `buildSeedGenerationContext` (lines 812–848) is domain logic that has nothing to do with AppDelegate's application-lifecycle role. It should live alongside the seed-generation orchestration code.

---

## 4. Verdict: Should Be Split

The 926-line length is **not justified**. The file conflates application bootstrap, menu customization, nine window factories, one animation utility, one domain-object assembler, and notification name declarations. Splitting it into focused files will:

- Make each new file independently readable and testable
- Eliminate the 23-property dependency bag (or at least contain it)
- Allow individual window presentations to be changed without touching unrelated code

---

## 5. Refactoring Plan

### Guiding principle
Keep `AppDelegate` as the `NSApplicationDelegate` conformance point only. Move window management into a dedicated service, move the menu setup into its own object, move the onboarding animation into its own file, and move domain helpers next to the feature they serve.

The 23 optional store/coordinator properties remain on `AppDelegate` because `SprungApp.onAppear` assigns them imperatively. If a future refactor introduces a proper DI container that `AppDelegate` can read, those can be eliminated entirely; this plan does not tackle that separately.

---

### New Files

---

#### File 1 — `Sprung/App/Services/SecondaryWindowManager.swift`

**Purpose:** Own the lifetime and presentation of all secondary `NSWindow` instances. Replaces the 9 window-creation methods and their associated window-reference properties currently on `AppDelegate`.

**What moves here (line ranges from AppDelegate.swift):**

| Lines | Content |
|-------|---------|
| 11–37 | All 8 `var …Window: NSWindow?` properties and the `toolbarCoordinator` property. The 14 store/coordinator optionals stay on `AppDelegate` because `SprungApp` assigns them by reference; `SecondaryWindowManager` receives them as constructor or method parameters instead. |
| 168–237 | `showSettingsWindow()` → becomes `showSettings(appEnvironment:modelContainer:enabledLLMStore:...)` (parameters replace the AppDelegate stored properties) |
| 238–288 | `showApplicantProfileWindow()` |
| 289–299 | `windowWillClose(_:)` — the notification handler; window refs live here now |
| 300–344 | `showTemplateEditorWindow()` |
| 345–413 | `showOnboardingInterviewWindow()` — calls into `OnboardingWindowAnimator` (File 2) |
| 467–553 | `showDiscoveryWindow(section:startOnboarding:…)` and the `@objc` no-arg overload |
| 554–614 | `showExperienceEditorWindow()` |
| 616–676 | `showResumeRevisionWindow()` |
| 678–712 | `showDebugLogsWindow(coordinator:)` and `handleShowDebugLogs(_:)` |
| 714–810 | `showSeedGenerationWindow()` and `handleShowSeedGeneration(_:)` |
| 850–880 | `showBackgroundActivityWindow()` |

**Signature sketch:**

```swift
@Observable
@MainActor
final class SecondaryWindowManager {
    // Window refs (currently on AppDelegate)
    var settingsWindow: NSWindow?
    var applicantProfileWindow: NSWindow?
    var templateEditorWindow: NSWindow?
    var onboardingInterviewWindow: NSWindow?
    var experienceEditorWindow: NSWindow?
    var searchOpsWindow: NSWindow?
    var debugLogsWindow: NSWindow?
    var seedGenerationWindow: NSWindow?
    var resumeRevisionWindow: NSWindow?
    var backgroundActivityWindow: NSWindow?

    // Injected at setup time (from SprungApp.onAppear, same as today)
    var appEnvironment: AppEnvironment?
    var modelContainer: ModelContainer?
    // … all other store refs …

    func showSettings()
    func showApplicantProfile()
    func showTemplateEditor()
    func showOnboardingInterview()
    func showDiscovery(section:startOnboarding:triggerDiscovery:…)
    func showExperienceEditor()
    func showResumeRevision()
    func showDebugLogs(coordinator:)
    func showSeedGeneration() async
    func showBackgroundActivity()
}
```

**How AppDelegate uses it:**

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    var windowManager = SecondaryWindowManager()
    var toolbarCoordinator: ToolbarCoordinator?
    // … the 14 store optionals remain for now (assigned from SprungApp) …

    func applicationDidFinishLaunching(_: Notification) { … }
    func setupMainWindowToolbar() { … }   // stays (it's toolbar, not window)
    private func setupAppMenu() { … }     // or moves to File 3
    func application(_:open:) { … }       // stays
}
```

`SprungApp.onAppear` assigns to `appDelegate.windowManager.appEnvironment`, etc. instead of `appDelegate.appEnvironment`. The `@objc` selectors in `applicationDidFinishLaunching` that currently call `self.showDebugLogs` and `self.showSeedGeneration` will forward to `windowManager`.

**Access level:** `SecondaryWindowManager` and its public `show…` methods are `internal` (default). No access changes required.

---

#### File 2 — `Sprung/App/Services/OnboardingWindowAnimator.swift`

**Purpose:** Encapsulate the three-phase spring animation for presenting the onboarding interview window. Currently mixed into `showOnboardingInterviewWindow` on `AppDelegate`.

**What moves here (line ranges from AppDelegate.swift):**

| Lines | Content |
|-------|---------|
| 415–466 | `presentOnboardingInterviewWindowAnimated(_:)` — the entire method |

**Signature sketch:**

```swift
/// Presents an NSWindow with a spring-in animation (scale + fade + overshoot).
/// Falls back to instant presentation when Reduce Motion is enabled.
@MainActor
enum OnboardingWindowAnimator {
    static func present(_ window: NSWindow)
}
```

Using a caseless `enum` (namespace) keeps it stateless and makes call sites read clearly: `OnboardingWindowAnimator.present(window)`.

**How SecondaryWindowManager uses it:**

Inside `showOnboardingInterview()`, replace the current call to `self.presentOnboardingInterviewWindowAnimated(window)` with `OnboardingWindowAnimator.present(window)`.

**Access level:** `internal`. No visibility changes needed.

---

#### File 3 — `Sprung/App/Services/AppMenuBuilder.swift`

**Purpose:** Contain the imperative NSMenu mutation logic that inserts "Applicant Profile…", "Template Editor…", and "Experience Editor…" menu items into the live app menu. This is a discrete, independently testable unit currently buried inside `AppDelegate.setupAppMenu()`.

**What moves here (line ranges from AppDelegate.swift):**

| Lines | Content |
|-------|---------|
| 99–167 | `setupAppMenu()` — the entire method body, renamed to a static function |

**Signature sketch:**

```swift
@MainActor
enum AppMenuBuilder {
    /// Inserts Sprung-specific items into the running application menu.
    /// Call once, after `applicationDidFinishLaunching`, on the main queue.
    static func install(
        showApplicantProfile: Selector,
        showTemplateEditor: Selector,
        showExperienceEditor: Selector,
        target: AnyObject
    )
}
```

**How AppDelegate uses it:**

```swift
private func setupAppMenu() {
    AppMenuBuilder.install(
        showApplicantProfile: #selector(windowManager.showApplicantProfile),
        showTemplateEditor:   #selector(windowManager.showTemplateEditor),
        showExperienceEditor: #selector(windowManager.showExperienceEditor),
        target: windowManager
    )
}
```

Note: because `@objc` selectors require the target to be an `NSObject` subclass or `@objc` exposed, this may require annotating the relevant methods on `SecondaryWindowManager` with `@objc` (they already are today on `AppDelegate`). No external visibility changes are needed.

**Access level:** `internal`.

---

#### File 4 — `Sprung/Onboarding/Services/SeedGenerationContextBuilder.swift`

**Purpose:** Move the pure domain helper `buildSeedGenerationContext(coordinator:skillStore:)` out of `AppDelegate` and into the onboarding feature module where it belongs.

**What moves here (line ranges from AppDelegate.swift):**

| Lines | Content |
|-------|---------|
| 812–848 | `buildSeedGenerationContext(coordinator:skillStore:)` — renamed `build(from:skillStore:)` or similar |

**Signature sketch:**

```swift
@MainActor
enum SeedGenerationContextBuilder {
    static func build(
        coordinator: OnboardingInterviewCoordinator,
        skillStore: SkillStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        applicantProfileStore: ApplicantProfileStore?,
        coverRefStore: CoverRefStore?,
        titleSetStore: TitleSetStore?
    ) async -> SeedGenerationContext?
}
```

All parameters that `buildSeedGenerationContext` currently accesses via `self.` are made explicit function parameters, eliminating the implicit dependency on AppDelegate's stored properties.

**How SecondaryWindowManager uses it:**

Inside `showSeedGenerationWindow()`, replace:
```swift
guard let context = await buildSeedGenerationContext(coordinator: ..., skillStore: ...) else { ... }
```
with:
```swift
guard let context = await SeedGenerationContextBuilder.build(
    coordinator: onboardingCoordinator,
    skillStore: skillStore,
    experienceDefaultsStore: experienceDefaultsStore,
    applicantProfileStore: applicantProfileStore,
    coverRefStore: coverRefStore,
    titleSetStore: titleSetStore
) else { ... }
```

**Access level:** `internal`. The `Onboarding/Services/` directory already exists (or create it alongside existing onboarding service files).

---

#### File 5 — Move `Notification.Name` extension

**What moves:**

| Lines | Content |
|-------|---------|
| 917–925 | The `extension Notification.Name` block declaring `captureJobFromURL`, `captureJobURLReady`, `showDebugLogs`, `showSeedGeneration` |

**Where it moves:** These are app-level notification names that have no intrinsic connection to `AppDelegate`. They should live with the other `Notification.Name` declarations in the codebase.

Search for where the existing notification names (e.g., `.polishResume`, `.newJobApp`) are declared:

```bash
grep -r "static let polishResume" Sprung/
```

If they are centralized in a file like `Sprung/App/Views/MenuNotificationHandler.swift` or a dedicated `AppNotifications.swift`, move the four names there. If no such file exists, create `Sprung/App/AppNotifications.swift` and move all `Notification.Name` extensions the codebase already declares into it during this refactor to complete the clean break.

**Access level:** No change; already `internal`.

---

### What Remains in AppDelegate.swift After Refactoring

```
AppDelegate: NSObject, NSApplicationDelegate
  ├── var windowManager: SecondaryWindowManager       // replaces 8 window vars
  ├── var toolbarCoordinator: ToolbarCoordinator?
  ├── var appEnvironment: AppEnvironment?             // 14 store/coordinator refs
  │   … (unchanged until SprungApp injection pattern is refactored)
  │
  ├── applicationDidFinishLaunching                   // ~10 lines
  ├── setupMainWindowToolbar                          // ~30 lines (unchanged)
  ├── setupAppMenu                                    // ~5 lines (delegates to AppMenuBuilder)
  ├── showSettingsWindow / showOnboardingInterviewWindow / etc.
  │   → forward calls to windowManager
  ├── application(_:open:) + handleIncomingURL        // ~25 lines (unchanged)
```

Estimated resulting size: ~100–130 lines.

---

### File Size Estimates After Split

| File | Estimated lines |
|------|----------------|
| `AppDelegate.swift` (trimmed) | ~110 |
| `SecondaryWindowManager.swift` | ~480 |
| `OnboardingWindowAnimator.swift` | ~60 |
| `AppMenuBuilder.swift` | ~75 |
| `SeedGenerationContextBuilder.swift` | ~45 |
| Notification names (merged into existing file) | ~6 added lines |

---

### Implementation Order

1. Create `OnboardingWindowAnimator.swift` — no dependencies on other new files; simple extraction.
2. Create `SeedGenerationContextBuilder.swift` — standalone; makes `buildSeedGenerationContext` parameters explicit.
3. Create `AppMenuBuilder.swift` — depends only on AppKit types.
4. Create `SecondaryWindowManager.swift` — references `OnboardingWindowAnimator` and `SeedGenerationContextBuilder`; move all window vars and `show…` methods.
5. Update `AppDelegate.swift` — replace body with forwarding calls to `windowManager` and `AppMenuBuilder`. Remove moved properties.
6. Update `SprungApp.swift` `.onAppear` — assign dependencies to `appDelegate.windowManager.*` instead of `appDelegate.*` for the properties that moved.
7. Move `Notification.Name` declarations — search for existing centralization point; move all four names.
8. Verify build: `xcodebuild -project Sprung.xcodeproj -scheme Sprung build 2>&1 | grep -Ei "(error:|warning:|failed|succeeded)" | head -20`

---

### Risks and Notes

- **`@objc` selectors for menu items:** The "Applicant Profile…", "Template Editor…", and "Experience Editor…" menu items use `#selector(showApplicantProfileWindow)` etc., with `target = self` (AppDelegate). After moving the implementations to `SecondaryWindowManager`, the target must change. `SecondaryWindowManager` must either be an `NSObject` subclass (and methods annotated `@objc`) or the menu item targets remain as thin `@objc` forwarders on `AppDelegate`. Thin forwarders (3 one-liners) on `AppDelegate` that call `windowManager.showX()` are the lowest-risk path.

- **`NotificationCenter` observers:** `handleShowDebugLogs`, `handleShowSeedGeneration`, and `handleShowResumeRevision` are registered in `applicationDidFinishLaunching` with `selector:`. They currently live on `AppDelegate`. The cleanest path is to keep the `@objc` stub on `AppDelegate` and have it call `Task { await windowManager.showSeedGeneration() }` etc. — same pattern as today, just forwarding.

- **The 23-property dependency bag:** `SprungApp.onAppear` imperatively assigns to `appDelegate.*`. After this refactor, many of those assignments will target `appDelegate.windowManager.*`. This is purely mechanical. A deeper refactor — making `AppDependencies` directly accessible from `SecondaryWindowManager` without the property-bag pattern — is out of scope here but the structure created by this plan makes it straightforward in a follow-on pass.

- **`BorderlessOverlayWindow`:** Used only in `showOnboardingInterviewWindow`. After the move, it is referenced from `SecondaryWindowManager` rather than `AppDelegate`. No access-level change needed (it is already `internal`).

- **`DiscoverySection` parameter type:** `showDiscoveryWindow(section:…)` references `DiscoverySection`. `SecondaryWindowManager` must import whatever module declares that type. Because `SecondaryWindowManager` lives in `Sprung/App/Services/` and `DiscoverySection` lives in the Discovery module (same target), no import changes are needed.
