//
//  AppDelegate.swift
//  Sprung
//
//  Application lifecycle delegate. Window management is handled by
//  SecondaryWindowService; menu construction by AppMenuBuilder.
//
import Cocoa
import SwiftUI

/// One-shot buffer for a `sprung://capture-job` URL that may arrive before the main
/// window's capture consumer (`AppSheetsModifier`, hosted by `UnifiedAppLayout`) has
/// mounted and subscribed to `.captureJobFromURL` — e.g. a bookmarklet firing during a
/// cold launch, before SwiftUI has evaluated the window's body. `NotificationCenter`
/// does not replay missed posts, so without this the capture is silently dropped.
///
/// Holds at most one URL (latest wins) and delivers it exactly once: either immediately
/// (consumer already ready) or on the next `consumerDidBecomeReady()` call (buffered).
/// Pure value type — no AppKit/SwiftUI dependency — so it's directly unit-testable.
struct CaptureURLBuffer {
    private var pendingURL: String?
    private var isConsumerReady = false

    /// Call when a capture URL arrives. Returns the URL to deliver right away if the
    /// consumer is ready, or `nil` if it was buffered for later delivery.
    mutating func capture(_ url: String) -> String? {
        guard isConsumerReady else {
            pendingURL = url
            return nil
        }
        return url
    }

    /// Call once the consumer has mounted and subscribed. Returns a buffered URL to
    /// deliver, if one arrived before this point. Idempotent: subsequent calls return
    /// `nil` since the buffer only ever holds one not-yet-delivered URL.
    mutating func consumerDidBecomeReady() -> String? {
        isConsumerReady = true
        defer { pendingURL = nil }
        return pendingURL
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let windowManager = SecondaryWindowService()
    var toolbarCoordinator: ToolbarCoordinator?
    private var captureURLBuffer = CaptureURLBuffer()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_: Notification) {
        // Wait until the app is fully loaded before modifying the menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupAppMenu()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowDebugLogs(_:)),
            name: .showDebugLogs,
            object: nil
        )

        // Customize entry choke point: observed here so the revision window
        // opens regardless of which module is active. Gating lives in
        // SecondaryWindowService.showResumeRevision().
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCustomizeResume(_:)),
            name: .customizeResume,
            object: nil
        )

        // Window-level notifications that must work regardless of which module is active.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettingsWindow),
            name: .showSettings,
            object: nil
        )
        // Deep-link to Settings → Models with the offending row highlighted. Observed
        // here so any "no model configured" failure can route the user to the picker
        // regardless of which window or module raised it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowModelSettings(_:)),
            name: .showModelSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOnboardingInterviewWindow),
            name: .startOnboardingInterview,
            object: nil
        )
    }

    func applicationWillTerminate(_: Notification) {
        // The LinkedIn MCP server is an app-managed child process (uvx →
        // headless browser); SIGTERM it so nothing outlives the app.
        windowManager.deps?.linkedInMCPServer.stop()
    }

    // MARK: - Toolbar

    /// Attach a pure AppKit NSToolbar to the main window, bypassing SwiftUI's broken toolbar(id:).
    func setupMainWindowToolbar() {
        let coordinator = ToolbarCoordinator()
        coordinator.jobAppStore = windowManager.deps?.jobAppStore
        coordinator.navigationState = windowManager.deps?.appEnvironment.navigationState
        coordinator.moduleNavigation = windowManager.deps?.moduleNavigation
        self.toolbarCoordinator = coordinator

        // Delay slightly so the SwiftUI Window scene has finished creating the NSWindow
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let window = NSApp.windows.first(where: {
                $0.identifier?.rawValue.contains("myApp") == true
                    || ($0.title.isEmpty && $0.contentView != nil && type(of: $0) != NSPanel.self)
            }) ?? NSApp.mainWindow else {
                Logger.warning("Could not find main window for toolbar setup", category: .ui)
                return
            }

            let toolbar = NSToolbar(identifier: "sprungMainToolbar")
            toolbar.delegate = coordinator
            toolbar.allowsUserCustomization = true
            // The item set is driven by the active module (see ToolbarCoordinator),
            // so persisting/restoring a saved configuration would fight the
            // module-contextual reconfiguration on launch.
            toolbar.autosavesConfiguration = false
            toolbar.displayMode = .iconAndLabel
            coordinator.attach(to: toolbar)

            window.toolbar = toolbar
            window.toolbarStyle = .expanded
            Logger.info("AppKit toolbar attached to main window", category: .ui)
        }
    }

    // MARK: - App Menu

    private func setupAppMenu() {
        AppMenuBuilder.install(
            navigateToProfile: #selector(navigateToProfileModule),
            navigateToExperience: #selector(navigateToExperienceModule),
            target: self
        )
    }

    // MARK: - @objc Forwarding Stubs (for NotificationCenter selectors and menu targets)

    @objc func showSettingsWindow() {
        windowManager.showSettings()
    }

    @objc private func handleShowModelSettings(_ notification: Notification) {
        let key = notification.userInfo?["settingKey"] as? String
        windowManager.showModelSettings(highlightKey: key)
    }

    /// The Profile editor lives in the main-window module shell (⌘9 / icon bar).
    /// The app-menu item navigates there rather than opening a duplicate window.
    @objc func navigateToProfileModule() {
        NotificationCenter.default.post(
            name: .navigateToModule, object: nil,
            userInfo: ["module": AppModule.profile.rawValue]
        )
    }

    @objc func showOnboardingInterviewWindow() {
        windowManager.showOnboardingInterview()
    }

    /// The Experience editor lives in the main-window module shell (⌘8 / icon bar).
    /// The app-menu item navigates there rather than opening a duplicate window.
    @objc func navigateToExperienceModule() {
        NotificationCenter.default.post(
            name: .navigateToModule, object: nil,
            userInfo: ["module": AppModule.experience.rawValue]
        )
    }

    @objc private func handleShowDebugLogs(_ notification: Notification) {
        Logger.info("Debug logs notification received", category: .ui)
        guard let coordinator = notification.object as? OnboardingInterviewCoordinator else {
            Logger.warning("Debug logs notification missing coordinator", category: .ui)
            return
        }
        windowManager.showDebugLogs(coordinator: coordinator)
    }

    @objc private func handleCustomizeResume(_ notification: Notification) {
        windowManager.showResumeRevision()
    }

    // MARK: - URL Scheme Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleIncomingURL(url)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "sprung" else { return }

        Logger.info("Received URL: \(url.absoluteString)", category: .appLifecycle)

        switch url.host {
        case "capture-job":
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let jobURLString = components.queryItems?.first(where: { $0.name == "url" })?.value {
                if let deliverable = captureURLBuffer.capture(jobURLString) {
                    deliverCaptureJobURL(deliverable)
                } else {
                    Logger.info("Buffering capture-job URL until the main window mounts", category: .appLifecycle)
                }
            } else {
                Logger.warning("capture-job URL missing 'url' parameter", category: .appLifecycle)
                ToastCenter.shared.show(.error("Couldn't capture job — the URL was missing required information."))
            }

        default:
            Logger.warning("Unknown URL host: \(url.host ?? "nil")", category: .appLifecycle)
        }
    }

    /// Called by `UnifiedAppLayout` once its `AppSheetsModifier` (the sole consumer of
    /// `.captureJobFromURL`) has mounted and subscribed. Drains and delivers any
    /// capture-job URL that arrived before the main window was ready to receive it.
    func mainWindowCaptureConsumerDidMount() {
        guard let bufferedURL = captureURLBuffer.consumerDidBecomeReady() else { return }
        deliverCaptureJobURL(bufferedURL)
    }

    private func deliverCaptureJobURL(_ jobURLString: String) {
        NotificationCenter.default.post(
            name: .captureJobFromURL,
            object: nil,
            userInfo: ["url": jobURLString]
        )
        NSApp.activate(ignoringOtherApps: true)
    }
}
