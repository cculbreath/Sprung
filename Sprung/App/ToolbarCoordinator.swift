// Sprung/App/ToolbarCoordinator.swift
//
// ──────────────────────────────────────────────────────────────────────────────
// WHY THIS FILE EXISTS (instead of SwiftUI's toolbar(id:) API)
// ──────────────────────────────────────────────────────────────────────────────
//
// SwiftUI's `CustomizableToolbarContent` protocol, used with the
// `.toolbar(id:)` view modifier, has a confirmed bug on macOS 15 (Sequoia)
// and later — including macOS 26 (Tahoe) beta 1. The bug is tracked as
// rdar://FB13106004 and discussed in Apple Developer Forums threads 763829
// and 772096.
//
// THE BUG
// -------
// When the user triggers "Customize Toolbar…" (right-click toolbar or
// View > Customize Toolbar), macOS internally calls
// `NSToolbar.prepareIndividualItemsToolbar` to build a *second* NSToolbar
// that populates the customization palette (the drag-and-drop sheet).
//
// In a correct NSToolbarDelegate implementation, the delegate method
// `toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)` is called
// once per item for the real toolbar and again for the palette toolbar,
// each time expecting a **fresh NSToolbarItem instance**. The boolean
// `willBeInsertedIntoToolbar` parameter distinguishes the two cases.
//
// SwiftUI's internal bridge does NOT do this correctly. It reuses the same
// NSToolbarItem instances for both the real toolbar and the palette toolbar.
// When NSToolbar tries to insert an item that already exists, it throws:
//
//   NSInternalInconsistencyException:
//   "NSToolbar 0x… already contains an item with the identifier <id>.
//    Duplicate items of this type are not allowed."
//
// This causes the customization sheet to never appear. The toolbar icons
// wiggle (indicating customization mode was entered) but the palette
// crashes before it can be presented.
//
// WHAT WE TRIED (AND WHY IT DIDN'T WORK)
// ----------------------------------------
// Before arriving at this solution, several SwiftUI-side workarounds were
// attempted — none resolved the issue because they all still flowed through
// SwiftUI's broken toolbar(id:) code path:
//
//   1. Removing duplicate toolbar IDs in the view hierarchy
//   2. Removing @Environment from the CustomizableToolbarContent struct
//   3. Removing @ToolbarContentBuilder from the wrapper function
//   4. Flattening nested Group computed properties
//   5. Renaming item identifiers to avoid collisions with Notification.Name
//   6. Changing item placements (.secondaryAction → .primaryAction)
//   7. Removing AppDelegate's direct NSToolbar manipulation
//   8. Removing .toolbarRole(.editor) from parent views
//
// THE FIX
// -------
// This file implements the toolbar using pure AppKit: an NSToolbarDelegate
// that creates fresh NSToolbarItem instances on every delegate callback.
// This is the behavior macOS expects and has supported reliably since the
// NSToolbar API was introduced.
//
// All button actions post the same Notification.Name values that the app's
// menu commands already use (defined in MenuCommands.swift). The existing
// MenuNotificationHandler bridges those notifications into SwiftUI bindings,
// so no additional plumbing was needed.
//
// Complex toolbar buttons that present sheets (BestJobButton,
// CoverLetterGenerateButton) are kept in the view hierarchy as hidden
// background views in ResumeEditorModuleView so their .sheet() and .alert()
// modifiers continue to function when triggered by notifications.
//
// RESTORING SwiftUI TOOLBAR IN THE FUTURE
// ----------------------------------------
// If Apple fixes rdar://FB13106004, the SwiftUI approach can be restored by:
//   1. Re-creating UnifiedToolbar.swift with CustomizableToolbarContent
//   2. Adding .toolbar(id: "sprungMainToolbar") back to ResumeEditorModuleView
//   3. Removing this file, the AppDelegate.setupMainWindowToolbar() call,
//      and the hidden background toolbar button views
//   4. The old implementation is preserved in git history
//
// ──────────────────────────────────────────────────────────────────────────────

import AppKit
import Foundation

// MARK: - Toolbar Item Identifiers

extension NSToolbarItem.Identifier {
    static let newListing = NSToolbarItem.Identifier("newListing")
    static let templateEditor = NSToolbarItem.Identifier("templateEditor")
    static let bestJob = NSToolbarItem.Identifier("bestJob")
    static let onboardingInterview = NSToolbarItem.Identifier("onboardingInterview")
    static let createResume = NSToolbarItem.Identifier("createResume")
    static let coverLetter = NSToolbarItem.Identifier("coverLetter")
    static let experienceEditor = NSToolbarItem.Identifier("experienceEditor")
    static let resumePolish = NSToolbarItem.Identifier("resumePolish")
    static let analyze = NSToolbarItem.Identifier("analyze")
    static let inspector = NSToolbarItem.Identifier("inspector")
    static let settingsItem = NSToolbarItem.Identifier("settings")
    static let applicantProfile = NSToolbarItem.Identifier("applicantProfile")
    static let ttsReadAloud = NSToolbarItem.Identifier("ttsReadAloud")
}

// MARK: - Toolbar Coordinator

/// Pure AppKit toolbar that bypasses SwiftUI's broken `toolbar(id:)` customization.
///
/// SwiftUI's `CustomizableToolbarContent` with `toolbar(id:)` has a known bug on macOS 15+
/// where `NSToolbar.prepareIndividualItemsToolbar` creates duplicate items, crashing the
/// customization palette (rdar://FB13106004). This coordinator implements `NSToolbarDelegate`
/// directly, creating fresh item instances on each delegate call and avoiding the bug entirely.
///
/// All button actions post the same `Notification.Name` values used by the menu commands,
/// so `MenuNotificationHandler` bridges them into the SwiftUI binding layer unchanged.
@MainActor
final class ToolbarCoordinator: NSObject, NSToolbarDelegate, NSToolbarItemValidation {

    weak var jobAppStore: JobAppStore?
    weak var navigationState: NavigationStateService?
    private weak var toolbar: NSToolbar?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshValidation),
            name: .toolbarNeedsValidation,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshValidation),
            name: .selectJobApp,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func attach(to toolbar: NSToolbar) {
        self.toolbar = toolbar
    }

    @objc private func refreshValidation() {
        toolbar?.validateVisibleItems()
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .newListing,
            .templateEditor,
            .flexibleSpace,
            .createResume,
            .coverLetter,
            .experienceEditor,
            .analyze,
            .flexibleSpace,
            .inspector,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .newListing,
            .templateEditor,
            .bestJob,
            .onboardingInterview,
            .createResume,
            .coverLetter,
            .experienceEditor,
            .resumePolish,
            .analyze,
            .inspector,
            .settingsItem,
            .applicantProfile,
            .ttsReadAloud,
            .flexibleSpace,
            .space,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.isBordered = true

        switch itemIdentifier {
        case .newListing:
            item.label = "New Listing"
            item.paletteLabel = "New Listing"
            item.toolTip = "Create new job listing"
            item.image = NSImage(systemSymbolName: "plus.rectangle.on.folder", accessibilityDescription: "New Listing")
            item.action = #selector(newListingAction)

        case .templateEditor:
            item.label = "Templates"
            item.paletteLabel = "Template Editor"
            item.toolTip = "Open Template Editor"
            item.image = NSImage(systemSymbolName: "compass.drawing", accessibilityDescription: "Templates")
            item.action = #selector(templateEditorAction)

        case .bestJob:
            item.label = "Best Job"
            item.paletteLabel = "Best Job Match"
            item.toolTip = "Find best job match based on your qualifications"
            item.image = NSImage(systemSymbolName: "medal", accessibilityDescription: "Best Job")
            item.action = #selector(bestJobAction)

        case .onboardingInterview:
            item.label = "Onboarding"
            item.paletteLabel = "Onboarding Interview"
            item.toolTip = "Launch onboarding interview"
            item.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: "Onboarding")
            item.action = #selector(onboardingInterviewAction)

        case .createResume:
            item.label = "Create Resume"
            item.paletteLabel = "Create Resume"
            item.toolTip = "Create resume for selected listing"
            item.image = NSImage(named: "custom.resume.new")
                ?? NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "Create Resume")
            item.action = #selector(createResumeAction)

        case .coverLetter:
            item.label = "Create Letter"
            item.paletteLabel = "Generate Cover Letter"
            item.toolTip = "Generate cover letter"
            item.image = NSImage(named: "custom.append.page.badge.plus")
                ?? NSImage(systemSymbolName: "envelope", accessibilityDescription: "Cover Letter")
            item.action = #selector(coverLetterAction)

        case .experienceEditor:
            item.label = "Experience"
            item.paletteLabel = "Experience Editor"
            item.toolTip = "Open Experience Editor"
            item.image = NSImage(systemSymbolName: "building.columns", accessibilityDescription: "Experience")
            item.action = #selector(experienceEditorAction)

        case .resumePolish:
            item.label = "Polish Resume"
            item.paletteLabel = "Polish Resume"
            item.toolTip = "Polish resume with AI revision agent"
            item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Polish Resume")
            item.action = #selector(resumePolishAction)

        case .analyze:
            item.label = "Analyze"
            item.paletteLabel = "Analyze Application"
            item.toolTip = "Analyze complete application"
            item.image = NSImage(systemSymbolName: "checkmark.seal", accessibilityDescription: "Analyze")
            item.action = #selector(analyzeAction)

        case .inspector:
            item.label = "Inspector"
            item.paletteLabel = "Cover Letter Inspector"
            item.toolTip = "Toggle Cover Letter Inspector"
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Inspector")
            item.action = #selector(inspectorAction)

        case .settingsItem:
            item.label = "Settings"
            item.paletteLabel = "Settings"
            item.toolTip = "Open Settings"
            item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
            item.action = #selector(settingsAction)

        case .applicantProfile:
            item.label = "Profile"
            item.paletteLabel = "Applicant Profile"
            item.toolTip = "Open Applicant Profile"
            item.image = NSImage(systemSymbolName: "person.text.rectangle", accessibilityDescription: "Profile")
            item.action = #selector(applicantProfileAction)

        case .ttsReadAloud:
            item.label = "Read Aloud"
            item.paletteLabel = "Read Aloud"
            item.toolTip = "Toggle text-to-speech playback"
            item.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Read Aloud")
            item.action = #selector(ttsReadAloudAction)

        default:
            return nil
        }

        return item
    }

    // MARK: - NSToolbarItemValidation

    nonisolated func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        MainActor.assumeIsolated {
            switch item.itemIdentifier {
            case .createResume:
                return jobAppStore?.selectedApp != nil
            case .coverLetter:
                return jobAppStore?.selectedApp?.selectedRes != nil
            case .resumePolish:
                return jobAppStore?.selectedApp?.selectedRes != nil
            case .analyze:
                return jobAppStore?.selectedApp?.selectedRes != nil
                    && jobAppStore?.selectedApp?.selectedCover?.generated == true
            case .inspector:
                return navigationState?.selectedTab == .coverLetter
            default:
                return true
            }
        }
    }

    // MARK: - Actions (post notifications handled by MenuNotificationHandler)

    @objc private func newListingAction() {
        NotificationCenter.default.post(name: .newJobApp, object: nil)
    }

    @objc private func templateEditorAction() {
        NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
    }

    @objc private func bestJobAction() {
        NotificationCenter.default.post(name: .bestJob, object: nil)
    }

    @objc private func onboardingInterviewAction() {
        NotificationCenter.default.post(name: .startOnboardingInterview, object: nil)
    }

    @objc private func createResumeAction() {
        NotificationCenter.default.post(name: .createNewResume, object: nil)
    }

    @objc private func coverLetterAction() {
        NotificationCenter.default.post(name: .generateCoverLetter, object: nil)
    }

    @objc private func experienceEditorAction() {
        NotificationCenter.default.post(name: .showExperienceEditor, object: nil)
    }

    @objc private func resumePolishAction() {
        NotificationCenter.default.post(name: .polishResume, object: nil)
    }

    @objc private func analyzeAction() {
        NotificationCenter.default.post(name: .analyzeApplication, object: nil)
    }

    @objc private func inspectorAction() {
        NotificationCenter.default.post(name: .showCoverLetterInspector, object: nil)
    }

    @objc private func settingsAction() {
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    @objc private func applicantProfileAction() {
        NotificationCenter.default.post(name: .showApplicantProfile, object: nil)
    }

    @objc private func ttsReadAloudAction() {
        NotificationCenter.default.post(name: .triggerTTSButton, object: nil)
    }
}
