//
//  AppDelegate.swift
//  PhysCloudResume
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
    var appEnvironment: AppEnvironment?
    var modelContainer: ModelContainer?
    var enabledLLMStore: EnabledLLMStore?

    func applicationDidFinishLaunching(_: Notification) {
        // DEBUG: Remove existing SwiftData SQLite store files to avoid migration errors
//        #if DEBUG
//            let fm = FileManager.default
//            if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
//                if let files = try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) {
//                    for url in files where url.pathExtension == "sqlite" || url.pathExtension == "sqlite-shm" || url.pathExtension == "sqlite-wal" {
//                        try? fm.removeItem(at: url)
//                        Logger.debug("[DEBUG] Removed SwiftData store file at \(url.path)")
//                    }
//                }
//            }
//        #endif
        
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
            "About PhysicsCloudResume",
            "About Physics Cloud Résumé",
            "About PhysCloudResume",
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
        appMenu.insertItem(templateMenuItem, at: aboutSeparatorIndex + 2)
    }

    @MainActor @objc func showSettingsWindow() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            
            // Create hosting view with proper environment objects
            let hostingView: NSHostingView<AnyView>
            if let appEnvironment = self.appEnvironment,
               let container = self.modelContainer,
               let enabledLLMStore = self.enabledLLMStore {
                let appState = appEnvironment.appState
                let debugSettingsStore = appState.debugSettingsStore ?? appEnvironment.debugSettingsStore

                let root = settingsView
                    .environment(appEnvironment)
                    .environment(appState)
                    .environment(appEnvironment.navigationState)
                    .environment(enabledLLMStore)
                    .environment(debugSettingsStore)
                    .modelContainer(container)

                hostingView = NSHostingView(rootView: AnyView(root))
            } else {
                // Fallback if appState or modelContainer is not available
                Logger.warning("⚠️ Settings window requested before environment is fully configured", category: .appLifecycle)
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
            let hostingView = NSHostingView(rootView: profileView)

            applicantProfileWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            applicantProfileWindow?.title = "Applicant Profile"
            applicantProfileWindow?.contentView = hostingView
            applicantProfileWindow?.isReleasedWhenClosed = false
            applicantProfileWindow?.center()

            // Set a minimum size for the window
            applicantProfileWindow?.minSize = NSSize(width: 500, height: 400)

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
        if notification.object as? NSWindow == applicantProfileWindow {}
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
                ))
            } else if let modelContainer = self.modelContainer {
                hostingView = NSHostingView(rootView: AnyView(editorView.modelContainer(modelContainer)))
            } else {
                hostingView = NSHostingView(rootView: AnyView(editorView))
            }
            
            templateEditorWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            templateEditorWindow?.title = "Template Editor"
            templateEditorWindow?.contentView = hostingView
            templateEditorWindow?.isReleasedWhenClosed = false
            templateEditorWindow?.center()
            
            // Set a minimum size for the window
            templateEditorWindow?.minSize = NSSize(width: 800, height: 600)
        }
        
        // Bring the window to the front
        templateEditorWindow?.makeKeyAndOrderFront(nil)
        
        // Activate the app to ensure focus
        NSApp.activate(ignoringOtherApps: true)
    }
}
