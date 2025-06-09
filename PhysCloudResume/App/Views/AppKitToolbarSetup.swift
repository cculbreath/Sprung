// PhysCloudResume/App/Views/AppKitToolbarSetup.swift

import AppKit
import SwiftUI

struct AppKitToolbarSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ToolbarHostView()
        
        DispatchQueue.main.async {
            if let window = view.window {
                setupAppKitToolbar(for: window)
            } else {
                // Retry after a brief delay if window isn't available yet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = view.window {
                        setupAppKitToolbar(for: window)
                    }
                }
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // No updates needed
    }
    
    private func setupAppKitToolbar(for window: NSWindow) {
        let toolbarDelegate = CustomizableToolbarDelegate()
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("MainToolbar"))
        
        toolbar.delegate = toolbarDelegate
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconAndLabel
        
        window.toolbar = toolbar
        
        // Store the delegate to prevent deallocation
        objc_setAssociatedObject(window, &ToolbarDelegateKey, toolbarDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private var ToolbarDelegateKey: UInt8 = 0

class ToolbarHostView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The setup is handled in the representable
    }
}

class CustomizableToolbarDelegate: NSObject, NSToolbarDelegate {
    
    // MARK: - Toolbar Item Identifiers
    
    static let newJobApp = NSToolbarItem.Identifier("newJobApp")
    static let bestJob = NSToolbarItem.Identifier("bestJob")
    static let customize = NSToolbarItem.Identifier("customize")
    static let clarifyCustomize = NSToolbarItem.Identifier("clarifyCustomize")
    static let optimize = NSToolbarItem.Identifier("optimize")
    static let coverLetter = NSToolbarItem.Identifier("coverLetter")
    static let batchLetter = NSToolbarItem.Identifier("batchLetter")
    static let bestLetter = NSToolbarItem.Identifier("bestLetter")
    static let committee = NSToolbarItem.Identifier("committee")
    static let analyze = NSToolbarItem.Identifier("analyze")
    static let inspector = NSToolbarItem.Identifier("inspector")
    
    // MARK: - NSToolbarDelegate Methods
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        
        switch itemIdentifier {
        case Self.newJobApp:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "New App"
            item.paletteLabel = "New Job Application"
            item.toolTip = "Create New Job Application"
            item.image = NSImage(systemSymbolName: "note.text.badge.plus", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(newJobAppAction)
            return item
            
        case Self.bestJob:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Best Job"
            item.paletteLabel = "Best Job Match"
            item.toolTip = "Find the best job match"
            item.image = NSImage(systemSymbolName: "medal.star", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(bestJobAction)
            return item
            
        case Self.customize:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Customize"
            item.paletteLabel = "Customize Resume"
            item.toolTip = "Create Resume Revisions"
            item.image = NSImage(systemSymbolName: "wand.and.sparkles", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(customizeAction)
            return item
            
        case Self.clarifyCustomize:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Clarify & Customize"
            item.paletteLabel = "Clarify and Customize Resume"
            item.toolTip = "Create Resume Revisions with Clarifying Questions"
            item.image = NSImage(named: "custom.wand.and.sparkles.badge.questionmark")
            item.target = self
            item.action = #selector(clarifyCustomizeAction)
            return item
            
        case Self.optimize:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Optimize"
            item.paletteLabel = "Optimize Resume"
            item.toolTip = "AI Resume Review"
            item.image = NSImage(systemSymbolName: "character.magnify", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(optimizeAction)
            return item
            
        case Self.coverLetter:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Cover Letter"
            item.paletteLabel = "Generate Cover Letter"
            item.toolTip = "Generate Cover Letter"
            item.image = NSImage(named: "custom.append.page.badge.plus")
            item.target = self
            item.action = #selector(coverLetterAction)
            return item
            
        case Self.batchLetter:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Batch Letter"
            item.paletteLabel = "Batch Cover Letter"
            item.toolTip = "Batch Cover Letter Operations"
            item.image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(batchLetterAction)
            return item
            
        case Self.bestLetter:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Best Letter"
            item.paletteLabel = "Choose Best Letter"
            item.toolTip = "Choose Best Cover Letter"
            item.image = NSImage(systemSymbolName: "medal", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(bestLetterAction)
            return item
            
        case Self.committee:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Committee"
            item.paletteLabel = "Multi-model Committee"
            item.toolTip = "Multi-model Choose Best Cover Letter"
            item.image = NSImage(named: "custom.medal.square.stack")
            item.target = self
            item.action = #selector(committeeAction)
            return item
            
        case Self.analyze:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Analyze"
            item.paletteLabel = "Analyze Application"
            item.toolTip = "Review Application"
            item.image = NSImage(systemSymbolName: "mail.and.text.magnifyingglass", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(analyzeAction)
            return item
            
        case Self.inspector:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Inspector"
            item.paletteLabel = "Show Inspector"
            item.toolTip = "Show Inspector"
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(inspectorAction)
            return item
            
        default:
            return nil
        }
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            Self.newJobApp,
            Self.bestJob,
            .flexibleSpace,
            Self.customize,
            Self.clarifyCustomize,
            Self.optimize,
            .flexibleSpace,
            Self.coverLetter,
            Self.batchLetter,
            Self.bestLetter,
            Self.committee,
            .flexibleSpace,
            Self.analyze,
            .flexibleSpace,
            Self.inspector
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            Self.newJobApp,
            Self.bestJob,
            Self.customize,
            Self.clarifyCustomize,
            Self.optimize,
            Self.coverLetter,
            Self.batchLetter,
            Self.bestLetter,
            Self.committee,
            Self.analyze,
            Self.inspector,
            .flexibleSpace,
            .space
        ]
    }
    
    // MARK: - Action Methods
    
    @objc private func newJobAppAction() {
        NotificationCenter.default.post(name: .toolbarNewJobApp, object: nil)
    }
    
    @objc private func bestJobAction() {
        NotificationCenter.default.post(name: .toolbarBestJob, object: nil)
    }
    
    @objc private func customizeAction() {
        NotificationCenter.default.post(name: .toolbarCustomize, object: nil)
    }
    
    @objc private func clarifyCustomizeAction() {
        NotificationCenter.default.post(name: .toolbarClarifyCustomize, object: nil)
    }
    
    @objc private func optimizeAction() {
        NotificationCenter.default.post(name: .toolbarOptimize, object: nil)
    }
    
    @objc private func coverLetterAction() {
        NotificationCenter.default.post(name: .toolbarCoverLetter, object: nil)
    }
    
    @objc private func batchLetterAction() {
        NotificationCenter.default.post(name: .toolbarBatchLetter, object: nil)
    }
    
    @objc private func bestLetterAction() {
        NotificationCenter.default.post(name: .toolbarBestLetter, object: nil)
    }
    
    @objc private func committeeAction() {
        NotificationCenter.default.post(name: .toolbarCommittee, object: nil)
    }
    
    @objc private func analyzeAction() {
        NotificationCenter.default.post(name: .toolbarAnalyze, object: nil)
    }
    
    @objc private func inspectorAction() {
        NotificationCenter.default.post(name: .toolbarInspector, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toolbarNewJobApp = Notification.Name("toolbarNewJobApp")
    static let toolbarBestJob = Notification.Name("toolbarBestJob")
    static let toolbarCustomize = Notification.Name("toolbarCustomize")
    static let toolbarClarifyCustomize = Notification.Name("toolbarClarifyCustomize")
    static let toolbarOptimize = Notification.Name("toolbarOptimize")
    static let toolbarCoverLetter = Notification.Name("toolbarCoverLetter")
    static let toolbarBatchLetter = Notification.Name("toolbarBatchLetter")
    static let toolbarBestLetter = Notification.Name("toolbarBestLetter")
    static let toolbarCommittee = Notification.Name("toolbarCommittee")
    static let toolbarAnalyze = Notification.Name("toolbarAnalyze")
    static let toolbarInspector = Notification.Name("toolbarInspector")
}