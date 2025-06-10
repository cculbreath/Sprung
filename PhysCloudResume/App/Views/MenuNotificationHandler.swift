// PhysCloudResume/App/Views/MenuNotificationHandler.swift

import SwiftUI
import Foundation
import AppKit

/// Handles menu command notifications and delegates to appropriate UI actions
@Observable
class MenuNotificationHandler {
    private weak var jobAppStore: JobAppStore?
    private var sheets: Binding<AppSheets>?
    private var selectedTab: Binding<TabList>?
    private var showSlidingList: Binding<Bool>?
    
    init() {}
    
    /// Setup the handler with required dependencies
    func configure(
        jobAppStore: JobAppStore,
        sheets: Binding<AppSheets>,
        selectedTab: Binding<TabList>,
        showSlidingList: Binding<Bool>
    ) {
        self.jobAppStore = jobAppStore
        self.sheets = sheets
        self.selectedTab = selectedTab
        self.showSlidingList = showSlidingList
        
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // Job Application Commands
        NotificationCenter.default.addObserver(
            forName: .newJobApp,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showNewJobApp = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .bestJob,
            object: nil,
            queue: .main
        ) { _ in
            // TODO: Implement best job functionality
            // This should trigger the same logic as the toolbar button
        }
        
        NotificationCenter.default.addObserver(
            forName: .showSources,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let showSlidingList = self?.showSlidingList else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.2)) {
                showSlidingList.wrappedValue.toggle()
            }
        }
        
        // Resume Commands
        NotificationCenter.default.addObserver(
            forName: .customizeResume,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.selectedTab?.wrappedValue = .resume
            // TODO: Trigger customize workflow
        }
        
        NotificationCenter.default.addObserver(
            forName: .clarifyCustomize,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.selectedTab?.wrappedValue = .resume
            // TODO: Trigger clarify customize workflow
        }
        
        NotificationCenter.default.addObserver(
            forName: .optimizeResume,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showResumeReview = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .showResumeInspector,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.selectedTab?.wrappedValue = .resume
            self?.sheets?.wrappedValue.showResumeInspector.toggle()
        }
        
        // Cover Letter Commands
        NotificationCenter.default.addObserver(
            forName: .generateCoverLetter,
            object: nil,
            queue: .main
        ) { _ in
            // TODO: Trigger cover letter generation
        }
        
        NotificationCenter.default.addObserver(
            forName: .batchCoverLetter,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showBatchCoverLetter = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .bestCoverLetter,
            object: nil,
            queue: .main
        ) { _ in
            // TODO: Trigger best cover letter functionality
        }
        
        NotificationCenter.default.addObserver(
            forName: .committee,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showMultiModelChooseBest = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .showCoverLetterInspector,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.selectedTab?.wrappedValue = .coverLetter
            self?.sheets?.wrappedValue.showCoverLetterInspector.toggle()
        }
        
        // Analysis Commands
        NotificationCenter.default.addObserver(
            forName: .analyzeApplication,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sheets?.wrappedValue.showApplicationReview = true
        }
        
        // Window Commands (toolbar buttons that delegate to existing menu commands)
        NotificationCenter.default.addObserver(
            forName: .showSettings,
            object: nil,
            queue: .main
        ) { _ in
            // Delegate to AppDelegate via existing menu command mechanism
            Task { @MainActor in
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.showSettingsWindow()
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .showApplicantProfile,
            object: nil,
            queue: .main
        ) { _ in
            // Delegate to AppDelegate via existing menu command mechanism
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.showApplicantProfileWindow()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .showTemplateEditor,
            object: nil,
            queue: .main
        ) { _ in
            // Delegate to AppDelegate via existing menu command mechanism
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.showTemplateEditorWindow()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}