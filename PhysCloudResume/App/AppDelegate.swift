import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var settingsWindow: NSWindow?
    var applicantProfileWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        // Wait until the app is fully loaded before modifying the menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupAppMenu()
        }

        // Also add the top-level Profile menu to make sure it's available
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.addProfileMainMenu()
        }
    }

    private func addProfileMainMenu() {
        // Add a top-level Profile menu
        guard let mainMenu = NSApp.mainMenu else {
            print("Main menu not available for Profile menu")
            return
        }

        // Create new Profile menu
        let profileMenu = NSMenu(title: "Profile")
        let profileMenuItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profileMenuItem.submenu = profileMenu

        // Add items to the menu
        let applicantMenuItem = NSMenuItem(
            title: "Applicant Profile...",
            action: #selector(showApplicantProfileWindow),
            keyEquivalent: "P"
        )
        applicantMenuItem.keyEquivalentModifierMask = [.command, .shift]
        applicantMenuItem.target = self
        profileMenu.addItem(applicantMenuItem)

        // Insert between Edit and View menus
        let insertPosition = 2 // Typically after Edit menu
        if mainMenu.numberOfItems > insertPosition {
            mainMenu.insertItem(profileMenuItem, at: insertPosition)
            print("Added top-level Profile menu at position \(insertPosition)")
        } else {
            mainMenu.addItem(profileMenuItem)
            print("Added top-level Profile menu at end")
        }
    }

    private func setupAppMenu() {
        guard let mainMenu = NSApp.mainMenu else {
            print("Main menu not available")
            return
        }

        print("Setting up app menu, main menu has \(mainMenu.numberOfItems) items")

        // Find the name of the application to look for the right menu item
        let appName = ProcessInfo.processInfo.processName

        // Find or create the Application menu (first menu)
        let appMenu: NSMenu
        if let existingAppMenu = mainMenu.item(at: 0)?.submenu {
            appMenu = existingAppMenu
            print("Found existing app menu: \(existingAppMenu.title)")
        } else {
            // Create a new app menu if it doesn't exist (unlikely)
            appMenu = NSMenu(title: appName)
            let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
            appMenuItem.submenu = appMenu
            mainMenu.insertItem(appMenuItem, at: 0)
            print("Created new app menu: \(appName)")
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
                print("Found About item at index \(index): \(title)")
                break
            }
        }

        // If About item not found, insert at the beginning
        let aboutSeparatorIndex = aboutItemIndex >= 0 ? aboutItemIndex + 1 : 0
        print("Will insert profile item at index \(aboutSeparatorIndex)")

        // If we already have an Applicant Profile menu item, remove it to avoid duplicates
        let existingProfileIndex = appMenu.indexOfItem(withTitle: "Applicant Profile...")
        if existingProfileIndex >= 0 {
            appMenu.removeItem(at: existingProfileIndex)
            print("Removed existing profile menu item")
        }

        // Insert separator if needed
        if aboutSeparatorIndex < appMenu.numberOfItems &&
            !appMenu.item(at: aboutSeparatorIndex)!.isSeparatorItem
        {
            appMenu.insertItem(NSMenuItem.separator(), at: aboutSeparatorIndex)
            print("Added separator")
        }

        // Add Applicant Profile menu item after separator
        let profileMenuItem = NSMenuItem(
            title: "Applicant Profile...",
            action: #selector(showApplicantProfileWindow),
            keyEquivalent: ""
        )
        profileMenuItem.target = self
        appMenu.insertItem(profileMenuItem, at: aboutSeparatorIndex + 1)
        print("Added Applicant Profile menu item")

        // Print all menu items for debugging
        for i in 0 ..< appMenu.numberOfItems {
            if let item = appMenu.item(at: i) {
                print("  Menu item \(i): \(item.title) (separator: \(item.isSeparatorItem))")
            }
        }
    }

    @objc func showSettingsWindow() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            settingsWindow?.title = "Settings"
            settingsWindow?.contentView = NSHostingView(rootView: settingsView)
            settingsWindow?.isReleasedWhenClosed = false

            // Center the window on the screen
            settingsWindow?.center()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showApplicantProfileWindow() {
        print("showApplicantProfileWindow called")

        // If window exists but was closed, reset it
        if let window = applicantProfileWindow, !window.isVisible {
            applicantProfileWindow = nil
            print("Window exists but is not visible, recreating")
        }

        if applicantProfileWindow == nil {
            print("Creating new applicant profile window")
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

        print("Profile window should now be visible")
    }

    @objc func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == applicantProfileWindow {
            print("Applicant profile window will close")
        }
    }
}
