//
//  AppDelegate.swift
//  Sprung
//
//  Application lifecycle delegate. Window management is handled by
//  SecondaryWindowManager; menu construction by AppMenuBuilder.
//
import Cocoa
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let windowManager = SecondaryWindowManager()
    var toolbarCoordinator: ToolbarCoordinator?

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSeedGeneration(_:)),
            name: .showSeedGeneration,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowResumeRevision(_:)),
            name: .polishResume,
            object: nil
        )

        // Window-level notifications that must work regardless of which module is active.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showTemplateEditorWindow),
            name: .showTemplateEditor,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettingsWindow),
            name: .showSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showApplicantProfileWindow),
            name: .showApplicantProfile,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showExperienceEditorWindow),
            name: .showExperienceEditor,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOnboardingInterviewWindow),
            name: .startOnboardingInterview,
            object: nil
        )
    }

    // MARK: - Toolbar

    /// Attach a pure AppKit NSToolbar to the main window, bypassing SwiftUI's broken toolbar(id:).
    func setupMainWindowToolbar() {
        let coordinator = ToolbarCoordinator()
        coordinator.jobAppStore = windowManager.jobAppStore
        coordinator.navigationState = windowManager.appEnvironment?.navigationState
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
            toolbar.autosavesConfiguration = true
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
            showApplicantProfile: #selector(showApplicantProfileWindow),
            showTemplateEditor: #selector(showTemplateEditorWindow),
            showExperienceEditor: #selector(showExperienceEditorWindow),
            target: self
        )
    }

    // MARK: - @objc Forwarding Stubs (for NotificationCenter selectors and menu targets)

    @objc func showSettingsWindow() {
        windowManager.showSettings()
    }

    @objc func showApplicantProfileWindow() {
        windowManager.showApplicantProfile()
    }

    @objc func showTemplateEditorWindow() {
        windowManager.showTemplateEditor()
    }

    @objc func showOnboardingInterviewWindow() {
        windowManager.showOnboardingInterview()
    }

    @objc func showExperienceEditorWindow() {
        windowManager.showExperienceEditor()
    }

    @objc func showBackgroundActivityWindow() {
        windowManager.showBackgroundActivity()
    }

    @objc func showDiscoveryWindow() {
        windowManager.showDiscovery()
    }

    func showDiscoveryWindow(
        section: DiscoverySection? = nil,
        startOnboarding: Bool = false,
        triggerDiscovery: Bool = false,
        triggerEventDiscovery: Bool = false,
        triggerTaskGeneration: Bool = false,
        triggerWeeklyReflection: Bool = false
    ) {
        windowManager.showDiscovery(
            section: section,
            startOnboarding: startOnboarding,
            triggerDiscovery: triggerDiscovery,
            triggerEventDiscovery: triggerEventDiscovery,
            triggerTaskGeneration: triggerTaskGeneration,
            triggerWeeklyReflection: triggerWeeklyReflection
        )
    }

    func showResumeRevisionWindow() {
        windowManager.showResumeRevision()
    }

    @objc private func handleShowDebugLogs(_ notification: Notification) {
        Logger.info("Debug logs notification received", category: .ui)
        guard let coordinator = notification.object as? OnboardingInterviewCoordinator else {
            Logger.warning("Debug logs notification missing coordinator", category: .ui)
            return
        }
        windowManager.showDebugLogs(coordinator: coordinator)
    }

    @objc private func handleShowSeedGeneration(_ notification: Notification) {
        Logger.info("Seed generation notification received", category: .ui)
        Task {
            await self.windowManager.showSeedGeneration()
        }
    }

    @objc private func handleShowResumeRevision(_ notification: Notification) {
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
                NotificationCenter.default.post(
                    name: .captureJobFromURL,
                    object: nil,
                    userInfo: ["url": jobURLString]
                )
                NSApp.activate(ignoringOtherApps: true)
            } else {
                Logger.warning("capture-job URL missing 'url' parameter", category: .appLifecycle)
            }

        default:
            Logger.warning("Unknown URL host: \(url.host ?? "nil")", category: .appLifecycle)
        }
    }
}
