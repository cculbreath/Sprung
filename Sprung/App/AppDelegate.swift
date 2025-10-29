


//
//  AppDelegate.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/1/24.
//

import Cocoa
import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    var settingsWindow: NSWindow?
    var applicantProfileWindow: NSWindow?
    var templateEditorWindow: NSWindow?
    var onboardingInterviewWindow: NSWindow?
    var experienceEditorWindow: NSWindow?
    var appEnvironment: AppEnvironment?
    var modelContainer: ModelContainer?
    var enabledLLMStore: EnabledLLMStore?
    var applicantProfileStore: ApplicantProfileStore?
    var llmService: LLMService?
    var onboardingInterviewService: OnboardingInterviewService?
    var onboardingArtifactStore: OnboardingArtifactStore?
    var experienceDefaultsStore: ExperienceDefaultsStore?
    var careerKeywordStore: CareerKeywordStore?

    func applicationDidFinishLaunching(_: Notification) {
        // Wait until the app is fully loaded before modifying the menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupAppMenu()
        }

        // We no longer add a separate Profile main menu to avoid duplication
    }

    private func setupAppMenu() {
        guard let mainMenu = NSApp.mainMenu else {
            return
        }

        // Find the name of the application to look for the right menu item
        let appName = ProcessInfo.processInfo.processName

        // Find or create the Application menu (first menu)
        let appMenu: NSMenu
        if let existingAppMenu = mainMenu.item(at: 0)?.submenu {
            appMenu = existingAppMenu
        } else {
            // Create a new app menu if it doesn't exist (unlikely)
            appMenu = NSMenu(title: appName)
            let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
            appMenuItem.submenu = appMenu
            mainMenu.insertItem(appMenuItem, at: 0)
        }

        // Find the About menu item with different possible titles
        let possibleAboutTitles = [
            "About \(appName)",
            "About Sprung",
            "About Physics Cloud Résumé",
        ]

        var aboutItemIndex = -1
        for title in possibleAboutTitles {
            let index = appMenu.indexOfItem(withTitle: title)
            if index >= 0 {
                aboutItemIndex = index
                break
            }
        }

        // If About item not found, insert at the beginning
        let aboutSeparatorIndex = aboutItemIndex >= 0 ? aboutItemIndex + 1 : 0

        // If we already have an Applicant Profile menu item, remove it to avoid duplicates
        let existingProfileIndex = appMenu.indexOfItem(withTitle: "Applicant Profile...")
        if existingProfileIndex >= 0 {
            appMenu.removeItem(at: existingProfileIndex)
        }

        // Insert separator if needed
        if aboutSeparatorIndex < appMenu.numberOfItems &&
            !appMenu.item(at: aboutSeparatorIndex)!.isSeparatorItem
        {
            appMenu.insertItem(NSMenuItem.separator(), at: aboutSeparatorIndex)
        }

        // Add Applicant Profile menu item after separator
        let profileMenuItem = NSMenuItem(
            title: "Applicant Profile...",
            action: #selector(showApplicantProfileWindow),
            keyEquivalent: ""
        )
        profileMenuItem.target = self
        appMenu.insertItem(profileMenuItem, at: aboutSeparatorIndex + 1)
        
        // Add Template Editor menu item
        let templateMenuItem = NSMenuItem(
            title: "Template Editor...",
            action: #selector(showTemplateEditorWindow),
            keyEquivalent: "T"
        )
        templateMenuItem.target = self
        templateMenuItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.insertItem(templateMenuItem, at: aboutSeparatorIndex + 2)

        let experienceMenuItem = NSMenuItem(
            title: "Experience Editor...",
            action: #selector(showExperienceEditorWindow),
            keyEquivalent: "E"
        )
        experienceMenuItem.keyEquivalentModifierMask = [.command, .shift]
        experienceMenuItem.target = self
        appMenu.insertItem(experienceMenuItem, at: aboutSeparatorIndex + 3)
    }

    @MainActor @objc func showSettingsWindow() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            
            // Create hosting view with proper environment objects
            let hostingView: NSHostingView<AnyView>
            if let appEnvironment = self.appEnvironment,
               let container = self.modelContainer,
               let enabledLLMStore = self.enabledLLMStore,
               let applicantProfileStore = self.applicantProfileStore,
               let llmService = self.llmService,
               let experienceDefaultsStore = self.experienceDefaultsStore,
               let careerKeywordStore = self.careerKeywordStore,
               let onboardingArtifactStore = self.onboardingArtifactStore {
                let appState = appEnvironment.appState
                let debugSettingsStore = appState.debugSettingsStore ?? appEnvironment.debugSettingsStore

                let root = settingsView
                    .environment(appEnvironment)
                    .environment(appState)
                    .environment(appEnvironment.navigationState)
                    .environment(appEnvironment.onboardingInterviewService)
                    .environment(enabledLLMStore)
                    .environment(applicantProfileStore)
                    .environment(experienceDefaultsStore)
                    .environment(careerKeywordStore)
                    .environment(onboardingArtifactStore)
                    .environment(appEnvironment.openRouterService)
                    .environment(llmService)
                    .environment(debugSettingsStore)
                    .modelContainer(container)

                hostingView = NSHostingView(rootView: AnyView(root))
            } else {
                // Fallback if appState or modelContainer is not available
                Logger.warning(
                    "⚠️ Settings window requested before environment is fully configured; dependencies missing",
                    category: .appLifecycle
                )
                hostingView = NSHostingView(
                    rootView: AnyView(
                        VStack(spacing: 16) {
                            Text("Settings Unavailable")
                                .font(.headline)
                            Text("App services are still loading. Please try opening Settings again in a moment.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 320, minHeight: 160)
                        .padding()
                    )
                )
            }
            
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            settingsWindow?.title = "Settings"
            settingsWindow?.contentView = hostingView
            settingsWindow?.isReleasedWhenClosed = false

            // Center the window on the screen
            settingsWindow?.center()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showApplicantProfileWindow() {
        // If window exists but was closed, reset it
        if let window = applicantProfileWindow, !window.isVisible {
            applicantProfileWindow = nil
        }

        if applicantProfileWindow == nil {
            let profileView = ApplicantProfileView()
            let hostingView: NSHostingView<AnyView>

            if let appEnvironment,
               let container = modelContainer,
               let applicantProfileStore {
                let root = profileView
                    .environment(appEnvironment)
                    .environment(appEnvironment.appState)
                    .environment(applicantProfileStore)
                    .environment(appEnvironment.experienceDefaultsStore)
                    .environment(appEnvironment.careerKeywordStore)
                    .modelContainer(container)
                hostingView = NSHostingView(rootView: AnyView(root))
            } else if let container = modelContainer {
                let root = profileView.modelContainer(container)
                hostingView = NSHostingView(rootView: AnyView(root))
            } else {
                hostingView = NSHostingView(rootView: AnyView(profileView))
            }

            applicantProfileWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            applicantProfileWindow?.title = "Applicant Profile"
            applicantProfileWindow?.contentView = hostingView
            applicantProfileWindow?.isReleasedWhenClosed = false
            applicantProfileWindow?.center()

            // Set a minimum size for the window
            applicantProfileWindow?.minSize = NSSize(width: 500, height: 520)

            // Register for notifications when window is closed
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: applicantProfileWindow
            )
        }

        // Bring the window to the front
        applicantProfileWindow?.makeKeyAndOrderFront(nil)

        // Activate the app to ensure focus
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == applicantProfileWindow {
            applicantProfileWindow = nil
        } else if notification.object as? NSWindow == templateEditorWindow {
            templateEditorWindow = nil
        } else if notification.object as? NSWindow == experienceEditorWindow {
            experienceEditorWindow = nil
        }
    }
    
    @objc func showTemplateEditorWindow() {
        // If window exists but was closed, reset it
        if let window = templateEditorWindow, !window.isVisible {
            templateEditorWindow = nil
        }
        
        if templateEditorWindow == nil {
            let editorView = TemplateEditorView()
            let hostingView: NSHostingView<AnyView>
            
            if let modelContainer = self.modelContainer,
               let appEnvironment = self.appEnvironment {
                hostingView = NSHostingView(rootView: AnyView(
                    editorView
                        .modelContainer(modelContainer)
                        .environment(appEnvironment)
                        .environment(appEnvironment.appState)
                        .environment(appEnvironment.navigationState)
                        .environment(appEnvironment.experienceDefaultsStore)
                        .environment(appEnvironment.careerKeywordStore)
                        .environment(appEnvironment.applicantProfileStore)
                ))
            } else if let modelContainer = self.modelContainer {
                hostingView = NSHostingView(rootView: AnyView(editorView.modelContainer(modelContainer)))
            } else {
                hostingView = NSHostingView(rootView: AnyView(editorView))
            }
            
            templateEditorWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            templateEditorWindow?.title = "Template Editor"
            templateEditorWindow?.tabbingMode = .disallowed
            templateEditorWindow?.contentView = hostingView
            templateEditorWindow?.isReleasedWhenClosed = false
            templateEditorWindow?.center()
            
            // Set a minimum size for the window
            templateEditorWindow?.minSize = NSSize(width: 960, height: 640)
        }
        
        // Bring the window to the front
        templateEditorWindow?.makeKeyAndOrderFront(nil)
        
        // Activate the app to ensure focus
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showOnboardingInterviewWindow() {
        Logger.info(
            "🎬 showOnboardingInterviewWindow invoked (existing window: \(onboardingInterviewWindow != nil))",
            category: .ui
        )
        if let window = onboardingInterviewWindow, !window.isVisible {
            onboardingInterviewWindow = nil
        }

        if onboardingInterviewWindow == nil {
            let interviewView = OnboardingInterviewView()
            let hostingView: NSHostingView<AnyView>

            if let modelContainer,
               let appEnvironment,
               let enabledLLMStore {
                let onboardingService = onboardingInterviewService ?? appEnvironment.onboardingInterviewService
                let root = interviewView
                    .modelContainer(modelContainer)
                    .environment(appEnvironment)
                    .environment(appEnvironment.appState)
                    .environment(appEnvironment.navigationState)
                    .environment(enabledLLMStore)
                    .environment(appEnvironment.applicantProfileStore)
                    .environment(appEnvironment.experienceDefaultsStore)
                    .environment(onboardingService)

                hostingView = NSHostingView(rootView: AnyView(root))
            } else if let modelContainer {
                hostingView = NSHostingView(rootView: AnyView(interviewView.modelContainer(modelContainer)))
            } else {
                hostingView = NSHostingView(rootView: AnyView(interviewView))
            }

            let innerXPadding: CGFloat = 32 * 2        // = 64
            let minCardWidth = 1040 + innerXPadding    // = 1104
            let outerPad: CGFloat = 30                 // same as shadowR (left/right)
            let windowW = minCardWidth + outerPad*2    // = 1164

            onboardingInterviewWindow = BorderlessOverlayWindow(
                contentRect: NSRect(x: 0, y: 0, width: windowW, height: 700)
            )
            hostingView.wantsLayer = true
            hostingView.layer?.masksToBounds = false
            onboardingInterviewWindow?.contentView = hostingView
            onboardingInterviewWindow?.isReleasedWhenClosed = false
            onboardingInterviewWindow?.center()
            onboardingInterviewWindow?.minSize = NSSize(width: windowW, height: 600)

            Logger.info("🆕 Created onboarding interview window", category: .ui)
        }

        onboardingInterviewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Logger.info("✅ Onboarding interview window presented", category: .ui)
    }

    @objc func showExperienceEditorWindow() {
        if let window = experienceEditorWindow, !window.isVisible {
            experienceEditorWindow = nil
        }

        if experienceEditorWindow == nil {
            let editorView = ExperienceEditorView()
            let hostingView: NSHostingView<AnyView>

            if let modelContainer,
               let appEnvironment,
               let experienceDefaultsStore {
                hostingView = NSHostingView(rootView: AnyView(
                    editorView
                        .modelContainer(modelContainer)
                        .environment(appEnvironment)
                        .environment(appEnvironment.appState)
                        .environment(experienceDefaultsStore)
                        .environment(appEnvironment.careerKeywordStore)
                ))
            } else if let modelContainer,
                      let experienceDefaultsStore,
                      let careerKeywordStore {
                hostingView = NSHostingView(rootView: AnyView(
                    editorView
                        .modelContainer(modelContainer)
                        .environment(experienceDefaultsStore)
                        .environment(careerKeywordStore)
                ))
            } else if let experienceDefaultsStore,
                      let careerKeywordStore {
                hostingView = NSHostingView(rootView: AnyView(
                    editorView
                        .environment(experienceDefaultsStore)
                        .environment(careerKeywordStore)
                ))
            } else {
                hostingView = NSHostingView(rootView: AnyView(editorView))
            }

            experienceEditorWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            experienceEditorWindow?.title = "Experience Editor"
            experienceEditorWindow?.tabbingMode = .disallowed
            experienceEditorWindow?.contentView = hostingView
            experienceEditorWindow?.isReleasedWhenClosed = false
            experienceEditorWindow?.center()
            experienceEditorWindow?.minSize = NSSize(width: 960, height: 680)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: experienceEditorWindow
            )
        }

        experienceEditorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
