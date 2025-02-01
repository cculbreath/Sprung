import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var settingsWindow: NSWindow?

    //  func applicationDidFinishLaunching(_ notification: Notification) {
//    // Set the title of the main window
//    if let window = NSApplication.shared.windows.first {
//      window.title = "Job Applications"
//    }
//
    //  }

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
}
