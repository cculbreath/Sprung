import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var settingsWindow: NSWindow?
    var applicantProfileWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupAppMenu()
    }
    
    private func setupAppMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        
        // Find or create the Application menu (first menu)
        let appMenu: NSMenu
        if let existingAppMenu = mainMenu.item(at: 0)?.submenu {
            appMenu = existingAppMenu
        } else {
            // Create a new app menu if it doesn't exist (unlikely)
            appMenu = NSMenu(title: "PhysicsCloudResume")
            let appMenuItem = NSMenuItem(title: "PhysicsCloudResume", action: nil, keyEquivalent: "")
            appMenuItem.submenu = appMenu
            mainMenu.insertItem(appMenuItem, at: 0)
        }
        
        // Add Applicant Profile item after About item (usually at index 0)
        let aboutSeparatorIndex = appMenu.indexOfItem(withTitle: "About PhysicsCloudResume") + 1
        
        // Insert separator if needed
        if appMenu.item(at: aboutSeparatorIndex)?.isSeparatorItem != true {
            appMenu.insertItem(NSMenuItem.separator(), at: aboutSeparatorIndex)
        }
        
        // Add Applicant Profile menu item after separator
        let profileMenuItem = NSMenuItem(
            title: "Applicant Profile...",
            action: #selector(showApplicantProfileWindow),
            keyEquivalent: ""
        )
        appMenu.insertItem(profileMenuItem, at: aboutSeparatorIndex + 1)
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
        if applicantProfileWindow == nil {
            let profileView = ApplicantProfileView()
            applicantProfileWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            applicantProfileWindow?.title = "Applicant Profile"
            applicantProfileWindow?.contentView = NSHostingView(rootView: profileView)
            applicantProfileWindow?.isReleasedWhenClosed = false
            
            // Center the window on the screen
            applicantProfileWindow?.center()
        }
        applicantProfileWindow?.makeKeyAndOrderFront(nil)
    }
}