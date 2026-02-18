//
//  AppMenuBuilder.swift
//  Sprung
//
//  Imperatively inserts Sprung-specific items (Applicant Profile, Template
//  Editor, Experience Editor) into the running application menu. Call once,
//  after applicationDidFinishLaunching, on the main queue.
//
import Cocoa

@MainActor
enum AppMenuBuilder {
    static func install(
        showApplicantProfile: Selector,
        showTemplateEditor: Selector,
        showExperienceEditor: Selector,
        target: AnyObject
    ) {
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
            "About Physics Cloud Resume"
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
            !appMenu.item(at: aboutSeparatorIndex)!.isSeparatorItem {
            appMenu.insertItem(NSMenuItem.separator(), at: aboutSeparatorIndex)
        }
        // Add Applicant Profile menu item after separator
        let profileMenuItem = NSMenuItem(
            title: "Applicant Profile...",
            action: showApplicantProfile,
            keyEquivalent: ""
        )
        profileMenuItem.target = target
        appMenu.insertItem(profileMenuItem, at: aboutSeparatorIndex + 1)
        // Add Template Editor menu item
        let templateMenuItem = NSMenuItem(
            title: "Template Editor...",
            action: showTemplateEditor,
            keyEquivalent: "T"
        )
        templateMenuItem.target = target
        templateMenuItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.insertItem(templateMenuItem, at: aboutSeparatorIndex + 2)
        let experienceMenuItem = NSMenuItem(
            title: "Experience Editor...",
            action: showExperienceEditor,
            keyEquivalent: "E"
        )
        experienceMenuItem.keyEquivalentModifierMask = [.command, .shift]
        experienceMenuItem.target = target
        appMenu.insertItem(experienceMenuItem, at: aboutSeparatorIndex + 3)
    }
}
